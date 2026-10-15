import "dotenv/config";

import { pool, q } from "../config/db.js";

const EXECUTE = process.argv.includes("--execute");
const CONFIRMED = process.argv.includes("--confirm") &&
  process.argv.includes("CLEAN_LAUNCH_PRODUCTION");

const PRESERVE_EXACT_TABLES = new Set([
  "app_user",
  "admin_role",
  "admin_role_permission",
  "admin_user_permission",
  "company_employee_profile",
  "courier_profile",
  "courier_presence",
  "inventory_audit_log",
  "merchant",
  "merchant_billing_profile",
  "merchant_category",
  "merchant_discovery_subcategory",
  "product",
  "product_attribute",
  "product_media",
  "product_review",
  "product_variant",
  "product_variant_group",
  "product_variant_option",
  "service_categories",
  "service_module_settings",
  "store_inventory_item",
  "store_activity_definition",
  "store_activity_internal_category_template",
  "taxi_vehicle_make",
  "taxi_vehicle_model",
]);

const PRESERVE_PREFIXES = ["social_"];

const TRUNCATE_EXACT = new Set([
  "ai_chat_message",
  "ai_chat_session",
  "ai_customer_profile",
  "app_crash_event",
  "app_notification",
  "car_listing_media",
  "company_attendance",
  "company_employee_review",
  "company_expense_claim",
  "company_payroll_item",
  "company_payroll_run",
  "delivery_day_archive",
  "delivery_dispatch_audit",
  "delivery_job",
  "delivery_pickup_stop",
  "merchant_app_payables_ledger",
  "merchant_cash_ledger_entry",
  "merchant_category_sales_stats",
  "merchant_daily_kpi",
  "merchant_monthly_subscription_invoice",
  "merchant_monthly_subscription_payment",
  "merchant_payment_allocation",
  "merchant_payment_invoice_allocation",
  "merchant_payment_request",
  "merchant_payment_request_status_history",
  "merchant_product_sales_stats",
  "merchant_receivable_invoice",
  "merchant_receivables_ledger",
  "merchant_settlement",
  "notification_action_event",
  "notification_delivery_event",
  "order_action_event",
  "order_chat_message",
  "order_group",
  "order_group_item_summary",
  "order_item",
  "order_revision",
  "order_revision_approval",
  "order_revision_event",
  "order_revision_financial_adjustment",
  "order_revision_item",
  "order_status_history",
  "paid_upgrade_audit",
  "paid_upgrade_request",
  "paid_upgrade_subscription",
  "pharmacy_conversation",
  "pharmacy_conversation_event_history",
  "real_estate_listing_media",
  "real_estate_listing_status_history",
  "realtime_outbox",
  "support_agent_presence",
  "support_ticket",
  "support_ticket_assignment",
  "support_ticket_attachment",
  "support_ticket_callback",
  "support_ticket_event",
  "support_ticket_internal_note",
  "support_ticket_link",
  "support_ticket_message",
]);

const DELETE_EXACT = new Set([
  "car_listing",
  "customer_order",
  "inventory_reservation",
  "merchant_offer",
  "real_estate_listing",
  "real_estate_saved_listing",
]);

function shouldPreserve(table) {
  if (PRESERVE_EXACT_TABLES.has(table)) return true;
  return PRESERVE_PREFIXES.some((prefix) => table.startsWith(prefix));
}

function shouldTruncateByPattern(table) {
  if (table.startsWith("taxi_") && !table.startsWith("taxi_vehicle_")) {
    return true;
  }
  if (table.startsWith("service_") && !shouldPreserve(table)) {
    return true;
  }
  if (table.startsWith("courier_") && !shouldPreserve(table)) {
    return true;
  }
  return false;
}

function quoteIdent(name) {
  if (!/^[a-z_][a-z0-9_]*$/.test(name)) {
    throw new Error(`Unsafe identifier: ${name}`);
  }
  return `"${name}"`;
}

async function existingTables() {
  const result = await q(
    `SELECT table_name
       FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE'
      ORDER BY table_name`
  );
  return result.rows.map((row) => row.table_name);
}

async function countTable(table) {
  const result = await q(`SELECT COUNT(*)::int AS count FROM ${quoteIdent(table)}`);
  return Number(result.rows[0]?.count || 0);
}

async function sequenceName(table) {
  const hasId = await q(
    `SELECT 1
       FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = $1
        AND column_name = 'id'
      LIMIT 1`,
    [table]
  );
  if (hasId.rowCount === 0) return null;
  const result = await q(`SELECT pg_get_serial_sequence($1, 'id') AS seq`, [table]);
  return result.rows[0]?.seq || null;
}

async function restartIdSequence(client, table) {
  const seq = await sequenceName(table);
  if (!seq) return;
  await client.query(`ALTER SEQUENCE ${seq} RESTART WITH 1`);
}

