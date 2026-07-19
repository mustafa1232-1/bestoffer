import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { q } from "../config/db.js";
import {
  validateCouponByCode,
  validateCouponByIdOrCode,
} from "../modules/coupons/coupons.repo.js";

const MARK = `cv_${randomUUID().replaceAll("-", "").slice(0, 6)}`;

function numericSuffix(input, length = 7) {
  const digits = String(input)
    .replace(/[^0-9a-f]/gi, "")
    .slice(0, 12)
    .toUpperCase();
  const asNumber = BigInt(`0x${digits || "1"}`).toString();
  return asNumber.slice(-length).padStart(length, "0");
}

async function cleanup({ ownerId, merchantId, customerId, couponId }) {
  if (couponId) {
    await q(`DELETE FROM coupon_redemption WHERE coupon_id = $1`, [couponId]).catch(
      () => {}
    );
    await q(`DELETE FROM company_coupon_target WHERE coupon_id = $1`, [couponId]).catch(
      () => {}
    );
    await q(`DELETE FROM coupon WHERE id = $1`, [couponId]).catch(() => {});
  }
  if (merchantId) {
    await q(`DELETE FROM merchant WHERE id = $1`, [merchantId]).catch(() => {});
  }
  if (customerId) {
    await q(`DELETE FROM app_user WHERE id = $1`, [customerId]).catch(() => {});
  }
  if (ownerId) {
    await q(`DELETE FROM app_user WHERE id = $1`, [ownerId]).catch(() => {});
  }
}

async function seedFixture() {
  const ownerRow = await q(
    `INSERT INTO app_user
       (full_name, phone, pin_hash, block, building_number, apartment, username, role)
     VALUES ($1,$2,'x','A','1','1',$3,'owner')
     RETURNING id`,
    [`${MARK} owner`, `079${numericSuffix(MARK, 7)}`, `${MARK}_owner`]
  );
  const ownerId = Number(ownerRow.rows[0].id);

  const merchantRow = await q(
    `INSERT INTO merchant
       (name, type, is_approved, is_disabled, is_open, owner_user_id)
     VALUES ($1,'market',TRUE,FALSE,TRUE,$2)
     RETURNING id`,
    [`${MARK} store`, ownerId]
  );
  const merchantId = Number(merchantRow.rows[0].id);

  const customerRow = await q(
    `INSERT INTO app_user
       (full_name, phone, pin_hash, block, building_number, apartment, username, role)
     VALUES ($1,$2,'x','A','1','1',$3,'user')
     RETURNING id`,
    [`${MARK} customer`, `078${numericSuffix(`${MARK}_customer`, 7)}`, `${MARK}_customer`]
  );
  const customerId = Number(customerRow.rows[0].id);

  const couponRow = await q(
    `INSERT INTO coupon
       (code, description, discount_type, discount_value, min_order_total,
        max_uses, merchant_id, scope_kind, valid_from, valid_until, created_by)
     VALUES ($1,$2,'percent',10,0,NULL,$3,'merchant',NULL,NULL,$4)
     RETURNING id, code`,
    [`${MARK.toUpperCase()}10`, `${MARK} coupon`, merchantId, ownerId]
  );
  const couponId = Number(couponRow.rows[0].id);
  const couponCode = String(couponRow.rows[0].code);

  return { ownerId, merchantId, customerId, couponId, couponCode };
}

test("coupon validation resolves merchant coupon without SQL parameter errors", async (t) => {
  const fixture = await seedFixture();
  t.after(async () => {
    await cleanup(fixture).catch(() => {});
  });

  const byCode = await validateCouponByCode(fixture.couponCode, {
    customerId: fixture.customerId,
    merchantId: fixture.merchantId,
    orderTotal: 15000,
  });

  assert.ok(byCode.coupon);
  assert.equal(byCode.reasonCode, null);
  assert.equal(Number(byCode.coupon.id), fixture.couponId);

  const byId = await validateCouponByIdOrCode(
    { couponId: fixture.couponId },
    {
      customerId: fixture.customerId,
      merchantId: fixture.merchantId,
      orderTotal: 15000,
    }
  );

  assert.ok(byId.coupon);
  assert.equal(byId.reasonCode, null);
  assert.equal(Number(byId.coupon.id), fixture.couponId);
});
