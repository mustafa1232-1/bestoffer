/* eslint-disable no-console */
import "dotenv/config";

import { q } from "../config/db.js";

async function run() {
  const result = await q(
    `SELECT
       u.id,
       u.username,
       u.full_name,
       u.phone,
       u.role,
       u.delivery_account_approved,
       EXISTS (
         SELECT 1 FROM courier_profile cp WHERE cp.user_id = u.id
       ) AS has_courier_profile,
       EXISTS (
         SELECT 1 FROM taxi_captain_profile tcp WHERE tcp.user_id = u.id
       ) AS has_taxi_captain_profile
     FROM app_user u
     WHERE (
       u.role = 'delivery'
       AND EXISTS (
         SELECT 1 FROM taxi_captain_profile tcp WHERE tcp.user_id = u.id
       )
     ) OR (
       u.role = 'taxi_captain'
       AND EXISTS (
         SELECT 1 FROM courier_profile cp WHERE cp.user_id = u.id
       )
     )
     ORDER BY u.id`
  );

  console.log(
    JSON.stringify(
      {
        count: result.rowCount || 0,
        accounts: result.rows,
      },
      null,
      2
    )
  );
}

run().catch((error) => {
  console.error("[identity-audit] failed:", error?.message || error);
  process.exitCode = 1;
});
