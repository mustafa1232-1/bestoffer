import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { q } from "../config/db.js";
import {
  confirmOwnerDailyInventoryCheck,
  getOwnerDailyInventory,
  updateOwnerDailyInventoryItem,
} from "../modules/owner/owner.service.js";

async function seedOwnerProduct() {
  const suffix = randomUUID().replaceAll("-", "").slice(0, 12);
  const user = await q(
    `INSERT INTO app_user
       (full_name, phone, username, pin_hash, block, building_number, apartment, role)
     VALUES ($1,$2,$3,'hash','1','1','1','owner')
     RETURNING id`,
    [
      `Inventory Owner ${suffix}`,
      `770${suffix.slice(0, 8)}`,
      `inv_${suffix}`,
    ],
  );
  const ownerId = Number(user.rows[0].id);
  const merchant = await q(
    `INSERT INTO merchant
       (name, type, owner_user_id, is_open, is_approved)
     VALUES ($1,'market',$2,TRUE,TRUE)
     RETURNING id`,
    [`Inventory Store ${suffix}`, ownerId],
  );
  const merchantId = Number(merchant.rows[0].id);
  const category = await q(
    `INSERT INTO merchant_category (merchant_id, name, sort_order)
     VALUES ($1,$2,0)
     RETURNING id`,
    [merchantId, `Inventory Category ${suffix}`],
  );
  const product = await q(
    `INSERT INTO product
       (merchant_id, category_id, name, price, is_available)
     VALUES ($1,$2,$3,1000,TRUE)
     RETURNING id`,
    [merchantId, Number(category.rows[0].id), `Inventory Product ${suffix}`],
  );
  return { ownerId, merchantId, productId: Number(product.rows[0].id) };
}

async function cleanupSeed(seed) {
  if (!seed) return;
  await q(`DELETE FROM merchant WHERE id=$1`, [seed.merchantId]);
  await q(`DELETE FROM app_user WHERE id=$1`, [seed.ownerId]);
}

test("owner daily inventory disables and restores product availability from stock counts", async () => {
  let seed;
  try {
    seed = await seedOwnerProduct();

    await updateOwnerDailyInventoryItem(seed.ownerId, seed.productId, {
      quantity: 0,
      isAvailable: true,
    });

    let product = await q(`SELECT is_available FROM product WHERE id=$1`, [
      seed.productId,
    ]);
    let item = await q(
      `SELECT quantity, stock_status, auto_disabled, manual_disabled
       FROM store_inventory_item
       WHERE merchant_id=$1 AND product_id=$2`,
      [seed.merchantId, seed.productId],
    );
    let settings = await q(
      `SELECT inventory_enabled, daily_update_mode, auto_disable_out_of_stock
       FROM inventory_settings
       WHERE merchant_id=$1`,
      [seed.merchantId],
    );

    assert.equal(product.rows[0].is_available, false);
    assert.equal(Number(item.rows[0].quantity), 0);
    assert.equal(item.rows[0].stock_status, "out_of_stock");
    assert.equal(item.rows[0].auto_disabled, true);
    assert.equal(item.rows[0].manual_disabled, false);
    assert.equal(settings.rows[0].inventory_enabled, true);
    assert.equal(settings.rows[0].daily_update_mode, "strict_daily");
    assert.equal(settings.rows[0].auto_disable_out_of_stock, true);

    await updateOwnerDailyInventoryItem(seed.ownerId, seed.productId, {
      quantity: 8,
      isAvailable: true,
    });

    product = await q(`SELECT is_available FROM product WHERE id=$1`, [
      seed.productId,
    ]);
    item = await q(
      `SELECT quantity, stock_status, auto_disabled, manual_disabled
       FROM store_inventory_item
       WHERE merchant_id=$1 AND product_id=$2`,
      [seed.merchantId, seed.productId],
    );

    assert.equal(product.rows[0].is_available, true);
    assert.equal(Number(item.rows[0].quantity), 8);
    assert.equal(item.rows[0].stock_status, "in_stock");
    assert.equal(item.rows[0].auto_disabled, false);
    assert.equal(item.rows[0].manual_disabled, false);

    const check = await confirmOwnerDailyInventoryCheck(seed.ownerId);
    assert.equal(Number(check.merchantId), seed.merchantId);
    assert.ok(check.todayCheck);

    const overview = await getOwnerDailyInventory(seed.ownerId);
    const listed = overview.products.find(
      (productRow) => Number(productRow.id) === seed.productId,
    );
    assert.ok(listed);
    assert.equal(Number(listed.stock_quantity), 8);
    assert.equal(listed.track_stock, true);
  } finally {
    await cleanupSeed(seed);
  }
});
