import "dotenv/config";

import { pool, q } from "../config/db.js";
import { closeRedisClient } from "../config/redis.js";

const search = String(process.argv.slice(2).join(" ") || "").trim();
if (!search) {
  console.error("Usage: node src/scripts/findMerchantOwnerByName.js <name>");
  process.exitCode = 2;
} else {
  try {
    const result = await q(
      `SELECT
         u.id,
         u.full_name,
         u.phone,
         u.role,
         COALESCE(u.is_account_disabled, FALSE) AS is_account_disabled,
         COALESCE(u.must_change_pin, FALSE) AS must_change_pin,
         COALESCE(
           json_agg(
             json_build_object('id', m.id, 'name', m.name)
             ORDER BY m.id
           ) FILTER (WHERE m.id IS NOT NULL),
           '[]'::json
         ) AS merchants
       FROM app_user u
       LEFT JOIN merchant m ON m.owner_user_id = u.id
       WHERE u.full_name ILIKE ('%' || $1 || '%')
          OR m.name ILIKE ('%' || $1 || '%')
       GROUP BY u.id
       ORDER BY u.id`,
      [search],
    );
    console.log(JSON.stringify({ search, matches: result.rows }, null, 2));
  } finally {
    await closeRedisClient().catch(() => {});
    await pool.end().catch(() => {});
  }
}
