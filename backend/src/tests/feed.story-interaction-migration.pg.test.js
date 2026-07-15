import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import test from "node:test";

import pg from "pg";

const migrationUrl = new URL(
  "../../sql/140_social_story_interaction_settings.sql",
  import.meta.url
);

function localDatabaseUrl() {
  const raw = String(
    process.env.SOCIAL_STORY_MIGRATION_DATABASE_URL ||
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

async function withIsolatedStorySchema(run) {
  const schema = `story_interaction_${randomUUID().replaceAll("-", "")}`;
  const schemaId = quoteIdentifier(schema);
  const client = new pg.Client({ connectionString: localDatabaseUrl() });
  await client.connect();
  try {
    await client.query(`CREATE SCHEMA ${schemaId}`);
    await client.query(`SET search_path TO ${schemaId}, public`);
    await client.query(`
      CREATE TABLE social_story (
        id BIGSERIAL PRIMARY KEY,
        caption TEXT,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await client.query(`
      CREATE TABLE social_chat_message (
        shared_entity_type TEXT,
        CONSTRAINT social_chat_message_shared_entity_type_chk
          CHECK (shared_entity_type IS NULL OR shared_entity_type IN ('post', 'reel', 'review'))
      )
    `);
    await client.query(`
      CREATE TABLE social_scope_chat_message (
        shared_entity_type VARCHAR(48),
        CONSTRAINT social_scope_chat_message_shared_entity_type_chk
          CHECK (shared_entity_type IS NULL OR shared_entity_type IN ('post', 'reel', 'review'))
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

async function interactionColumns(client, schema) {
  const result = await client.query(
    `SELECT column_name, data_type, is_nullable, column_default
       FROM information_schema.columns
      WHERE table_schema = $1
        AND table_name = 'social_story'
        AND column_name = ANY($2::text[])
      ORDER BY ordinal_position`,
    [
      schema,
      [
        "allow_likes",
        "allow_private_replies",
        "allow_comments",
        "allow_sharing",
        "allow_reshare",
      ],
    ]
  );
  return result.rows;
}

function assertCanonicalColumns(columns) {
  assert.deepEqual(
    columns.map((column) => column.column_name),
    [
      "allow_likes",
      "allow_private_replies",
      "allow_comments",
      "allow_sharing",
      "allow_reshare",
    ]
  );
  for (const column of columns) {
    assert.equal(column.data_type, "boolean");
    assert.equal(column.is_nullable, "NO");
    assert.match(String(column.column_default), /true/i);
  }
}

const canonicalSharedEntityTypes = [
  "post",
  "reel",
  "story",
  "profile",
  "user",
  "review",
  "merchant_review",
  "car_listing",
  "real_estate_listing",
  "location",
  "service_offering",
  "service_provider",
  "service_request",
];

async function sharedEntityConstraints(client) {
  const result = await client.query(`
    SELECT c.conname, c.oid::text AS oid, pg_get_constraintdef(c.oid) AS definition
      FROM pg_constraint c
     WHERE c.conname IN (
       'social_chat_message_shared_entity_type_chk',
       'social_scope_chat_message_shared_entity_type_chk'
     )
       AND c.conrelid IN (
         'social_chat_message'::regclass,
         'social_scope_chat_message'::regclass
       )
     ORDER BY c.conname
  `);
  return result.rows;
}

async function assertCanonicalSharedEntityConstraints(client) {
  const constraints = await sharedEntityConstraints(client);
  assert.equal(constraints.length, 2);
  for (const constraint of constraints) {
    for (const entityType of canonicalSharedEntityTypes) {
      assert.match(constraint.definition, new RegExp(`'${entityType}'`));
    }
  }

  for (const table of ["social_chat_message", "social_scope_chat_message"]) {
    await client.query(
      `INSERT INTO ${table} (shared_entity_type)
       SELECT UNNEST($1::text[])`,
      [canonicalSharedEntityTypes]
    );
    await assert.rejects(
      client.query(`INSERT INTO ${table} (shared_entity_type) VALUES ('invalid_type')`),
      (error) => error.code === "23514"
    );
  }
}

test(
  "migration 140 upgrades a pre-feature social_story schema",
  async () => {
    await withIsolatedStorySchema(async (client, schema) => {
      await client.query("INSERT INTO social_story (caption) VALUES ('legacy')");
      await client.query(await readMigrationSql());

      assertCanonicalColumns(await interactionColumns(client, schema));
      await assertCanonicalSharedEntityConstraints(client);
      const legacy = await client.query(
        `SELECT allow_likes, allow_private_replies, allow_comments,
                allow_sharing, allow_reshare
           FROM social_story
          WHERE caption = 'legacy'`
      );
      assert.deepEqual(legacy.rows[0], {
        allow_likes: true,
        allow_private_replies: true,
        allow_comments: true,
        allow_sharing: true,
        allow_reshare: true,
      });
    });
  }
);

test(
  "migration 140 reconciles a schema where the old Social 136 was applied",
  async () => {
    await withIsolatedStorySchema(async (client, schema) => {
      await client.query(`
        ALTER TABLE social_story
          ADD COLUMN allow_likes BOOLEAN NOT NULL DEFAULT TRUE,
          ADD COLUMN allow_private_replies BOOLEAN NOT NULL DEFAULT TRUE,
          ADD COLUMN allow_comments BOOLEAN NOT NULL DEFAULT TRUE,
          ADD COLUMN allow_sharing BOOLEAN NOT NULL DEFAULT TRUE,
          ADD COLUMN allow_reshare BOOLEAN NOT NULL DEFAULT TRUE
      `);
      await client.query(`
        INSERT INTO social_story (
          caption, allow_likes, allow_private_replies, allow_comments,
          allow_sharing, allow_reshare
        ) VALUES ('old-136', FALSE, FALSE, FALSE, FALSE, FALSE)
      `);

      await client.query(`
        CREATE TABLE schema_migration (
          id BIGSERIAL PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      `);
      await client.query(
        "INSERT INTO schema_migration (name) VALUES ($1)",
        ["136_social_story_interaction_settings.sql"]
      );
      const before = await client.query(
        "SELECT xmin::text AS xmin FROM social_story WHERE caption = 'old-136'"
      );

      await client.query(await readMigrationSql());
      await client.query(
        "INSERT INTO schema_migration (name) VALUES ($1)",
        ["140_social_story_interaction_settings.sql"]
      );

      assertCanonicalColumns(await interactionColumns(client, schema));
      await assertCanonicalSharedEntityConstraints(client);
      const preserved = await client.query(
        `SELECT allow_likes, allow_private_replies, allow_comments,
                allow_sharing, allow_reshare
           FROM social_story
          WHERE caption = 'old-136'`
      );
      assert.deepEqual(preserved.rows[0], {
        allow_likes: false,
        allow_private_replies: false,
        allow_comments: false,
        allow_sharing: false,
        allow_reshare: false,
      });
      const after = await client.query(
        "SELECT xmin::text AS xmin FROM social_story WHERE caption = 'old-136'"
      );
      assert.equal(after.rows[0].xmin, before.rows[0].xmin);
      const ledger = await client.query(
        "SELECT name FROM schema_migration ORDER BY id"
      );
      assert.deepEqual(
        ledger.rows.map((row) => row.name),
        [
          "136_social_story_interaction_settings.sql",
          "140_social_story_interaction_settings.sql",
        ]
      );
    });
  }
);

test(
  "migration 140 is idempotent and its second execution rewrites no stories",
  async () => {
    await withIsolatedStorySchema(async (client, schema) => {
      await client.query("INSERT INTO social_story (caption) VALUES ('twice')");
      const migrationSql = await readMigrationSql();
      await client.query(migrationSql);
      await client.query("UPDATE social_story SET allow_likes = FALSE");
      await client.query("CREATE TABLE migration_update_audit (updates INT NOT NULL)");
      await client.query("INSERT INTO migration_update_audit (updates) VALUES (0)");
      await client.query(`
        CREATE FUNCTION count_story_migration_updates()
        RETURNS TRIGGER
        LANGUAGE plpgsql
        AS $function$
        BEGIN
          UPDATE migration_update_audit SET updates = updates + 1;
          RETURN NEW;
        END
        $function$
      `);
      await client.query(`
        CREATE TRIGGER count_story_migration_updates
        BEFORE UPDATE ON social_story
        FOR EACH ROW EXECUTE FUNCTION count_story_migration_updates()
      `);

      const constraintsBeforeSecondRun = await sharedEntityConstraints(client);
      await client.query(migrationSql);

      assertCanonicalColumns(await interactionColumns(client, schema));
      await assertCanonicalSharedEntityConstraints(client);
      assert.deepEqual(
        await sharedEntityConstraints(client),
        constraintsBeforeSecondRun,
        "an already-canonical constraint must not be dropped and recreated"
      );
      const result = await client.query(`
        SELECT
          (SELECT allow_likes FROM social_story WHERE caption = 'twice') AS allow_likes,
          (SELECT updates FROM migration_update_audit) AS updates
      `);
      assert.equal(result.rows[0].allow_likes, false);
      assert.equal(result.rows[0].updates, 0);
    });
  }
);
