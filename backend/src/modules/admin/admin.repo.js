import { pool, q } from "../../config/db.js";

const ACTIVE_TAXI_RIDE_STATUSES = [
  "searching",
  "captain_assigned",
  "captain_arriving",
  "ride_started",
];

export async function getTaxiAdminOverview({
  status,
  captainStatus,
  search,
  limit = 50,
  offset = 0,
}) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 50));
  const safeOffset = Math.max(0, Number(offset) || 0);
  const normalizedSearch = String(search || "").trim();

  const rideParams = [];
  const rideWhere = [];
  if (status) {
    rideParams.push(status);
    rideWhere.push(`r.status = $${rideParams.length}`);
  }
  if (normalizedSearch) {
    rideParams.push(`%${normalizedSearch}%`);
    const p = `$${rideParams.length}`;
    rideWhere.push(`(
      r.id::text ILIKE ${p} OR cu.full_name ILIKE ${p} OR cu.phone ILIKE ${p}
      OR ca.full_name ILIKE ${p} OR ca.phone ILIKE ${p}
    )`);
  }
  rideParams.push(safeLimit, safeOffset);
  const rides = await q(
    `SELECT r.id, r.status, r.customer_user_id, r.assigned_captain_user_id,
            r.pickup_label, r.pickup_latitude, r.pickup_longitude,
            r.dropoff_label, r.dropoff_latitude, r.dropoff_longitude,
            r.proposed_fare_iqd, r.agreed_fare_iqd, r.created_at, r.updated_at,
            r.started_at, r.completed_at, r.cancelled_at,
            cu.full_name AS customer_full_name, cu.phone AS customer_phone,
            ca.full_name AS captain_full_name, ca.phone AS captain_phone
       FROM taxi_ride_request r
       JOIN app_user cu ON cu.id = r.customer_user_id
       LEFT JOIN app_user ca ON ca.id = r.assigned_captain_user_id
       ${rideWhere.length ? `WHERE ${rideWhere.join(" AND ")}` : ""}
       ORDER BY r.created_at DESC, r.id DESC
       LIMIT $${rideParams.length - 1} OFFSET $${rideParams.length}`,
    rideParams
  );

  const captainParams = [];
  // Taxi captains currently share the legacy `delivery` role with couriers;
  // the taxi profile is the reliable discriminator between the two products.
  const captainWhere = [`u.role = 'delivery'`, `p.user_id IS NOT NULL`];
  if (normalizedSearch) {
    captainParams.push(`%${normalizedSearch}%`);
    const p = `$${captainParams.length}`;
    captainWhere.push(`(
      u.id::text ILIKE ${p} OR u.full_name ILIKE ${p} OR u.phone ILIKE ${p}
      OR p.plate_number ILIKE ${p} OR p.car_make ILIKE ${p} OR p.car_model ILIKE ${p}
    )`);
  }
  const creditRemaining = `(COALESCE(s.purchased_ride_credits, 15) - COALESCE(s.consumed_ride_credits, 0))`;
  if (captainStatus === "active") captainWhere.push(`${creditRemaining} > 1`);
  if (captainStatus === "online") captainWhere.push(`COALESCE(pr.is_online, FALSE) = TRUE`);
  if (captainStatus === "offline") captainWhere.push(`COALESCE(pr.is_online, FALSE) = FALSE`);
  if (captainStatus === "near_exhaustion") captainWhere.push(`${creditRemaining} = 1`);
  if (captainStatus === "exhausted") captainWhere.push(`${creditRemaining} <= 0`);
  if (captainStatus === "payment_pending") captainWhere.push(`COALESCE(s.cash_payment_pending, FALSE) = TRUE`);
  captainParams.push(safeLimit, safeOffset);
  const captains = await q(
    `SELECT u.id, u.full_name, u.phone, u.delivery_account_approved,
            p.profile_image_url, p.car_image_url, p.vehicle_type, p.car_make,
            p.car_model, p.car_year, p.car_color, p.plate_number,
            pr.is_online, pr.last_seen_at,
            COALESCE(s.package_price_iqd, 10000)::int AS package_price_iqd,
            COALESCE(s.package_ride_count, 15)::int AS package_ride_count,
            COALESCE(s.purchased_ride_credits, 15)::int AS purchased_ride_credits,
            COALESCE(s.consumed_ride_credits, 0)::int AS consumed_ride_credits,
            COALESCE(s.cash_payment_pending, FALSE) AS cash_payment_pending,
            s.cash_payment_requested_at, s.last_cash_payment_confirmed_at,
            COUNT(r.id)::int AS rides_total,
            COUNT(r.id) FILTER (WHERE r.status = 'completed')::int AS rides_completed,
            COUNT(r.id) FILTER (WHERE r.status = ANY($${captainParams.length + 1}::text[]))::int AS rides_active,
            COUNT(r.id) FILTER (WHERE r.status = 'cancelled')::int AS rides_cancelled
       FROM app_user u
       LEFT JOIN taxi_captain_profile p ON p.user_id = u.id
       LEFT JOIN taxi_captain_presence pr ON pr.captain_user_id = u.id
       LEFT JOIN taxi_captain_subscription s ON s.captain_user_id = u.id
       LEFT JOIN taxi_ride_request r ON r.assigned_captain_user_id = u.id
       WHERE ${captainWhere.join(" AND ")}
       GROUP BY u.id, p.user_id, pr.captain_user_id, s.captain_user_id
       ORDER BY u.created_at DESC, u.id DESC
       LIMIT $${captainParams.length - 1} OFFSET $${captainParams.length}`,
    [...captainParams, ACTIVE_TAXI_RIDE_STATUSES]
  );

  const summary = await q(
    `SELECT
       (SELECT COUNT(*)::int FROM taxi_ride_request) AS rides_total,
       (SELECT COUNT(*)::int FROM taxi_ride_request WHERE status = ANY($1::text[])) AS rides_active,
       (SELECT COUNT(*)::int FROM taxi_ride_request WHERE status = 'searching') AS rides_searching,
       (SELECT COUNT(*)::int FROM taxi_ride_request WHERE status = 'captain_assigned') AS rides_captain_assigned,
       (SELECT COUNT(*)::int FROM taxi_ride_request WHERE status = 'captain_arriving') AS rides_captain_arriving,
       (SELECT COUNT(*)::int FROM taxi_ride_request WHERE status = 'ride_started') AS rides_started,
       (SELECT COUNT(*)::int FROM taxi_ride_request WHERE status = 'completed') AS rides_completed,
       (SELECT COUNT(*)::int FROM taxi_ride_request WHERE status = 'cancelled') AS rides_cancelled,
       (SELECT COUNT(*)::int FROM taxi_ride_request WHERE status = 'expired') AS rides_expired,
       (SELECT COUNT(*)::int FROM app_user u JOIN taxi_captain_profile cp ON cp.user_id=u.id WHERE u.role='delivery') AS captains_total,
       (SELECT COUNT(*)::int FROM app_user u JOIN taxi_captain_profile cp ON cp.user_id=u.id JOIN taxi_captain_presence p ON p.captain_user_id=u.id WHERE u.role='delivery' AND p.is_online=TRUE) AS captains_online,
       (SELECT COUNT(*)::int FROM app_user u JOIN taxi_captain_profile cp ON cp.user_id=u.id LEFT JOIN taxi_captain_subscription s ON s.captain_user_id=u.id WHERE u.role='delivery' AND COALESCE(s.purchased_ride_credits,15)-COALESCE(s.consumed_ride_credits,0)=1) AS captains_near_exhaustion,
       (SELECT COUNT(*)::int FROM app_user u JOIN taxi_captain_profile cp ON cp.user_id=u.id LEFT JOIN taxi_captain_subscription s ON s.captain_user_id=u.id WHERE u.role='delivery' AND COALESCE(s.purchased_ride_credits,15)-COALESCE(s.consumed_ride_credits,0)<=0) AS captains_exhausted,
       (SELECT COUNT(*)::int FROM taxi_captain_subscription s JOIN taxi_captain_profile cp ON cp.user_id=s.captain_user_id WHERE s.cash_payment_pending=TRUE) AS captains_payment_pending`,
    [ACTIVE_TAXI_RIDE_STATUSES]
  );

  return { summary: summary.rows[0], rides: rides.rows, captains: captains.rows };
}

