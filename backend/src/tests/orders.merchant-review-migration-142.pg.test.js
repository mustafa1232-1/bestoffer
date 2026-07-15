import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import test from "node:test";

import pg from "pg";

const migrationUrl = new URL("../../sql/142_merchant_review_social_link.sql", import.meta.url);

function localDatabaseUrl() {
  const raw = String(
    process.env.MERCHANT_REVIEW_MIGRATION_DATABASE_URL ||
      process.env.DATABASE_URL ||
      ""
  ).trim();
  assert.ok(raw, "a local PostgreSQL URL is required");
  const parsed = new URL(raw);
  assert.ok(
    ["127.0.0.1", "localhost", "::1"].includes(parsed.hostname),
    "migration integration tests may only target loopback PostgreSQL"
  );
  return raw;
}

function quoteIdentifier(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

async function withIsolatedSchema(run) {
  const schema = `merchant_review_142_${randomUUID().replaceAll("-", "")}`;
  const schemaId = quoteIdentifier(schema);
  const client = new pg.Client({ connectionString: localDatabaseUrl() });
  await client.connect();
  try {
    await client.query(`CREATE SCHEMA ${schemaId}`);
    await client.query(`SET search_path TO ${schemaId}, public`);
    await client.query(`CREATE TABLE app_user (id BIGSERIAL PRIMARY KEY)`);
    await client.query(`CREATE TABLE merchant (id BIGSERIAL PRIMARY KEY)`);
    await client.query(`
      CREATE TABLE customer_order (
        id BIGSERIAL PRIMARY KEY,
        merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
        customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE
      )
    `);
    await client.query(`
      CREATE TABLE merchant_verified_review (
        id BIGSERIAL PRIMARY KEY,
        order_id BIGINT NOT NULL REFERENCES customer_order(id) ON DELETE CASCADE,
        merchant_id BIGINT NOT NULL REFERENCES merchant(id) ON DELETE CASCADE,
        customer_user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
        rating INTEGER NOT NULL,
        review_text TEXT,
        is_verified BOOLEAN NOT NULL DEFAULT TRUE,
        review_state VARCHAR(24) NOT NULL DEFAULT 'active',
        review_moderation_note TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb
      )
    `);
    await client.query(`
      CREATE TABLE social_post (
        id BIGSERIAL PRIMARY KEY,
        user_id BIGINT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
        post_kind TEXT NOT NULL,
        merchant_id BIGINT REFERENCES merchant(id) ON DELETE SET NULL,
        review_rating INTEGER,
        verified_purchase BOOLEAN NOT NULL DEFAULT FALSE,
        verified_purchase_order_id BIGINT REFERENCES customer_order(id) ON DELETE SET NULL,
        verified_purchase_verified_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await run(client, schema);
  } finally {
    await client.query("SET search_path TO public").catch(() => {});
    await client.query(`DROP SCHEMA IF EXISTS ${schemaId} CASCADE`).catch(() => {});
    await client.end();
  }
}

async function readMigrationSql() {
  return fs.readFile(migrationUrl, "utf8");
}

test("migration 142 links exact merchant-review social posts and is idempotent", async () => {
  await withIsolatedSchema(async (client, schema) => {
    const merchantId = Number((await client.query(`INSERT INTO merchant DEFAULT VALUES RETURNING id`)).rows[0].id);
    const customerId = Number((await client.query(`INSERT INTO app_user DEFAULT VALUES RETURNING id`)).rows[0].id);
    const orderId = Number(
      (
        await client.query(
          `INSERT INTO customer_order (merchant_id, customer_user_id)
           VALUES ($1, $2)
           RETURNING id`,
          [merchantId, customerId]
        )
      ).rows[0].id
    );
    const postId = Number(
      (
        await client.query(
          `INSERT INTO social_post
             (user_id, post_kind, merchant_id, review_rating, verified_purchase,
              verified_purchase_order_id, verified_purchase_verified_at)
           VALUES ($1, 'merchant_review', $2, 5, TRUE, $3, NOW())
           RETURNING id`,
          [customerId, merchantId, orderId]
        )
      ).rows[0].id
    );
    await client.query(
      `INSERT INTO merchant_verified_review
         (order_id, merchant_id, customer_user_id, rating, review_text, is_verified, metadata_json)
       VALUES ($1, $2, $3, 5, 'legacy review', TRUE, '{}'::jsonb)`,
      [orderId, merchantId, customerId]
    );

    await client.query(await readMigrationSql());

    const linked = await client.query(
      `SELECT social_post_id, review_state, review_moderation_note
       FROM merchant_verified_review
       WHERE order_id = $1`,
      [orderId]
    );
    assert.equal(linked.rowCount, 1);
    assert.equal(Number(linked.rows[0].social_post_id), postId);
    assert.equal(linked.rows[0].review_state, "active");

    const indexes = await client.query(
      `SELECT indexname
       FROM pg_indexes
       WHERE schemaname = $1
         AND tablename = 'merchant_verified_review'`,
      [schema]
    );
    assert.ok(
      indexes.rows.some((row) => row.indexname === "idx_merchant_verified_review_social_post_unique"),
      "social post uniqueness index missing"
    );

    await client.query(await readMigrationSql());
    const rerun = await client.query(
      `SELECT social_post_id
       FROM merchant_verified_review
       WHERE order_id = $1`,
      [orderId]
    );
    assert.equal(Number(rerun.rows[0].social_post_id), postId);
  });
});
