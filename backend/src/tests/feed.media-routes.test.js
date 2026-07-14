import assert from "node:assert/strict";
import test from "node:test";

import { feedRouter } from "../modules/feed/feed.routes.js";

/** Collect "METHOD path" strings registered on an Express router. */
function registeredRoutes(router) {
  const out = [];
  for (const layer of router.stack) {
    if (layer.route && layer.route.path) {
      const methods = Object.keys(layer.route.methods || {})
        .filter((m) => layer.route.methods[m])
        .map((m) => m.toUpperCase());
      for (const m of methods) out.push(`${m} ${layer.route.path}`);
    }
  }
  return out;
}

test("Stream media HTTP routes are registered on feedRouter", () => {
  const routes = registeredRoutes(feedRouter);
  assert.ok(
    routes.includes("POST /media/stream/upload-session"),
    "create upload-session route missing"
  );
  assert.ok(
    routes.includes("POST /media/stream/upload-session/:assetId/cancel"),
    "cancel upload-session route missing"
  );
  assert.ok(
    routes.includes("GET /media/assets/:assetId"),
    "get asset route missing"
  );
  assert.ok(
    routes.includes("POST /media/stream/webhook"),
    "webhook route missing"
  );
  assert.ok(
    routes.some((r) => r === "POST /reels"),
    "publish reel route missing"
  );
});