export async function adminCancelTaxiRide({ rideId, adminUserId, reason }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const locked = await client.query(
      `SELECT id, status, customer_user_id, assigned_captain_user_id
       FROM taxi_ride_request WHERE id=$1 FOR UPDATE`,
      [Number(rideId)]
    );
    const ride = locked.rows[0];
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "NOT_FOUND" };
    }
    if (["completed", "cancelled", "expired"].includes(ride.status)) {
      await client.query("ROLLBACK");
      return { code: "ALREADY_CLOSED", ride };
    }
    const updated = await client.query(
      `UPDATE taxi_ride_request SET status='cancelled', current_bid_id=NULL,
              cancelled_at=NOW(), updated_at=NOW() WHERE id=$1
       RETURNING id, status, customer_user_id, assigned_captain_user_id, cancelled_at`,
      [Number(rideId)]
    );
    await client.query(
      `UPDATE taxi_ride_bid SET status='expired', updated_at=NOW()
       WHERE ride_request_id=$1 AND status IN ('active','waiting')`,
      [Number(rideId)]
    );
    await client.query(
      `INSERT INTO taxi_ride_event
        (ride_request_id, actor_user_id, event_type, message, payload)
       VALUES ($1,$2,'ride_cancelled_by_admin',$3,$4::jsonb)`,
      [Number(rideId), Number(adminUserId), reason, JSON.stringify({ reason, previousStatus: ride.status })]
    );
    await client.query("COMMIT");
    return { code: "OK", ride: updated.rows[0], previousStatus: ride.status };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function adjustCaptainRideCredits({ captainUserId, delta, adminUserId, reason }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      `INSERT INTO taxi_captain_subscription (captain_user_id)
       VALUES ($1) ON CONFLICT DO NOTHING`,
      [Number(captainUserId)]
    );
    const r = await client.query(
      `UPDATE taxi_captain_subscription
         SET purchased_ride_credits = purchased_ride_credits + $2,
             updated_at = NOW()
       WHERE captain_user_id=$1
         AND purchased_ride_credits + $2 >= consumed_ride_credits
       RETURNING captain_user_id, package_price_iqd, package_ride_count,
                 purchased_ride_credits, consumed_ride_credits, cash_payment_pending`,
      [Number(captainUserId), Number(delta)]
    );
    const row = r.rows[0] || null;
    if (!row) {
      await client.query("ROLLBACK");
      return null;
    }
    await client.query(
      `INSERT INTO taxi_captain_credit_transaction
        (captain_user_id, delta, transaction_type, actor_user_id, note)
       VALUES ($1,$2,'admin_adjustment',$3,$4)`,
      [Number(captainUserId), Number(delta), Number(adminUserId), reason]
    );
    await client.query("COMMIT");
    return row;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function findTaxiCaptainById(captainUserId) {
  const r = await q(
    `SELECT u.id FROM app_user u
     JOIN taxi_captain_profile p ON p.user_id=u.id
     WHERE u.id=$1 AND u.role='delivery' LIMIT 1`,
    [Number(captainUserId)]
  );
  return r.rows[0] || null;
}

