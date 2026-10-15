import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

import { pool, q } from "../config/db.js";
import {
  listCustomerCoupons,
  validateCouponByCode,
  validateCouponByIdOrCode,
} from "../modules/coupons/coupons.repo.js";
import { consumeCouponRedemptionByOrderTx } from "../modules/orders/order-incentives.repo.js";

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
    await q(`DELETE FROM customer_order WHERE merchant_id = $1`, [merchantId]).catch(
      () => {}
    );
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

async function createCouponTestOrder({ merchantId, customerId, couponId, couponCode }) {
  const row = await q(
    `INSERT INTO customer_order
       (
         merchant_id,
         customer_user_id,
         customer_full_name,
         customer_phone,
         customer_block,
         customer_building_number,
         customer_apartment,
         subtotal,
         coupon_id,
         coupon_code,
         coupon_discount_total,
         total_amount
       )
     VALUES ($1,$2,$3,$4,'A','1','1',10000,$5,$6,1000,9500)
     RETURNING id`,
    [
      Number(merchantId),
      Number(customerId),
      `${MARK} customer`,
      `078${numericSuffix(`${MARK}_order`, 7)}`,
      Number(couponId),
      couponCode,
    ]
  );
  return Number(row.rows[0].id);
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

test("coupon consumption allows the same customer until max uses is reached", async (t) => {
  const fixture = await seedFixture();
  t.after(async () => {
    await cleanup(fixture).catch(() => {});
  });
  await q(`UPDATE coupon SET max_uses = 10 WHERE id = $1`, [fixture.couponId]);

  for (let i = 0; i < 10; i += 1) {
    const orderId = await createCouponTestOrder(fixture);
    const client = await pool.connect();
    try {
      await client.query(`BEGIN`);
      await consumeCouponRedemptionByOrderTx(client, {
        couponId: fixture.couponId,
        customerId: fixture.customerId,
        orderId,
        discountAmount: 1000,
      });
      await client.query(`COMMIT`);
    } catch (error) {
      await client.query(`ROLLBACK`);
      throw error;
    } finally {
      client.release();
    }
  }

  const eleventhOrderId = await createCouponTestOrder(fixture);
  const client = await pool.connect();
  try {
    await client.query(`BEGIN`);
    await assert.rejects(
      () =>
        consumeCouponRedemptionByOrderTx(client, {
          couponId: fixture.couponId,
          customerId: fixture.customerId,
          orderId: eleventhOrderId,
          discountAmount: 1000,
        }),
      /COUPON_INVALID_OR_EXPIRED/
    );
    await client.query(`ROLLBACK`);
  } catch (error) {
    await client.query(`ROLLBACK`);
    throw error;
  } finally {
    client.release();
  }

  const counts = await q(
    `SELECT
       c.uses_count,
       COUNT(cr.id)::int AS redemptions
     FROM coupon c
     LEFT JOIN coupon_redemption cr
       ON cr.coupon_id = c.id
      AND COALESCE(cr.is_void, FALSE) = FALSE
     WHERE c.id = $1
     GROUP BY c.id`,
    [fixture.couponId]
  );
  assert.equal(Number(counts.rows[0].uses_count), 10);
  assert.equal(Number(counts.rows[0].redemptions), 10);
});

test("coupon validation remains usable after one redemption until the total limit", async (t) => {
  const fixture = await seedFixture();
  t.after(async () => {
    await cleanup(fixture).catch(() => {});
  });
  await q(`UPDATE coupon SET max_uses = 10 WHERE id = $1`, [fixture.couponId]);

  const orderId = await createCouponTestOrder(fixture);
  const client = await pool.connect();
  try {
    await client.query(`BEGIN`);
    await consumeCouponRedemptionByOrderTx(client, {
      couponId: fixture.couponId,
      customerId: fixture.customerId,
      orderId,
      discountAmount: 1000,
    });
    await client.query(`COMMIT`);
  } catch (error) {
    await client.query(`ROLLBACK`);
    throw error;
  } finally {
    client.release();
  }

  const validated = await validateCouponByCode(fixture.couponCode, {
    customerId: fixture.customerId,
    merchantId: fixture.merchantId,
    orderTotal: 15000,
  });
  assert.ok(validated.coupon);
  assert.equal(validated.reasonCode, null);
  assert.equal(Number(validated.coupon.uses_count), 1);
  assert.equal(Number(validated.coupon.max_uses), 10);

  const visibleCoupons = await listCustomerCoupons({
    customerId: fixture.customerId,
    merchantId: fixture.merchantId,
    limit: 20,
  });
  assert.ok(
    visibleCoupons.some((coupon) => Number(coupon.id) === fixture.couponId)
  );
});
