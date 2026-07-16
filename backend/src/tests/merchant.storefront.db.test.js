// DB-backed test for the public store summary contract (storefront fields,
// zero-reviews, hasActiveOffer) against loopback QA PostgreSQL.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { q } from "../config/db.js";
import { getPublicMerchantSummary } from "../modules/merchants/merchants.service.js";

const MARKER = `storetest_${randomUUID().replaceAll("-", "").slice(0, 10)}`;

test("public store summary exposes real storefront contract with no fake fallbacks", async () => {
  let merchantId;
  try {
    const inserted = await q(
      `INSERT INTO merchant
         (name, type, is_approved, is_disabled, is_open,
          logo_url, cover_image_url, delivery_eta_min_minutes,
          delivery_eta_max_minutes, delivery_fee, minimum_order, is_verified)
       VALUES ($1,'market',TRUE,FALSE,TRUE,$2,$3,$4,$5,$6,$7,TRUE)
       RETURNING id`,
      [
        `${MARKER} store`,
        "https://cdn.example.com/logo.png",
        "https://cdn.example.com/cover.png",
        20,
        35,
        3000,
        10000,
      ]
    );
    merchantId = Number(inserted.rows[0].id);

    const summary = await getPublicMerchantSummary(merchantId);

    assert.equal(summary.logoUrl, "https://cdn.example.com/logo.png");
    assert.equal(summary.coverImageUrl, "https://cdn.example.com/cover.png");
    assert.equal(summary.deliveryEtaMinMinutes, 20);
    assert.equal(summary.deliveryEtaMaxMinutes, 35);
    assert.equal(summary.deliveryFee, 3000);
    assert.equal(summary.minimumOrder, 10000);
    assert.equal(summary.isVerified, true);
    assert.equal(summary.isOpen, true);
    // Zero-reviews store: real aggregates are 0, never a fabricated rating.
    assert.equal(summary.ratingCount, 0);
    assert.equal(summary.avgMerchantRating, 0);
    // No products / offers seeded.
    assert.equal(summary.hasActiveOffer, false);
  } finally {
    if (merchantId) {
      await q(`DELETE FROM merchant WHERE id=$1`, [merchantId]);
    }
  }
});

test("store with unset delivery fields returns null (unknown, not zero)", async () => {
  let merchantId;
  try {
    const inserted = await q(
      `INSERT INTO merchant (name, type, is_approved, is_disabled, is_open)
       VALUES ($1,'restaurant',TRUE,FALSE,FALSE)
       RETURNING id`,
      [`${MARKER} bare`]
    );
    merchantId = Number(inserted.rows[0].id);

    const summary = await getPublicMerchantSummary(merchantId);
    assert.equal(summary.deliveryEtaMinMinutes, null);
    assert.equal(summary.deliveryEtaMaxMinutes, null);
    assert.equal(summary.deliveryFee, null);
    assert.equal(summary.minimumOrder, null);
    assert.equal(summary.logoUrl, null);
    assert.equal(summary.coverImageUrl, null);
    assert.equal(summary.isVerified, false);
  } finally {
    if (merchantId) {
      await q(`DELETE FROM merchant WHERE id=$1`, [merchantId]);
    }
  }
});
