import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import test from "node:test";

import pg from "pg";

const migrationUrl = new URL("../../sql/141_merchant_review_active_contract.sql", import.meta.url);

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
  const schema = `merchant_review_141_${randomUUID().replaceAll("-", "")}`;
  const schemaId = quoteIdentifier(schema);
  const client = new pg.Client({ connectionString: localDatabaseUrl() });
  await client.connect();
  try {
    await client.query(`CREATE SCHEMA ${schemaId}`);
    await client.query(`SET search_path TO ${schemaId}, public`);
    await client.query(`
      CREATE TABLE app_user (
        id BIGSERIAL PRIMARY KEY
      )
    `);
    await client.query(`
      CREATE TABLE merchant (
        id BIGSERIAL PRIMARY KEY
      )
    `);
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
        rating INTEGER,
        review_text TEXT,
        is_verified BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb
      )
    `);
    await client.query(`
      CREATE TABLE social_post (
        id BIGSERIAL PRIMARY KEY,
        post_kind TEXT NOT NULL,
        review_rating INTEGER,
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

async function columnRows(client, schema, table) {
  const result = await client.query(
    `SELECT column_name, data_type, is_nullable, column_default
       FROM information_schema.columns
      WHERE table_schema = $1
        AND table_name = $2
      ORDER BY ordinal_position`,
    [schema, table]
  );
  return result.rows;
}

async function indexRows(client, schema, table) {
  const result = await client.query(
    `SELECT indexname, indexdef
       FROM pg_indexes
      WHERE schemaname = $1
        AND tablename = $2
      ORDER BY indexname`,
    [schema, table]
  );
  return result.rows;
}

test("migration 141 adds the merchant-review contract columns and index", async () => {
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
    await client.query(
      `INSERT INTO merchant_verified_review (order_id, merchant_id, customer_user_id, rating, review_text, is_verified)
       VALUES ($1, $2, $3, 5, 'legacy', TRUE)`,
      [orderId, merchantId, customerId]
    );
    await client.query(`INSERT INTO social_post (post_kind, review_rating) VALUES ('merchant_review', 5)`);

    await client.query(await readMigrationSql());

    const reviewColumns = await columnRows(client, schema, "merchant_verified_review");
    for (const expected of [
      "review_state",
      "review_deleted_at",
      "review_deleted_by_user_id",
      "review_moderated_at",
      "review_moderated_by_user_id",
      "review_moderation_note",
    ]) {
      assert.ok(reviewColumns.some((column) => column.column_name === expected), `missing column ${expected}`);
    }

    const postColumns = await columnRows(client, schema, "social_post");
    for (const expected of [
      "verified_purchase",
      "verified_purchase_order_id",
      "verified_purchase_verified_at",
    ]) {
      assert.ok(postColumns.some((column) => column.column_name === expected), `missing post column ${expected}`);
    }

    const indexes = await indexRows(client, schema, "merchant_verified_review");
    assert.ok(
      indexes.some((row) => row.indexname === "idx_merchant_verified_review_customer_merchant_unique"),
      "unique active merchant-review index missing"
    );
    assert.ok(
      indexes.some((row) => row.indexname === "idx_merchant_verified_review_merchant_state_recent"),
      "merchant recent index missing"
    );
    assert.ok(
      indexes.some((row) => row.indexname === "idx_merchant_verified_review_customer_state_recent"),
      "customer recent index missing"
    );
  });
});

test("migration 141 preserves valid rows, reconciles duplicates, and is idempotent", async () => {
  await withIsolatedSchema(async (client) => {
    const merchantId = Number((await client.query(`INSERT INTO merchant DEFAULT VALUES RETURNING id`)).rows[0].id);
    const customerId = Number((await client.query(`INSERT INTO app_user DEFAULT VALUES RETURNING id`)).rows[0].id);
    const order1 = Number(
      (
        await client.query(
          `INSERT INTO customer_order (merchant_id, customer_user_id)
           VALUES ($1, $2)
           RETURNING id`,
          [merchantId, customerId]
        )
      ).rows[0].id
    );
    const order2 = Number(
      (
        await client.query(
          `INSERT INTO customer_order (merchant_id, customer_user_id)
           VALUES ($1, $2)
           RETURNING id`,
          [merchantId, customerId]
        )
      ).rows[0].id
    );
    await client.query(
      `INSERT INTO merchant_verified_review (order_id, merchant_id, customer_user_id, rating, review_text, is_verified, updated_at)
       VALUES ($1, $2, $3, 4, 'older', TRUE, NOW() - INTERVAL '1 day')`,
      [order1, merchantId, customerId]
    );
    await client.query(
      `INSERT INTO merchant_verified_review (order_id, merchant_id, customer_user_id, rating, review_text, is_verified, updated_at)
       VALUES ($1, $2, $3, 5, 'newer', TRUE, NOW())`,
      [order2, merchantId, customerId]
    );

    await client.query(await readMigrationSql());

    const firstPass = await client.query(
      `SELECT order_id, rating, review_text, review_state, review_deleted_at, review_moderation_note
       FROM merchant_verified_review
       WHERE merchant_id = $1 AND customer_user_id = $2
       ORDER BY updated_at DESC, id DESC`,
      [merchantId, customerId]
    );

    assert.equal(firstPass.rowCount, 2);
    assert.equal(Number(firstPass.rows[0].order_id), order2);
    assert.equal(firstPass.rows[0].review_state, "active");
    assert.equal(Number(firstPass.rows[0].rating), 5);
    assert.equal(firstPass.rows[1].review_state, "deleted");
    assert.equal(Number(firstPass.rows[1].rating), 4);
    assert.match(String(firstPass.rows[1].review_moderation_note || ""), /Superseded by migration 141/i);
    assert.ok(firstPass.rows[1].review_deleted_at != null);

    await client.query(await readMigrationSql());

    const secondPass = await client.query(
      `SELECT order_id, rating, review_text, review_state
       FROM merchant_verified_review
       WHERE merchant_id = $1 AND customer_user_id = $2
       ORDER BY updated_at DESC, id DESC`,
      [merchantId, customerId]
    );
    assert.deepEqual(
      secondPass.rows.map((row) => [Number(row.order_id), Number(row.rating), row.review_state]),
      [
        [order2, 5, "active"],
        [order1, 4, "deleted"],
      ]
    );

    const activeCount = await client.query(
      `SELECT COUNT(*)::int AS count
       FROM merchant_verified_review
       WHERE merchant_id = $1
         AND customer_user_id = $2
         AND review_state IN ('active', 'restored')`,
      [merchantId, customerId]
    );
    assert.equal(activeCount.rows[0].count, 1);
  });
});
