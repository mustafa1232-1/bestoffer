import "dotenv/config";
import { pool } from "../config/db.js";

const search = process.argv[2] || "\u0627\u0644\u0646\u0648\u0631";
try {
  const merchants = await pool.query(`SELECT id, name, type, is_approved, is_disabled, is_open,
    approval_status FROM merchant WHERE name ILIKE $1 ORDER BY id LIMIT 20`, [`%${search}%`]);
  console.log(JSON.stringify({ merchants: merchants.rows }));
  for (const merchant of merchants.rows) {
    const params = [merchant.id];
    const products = await pool.query(`SELECT id, name, category_id, is_available,
      deleted_at
      FROM product WHERE merchant_id=$1 ORDER BY id LIMIT 150`, params);
    const categories = await pool.query(`SELECT id, name, is_active, catalog_type
      FROM merchant_category WHERE merchant_id=$1 ORDER BY id`, params);
    const settings = await pool.query(`SELECT * FROM inventory_settings WHERE merchant_id=$1`, params);
    const inventory = await pool.query(`SELECT product_id, quantity, stock_status, manual_disabled, auto_disabled
      FROM store_inventory_item WHERE merchant_id=$1 ORDER BY product_id LIMIT 150`, params);
    console.log(JSON.stringify({ merchantId: merchant.id, products: products.rows,
      categories: categories.rows, inventorySettings: settings.rows, inventory: inventory.rows }));
  }
} catch (error) {
  console.error(error.code, error.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