export async function listAvailableOwnerAccounts() {
  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.block,
       u.building_number,
       u.apartment
     FROM app_user u
     LEFT JOIN merchant m
       ON m.owner_user_id = u.id
     WHERE u.role = 'owner'
       AND m.id IS NULL
     ORDER BY u.full_name ASC, u.id DESC`
  );

  return r.rows;
}

export async function listManagedMerchants() {
  const r = await q(
    `SELECT
       m.id,
       m.name,
       m.type,
       m.phone,
       m.is_open,
       m.is_approved,
       m.is_disabled,
       m.created_at,
       u.id AS owner_user_id,
       u.full_name AS owner_full_name,
       u.phone AS owner_phone,
       COALESCE(
         COUNT(o.id) FILTER (
           WHERE o.created_at >= DATE_TRUNC('day', NOW())
         ),
         0
       )::int AS today_orders_count
     FROM merchant m
     LEFT JOIN app_user u ON u.id = m.owner_user_id
     LEFT JOIN customer_order o ON o.merchant_id = m.id
     GROUP BY m.id, u.id
     ORDER BY m.id DESC`
  );
  return r.rows;
}

export async function setMerchantDisabled(merchantId, isDisabled) {
  const r = await q(
    `UPDATE merchant
     SET is_disabled = $2
     WHERE id = $1
     RETURNING
       id,
       name,
       owner_user_id,
       is_disabled`,
    [Number(merchantId), isDisabled === true]
  );
  return r.rows[0] || null;
}

export async function isUserSuperAdmin(userId) {
  const id = Number(userId);
  if (!Number.isFinite(id) || id <= 0) return false;

  const r = await q(
    `SELECT is_super_admin
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [id]
  );

  return r.rows[0]?.is_super_admin === true;
}

