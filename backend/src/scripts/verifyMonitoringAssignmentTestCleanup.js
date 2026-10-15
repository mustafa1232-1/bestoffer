import { pool } from "../config/db.js";

const MARK = "fx_mon_asg_%";

async function count(query) {
  const result = await pool.query(query, [MARK]);
  return Number(result.rows[0]?.count || 0);
}

async function main() {
  const [users, orders, merchants, assignments, notifications] =
    await Promise.all([
      count("SELECT COUNT(*)::int AS count FROM app_user WHERE username LIKE $1"),
      count(
        "SELECT COUNT(*)::int AS count FROM customer_order WHERE customer_full_name LIKE $1"
      ),
      count("SELECT COUNT(*)::int AS count FROM merchant WHERE name LIKE $1"),
      count(
        `SELECT COUNT(*)::int AS count
           FROM courier_assignment
          WHERE courier_user_id IN (
            SELECT id FROM app_user WHERE username LIKE $1
          )
             OR order_id IN (
            SELECT id FROM customer_order WHERE customer_full_name LIKE $1
          )`
      ),
      count(
        `SELECT COUNT(*)::int AS count
           FROM app_notification
          WHERE user_id IN (
            SELECT id FROM app_user WHERE username LIKE $1
          )`
      ),
    ]);

  console.log(
    JSON.stringify(
      { marker: MARK, users, orders, merchants, assignments, notifications },
      null,
      2
    )
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
