/* eslint-disable no-console */
import { spawn } from "node:child_process";

const steps = [
  { label: "realtime-runtime", script: "realtime:runtime:check" },
  { label: "security", script: "security:runtime:check" },
  { label: "auth-session-push", script: "auth:session:push:check" },
  { label: "new-streams", script: "e2e:new-streams:check" },
  { label: "order", script: "e2e:order:check" },
  { label: "taxi", script: "e2e:taxi:check" },
  { label: "community", script: "e2e:community:check" },
  { label: "services", script: "e2e:services:check" },
  { label: "jobs", script: "e2e:jobs:check" },
  { label: "pharmacy", script: "e2e:pharmacy:check" },
];

const transientPatterns = [
  /timeout exceeded when trying to connect/i,
  /connection terminated due to connection timeout/i,
  /connection terminated unexpectedly/i,
  /query read timeout/i,
  /econnreset/i,
  /terminat(?:ed|ion).*timeout/i,
];

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isTransientFailure(output) {
  const text = String(output || "");
  return transientPatterns.some((pattern) => pattern.test(text));
}

function runStep(step) {
  return new Promise((resolve, reject) => {
    const npmExecPath = String(process.env.npm_execpath || "").trim();
    const command = npmExecPath ? process.execPath : process.platform === "win32" ? "npm.cmd" : "npm";
    const args = npmExecPath ? [npmExecPath, "run", step.script] : ["run", step.script];
    const child = spawn(command, args, {
      cwd: process.cwd(),
      env: {
        ...process.env,
        ...(process.env.RAILWAY_SERVICE_NAME ||
        process.env.RAILWAY_ENVIRONMENT_NAME
          ? { ALLOW_E2E_PRODUCTION_TARGET: "true" }
          : {}),
      },
      stdio: ["ignore", "pipe", "pipe"],
    });

    let combined = "";

    child.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      combined += text;
      process.stdout.write(text);
    });

    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      combined += text;
      process.stderr.write(text);
    });

    child.on("error", reject);
    child.on("close", (code) => {
      resolve({
        code: Number(code || 0),
        combined,
      });
    });
  });
}

async function main() {
  for (const step of steps) {
    let attempt = 1;
    const maxAttempts = 2;
    while (attempt <= maxAttempts) {
      if (attempt > 1) {
        console.warn(
          `[verify-release-runtime] retrying ${step.label} after transient failure (attempt ${attempt}/${maxAttempts})`
        );
      }

      const result = await runStep(step);
      if (result.code === 0) break;

      if (attempt < maxAttempts && isTransientFailure(result.combined)) {
        attempt += 1;
        await sleep(5000);
        continue;
      }

      process.exit(result.code || 1);
    }
  }

  console.log("[verify-release-runtime] all runtime checks passed");
}

main().catch((error) => {
  console.error("[verify-release-runtime] failed", error);
  process.exit(1);
});
