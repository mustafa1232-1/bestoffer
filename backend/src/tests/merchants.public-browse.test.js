import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { app } from "../app.js";
import { q } from "../config/db.js";
import {
  assertStatus,
  createActor,
  request,
  startLocalServer,
  stopLocalServer,
} from "../scripts/e2eTestUtils.js";

test("public merchant browsing is not hidden by missing or outside location", async () => {
  const { server, baseUrl } = await startLocalServer(app);
  const runTag = `merchant-browse-${Date.now().toString(36)}`;
  const actor = createActor("public-browse", runTag);
  actor.appFlavor = "user";
  const marker = `browse-visible-${randomUUID()}`;
  let merchantId = null;

  try {
    const inserted = await q(
      `INSERT INTO merchant
         (name, type, activity_type, is_approved, is_disabled, is_open)
       VALUES ($1, 'market', 'supermarket', TRUE, FALSE, TRUE)
       RETURNING id`,
      [marker]
    );
    merchantId = Number(inserted.rows[0].id);

    const withoutLocation = await request(
      baseUrl,
      actor,
      "GET",
      `/api/merchants?search=${encodeURIComponent(marker)}`
    );
    assertStatus(withoutLocation, 200, "browse without location");
    assert.ok(
      withoutLocation.data.some((row) => Number(row.id) === merchantId),
      "approved stores must remain visible when the client has no GPS"
    );

    const outsideLocation = await request(
      baseUrl,
      actor,
      "GET",
      `/api/merchants?search=${encodeURIComponent(marker)}&lat=0&lng=0`
    );
    assertStatus(outsideLocation, 200, "browse outside service area");
    assert.ok(
      outsideLocation.data.some((row) => Number(row.id) === merchantId),
      "approved stores must remain visible even when browse GPS is outside"
    );
  } finally {
    if (merchantId) {
      await q(`DELETE FROM merchant WHERE id = $1`, [merchantId]).catch(
        () => {}
      );
    }
    await stopLocalServer(server);
  }
});
