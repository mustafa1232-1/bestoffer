import pg from "pg";
const url = process.env.DATABASE_URL;
async function tryMode(name, ssl) {
  const c = new pg.Client({ connectionString: url, ssl, connectionTimeoutMillis: 12000 });
  try {
    await c.connect();
    const r = await c.query("select now() as now");
    console.log(`[${name}] OK`, r.rows[0].now);
    await c.end();
    return true;
  } catch (e) {
    console.log(`[${name}] FAIL`, e.code || "", (e.message || "").slice(0, 120));
    try { await c.end(); } catch {}
    return false;
  }
}
const modes = [
  ["ssl_false", false],
  ["ssl_reject_false", { rejectUnauthorized: false }],
  ["ssl_require", { require: true, rejectUnauthorized: false }],
];
for (const [n, s] of modes) {
  const ok = await tryMode(n, s);
  if (ok) { console.log("WORKING_MODE:", n); break; }
}
process.exit(0);