async function buildPlan() {
  const tables = await existingTables();
  const tableSet = new Set(tables);
  const truncateTables = [];
  const deleteTables = [];

  for (const table of tables) {
    if (shouldPreserve(table)) continue;
    if (TRUNCATE_EXACT.has(table) || shouldTruncateByPattern(table)) {
      truncateTables.push(table);
      continue;
    }
    if (DELETE_EXACT.has(table)) {
      deleteTables.push(table);
    }
  }

  const optionalOfferTables = [
    "coupon",
    "coupon_usage",
    "merchant_offer_product",
    "merchant_offer_usage",
  ];
  for (const table of optionalOfferTables) {
    if (tableSet.has(table) && !shouldPreserve(table) && !truncateTables.includes(table)) {
      truncateTables.push(table);
    }
  }

  return {
    truncateTables: truncateTables.sort(),
    deleteTables: deleteTables.sort(),
  };
}

async function countRows(tables) {
  const rows = [];
  for (const table of tables) {
    rows.push({ table, count: await countTable(table) });
  }
  return rows;
}

async function userDeletePreview() {
  const roles = ["taxi_captain", "service_provider"];
  const users = await q(
    `SELECT id, phone, full_name, role
       FROM app_user
      WHERE role::text = ANY($1::text[])
      ORDER BY role, id`,
    [roles]
  );
  const ids = users.rows.map((row) => Number(row.id)).filter(Number.isFinite);
  let socialRows = [];
  if (ids.length > 0) {
    const social = await q(
      `SELECT 'social_post' AS table_name, COUNT(*)::int AS count
         FROM social_post
        WHERE user_id = ANY($1::bigint[])
       UNION ALL
       SELECT 'social_story' AS table_name, COUNT(*)::int AS count
         FROM social_story
        WHERE user_id = ANY($1::bigint[])
       UNION ALL
       SELECT 'social_chat_message' AS table_name, COUNT(*)::int AS count
         FROM social_chat_message
        WHERE sender_user_id = ANY($1::bigint[])`,
      [ids]
    );
    socialRows = social.rows;
  }
  return { users: users.rows, socialRows };
}

async function main() {
  const plan = await buildPlan();
  const tables = Array.from(new Set([...plan.truncateTables, ...plan.deleteTables]));
  const before = await countRows(tables);
  const deleteUsers = await userDeletePreview();

  const dryRun = {
    mode: EXECUTE ? "execute" : "dry-run",
    executeAllowed: EXECUTE && CONFIRMED,
    preserved: {
      accounts: "app_user except taxi_captain and service_provider",
      socialTables: "all social_* tables",
      merchantAccounts: "merchant + owner users",
      deliveryAccounts: "delivery users + courier_profile/courier_presence",
      staffAccounts: "staff users + company_employee_profile",
      catalogs: [
        "service_categories",
        "service_module_settings",
        "taxi_vehicle_make",
        "taxi_vehicle_model",
        "store_activity_definition",
        "store_activity_internal_category_template",
      ],
    },
    deleteUsers,
    truncateTables: await countRows(plan.truncateTables),
    deleteTables: await countRows(plan.deleteTables),
  };

  if (!EXECUTE) {
    console.log(JSON.stringify(dryRun, null, 2));
    return;
  }

  if (!CONFIRMED) {
    console.error(
      "Refusing to execute. Use: --execute --confirm CLEAN_LAUNCH_PRODUCTION"
    );
    console.log(JSON.stringify(dryRun, null, 2));
    process.exitCode = 2;
    return;
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT pg_advisory_xact_lock($1)", [908_202_601]);

    if (plan.truncateTables.length > 0) {
      await client.query(
        `TRUNCATE ${plan.truncateTables.map(quoteIdent).join(", ")} RESTART IDENTITY CASCADE`
      );
    }

    await client.query(
      `UPDATE social_post
          SET verified_purchase_order_id = NULL,
              verified_purchase = FALSE,
              verified_purchase_verified_at = NULL
        WHERE verified_purchase_order_id IS NOT NULL`
    );

    for (const table of plan.deleteTables) {
      await client.query(`DELETE FROM ${quoteIdent(table)}`);
      await restartIdSequence(client, table);
    }

    const deletedUsers = await client.query(
      `DELETE FROM app_user
        WHERE role::text IN ('taxi_captain', 'service_provider')
        RETURNING id, phone, full_name, role`
    );

    await client.query("COMMIT");

    const after = await countRows(tables);
    const roles = await q(
      `SELECT role, COUNT(*)::int AS count
         FROM app_user
        GROUP BY role
        ORDER BY role`
    );
    console.log(
      JSON.stringify(
        {
          ok: true,
          deletedUsers: deletedUsers.rows,
          before,
          after,
          remainingUserRoles: roles.rows,
        },
        null,
        2
      )
    );
  } catch (error) {
    await client.query("ROLLBACK");
    console.error("[clean-launch] failed:", error?.message || error);
    process.exit(1);
  } finally {
    client.release();
  }
}

main()
  .catch((error) => {
    console.error("[clean-launch] failed:", error?.message || error);
    process.exitCode = 1;
  })
  .finally(() => pool.end().catch(() => {}));
