/* eslint-disable no-console */
import "dotenv/config";

import { assertStatus, buildRunTag, createActor, request } from "./e2eTestUtils.js";

const DEFAULT_BASE_URL = "https://bestoffer-production.up.railway.app";

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    baseUrl: String(process.env.LOAD_BASE_URL || DEFAULT_BASE_URL).trim().replace(/\/+$/, ""),
    runTag: String(process.env.LOAD_RUN_TAG || "").trim() || buildRunTag("unused"),
  };
  for (let i = 0; i < args.length; i += 1) {
    const key = String(args[i] || "").trim();
    const next = String(args[i + 1] || "").trim();
    if (key === "--base-url" && next) {
      out.baseUrl = next.replace(/\/+$/, "");
      i += 1;
      continue;
    }
    if (key === "--run-tag" && next) {
      out.runTag = next;
      i += 1;
    }
  }
  return out;
}

async function main() {
  const cfg = parseArgs();
  const admin = createActor("load-admin-cleanup", cfg.runTag, "load-cleanup/1");
  const login = await request(cfg.baseUrl, admin, "POST", "/api/auth/login", {
    phone: process.env.SUPER_ADMIN_PHONE,
    pin: process.env.SUPER_ADMIN_PIN,
  });
  assertStatus(login, 200, "super admin login");
  admin.token = String(login.data?.token || "");

  const cleanup = await request(
    cfg.baseUrl,
    admin,
    "POST",
    "/api/admin/ops/test-artifacts/cleanup",
    { runTag: cfg.runTag }
  );
  assertStatus(cleanup, 200, "cleanup test artifacts");
  console.log(JSON.stringify(cleanup.data?.summary || cleanup.data || {}));
}

main().catch((error) => {
  console.error("[cleanup-load-fixtures] failed:", error);
  process.exitCode = 1;
});
