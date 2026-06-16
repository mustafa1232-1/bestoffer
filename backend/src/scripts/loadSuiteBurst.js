/* eslint-disable no-console */
import { spawn } from "node:child_process";

const DEFAULT_SCENARIOS = ["order", "taxi", "community", "jobs"];
const USERS_PER_SCENARIO = {
  order: 3,
  taxi: 2,
  community: 3,
  jobs: 2,
};
const SCRIPT_BY_SCENARIO = {
  order: "src/scripts/orderE2ECheck.js",
  taxi: "src/scripts/taxiE2ECheck.js",
  community: "src/scripts/communityE2ECheck.js",
  jobs: "src/scripts/jobsE2ECheck.js",
};

function toInt(value, fallback) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) return fallback;
  return n;
}

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    users: 1000,
    parallel: 10,
    timeoutSec: 600,
    scenarios: [...DEFAULT_SCENARIOS],
  };
  for (let i = 0; i < args.length; i += 1) {
    const key = String(args[i] || "").trim();
    const next = String(args[i + 1] || "").trim();
    if (!key.startsWith("--")) continue;
    if (key === "--users") {
      out.users = toInt(next, out.users);
      i += 1;
      continue;
    }
    if (key === "--parallel") {
      out.parallel = toInt(next, out.parallel);
      i += 1;
      continue;
    }
    if (key === "--timeout-sec") {
      out.timeoutSec = toInt(next, out.timeoutSec);
      i += 1;
      continue;
    }
    if (key === "--scenarios") {
      const chosen = next
        .split(",")
        .map((v) => String(v || "").trim().toLowerCase())
        .filter((v) => DEFAULT_SCENARIOS.includes(v));
      if (chosen.length > 0) out.scenarios = chosen;
      i += 1;
    }
  }
  return out;
}

function effectiveUsersPerSuite(scenarios) {
  return scenarios.reduce((sum, key) => sum + Number(USERS_PER_SCENARIO[key] || 0), 0);
}

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

function runScenarioOnce({ scenario, timeoutSec }) {
  const script = SCRIPT_BY_SCENARIO[scenario];
  if (!script) {
    return Promise.resolve({
      ok: false,
      code: -1,
      scenario,
      output: [`Unknown scenario: ${scenario}`],
      durationMs: 0,
    });
  }

  const startedAt = Date.now();
  const output = [];
  const env = {
    ...process.env,
    E2E_SKIP_SQL_MIGRATIONS: "true",
    E2E_SKIP_ENSURE_SCHEMA: "true",
  };

  return new Promise((resolve) => {
    let settled = false;
    const child = spawn("node", [script], {
      env,
      cwd: process.cwd(),
      stdio: ["ignore", "pipe", "pipe"],
    });

    const timeout = setTimeout(() => {
      output.push(`[timeout] scenario=${scenario} timeoutSec=${timeoutSec}`);
      child.kill("SIGKILL");
    }, Math.max(30, timeoutSec) * 1000);

    child.stdout.on("data", (chunk) => {
      output.push(String(chunk));
    });
    child.stderr.on("data", (chunk) => {
      output.push(String(chunk));
    });

    child.on("error", (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      output.push(`[spawn-error] ${String(error?.code || error?.message || error)}`);
      resolve({
        ok: false,
        code: -1,
        scenario,
        output,
        durationMs: Date.now() - startedAt,
        spawnErrorCode: String(error?.code || ""),
      });
    });

    child.on("close", (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      resolve({
        ok: Number(code) === 0,
        code: Number(code || 0),
        scenario,
        output,
        durationMs: Date.now() - startedAt,
      });
    });
  });
}

async function runScenario({ scenario, timeoutSec }) {
  const maxRetries = 3;
  let last = null;
  for (let attempt = 1; attempt <= maxRetries; attempt += 1) {
    const result = await runScenarioOnce({ scenario, timeoutSec });
    last = result;
    if (result.ok) return result;
    if (result.spawnErrorCode !== "EAGAIN" || attempt === maxRetries) {
      return result;
    }
    await sleep(300 * attempt);
  }
  return (
    last || {
      ok: false,
      code: -1,
      scenario,
      output: ["Unknown load scenario failure"],
      durationMs: 0,
    }
  );
}

async function runSuite({ suiteNo, scenarios, timeoutSec, stats }) {
  const localScenarios = [...scenarios];
  if (localScenarios.length > 1) {
    const shift = suiteNo % localScenarios.length;
    for (let i = 0; i < shift; i += 1) {
      localScenarios.push(localScenarios.shift());
    }
  }
  console.log(`[load] suite#${suiteNo} started scenarios=${localScenarios.join(",")}`);
  for (const scenario of localScenarios) {
    const result = await runScenario({ scenario, timeoutSec });
    stats.totalRuns += 1;
    if (!stats.byScenario[scenario]) {
      stats.byScenario[scenario] = { pass: 0, fail: 0, ms: 0 };
    }
    stats.byScenario[scenario].ms += result.durationMs;
    if (result.ok) {
      stats.byScenario[scenario].pass += 1;
      console.log(
        `[load] suite#${suiteNo} scenario=${scenario} PASS durationMs=${result.durationMs}`
      );
    } else {
      stats.byScenario[scenario].fail += 1;
      const tail = result.output.join("").slice(-3000);
      console.error(
        `[load] suite#${suiteNo} scenario=${scenario} FAIL code=${result.code} durationMs=${result.durationMs}\n${tail}`
      );
    }
  }
  console.log(`[load] suite#${suiteNo} finished`);
}

async function main() {
  const args = parseArgs();
  const usersPerSuite = effectiveUsersPerSuite(args.scenarios);
  const suitesNeeded = Math.ceil(args.users / Math.max(1, usersPerSuite));
  const parallel = Math.min(args.parallel, suitesNeeded);

  const stats = {
    usersTarget: args.users,
    usersPerSuite,
    suitesNeeded,
    parallel,
    totalRuns: 0,
    byScenario: {},
    startedAt: new Date().toISOString(),
  };

  console.log(
    `[load] start targetUsers=${args.users} usersPerSuite=${usersPerSuite} suites=${suitesNeeded} parallel=${parallel} timeoutSec=${args.timeoutSec}`
  );

  let nextSuite = 1;
  const workers = Array.from({ length: parallel }).map(async (_, workerIdx) => {
    for (;;) {
      const current = nextSuite;
      nextSuite += 1;
      if (current > suitesNeeded) return;
      console.log(`[load] worker#${workerIdx + 1} taking suite#${current}`);
      await runSuite({
        suiteNo: current,
        scenarios: args.scenarios,
        timeoutSec: args.timeoutSec,
        stats,
      });
    }
  });

  await Promise.all(workers);

  const computedUsers = suitesNeeded * usersPerSuite;
  const completedAt = new Date().toISOString();
  console.log("[load] completed");
  console.log(
    JSON.stringify(
      {
        ...stats,
        completedAt,
        computedUsers,
      },
      null,
      2
    )
  );
}

main().catch((error) => {
  console.error("[load] failed", error);
  process.exitCode = 1;
});
