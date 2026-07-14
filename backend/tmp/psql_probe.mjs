import { spawnSync } from "child_process";
const url = process.env.DATABASE_URL || "";
const m = url.match(/^postgres(?:ql)?:\/\/([^:]+):([^@]+)@([^:]+):(\d+)\/([^?]+)/);
if (!m) { console.log("URL parse fail"); process.exit(1); }
const [, user, pass, host, port, db] = m;
const baseEnv = { ...process.env, PGPASSWORD: pass, PGCONNECT_TIMEOUT: "12" };
for (const sslmode of ["require", "prefer", "disable"]) {
  const env = { ...baseEnv, PGSSLMODE: sslmode };
  const r = spawnSync("psql", ["-h", host, "-p", port, "-U", user, "-d", db, "-w", "-tAc", "select 1 as ok, now()"], { env, encoding: "utf8", timeout: 20000 });
  console.log(`--- sslmode=${sslmode} exit=${r.status} ---`);
  if (r.stdout) console.log("STDOUT:", r.stdout.trim());
  if (r.stderr) console.log("STDERR:", r.stderr.trim().slice(0, 400));
  if (r.status === 0) { console.log("WORKING_SSLMODE:", sslmode); break; }
}
