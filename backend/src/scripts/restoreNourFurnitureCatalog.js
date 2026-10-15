import "dotenv/config";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { pool } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";
import { invalidateMerchantCatalogCache } from "../modules/merchants/merchants.repo.js";

const merchantId = 22;
const categoryId = 268;
const productIds = [1727, 1731, 1736, 1740, 1743, 1747, 1750, 1754, 1757, 1760, 1762, 1764];
const expectedName = "\u0634\u0631\u0643\u0629 \u0627\u0644\u0646\u0648\u0631 \u0644\u0644\u0627\u062b\u0627\u062b \u0627\u0644\u062a\u0631\u0643\u064a";
const apply = process.argv.includes("--apply");
let client;
try {
  client = await pool.connect();
  await client.query("BEGIN");
  const merchant = (await client.query(
    "SELECT id, name, activity_type FROM merchant WHERE id=$1 FOR UPDATE", [merchantId])).rows[0];
  if (merchant?.name !== expectedName || merchant.activity_type !== "home_furniture") {
    throw new Error("MERCHANT_IDENTITY_MISMATCH");
  }
  const category = (await client.query(
    "SELECT * FROM merchant_category WHERE id=$1 AND merchant_id=$2 FOR UPDATE", [categoryId, merchantId])).rows[0];
  if (!category || !["electronics", "furniture"].includes(category.catalog_type)) {
    throw new Error("CATEGORY_STATE_CHANGED");
  }
  const products = (await client.query(
    "SELECT * FROM product WHERE merchant_id=$1 AND id=ANY($2::bigint[]) ORDER BY id FOR UPDATE",
    [merchantId, productIds])).rows;
  if (products.length !== productIds.length || products.some((p) => Number(p.category_id) !== categoryId)) {
    throw new Error("PRODUCT_SET_CHANGED");
  }
  console.log(JSON.stringify({ apply, merchantId, products: products.length,
    deleted: products.filter((p) => p.deleted_at != null).length,
    categoryBefore: category.catalog_type }));
  if (apply) {
    const workspace = fileURLToPath(new URL("../../../", import.meta.url));
    const backupDirectory = path.join(workspace, "output", "db-backups");
    await mkdir(backupDirectory, { recursive: true });
    const backupPath = path.join(backupDirectory, `nour-furniture-${Date.now()}.json`);
    await writeFile(backupPath, JSON.stringify({ merchant, category, products }, null, 2), { flag: "wx" });
    const restored = await client.query(`UPDATE product SET deleted_at=NULL, is_available=TRUE,
      unavailable_reason=NULL, unavailable_until=NULL, updated_at=NOW()
      WHERE merchant_id=$1 AND id=ANY($2::bigint[]) RETURNING id`, [merchantId, productIds]);
    if (restored.rowCount !== productIds.length) throw new Error("RESTORE_COUNT_MISMATCH");
    await client.query(`UPDATE merchant_category SET catalog_type='furniture', is_active=TRUE,
      updated_at=NOW() WHERE id=$1 AND merchant_id=$2`, [categoryId, merchantId]);
    await client.query("COMMIT");
    await invalidateMerchantCatalogCache(merchantId);
    console.log(JSON.stringify({ restoredIds: restored.rows.map((row) => Number(row.id)), backupPath }));
  } else {
    await client.query("ROLLBACK");
  }
} catch (error) {
  if (client) await client.query("ROLLBACK").catch(() => {});
  console.error(error.code || "RESTORE_FAILED", error.message);
  process.exitCode = 1;
} finally {
  client?.release();
  await closeRedisClient().catch(() => {});
  await pool.end();
}
