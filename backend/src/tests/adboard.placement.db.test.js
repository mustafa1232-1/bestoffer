// DB-backed tests for the ad_board placement engine against a loopback QA
// PostgreSQL (DATABASE_URL from .env.test). Seeds are tagged with a unique
// marker and removed in the finally block so the shared schema stays clean.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { q } from "../config/db.js";
import {
  getPublicAdBoardItems,
  incrementAdBoardImpression,
  incrementAdBoardClick,
} from "../modules/merchants/merchants.repo.js";

const MARKER = `adtest_${randomUUID().replaceAll("-", "").slice(0, 12)}`;

async function seedAd({
  title,
  placement,
  isActive = true,
  category = null,
  activityType = null,
  startsAt = null,
  endsAt = null,
  priority = 100,
}) {
  const r = await q(
    `INSERT INTO app_ad_board_item
       (title, subtitle, cta_target_type, priority, is_active, placement,
        category, activity_type, starts_at, ends_at)
     VALUES ($1,$2,'none',$3,$4,$5,$6,$7,$8,$9)
     RETURNING id`,
    [
      `${MARKER}:${title}`,
      "sub",
      priority,
      isActive,
      placement,
      category,
      activityType,
      startsAt,
      endsAt,
    ]
  );
  return Number(r.rows[0].id);
}

function mine(rows) {
  return rows.filter((row) => String(row.title || "").startsWith(`${MARKER}:`));
}

function titles(rows) {
  return mine(rows).map((row) => String(row.title).split(":")[1]);
}

test("ad_board placement engine (DB): filtering, targeting, fallback, schedule, analytics", async () => {
  const ids = {};
  try {
    ids.home = await seedAd({ title: "home", placement: "HOME_MAIN" });
    ids.mktHome = await seedAd({ title: "mkt", placement: "MARKETPLACE_HOME" });
    ids.catFashion = await seedAd({
      title: "fashion",
      placement: "MARKETPLACE_CATEGORY",
      category: "fashion",
      priority: 10,
    });
    ids.catGeneral = await seedAd({
      title: "general",
      placement: "MARKETPLACE_CATEGORY",
      priority: 200,
    });
    ids.expired = await seedAd({
      title: "expired",
      placement: "MARKETPLACE_HOME",
      startsAt: new Date(Date.now() - 2 * 86400000),
      endsAt: new Date(Date.now() - 86400000),
    });
    ids.disabled = await seedAd({
      title: "disabled",
      placement: "MARKETPLACE_HOME",
      isActive: false,
    });
    ids.scheduled = await seedAd({
      title: "scheduled",
      placement: "MARKETPLACE_HOME",
      startsAt: new Date(Date.now() + 5 * 86400000),
    });

    // --- placement filtering ---
    const homeRows = await getPublicAdBoardItems({
      type: null,
      placement: "HOME_MAIN",
    });
    assert.deepEqual(titles(homeRows), ["home"], "HOME_MAIN sees only home ad");

    const mktRows = await getPublicAdBoardItems({
      type: null,
      placement: "MARKETPLACE_HOME",
    });
    const mktTitles = titles(mktRows);
    assert.ok(mktTitles.includes("mkt"), "marketplace home ad present");
    assert.ok(!mktTitles.includes("expired"), "expired ad excluded");
    assert.ok(!mktTitles.includes("disabled"), "disabled ad excluded");
    assert.ok(!mktTitles.includes("scheduled"), "scheduled ad excluded");

    // --- category targeting + general fallback ordering ---
    const fashionRows = await getPublicAdBoardItems({
      type: null,
      placement: "MARKETPLACE_CATEGORY",
      categoryKey: "fashion",
    });
    assert.deepEqual(
      titles(fashionRows),
      ["fashion", "general"],
      "category-specific ad ranks before the general fallback"
    );

    // --- unmatched category → only the general fallback ---
    const electronicsRows = await getPublicAdBoardItems({
      type: null,
      placement: "MARKETPLACE_CATEGORY",
      categoryKey: "electronics",
    });
    assert.deepEqual(
      titles(electronicsRows),
      ["general"],
      "unmatched category sees only the general fallback"
    );

    // --- analytics counters ---
    await incrementAdBoardImpression(ids.mktHome);
    await incrementAdBoardImpression(ids.mktHome);
    await incrementAdBoardClick(ids.mktHome);
    const counts = await q(
      `SELECT impression_count, click_count FROM app_ad_board_item WHERE id=$1`,
      [ids.mktHome]
    );
    assert.equal(Number(counts.rows[0].impression_count), 2);
    assert.equal(Number(counts.rows[0].click_count), 1);
  } finally {
    await q(`DELETE FROM app_ad_board_item WHERE title LIKE $1`, [`${MARKER}:%`]);
  }
});
