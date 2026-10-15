// Read-only deployment diagnostics. Never prints credentials or user records.
import { pool } from "../config/db.js";
import { env } from "../config/env.js";

const report = {
  livekitConfigured: Boolean(env.livekitUrl && env.livekitApiKey && env.livekitApiSecret),
};
let client;
try {
  client = await pool.connect();
  await client.query("BEGIN READ ONLY");
  await client.query("SET LOCAL statement_timeout = '5s'");
  const schema = await client.query(`SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='social_call_session'
      AND column_name='voice_transport'
  ) AS "transportColumn", to_regclass('public.social_call_voice_cleanup') IS NOT NULL AS "cleanupTable"`);
  Object.assign(report, schema.rows[0]);
  if (report.transportColumn) {
    const recent = await client.query(`SELECT voice_transport AS transport, status, count(*)::int AS count
      FROM social_call_session WHERE created_at >= NOW() - INTERVAL '7 days'
      GROUP BY voice_transport, status ORDER BY voice_transport, status`);
    report.lastSevenDays = recent.rows;
  }
  await client.query("ROLLBACK");
  console.log(JSON.stringify(report));
} catch (error) {
  console.log(JSON.stringify({ ...report, diagnosticError: error.code || "CONNECTION_FAILED" }));
  process.exitCode = 1;
} finally {
  client?.release();
  await pool.end();
}
