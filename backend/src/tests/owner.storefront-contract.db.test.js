// DB-backed round-trip tests for the owner merchant storefront contract against
// loopback QA PostgreSQL. Proves mapMerchant + repo select/update expose the new
// fields, ETA/fee/min persist, logo/cover set + clear, and null stays null.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { q } from "../config/db.js";
import {
  findMerchantByOwnerUserId,
  updateOwnerMerchant,
} from "../modules/owner/owner.repo.js";
import { mapMerchant } from "../modules/owner/owner.service.js";

const MARKER = `ownertest_${randomUUID().replaceAll("-", "").slice(0, 10)}`;

async function seedOwnerWithMerchant(storefront) {
  const phone = `0790${Math.abs(hash(MARKER)) % 10000000}`.slice(0, 11);
  const user = await q(
    `INSERT INTO app_user
       (full_name, phone, pin_hash, block, building_number, apartment, username, role)
     VALUES ($1,$2,'x','1','1','1',$3,'owner') RETURNING id`,
    [`${MARKER} owner`, phone, `${MARKER}_u`]
  );
  const ownerId = Number(user.rows[0].id);
  const m = await q(
    `INSERT INTO merchant
       (name, type, is_approved, is_disabled, is_open, owner_user_id,
        logo_url, cover_image_url, delivery_eta_min_minutes,
        delivery_eta_max_minutes, delivery_fee, minimum_order, is_verified)
     VALUES ($1,'market',TRUE,FALSE,TRUE,$2,$3,$4,$5,$6,$7,$8,$9)
     RETURNING id`,
    [
      `${MARKER} store`,
      ownerId,
      storefront.logoUrl ?? null,
      storefront.coverImageUrl ?? null,
      storefront.etaMin ?? null,
      storefront.etaMax ?? null,
      storefront.fee ?? null,
      storefront.minOrder ?? null,
      storefront.verified ?? false,
    ]
  );
  return { ownerId, merchantId: Number(m.rows[0].id) };
}

function hash(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return h;
}

async function cleanup(ownerId) {
  await q(`DELETE FROM merchant WHERE owner_user_id=$1`, [ownerId]);
  await q(`DELETE FROM app_user WHERE id=$1`, [ownerId]);
}

test("owner merchant contract: get/update/upload/refresh/clear/null-stays-null", async () => {
  const { ownerId } = await seedOwnerWithMerchant({
    logoUrl: "https://cdn.example.com/l.png",
    coverImageUrl: "https://cdn.example.com/c.png",
    etaMin: 15,
    etaMax: 25,
    fee: 2000,
    minOrder: 8000,
    verified: true,
  });
  try {
    // 1. get returns all storefront fields
    const got = mapMerchant(await findMerchantByOwnerUserId(ownerId));
    assert.equal(got.logoUrl, "https://cdn.example.com/l.png");
    assert.equal(got.coverImageUrl, "https://cdn.example.com/c.png");
    assert.equal(got.deliveryEtaMinMinutes, 15);
    assert.equal(got.deliveryEtaMaxMinutes, 25);
    assert.equal(got.deliveryFee, 2000);
    assert.equal(got.minimumOrder, 8000);
    assert.equal(got.isVerified, true);

    // 2. update ETA/fee/min → response reflects new values
    const updated = mapMerchant(
      await updateOwnerMerchant(ownerId, {
        deliveryEtaMinMinutes: 20,
        deliveryEtaMaxMinutes: 30,
        deliveryFee: 3000,
        minimumOrder: 10000,
      })
    );
    assert.equal(updated.deliveryEtaMinMinutes, 20);
    assert.equal(updated.deliveryEtaMaxMinutes, 30);
    assert.equal(updated.deliveryFee, 3000);
    assert.equal(updated.minimumOrder, 10000);

    // 3. "upload" logo/cover (URL) → response returns both
    const withImages = mapMerchant(
      await updateOwnerMerchant(ownerId, {
        logoUrl: "https://cdn.example.com/l2.png",
        coverImageUrl: "https://cdn.example.com/c2.png",
      })
    );
    assert.equal(withImages.logoUrl, "https://cdn.example.com/l2.png");
    assert.equal(withImages.coverImageUrl, "https://cdn.example.com/c2.png");

    // 4. refresh GET returns the same persisted values
    const refreshed = mapMerchant(await findMerchantByOwnerUserId(ownerId));
    assert.equal(refreshed.logoUrl, "https://cdn.example.com/l2.png");
    assert.equal(refreshed.deliveryEtaMinMinutes, 20);
    assert.equal(refreshed.deliveryFee, 3000);

    // 6. clear logo/cover (empty → null via repo NULL patch)
    const cleared = mapMerchant(
      await updateOwnerMerchant(ownerId, { logoUrl: null, coverImageUrl: null })
    );
    assert.equal(cleared.logoUrl, null);
    assert.equal(cleared.coverImageUrl, null);
  } finally {
    await cleanup(ownerId);
  }
});

test("null delivery fields stay null (never coerced to 0)", async () => {
  const { ownerId } = await seedOwnerWithMerchant({});
  try {
    const got = mapMerchant(await findMerchantByOwnerUserId(ownerId));
    assert.equal(got.logoUrl, null);
    assert.equal(got.coverImageUrl, null);
    assert.equal(got.deliveryEtaMinMinutes, null);
    assert.equal(got.deliveryEtaMaxMinutes, null);
    assert.equal(got.deliveryFee, null);
    assert.equal(got.minimumOrder, null);
    assert.equal(got.isVerified, false);
    assert.equal(got.nextOpenAt, null);
  } finally {
    await cleanup(ownerId);
  }
});
