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
    ids.mktHomeSecond = await seedAd({
      title: "mkt_second",
      placement: "MARKETPLACE_HOME",
      priority: 101,
    });
    ids.foodLanding = await seedAd({
      title: "food_landing",
      placement: "MARKETPLACE_CATEGORY",
      category: "food",
      priority: 20,
    });
    ids.foodLandingSecond = await seedAd({
      title: "food_landing_second",
      placement: "MARKETPLACE_CATEGORY",
      category: "food",
      priority: 21,
    });
    ids.catFashion = await seedAd({
      title: "fashion",
      placement: "MARKETPLACE_CATEGORY",
      category: "fashion",
      priority: 10,
    });
    ids.fashionActivity = await seedAd({
      title: "fashion_activity",
      placement: "MARKETPLACE_CATEGORY",
      activityType: "fashion_clothing",
      priority: 1,
    });
    ids.fashionMen = await seedAd({
      title: "fashion_men",
      placement: "MARKETPLACE_CATEGORY",
      category: "men",
      activityType: "fashion_clothing",
      priority: 100,
    });
    ids.fashionMenSecond = await seedAd({
      title: "fashion_men_second",
      placement: "MARKETPLACE_CATEGORY",
      category: "men",
      activityType: "fashion_clothing",
      priority: 101,
    });
    ids.menOtherActivity = await seedAd({
      title: "men_other_activity",
      placement: "MARKETPLACE_CATEGORY",
      category: "men",
      activityType: "home_furniture",
      priority: 1,
    });
    ids.fashionWomen = await seedAd({
      title: "fashion_women",
      placement: "MARKETPLACE_CATEGORY",
      category: "women",
      activityType: "fashion_clothing",
      priority: 100,
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
    assert.ok(
      mktTitles.includes("mkt_second"),
      "marketplace home returns every active ad for carousel rotation"
    );
    assert.ok(!mktTitles.includes("expired"), "expired ad excluded");
    assert.ok(!mktTitles.includes("disabled"), "disabled ad excluded");
    assert.ok(!mktTitles.includes("scheduled"), "scheduled ad excluded");

    const foodLandingRows = await getPublicAdBoardItems({
      type: null,
      placement: "MARKETPLACE_CATEGORY",
      categoryKey: "food",
    });
    assert.deepEqual(
      titles(foodLandingRows),
      ["food_landing", "food_landing_second", "general"],
      "sub-market landing pages return all ads for their category key"
    );

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

    // --- department/category targeting is isolated for men/women fashion ---
    const fashionMenRows = await getPublicAdBoardItems({
      type: null,
      placement: "MARKETPLACE_CATEGORY",
      categoryKey: "men",
      activityType: "fashion_clothing",
    });
    assert.deepEqual(
      titles(fashionMenRows),
      ["fashion_men", "fashion_men_second", "general"],
      "men fashion sees only men-specific ads and the general fallback"
    );

    const fashionWomenRows = await getPublicAdBoardItems({
      type: null,
      placement: "MARKETPLACE_CATEGORY",
      categoryKey: "women",
      activityType: "fashion_clothing",
    });
    assert.deepEqual(
      titles(fashionWomenRows),
      ["fashion_women", "general"],
      "women fashion sees only women-specific ads and the general fallback"
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
