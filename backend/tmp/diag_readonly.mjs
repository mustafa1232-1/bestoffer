// READ-ONLY production diagnostic. No writes. No app imports.
import pg from "pg";

const url = process.env.DATABASE_URL;
if (!url) {
  console.error("NO DATABASE_URL");
  process.exit(2);
}
const host = url.replace(/\/\/[^:]+:[^@]+@/, "//***:***@");
console.log("DB target:", host.split("@")[1] || "(hidden)");

const isLocal = /@(127\.0\.0\.1|localhost)[:/]/.test(url);
const pool = new pg.Pool({
  connectionString: url,
  ssl: isLocal ? false : { rejectUnauthorized: false },
  max: 2,
  statement_timeout: 20000,
  query_timeout: 20000,
  connectionTimeoutMillis: 15000,
});

async function safe(label, text, params = []) {
  try {
    const r = await pool.query(text, params);
    console.log(`\n===== ${label} =====`);
    console.table ? console.table(r.rows) : console.log(r.rows);
    if (!r.rows.length) console.log("(0 rows)");
    return r.rows;
  } catch (e) {
    console.log(`\n===== ${label} =====`);
    console.log("ERROR:", e.code || "", e.message);
    return null;
  }
}

async function main() {
  await safe("CONNECT", "SELECT now() AS now, current_database() AS db, version()");

  await safe(
    "TABLES_EXIST",
    `SELECT table_name FROM information_schema.tables
     WHERE table_schema='public'
       AND table_name IN (
         'app_user','customer_order','courier_assignment','courier_presence',
         'courier_profile','taxi_captain_profile','taxi_captain_presence',
         'merchant_delivery_agent','courier_daily_stats','delivery_dispatch_policy',
         'realtime_outbox','notification_outbox','app_notification')
     ORDER BY table_name`
  );

  await safe(
    "APP_USER_ROLE_COUNTS",
    `SELECT role, count(*) AS n,
            count(*) FILTER (WHERE delivery_account_approved) AS approved,
            count(*) FILTER (WHERE is_account_disabled) AS disabled
     FROM app_user GROUP BY role ORDER BY n DESC`
  );

  await safe(
    "ROLE_ENUM_LABELS",
    `SELECT e.enumlabel FROM pg_type t JOIN pg_enum e ON t.oid=e.enumtypid
     WHERE t.typname='user_role' ORDER BY e.enumsortorder`
  );

  // customer_order key columns
  await safe(
    "CUSTOMER_ORDER_COLS",
    `SELECT column_name, data_type, column_default, is_nullable
     FROM information_schema.columns
     WHERE table_schema='public' AND table_name='customer_order'
       AND column_name IN (
         'delivery_assignment_status','delivery_user_id','assigned_by_store',
         'is_merchant_delivery','courier_requested_at','courier_assigned_at',
         'prepared_at','preparing_started_at','approved_at','status','fulfillment_type',
         'delivery_method','requires_delivery','delivery_type','delivery_mode')
     ORDER BY column_name`
  );

  await safe(
    "COURIER_ASSIGNMENT_COLS",
    `SELECT column_name, data_type, column_default, is_nullable
     FROM information_schema.columns
     WHERE table_schema='public' AND table_name='courier_assignment'
     ORDER BY ordinal_position`
  );

  await safe(
    "COURIER_PRESENCE_COLS",
    `SELECT column_name, data_type, column_default, is_nullable
     FROM information_schema.columns
     WHERE table_schema='public' AND table_name='courier_presence'
     ORDER BY ordinal_position`
  );

  await safe(
    "COURIER_PROFILE_COLS",
    `SELECT column_name, data_type
     FROM information_schema.columns
     WHERE table_schema='public' AND table_name='courier_profile'
     ORDER BY ordinal_position`
  );

  // How many delivery-model accounts exist and their profile shape
  await safe(
    "DELIVERY_ACCOUNTS_SHAPE",
    `SELECT
        u.role,
        count(*) AS n,
        count(*) FILTER (WHERE u.delivery_account_approved) AS approved,
        count(*) FILTER (WHERE u.is_account_disabled) AS disabled,
        count(cp.user_id) AS has_courier_profile,
        count(tcp.user_id) AS has_taxi_captain_profile
     FROM app_user u
     LEFT JOIN courier_profile cp ON cp.user_id=u.id
     LEFT JOIN taxi_captain_profile tcp ON tcp.user_id=u.id
     WHERE u.role IN ('delivery','courier','delivery_driver','driver','taxi_captain')
     GROUP BY u.role ORDER BY n DESC`
  );

  // courier_profile availability distribution
  await safe(
    "COURIER_PROFILE_AVAILABILITY",
    `SELECT COALESCE(LOWER(availability_status),'(null)') AS availability, COALESCE(driver_type,'(null)') AS driver_type, count(*) AS n
     FROM courier_profile GROUP BY 1,2 ORDER BY n DESC`
  );

  // presence freshness
  await safe(
    "COURIER_PRESENCE_FRESHNESS",
    `SELECT
        count(*) AS total_rows,
        count(*) FILTER (WHERE is_online) AS online_rows,
        count(*) FILTER (WHERE updated_at >= now() - interval '90 seconds') AS fresh_90s,
        count(*) FILTER (WHERE updated_at >= now() - interval '10 minutes') AS fresh_10m,
        max(updated_at) AS most_recent_update
     FROM courier_presence`
  );

  await safe(
    "COURIER_PRESENCE_RECENT",
    `SELECT p.courier_user_id, u.role, u.full_name, p.is_online, p.updated_at,
            round(extract(epoch from (now()-p.updated_at)))::int AS age_s
     FROM courier_presence p LEFT JOIN app_user u ON u.id=p.courier_user_id
     ORDER BY p.updated_at DESC NULLS LAST LIMIT 15`
  );

  // EXACT eligibility (order-independent) mirroring lockEligibleCourierCandidateTx
  await safe(
    "ELIGIBLE_DRIVERS_NOW",
    `SELECT u.id, u.role, u.full_name,
            u.delivery_account_approved AS approved, u.is_account_disabled AS disabled,
            cp.availability_status,
            EXISTS(SELECT 1 FROM courier_presence pr WHERE pr.courier_user_id=u.id AND pr.is_online AND pr.updated_at >= now()-interval '90 seconds') AS fresh_presence,
            EXISTS(SELECT 1 FROM taxi_captain_profile t WHERE t.user_id=u.id) AS is_taxi_captain,
            (SELECT count(*) FROM courier_assignment ca WHERE ca.courier_user_id=u.id AND ca.ended_at IS NULL) AS open_assignments,
            (SELECT count(*) FROM customer_order o WHERE o.delivery_user_id=u.id AND o.delivery_assignment_status='ASSIGNED') AS active_assigned_orders
     FROM app_user u
     LEFT JOIN courier_profile cp ON cp.user_id=u.id
     WHERE u.role='delivery'
       AND u.delivery_account_approved = TRUE
       AND u.is_account_disabled = FALSE
     ORDER BY u.id DESC LIMIT 50`
  );

  // Count of fully-eligible drivers per the real filter
  await safe(
    "ELIGIBLE_COUNT_STRICT",
    `SELECT count(*) AS eligible_now
     FROM app_user u
     LEFT JOIN courier_profile cp ON cp.user_id=u.id
     WHERE u.role='delivery'
       AND u.delivery_account_approved = TRUE
       AND u.is_account_disabled = FALSE
       AND NOT EXISTS (SELECT 1 FROM taxi_captain_profile tcp WHERE tcp.user_id=u.id)
       AND COALESCE(LOWER(cp.availability_status),'online')='online'
       AND EXISTS (SELECT 1 FROM courier_presence pr WHERE pr.courier_user_id=u.id AND pr.is_online AND pr.updated_at >= now()-interval '90 seconds')
       AND NOT EXISTS (SELECT 1 FROM customer_order ao WHERE ao.delivery_user_id=u.id AND ao.delivery_assignment_status='ASSIGNED')
       AND NOT EXISTS (SELECT 1 FROM courier_assignment oa WHERE oa.courier_user_id=u.id AND oa.ended_at IS NULL)`
  );

  // Specific stuck orders + latest delivery orders not completed
  await safe(
    "ORDERS_181_199",
    `SELECT id, status, delivery_assignment_status, delivery_user_id, assigned_by_store,
            is_merchant_delivery, merchant_id, created_at, approved_at, preparing_started_at,
            prepared_at, courier_requested_at
     FROM customer_order WHERE id IN (181,199) ORDER BY id`
  );

  await safe(
    "LATEST_UNDELIVERED_DELIVERY_ORDERS",
    `SELECT id, status, delivery_assignment_status, delivery_user_id, assigned_by_store,
            is_merchant_delivery, merchant_id, created_at, approved_at, courier_requested_at
     FROM customer_order
     WHERE status IN ('approved','preparing','ready_for_delivery','on_the_way','arrived')
     ORDER BY id DESC LIMIT 25`
  );

  await safe(
    "DELIVERY_STATUS_DISTRIBUTION",
    `SELECT COALESCE(delivery_assignment_status,'(null)') AS das, status, count(*) AS n
     FROM customer_order
     WHERE created_at >= now() - interval '60 days'
     GROUP BY 1,2 ORDER BY n DESC LIMIT 40`
  );

  // Open assignments + anomalies
  await safe(
    "OPEN_ASSIGNMENTS",
    `SELECT count(*) AS open_rows,
            count(DISTINCT order_id) AS distinct_orders,
            count(DISTINCT courier_user_id) AS distinct_couriers
     FROM courier_assignment WHERE ended_at IS NULL`
  );

  await safe(
    "ANOMALY_assigned_without_open_assignment",
    `SELECT o.id, o.status, o.delivery_assignment_status, o.delivery_user_id
     FROM customer_order o
     WHERE o.delivery_assignment_status='ASSIGNED'
       AND NOT EXISTS (SELECT 1 FROM courier_assignment ca WHERE ca.order_id=o.id AND ca.ended_at IS NULL)
     ORDER BY o.id DESC LIMIT 20`
  );

  await safe(
    "ANOMALY_assigned_null_driver",
    `SELECT id, status, delivery_assignment_status, delivery_user_id
     FROM customer_order
     WHERE delivery_assignment_status='ASSIGNED' AND delivery_user_id IS NULL LIMIT 20`
  );

  await safe(
    "ANOMALY_open_assignment_driver_mismatch",
    `SELECT ca.order_id, ca.courier_user_id AS assignment_courier, o.delivery_user_id AS order_courier, o.delivery_assignment_status
     FROM courier_assignment ca JOIN customer_order o ON o.id=ca.order_id
     WHERE ca.ended_at IS NULL AND o.delivery_user_id IS DISTINCT FROM ca.courier_user_id LIMIT 20`
  );

  await safe(
    "COURIER_ASSIGNMENT_STATUS_DIST",
    `SELECT status, (ended_at IS NULL) AS open, count(*) AS n
     FROM courier_assignment GROUP BY 1,2 ORDER BY n DESC LIMIT 30`
  );

  await safe(
    "COURIER_ASSIGNMENT_RECENT",
    `SELECT id, order_id, courier_user_id, status, requested_at, responded_at, assigned_at, ended_at, ended_reason
     FROM courier_assignment ORDER BY id DESC LIMIT 15`
  );

  // constraints / indexes
  await safe(
    "COURIER_ASSIGNMENT_INDEXES",
    `SELECT indexname, indexdef FROM pg_indexes
     WHERE schemaname='public' AND tablename='courier_assignment' ORDER BY indexname`
  );

  await pool.end();
  console.log("\n=== DONE ===");
}

main().catch((e) => {
  console.error("FATAL", e);
  process.exit(1);
});