export async function listPendingDeliveryAccounts() {
  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.block,
       u.building_number,
       u.apartment,
       u.created_at,
       p.vehicle_type,
       p.car_make,
       p.car_model,
       p.car_year,
       p.car_color,
       p.plate_number,
       p.profile_image_url,
       p.car_image_url
     FROM app_user u
     LEFT JOIN taxi_captain_profile p
       ON p.user_id = u.id
     WHERE u.role = 'delivery'
       AND u.delivery_account_approved = FALSE
     ORDER BY u.created_at DESC, u.id DESC`
  );

  return r.rows;
}

export async function approveDeliveryAccount(deliveryUserId, approvedByUserId) {
  const r = await q(
    `UPDATE app_user
     SET delivery_account_approved = TRUE,
         delivery_approved_by_user_id = $2,
         delivery_approved_at = NOW()
     WHERE id = $1
       AND role = 'delivery'
       AND delivery_account_approved = FALSE
     RETURNING id, full_name, phone`,
    [Number(deliveryUserId), Number(approvedByUserId)]
  );

  return r.rows[0] || null;
}

export async function getMerchantById(merchantId) {
  const r = await q(
    `SELECT id, name, type, is_approved, is_disabled
     FROM merchant
     WHERE id = $1
     LIMIT 1`,
    [Number(merchantId)]
  );
  return r.rows[0] || null;
}

export async function listAdBoardItems() {
  const r = await q(
    `SELECT
       a.*,
       m.name AS merchant_name,
       m.type::text AS merchant_type,
       m.is_approved AS merchant_is_approved,
       m.is_disabled AS merchant_is_disabled
     FROM app_ad_board_item a
     LEFT JOIN merchant m ON m.id = a.merchant_id
     ORDER BY a.priority ASC, a.id DESC`
  );
  return r.rows;
}

export async function createAdBoardItem(item) {
  const r = await q(
    `INSERT INTO app_ad_board_item
      (
        title,
        subtitle,
        image_url,
        badge_label,
        cta_label,
        cta_target_type,
        cta_target_value,
        merchant_id,
        priority,
        is_active,
        starts_at,
        ends_at,
        created_by_user_id,
        updated_by_user_id
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13)
     RETURNING *`,
    [
      item.title,
      item.subtitle,
      item.imageUrl || null,
      item.badgeLabel || null,
      item.ctaLabel || null,
      item.ctaTargetType || "none",
      item.ctaTargetValue || null,
      item.merchantId || null,
      Number(item.priority ?? 100),
      item.isActive !== false,
      item.startsAt || null,
      item.endsAt || null,
      Number(item.actorUserId) || null,
    ]
  );
  return r.rows[0] || null;
}

export async function updateAdBoardItem(itemId, patch, actorUserId) {
  const allowed = new Map([
    ["title", "title"],
    ["subtitle", "subtitle"],
    ["imageUrl", "image_url"],
    ["badgeLabel", "badge_label"],
    ["ctaLabel", "cta_label"],
    ["ctaTargetType", "cta_target_type"],
    ["ctaTargetValue", "cta_target_value"],
    ["merchantId", "merchant_id"],
    ["priority", "priority"],
    ["isActive", "is_active"],
    ["startsAt", "starts_at"],
    ["endsAt", "ends_at"],
  ]);

  const keys = Object.keys(patch || {}).filter((key) => allowed.has(key));
  if (!keys.length) return null;

  const params = [];
  const assignments = keys.map((key, index) => {
    params.push(patch[key]);
    return `${allowed.get(key)} = $${index + 2}`;
  });

  params.unshift(Number(itemId));
  params.push(Number(actorUserId) || null);

  const updatedByPosition = params.length;

  const sql = `
    UPDATE app_ad_board_item
    SET ${assignments.join(", ")},
        updated_by_user_id = $${updatedByPosition}
    WHERE id = $1
    RETURNING *`;

  const r = await q(sql, params);
  return r.rows[0] || null;
}

export async function deleteAdBoardItem(itemId) {
  const r = await q(
    `DELETE FROM app_ad_board_item
     WHERE id = $1
     RETURNING id`,
    [Number(itemId)]
  );
  return r.rows[0] || null;
}
