import crypto from "crypto";

import { env } from "../../config/env.js";
import { ensureSchema, pool, q } from "../../config/db.js";
import {
  normalizeBid,
  normalizeCallSession,
  normalizeCallSignal,
  normalizeChatMessage,
  normalizeEvent,
  normalizeLocation,
  normalizePresence,
  normalizeRide,
  normalizeRideFriendShare,
  toIntOrNull,
  toNumberOrNull,
} from "./taxi.mappers.js";
import {
  evaluateTaxiCancellation,
  TAXI_TERMINAL_STATUSES,
} from "./taxi.cancellation.js";

const ACTIVE_RIDE_STATUSES = [
  "price_raise_required",
  "searching",
  "captain_assigned",
  "captain_arriving",
  "ride_started",
];
const ACTIVE_ASSIGNED_RIDE_STATUSES = [
  "captain_assigned",
  "captain_arriving",
  "ride_started",
];
const TAXI_STATUS_TRANSITION_QUERY_OPTIONS = {
  query_timeout: Math.max(Number(env.dbQueryTimeoutMs || 25_000), 60_000),
  statement_timeout: Math.max(Number(env.dbStatementTimeoutMs || 20_000), 60_000),
};

const RIDE_SELECT = `
  SELECT
    r.*,
    cu.full_name AS customer_full_name,
    cu.phone AS customer_phone,
    ca.full_name AS captain_full_name,
    ca.phone AS captain_phone,
    cp.profile_image_url AS captain_profile_image_url,
    cp.car_image_url AS captain_car_image_url,
    cp.vehicle_type AS captain_vehicle_type,
    cp.car_make AS captain_car_make,
    cp.car_model AS captain_car_model,
    cp.car_year AS captain_car_year,
    cp.car_color AS captain_car_color,
    cp.plate_number AS captain_plate_number,
    cp.plate_governorate AS captain_plate_governorate,
    cp.plate_category AS captain_plate_category,
    cp.plate_letter AS captain_plate_letter,
    cp.plate_digits AS captain_plate_digits,
    cp.rating_avg AS captain_rating_avg,
    cp.rides_count AS captain_rides_count
  FROM taxi_ride_request r
  LEFT JOIN app_user cu ON cu.id = r.customer_user_id
  LEFT JOIN app_user ca ON ca.id = r.assigned_captain_user_id
  LEFT JOIN taxi_captain_profile cp ON cp.user_id = r.assigned_captain_user_id
`;


function distanceSql(latExpr, lngExpr, latParam, lngParam) {
  return `(
    6371000 * acos(
      LEAST(
        1,
        GREATEST(
          -1,
          cos(radians(${latParam})) * cos(radians(${latExpr}))
          * cos(radians(${lngExpr}) - radians(${lngParam}))
          + sin(radians(${latParam})) * sin(radians(${latExpr}))
        )
      )
    )
  )`;
}

function normalizeCatalogName(value) {
  return String(value || "")
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

export async function listVehicleCatalog() {
  const r = await q(
    `SELECT
       m.id AS make_id,
       m.name AS make_name,
       mo.id AS model_id,
       mo.name AS model_name
     FROM taxi_vehicle_make m
     LEFT JOIN taxi_vehicle_model mo
       ON mo.make_id = m.id
      AND mo.is_active = TRUE
     WHERE m.is_active = TRUE
     ORDER BY m.name ASC, mo.name ASC`
  );

  const makesById = new Map();
  for (const row of r.rows) {
    const makeId = Number(row.make_id);
    if (!makesById.has(makeId)) {
      makesById.set(makeId, {
        id: makeId,
        name: row.make_name,
        models: [],
      });
    }
    if (row.model_id != null) {
      makesById.get(makeId).models.push({
        id: Number(row.model_id),
        makeId,
        name: row.model_name,
      });
    }
  }
  return [...makesById.values()];
}

export async function createVehicleMake({ name, userId = null }) {
  const label = String(name || "").trim().replace(/\s+/g, " ").slice(0, 120);
  const normalized = normalizeCatalogName(label);
  if (!label || !normalized) return null;
  const r = await q(
    `INSERT INTO taxi_vehicle_make
       (name, normalized_name, is_active, created_by_user_id, created_at, updated_at)
     VALUES ($1, $2, TRUE, $3, NOW(), NOW())
     ON CONFLICT (normalized_name) DO UPDATE
       SET name = EXCLUDED.name,
           is_active = TRUE,
           updated_at = NOW()
     RETURNING id, name`,
    [label, normalized, userId == null ? null : Number(userId)]
  );
  return r.rows[0] ? { id: Number(r.rows[0].id), name: r.rows[0].name } : null;
}

export async function createVehicleModel({ makeId, makeName = null, name, userId = null }) {
  let safeMakeId = Number(makeId);
  if ((!Number.isInteger(safeMakeId) || safeMakeId <= 0) && makeName) {
    const make = await createVehicleMake({ name: makeName, userId });
    safeMakeId = Number(make?.id);
  }
  if (!Number.isInteger(safeMakeId) || safeMakeId <= 0) return null;

  const label = String(name || "").trim().replace(/\s+/g, " ").slice(0, 120);
  const normalized = normalizeCatalogName(label);
  if (!label || !normalized) return null;

  const r = await q(
    `INSERT INTO taxi_vehicle_model
       (make_id, name, normalized_name, is_active, created_by_user_id, created_at, updated_at)
     VALUES ($1, $2, $3, TRUE, $4, NOW(), NOW())
     ON CONFLICT (make_id, normalized_name) DO UPDATE
       SET name = EXCLUDED.name,
           is_active = TRUE,
           updated_at = NOW()
     RETURNING id, make_id, name`,
    [safeMakeId, label, normalized, userId == null ? null : Number(userId)]
  );
  return r.rows[0]
    ? {
        id: Number(r.rows[0].id),
        makeId: Number(r.rows[0].make_id),
        name: r.rows[0].name,
      }
    : null;
}

async function queryRideById(client, rideId, queryOptions = null) {
  const r = await client.query({
    text: `${RIDE_SELECT}
     WHERE r.id = $1
     LIMIT 1`,
    values: [Number(rideId)],
    ...(queryOptions || {}),
  });
  return normalizeRide(r.rows[0]);
}

export async function expireSearchingRides() {
  const r = await q(
    `UPDATE taxi_ride_request
     SET status = 'expired',
         updated_at = NOW()
     WHERE status = 'searching'
       AND expires_at <= NOW()
     RETURNING id, customer_user_id, assigned_captain_user_id`
  );

  return r.rows.map((row) => ({
    id: Number(row.id),
    customerUserId: Number(row.customer_user_id),
    assignedCaptainUserId: toIntOrNull(row.assigned_captain_user_id),
  }));
}

export async function getCaptainPresence(captainUserId) {
  const r = await q(
    `SELECT *
     FROM taxi_captain_presence
     WHERE captain_user_id = $1
     LIMIT 1`,
    [Number(captainUserId)]
  );
  return normalizePresence(r.rows[0]);
}

export async function upsertCaptainPresence({
  captainUserId,
  isOnline,
  latitude,
  longitude,
  headingDeg,
  speedKmh,
  accuracyM,
}) {
  await ensureSchema();

  const hasCoordinates = latitude != null && longitude != null;

  const r = await q(
    `INSERT INTO taxi_captain_presence
      (
        captain_user_id,
        is_online,
        latitude,
        longitude,
        heading_deg,
        speed_kmh,
        accuracy_m,
        last_seen_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NOW())
     ON CONFLICT (captain_user_id)
     DO UPDATE SET
       is_online = EXCLUDED.is_online,
       latitude = EXCLUDED.latitude,
       longitude = EXCLUDED.longitude,
       heading_deg = EXCLUDED.heading_deg,
       speed_kmh = EXCLUDED.speed_kmh,
       accuracy_m = EXCLUDED.accuracy_m,
       last_seen_at = EXCLUDED.last_seen_at,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(captainUserId),
      isOnline === true,
      latitude,
      longitude,
      headingDeg,
      speedKmh,
      accuracyM,
      hasCoordinates ? new Date() : null,
    ]
  );

  return normalizePresence(r.rows[0]);
}

export async function listNearbyCaptainsForPickup({
  pickupLatitude,
  pickupLongitude,
  radiusM,
  limit = 50,
}) {
  const distanceExpr = distanceSql("p.latitude", "p.longitude", "$1", "$2");

  const r = await q(
    `SELECT
       p.captain_user_id,
       ${distanceExpr} AS distance_m
     FROM taxi_captain_presence p
     JOIN app_user u ON u.id = p.captain_user_id
     WHERE p.is_online = TRUE
       AND u.role = 'taxi_captain'
       AND p.latitude IS NOT NULL
       AND p.longitude IS NOT NULL
       AND p.last_seen_at >= NOW() - INTERVAL '3 minutes'
       AND NOT EXISTS (
         SELECT 1
         FROM taxi_ride_request active_ride
         WHERE active_ride.assigned_captain_user_id = p.captain_user_id
           AND active_ride.status = ANY($5::text[])
       )
       AND ${distanceExpr} <= $3
     ORDER BY distance_m ASC, p.last_seen_at DESC
     LIMIT $4`,
    [
      Number(pickupLatitude),
      Number(pickupLongitude),
      Number(radiusM),
      Math.max(1, Math.min(200, Number(limit) || 50)),
      ACTIVE_ASSIGNED_RIDE_STATUSES,
    ]
  );

  return r.rows.map((row) => ({
    captainUserId: Number(row.captain_user_id),
    distanceM: toNumberOrNull(row.distance_m),
  }));
}

export async function listNearbyCaptainMarkers({
  latitude,
  longitude,
  radiusM,
  limit = 80,
}) {
  const distanceExpr = distanceSql("p.latitude", "p.longitude", "$1", "$2");

  const r = await q(
    `SELECT
       p.captain_user_id,
       p.latitude,
       p.longitude,
       p.heading_deg,
       p.speed_kmh,
       p.last_seen_at,
       ${distanceExpr} AS distance_m
     FROM taxi_captain_presence p
     JOIN app_user u ON u.id = p.captain_user_id
     WHERE p.is_online = TRUE
       AND u.role = 'taxi_captain'
       AND p.latitude IS NOT NULL
       AND p.longitude IS NOT NULL
       AND p.last_seen_at >= NOW() - INTERVAL '3 minutes'
       AND ${distanceExpr} <= $3
     ORDER BY distance_m ASC, p.last_seen_at DESC
     LIMIT $4`,
    [
      Number(latitude),
      Number(longitude),
      Number(radiusM),
      Math.max(1, Math.min(200, Number(limit) || 80)),
    ]
  );

  return r.rows.map((row) => ({
    captainUserId: Number(row.captain_user_id),
    latitude: toNumberOrNull(row.latitude),
    longitude: toNumberOrNull(row.longitude),
    headingDeg: toNumberOrNull(row.heading_deg),
    speedKmh: toNumberOrNull(row.speed_kmh),
    lastSeenAt: row.last_seen_at || null,
    distanceM: toNumberOrNull(row.distance_m),
  }));
}

export async function createRideRequest({
  customerUserId,
  pickupLatitude,
  pickupLongitude,
  dropoffLatitude,
  dropoffLongitude,
  pickupLabel,
  dropoffLabel,
  proposedFareIqd,
  searchRadiusM,
  note,
  scheduleMode = "now",
  scheduledRideId = null,
  scheduledFor = null,
  couponId = null,
  couponCodeSnapshot = null,
  couponUseIndex = null,
  fareBeforeDiscountIqd = null,
  couponDiscountIqd = null,
  fareAfterDiscountIqd = null,
  couponSettlementState = "none",
}) {
  await ensureSchema();

  const r = await q(
    `INSERT INTO taxi_ride_request
      (
        customer_user_id,
        pickup_latitude,
        pickup_longitude,
        dropoff_latitude,
        dropoff_longitude,
        pickup_label,
        dropoff_label,
        proposed_fare_iqd,
        search_radius_m,
        search_phase,
        next_escalation_at,
        final_acceptance_deadline_at,
        note,
        status,
        pricing_round,
        previous_proposed_fare_iqd,
        price_raise_required_at,
        fare_version,
        schedule_mode,
        scheduled_ride_id,
        scheduled_for,
        coupon_id,
        coupon_code_snapshot,
        coupon_use_index,
        fare_before_discount_iqd,
        coupon_discount_iqd,
        fare_after_discount_iqd,
        coupon_settlement_state
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,1,NOW() + INTERVAL '5 minutes',NOW() + INTERVAL '5 minutes',$10,'searching',1,NULL,NULL,1,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20)
     RETURNING *`,
    [
      Number(customerUserId),
      Number(pickupLatitude),
      Number(pickupLongitude),
      Number(dropoffLatitude),
      Number(dropoffLongitude),
      pickupLabel,
      dropoffLabel,
      Number(proposedFareIqd),
      Number(searchRadiusM),
      note || null,
      scheduleMode === "scheduled" ? "scheduled" : "now",
      scheduledRideId == null ? null : Number(scheduledRideId),
      scheduledFor || null,
      couponId == null ? null : Number(couponId),
      couponCodeSnapshot || null,
      couponUseIndex == null ? null : Number(couponUseIndex),
      fareBeforeDiscountIqd == null ? null : Number(fareBeforeDiscountIqd),
      couponDiscountIqd == null ? 0 : Number(couponDiscountIqd),
      fareAfterDiscountIqd == null ? null : Number(fareAfterDiscountIqd),
      couponSettlementState || "none",
    ]
  );

  return normalizeRide(r.rows[0]);
}

export async function getRideById(rideId) {
  const r = await q(
    `${RIDE_SELECT}
     WHERE r.id = $1
     LIMIT 1`,
    [Number(rideId)]
  );
  return normalizeRide(r.rows[0]);
}

export async function getRideByIdForCustomer(rideId, customerUserId) {
  const r = await q(
    `${RIDE_SELECT}
     WHERE r.id = $1
       AND r.customer_user_id = $2
     LIMIT 1`,
    [Number(rideId), Number(customerUserId)]
  );
  return normalizeRide(r.rows[0]);
}

export async function getRideByIdForCaptain(rideId, captainUserId) {
  const r = await q(
    `${RIDE_SELECT}
     WHERE r.id = $1
       AND r.assigned_captain_user_id = $2
     LIMIT 1`,
    [Number(rideId), Number(captainUserId)]
  );
  return normalizeRide(r.rows[0]);
}

export async function getCustomerCurrentRide(customerUserId) {
  const r = await q(
    `${RIDE_SELECT}
     WHERE r.customer_user_id = $1
       AND r.status = ANY($2::text[])
     ORDER BY r.created_at DESC
     LIMIT 1`,
    [Number(customerUserId), ACTIVE_RIDE_STATUSES]
  );
  return normalizeRide(r.rows[0]);
}

export async function getCaptainCurrentRide(captainUserId) {
  const r = await q(
    `${RIDE_SELECT}
     WHERE r.assigned_captain_user_id = $1
       AND r.status = ANY($2::text[])
     ORDER BY r.created_at DESC
     LIMIT 1`,
    [Number(captainUserId), ACTIVE_ASSIGNED_RIDE_STATUSES]
  );
  return normalizeRide(r.rows[0]);
}

export async function listRideBids(rideId) {
  const distanceExpr = distanceSql(
    "r.pickup_latitude",
    "r.pickup_longitude",
    "cpres.latitude",
    "cpres.longitude"
  );
  const r = await q(
    `SELECT
       b.*,
       u.full_name AS captain_full_name,
       u.phone AS captain_phone,
       cp.profile_image_url AS captain_profile_image_url,
       cp.car_image_url AS captain_car_image_url,
       cp.vehicle_type AS captain_vehicle_type,
       cp.car_make AS captain_car_make,
       cp.car_model AS captain_car_model,
       cp.car_year AS captain_car_year,
       cp.car_color AS captain_car_color,
       cp.plate_number AS captain_plate_number,
       cp.plate_governorate AS captain_plate_governorate,
       cp.plate_category AS captain_plate_category,
       cp.plate_letter AS captain_plate_letter,
       cp.plate_digits AS captain_plate_digits,
       cp.rating_avg AS captain_rating_avg,
       cp.rides_count AS captain_rides_count,
       CASE
         WHEN cpres.latitude IS NOT NULL AND cpres.longitude IS NOT NULL
         THEN ${distanceExpr}
         ELSE NULL
       END AS distance_m
     FROM taxi_ride_bid b
     JOIN taxi_ride_request r
       ON r.id = b.ride_request_id
     JOIN app_user u ON u.id = b.captain_user_id
     LEFT JOIN taxi_captain_profile cp ON cp.user_id = b.captain_user_id
     LEFT JOIN taxi_captain_presence cpres ON cpres.captain_user_id = b.captain_user_id
     WHERE b.ride_request_id = $1
     ORDER BY b.created_at DESC`,
    [Number(rideId)]
  );
  return r.rows.map(normalizeBid);
}

async function lockRideForNegotiation(client, rideId, customerUserId) {
  const r = await client.query(
    `SELECT id, customer_user_id, status, current_bid_id
     FROM taxi_ride_request
     WHERE id = $1
       AND customer_user_id = $2
     FOR UPDATE`,
    [Number(rideId), Number(customerUserId)]
  );
  return r.rows[0] || null;
}

async function lockCaptainAssignment(client, captainUserId) {
  await client.query(`SELECT pg_advisory_xact_lock($1)`, [Number(captainUserId)]);
}

async function getCaptainActiveRideForUpdate(client, captainUserId) {
  const r = await client.query(
    `SELECT id, status, customer_user_id, assigned_captain_user_id
     FROM taxi_ride_request
     WHERE assigned_captain_user_id = $1
       AND status = ANY($2::text[])
     ORDER BY created_at DESC, id DESC
     LIMIT 1
     FOR UPDATE`,
    [Number(captainUserId), ACTIVE_ASSIGNED_RIDE_STATUSES]
  );
  return r.rows[0] || null;
}

async function findEarliestActiveBid(client, rideId) {
  const r = await client.query(
    `SELECT id, captain_user_id, offered_fare_iqd, eta_minutes, note, status,
            counter_offer_count, last_offer_iqd, last_offer_by, created_at, updated_at
     FROM taxi_ride_bid
     WHERE ride_request_id = $1
       AND status = 'active'
     ORDER BY created_at ASC, id ASC
     LIMIT 1
     FOR UPDATE`,
    [Number(rideId)]
  );
  return normalizeBid(r.rows[0]);
}

async function promoteNextActiveBid(client, rideId) {
  const next = await findEarliestActiveBid(client, rideId);
  await client.query(
    `UPDATE taxi_ride_request
     SET current_bid_id = $2,
         updated_at = NOW()
     WHERE id = $1`,
    [Number(rideId), next ? Number(next.id) : null]
  );
  return next;
}

async function lockCurrentActiveBid(client, rideId, currentBidId) {
  if (!currentBidId) return null;
  const r = await client.query(
    `SELECT id, ride_request_id, captain_user_id, offered_fare_iqd, eta_minutes, note, status,
            counter_offer_count, last_offer_iqd, last_offer_by, created_at, updated_at
     FROM taxi_ride_bid
     WHERE id = $1
       AND ride_request_id = $2
     FOR UPDATE`,
    [Number(currentBidId), Number(rideId)]
  );
  const bid = normalizeBid(r.rows[0]);
  if (!bid || bid.status !== "active") return null;
  return bid;
}

async function lockRideBidById(client, rideId, bidId) {
  if (!bidId) return null;
  const r = await client.query(
    `SELECT id, ride_request_id, captain_user_id, offered_fare_iqd, eta_minutes, note, status,
            counter_offer_count, last_offer_iqd, last_offer_by, created_at, updated_at
     FROM taxi_ride_bid
     WHERE id = $1
       AND ride_request_id = $2
     FOR UPDATE`,
    [Number(bidId), Number(rideId)]
  );
  return normalizeBid(r.rows[0]);
}

export async function ensureRideCurrentBid(rideId) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const rideLock = await client.query(
      `SELECT id, status, current_bid_id
       FROM taxi_ride_request
       WHERE id = $1
       FOR UPDATE`,
      [Number(rideId)]
    );
    const ride = rideLock.rows[0];
    if (!ride || ride.status !== "searching") {
      await client.query("ROLLBACK");
      return null;
    }

    const currentBid = await lockCurrentActiveBid(
      client,
      ride.id,
      ride.current_bid_id
    );
    if (currentBid) {
      await client.query("COMMIT");
      return currentBid;
    }

    const next = await promoteNextActiveBid(client, ride.id);
    await client.query("COMMIT");
    return next;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function getRideCurrentBid(rideId) {
  const distanceExpr = distanceSql(
    "r.pickup_latitude",
    "r.pickup_longitude",
    "cpres.latitude",
    "cpres.longitude"
  );
  const r = await q(
    `SELECT
       b.*,
       u.full_name AS captain_full_name,
       u.phone AS captain_phone,
       cp.profile_image_url AS captain_profile_image_url,
       cp.car_image_url AS captain_car_image_url,
       cp.vehicle_type AS captain_vehicle_type,
       cp.car_make AS captain_car_make,
       cp.car_model AS captain_car_model,
       cp.car_year AS captain_car_year,
       cp.car_color AS captain_car_color,
       cp.plate_number AS captain_plate_number,
       cp.plate_governorate AS captain_plate_governorate,
       cp.plate_category AS captain_plate_category,
       cp.plate_letter AS captain_plate_letter,
       cp.plate_digits AS captain_plate_digits,
       cp.rating_avg AS captain_rating_avg,
       cp.rides_count AS captain_rides_count,
       CASE
         WHEN cpres.latitude IS NOT NULL AND cpres.longitude IS NOT NULL
         THEN ${distanceExpr}
         ELSE NULL
       END AS distance_m
     FROM taxi_ride_request r
     JOIN taxi_ride_bid b
       ON b.id = r.current_bid_id
     JOIN app_user u
       ON u.id = b.captain_user_id
     LEFT JOIN taxi_captain_profile cp
       ON cp.user_id = b.captain_user_id
     LEFT JOIN taxi_captain_presence cpres
       ON cpres.captain_user_id = b.captain_user_id
     WHERE r.id = $1
       AND r.status = 'searching'
       AND b.status = 'active'
     LIMIT 1`,
    [Number(rideId)]
  );
  return normalizeBid(r.rows[0]);
}

export async function isCaptainCurrentBidOwner({ rideId, captainUserId }) {
  const r = await q(
    `SELECT 1
     FROM taxi_ride_request r
     JOIN taxi_ride_bid b
       ON b.id = r.current_bid_id
      AND b.status = 'active'
     WHERE r.id = $1
       AND r.status = 'searching'
       AND b.captain_user_id = $2
     LIMIT 1`,
    [Number(rideId), Number(captainUserId)]
  );
  return Boolean(r.rows[0]);
}

export async function upsertRideBid({
  rideRequestId,
  captainUserId,
  offeredFareIqd,
  etaMinutes,
  note,
}) {
  const r = await q(
    `INSERT INTO taxi_ride_bid
      (
        ride_request_id,
        captain_user_id,
        offered_fare_iqd,
        eta_minutes,
        note,
        status,
        counter_offer_count,
        last_offer_iqd,
        last_offer_by,
        updated_at
      )
     VALUES ($1,$2,$3,$4,$5,'active',0,$3,'captain',NOW())
     ON CONFLICT (ride_request_id, captain_user_id)
     DO UPDATE SET
       offered_fare_iqd = EXCLUDED.offered_fare_iqd,
       eta_minutes = EXCLUDED.eta_minutes,
       note = EXCLUDED.note,
       status = 'active',
       last_offer_iqd = EXCLUDED.offered_fare_iqd,
       last_offer_by = 'captain',
       updated_at = NOW()
     RETURNING *`,
    [
      Number(rideRequestId),
      Number(captainUserId),
      Number(offeredFareIqd),
      etaMinutes == null ? null : Number(etaMinutes),
      note || null,
    ]
  );

  const bid = normalizeBid(r.rows[0]);
  if (!bid) return null;

  await q(
    `UPDATE taxi_ride_request
     SET current_bid_id = COALESCE(current_bid_id, $2),
         updated_at = NOW()
     WHERE id = $1
       AND status = 'searching'`,
    [Number(rideRequestId), Number(bid.id)]
  );

  await ensureRideCurrentBid(rideRequestId);

  const full = await q(
    `SELECT
       b.*,
       u.full_name AS captain_full_name,
       u.phone AS captain_phone,
       cp.profile_image_url AS captain_profile_image_url,
       cp.car_image_url AS captain_car_image_url,
       cp.vehicle_type AS captain_vehicle_type,
       cp.car_make AS captain_car_make,
       cp.car_model AS captain_car_model,
       cp.car_year AS captain_car_year,
       cp.car_color AS captain_car_color,
       cp.plate_number AS captain_plate_number,
       cp.plate_governorate AS captain_plate_governorate,
       cp.plate_category AS captain_plate_category,
       cp.plate_letter AS captain_plate_letter,
       cp.plate_digits AS captain_plate_digits,
       cp.rating_avg AS captain_rating_avg,
       cp.rides_count AS captain_rides_count,
       CASE
         WHEN cpres.latitude IS NOT NULL AND cpres.longitude IS NOT NULL
         THEN ${distanceSql(
           "r.pickup_latitude",
           "r.pickup_longitude",
           "cpres.latitude",
           "cpres.longitude"
         )}
         ELSE NULL
       END AS distance_m
     FROM taxi_ride_bid b
     JOIN taxi_ride_request r ON r.id = b.ride_request_id
     JOIN app_user u ON u.id = b.captain_user_id
     LEFT JOIN taxi_captain_profile cp ON cp.user_id = b.captain_user_id
     LEFT JOIN taxi_captain_presence cpres ON cpres.captain_user_id = b.captain_user_id
     WHERE b.id = $1
     LIMIT 1`,
    [bid.id]
  );

  return normalizeBid(full.rows[0]);
}

export async function acceptRideBid({ rideId, bidId, customerUserId }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const rideLock = await client.query(
      `SELECT *
       FROM taxi_ride_request
       WHERE id = $1
         AND customer_user_id = $2
       FOR UPDATE`,
      [Number(rideId), Number(customerUserId)]
    );

    const rideRow = rideLock.rows[0];
    if (!rideRow) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }

    if (rideRow.status !== "searching") {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_ACCEPTING_BIDS" };
    }

    const bidLock = await client.query(
      `SELECT *
       FROM taxi_ride_bid
       WHERE id = $1
         AND ride_request_id = $2
       FOR UPDATE`,
      [Number(bidId), Number(rideId)]
    );

    const bidRow = bidLock.rows[0];
    if (!bidRow) {
      await client.query("ROLLBACK");
      return { code: "BID_NOT_FOUND" };
    }

    if (bidRow.status !== "active") {
      await client.query("ROLLBACK");
      return { code: "BID_NOT_ACTIVE" };
    }

    await lockCaptainAssignment(client, bidRow.captain_user_id);
    const captainBusyRide = await getCaptainActiveRideForUpdate(
      client,
      bidRow.captain_user_id
    );
    if (captainBusyRide && Number(captainBusyRide.id) !== Number(rideId)) {
      await client.query("ROLLBACK");
      return {
        code: "CAPTAIN_ALREADY_ASSIGNED",
        busyRideId: Number(captainBusyRide.id),
      };
    }

    await client.query(
      `UPDATE taxi_ride_request
       SET assigned_captain_user_id = $1,
           accepted_bid_id = $2,
           current_bid_id = NULL,
           agreed_fare_iqd = $3,
           status = 'captain_assigned',
           accepted_at = NOW(),
           updated_at = NOW()
       WHERE id = $4`,
      [
        Number(bidRow.captain_user_id),
        Number(bidRow.id),
        Number(bidRow.offered_fare_iqd),
        Number(rideId),
      ]
    );

    await client.query(
      `UPDATE taxi_ride_bid
       SET status = CASE WHEN id = $1 THEN 'accepted' ELSE 'rejected' END,
           updated_at = NOW()
       WHERE ride_request_id = $2
         AND status = 'active'`,
      [Number(bidId), Number(rideId)]
    );

    const bidsResult = await client.query(
      `SELECT id, captain_user_id, status
       FROM taxi_ride_bid
       WHERE ride_request_id = $1`,
      [Number(rideId)]
    );

    const ride = await queryRideById(client, rideId);
    const acceptedBid = normalizeBid({
      ...bidRow,
      id: Number(bidRow.id),
      ride_request_id: Number(rideId),
      captain_user_id: Number(bidRow.captain_user_id),
      status: "accepted",
    });

    await client.query("COMMIT");

    return {
      code: "OK",
      ride,
      acceptedBid,
      bids: bidsResult.rows.map((row) => ({
        id: Number(row.id),
        captainUserId: Number(row.captain_user_id),
        status: row.status,
      })),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function rejectCurrentRideBidByCustomer({
  rideId,
  customerUserId,
  bidId = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const ride = await lockRideForNegotiation(client, rideId, customerUserId);
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }
    if (ride.status !== "searching") {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_ACCEPTING_BIDS" };
    }

    const rideCurrentBid = await lockCurrentActiveBid(
      client,
      ride.id,
      ride.current_bid_id
    );
    let targetBid = bidId
      ? await lockRideBidById(client, ride.id, bidId)
      : rideCurrentBid;

    if (!targetBid) {
      if (bidId) {
        await client.query("ROLLBACK");
        return { code: "BID_NOT_FOUND" };
      }
      targetBid = await promoteNextActiveBid(client, ride.id);
    }
    if (!targetBid) {
      await client.query("COMMIT");
      return { code: "NO_ACTIVE_BID", ride: await getRideById(ride.id) };
    }

    if (targetBid.status !== "active") {
      await client.query("ROLLBACK");
      return { code: "BID_NOT_ACTIVE" };
    }

    await client.query(
      `UPDATE taxi_ride_bid
       SET status = 'rejected',
           updated_at = NOW()
       WHERE id = $1`,
      [Number(targetBid.id)]
    );

    const shouldPromote =
      !ride.current_bid_id || Number(rideCurrentBid?.id || 0) === Number(targetBid.id);
    const nextBid = shouldPromote
      ? await promoteNextActiveBid(client, ride.id)
      : rideCurrentBid;
    const fullRide = await queryRideById(client, ride.id);
    const bidsResult = await client.query(
      `SELECT id, captain_user_id, status
       FROM taxi_ride_bid
       WHERE ride_request_id = $1`,
      [Number(ride.id)]
    );

    await client.query("COMMIT");

    return {
      code: "OK",
      ride: fullRide,
      rejectedBid: targetBid,
      nextBid,
      bids: bidsResult.rows.map((row) => ({
        id: Number(row.id),
        captainUserId: Number(row.captain_user_id),
        status: row.status,
      })),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function counterOfferCurrentRideBidByCustomer({
  rideId,
  customerUserId,
  offeredFareIqd,
  note,
  bidId = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const ride = await lockRideForNegotiation(client, rideId, customerUserId);
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }
    if (ride.status !== "searching") {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_ACCEPTING_BIDS" };
    }

    const rideCurrentBid = await lockCurrentActiveBid(
      client,
      ride.id,
      ride.current_bid_id
    );
    let currentBid = bidId
      ? await lockRideBidById(client, ride.id, bidId)
      : rideCurrentBid;
    if (!currentBid) {
      currentBid = await promoteNextActiveBid(client, ride.id);
    }
    if (!currentBid) {
      await client.query("COMMIT");
      return { code: "NO_ACTIVE_BID", ride: await getRideById(ride.id) };
    }
    if (currentBid.status !== "active") {
      await client.query("ROLLBACK");
      return { code: "BID_NOT_ACTIVE" };
    }

    const nextCounterCount = (currentBid.counterOfferCount || 0) + 1;
    if (nextCounterCount > 6) {
      await client.query(
        `UPDATE taxi_ride_bid
         SET status = 'rejected',
             updated_at = NOW()
         WHERE id = $1`,
        [Number(currentBid.id)]
      );
      const nextBid = await promoteNextActiveBid(client, ride.id);
      const fullRide = await queryRideById(client, ride.id);
      await client.query("COMMIT");
      return {
        code: "COUNTER_LIMIT_REACHED",
        ride: fullRide,
        previousBid: currentBid,
        nextBid,
      };
    }

    const updateBid = await client.query(
      `UPDATE taxi_ride_bid
       SET offered_fare_iqd = $2,
           note = COALESCE(NULLIF($3, ''), note),
           counter_offer_count = $4,
           last_offer_iqd = $2,
           last_offer_by = 'customer',
           updated_at = NOW()
       WHERE id = $1
       RETURNING id, ride_request_id, captain_user_id, offered_fare_iqd, eta_minutes, note, status,
                 counter_offer_count, last_offer_iqd, last_offer_by, created_at, updated_at`,
      [
        Number(currentBid.id),
        Number(offeredFareIqd),
        note || "",
        Number(nextCounterCount),
      ]
    );

    const updatedBid = normalizeBid(updateBid.rows[0]);
    let switchedToNext = false;
    let nextBid = null;

    if ((updatedBid?.counterOfferCount || 0) >= 6) {
      await client.query(
        `UPDATE taxi_ride_bid
         SET status = 'rejected',
             updated_at = NOW()
         WHERE id = $1`,
        [Number(updatedBid.id)]
      );
      switchedToNext = true;
      nextBid = await promoteNextActiveBid(client, ride.id);
    } else {
      await client.query(
        `UPDATE taxi_ride_request
         SET current_bid_id = $2,
             updated_at = NOW()
         WHERE id = $1`,
        [Number(ride.id), Number(updatedBid.id)]
      );
    }

    const fullRide = await queryRideById(client, ride.id);
    const bidsResult = await client.query(
      `SELECT id, captain_user_id, status
       FROM taxi_ride_bid
       WHERE ride_request_id = $1`,
      [Number(ride.id)]
    );

    await client.query("COMMIT");

    return {
      code: switchedToNext ? "COUNTER_LIMIT_REACHED" : "OK",
      ride: fullRide,
      updatedBid,
      switchedToNext,
      nextBid,
      bids: bidsResult.rows.map((row) => ({
        id: Number(row.id),
        captainUserId: Number(row.captain_user_id),
        status: row.status,
      })),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function cancelRide({
  rideId,
  customerUserId,
  reasonCode = null,
  reasonText = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const lock = await client.query(
      `SELECT *
       FROM taxi_ride_request
       WHERE id = $1
         AND customer_user_id = $2
       FOR UPDATE`,
      [Number(rideId), Number(customerUserId)]
    );

    const ride = lock.rows[0];
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }

    const decision = evaluateTaxiCancellation({
      status: ride.status,
      actorRole: "customer",
    });

    if (decision.outcome === "already_closed") {
      // إعادة إرسال إلغاء لرحلة ملغاة مسبقاً = idempotent no-op.
      if (ride.status === "cancelled") {
        const full = await queryRideById(client, rideId);
        await client.query("COMMIT");
        return { code: "ALREADY_CANCELLED", ride: full };
      }
      await client.query("ROLLBACK");
      return { code: "RIDE_ALREADY_CLOSED", currentStatus: ride.status };
    }

    if (decision.outcome !== "allowed") {
      await client.query("ROLLBACK");
      return {
        code: decision.code || "TAXI_CANCELLATION_LOCKED",
        currentStatus: ride.status,
      };
    }

    await client.query(
      `UPDATE taxi_ride_request
       SET status = 'cancelled',
           current_bid_id = NULL,
           cancelled_at = NOW(),
           updated_at = NOW(),
           cancelled_by_role = 'customer',
           cancelled_by_user_id = $2,
           cancel_reason_code = $3,
           cancel_reason_text = $4,
           cancel_previous_status = $5,
           cancel_is_emergency = FALSE
       WHERE id = $1`,
      [
        Number(rideId),
        Number(customerUserId),
        reasonCode,
        reasonText,
        ride.status,
      ]
    );

    await client.query(
      `UPDATE taxi_ride_bid
       SET status = 'expired',
           updated_at = NOW()
       WHERE ride_request_id = $1
         AND status = 'active'`,
      [Number(rideId)]
    );

    const full = await queryRideById(client, rideId);

    await client.query("COMMIT");
    return { code: "OK", ride: full, previousStatus: ride.status };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function cancelRideByCaptain({
  rideId,
  captainUserId,
  reasonCode = null,
  reasonText = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const lock = await client.query(
      `SELECT *
       FROM taxi_ride_request
       WHERE id = $1
       FOR UPDATE`,
      [Number(rideId)]
    );

    const ride = lock.rows[0];
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }

    if (Number(ride.assigned_captain_user_id) !== Number(captainUserId)) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_ASSIGNED_TO_CAPTAIN" };
    }

    const decision = evaluateTaxiCancellation({
      status: ride.status,
      actorRole: "captain",
    });

    if (decision.outcome === "already_closed") {
      if (ride.status === "cancelled") {
        const full = await queryRideById(client, rideId);
        await client.query("COMMIT");
        return { code: "ALREADY_CANCELLED", ride: full };
      }
      await client.query("ROLLBACK");
      return { code: "RIDE_ALREADY_CLOSED", currentStatus: ride.status };
    }

    if (decision.outcome !== "allowed") {
      await client.query("ROLLBACK");
      return {
        code: decision.code || "TAXI_CANCELLATION_LOCKED",
        currentStatus: ride.status,
      };
    }

    await client.query(
      `UPDATE taxi_ride_request
       SET status = 'cancelled',
           current_bid_id = NULL,
           cancelled_at = NOW(),
           updated_at = NOW(),
           cancelled_by_role = 'captain',
           cancelled_by_user_id = $2,
           cancel_reason_code = $3,
           cancel_reason_text = $4,
           cancel_previous_status = $5,
           cancel_is_emergency = FALSE
       WHERE id = $1`,
      [
        Number(rideId),
        Number(captainUserId),
        reasonCode,
        reasonText,
        ride.status,
      ]
    );

    await client.query(
      `UPDATE taxi_ride_bid
       SET status = 'expired',
           updated_at = NOW()
       WHERE ride_request_id = $1
         AND status = 'active'`,
      [Number(rideId)]
    );

    const full = await queryRideById(client, rideId);

    await client.query("COMMIT");
    return { code: "OK", ride: full, previousStatus: ride.status };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function createRideEmergency({
  rideId,
  reportedByUserId,
  reportedByRole,
  category = "safety",
  message = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const lock = await client.query(
      `SELECT *
       FROM taxi_ride_request
       WHERE id = $1
       FOR UPDATE`,
      [Number(rideId)]
    );

    const ride = lock.rows[0];
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }

    if (TAXI_TERMINAL_STATUSES.includes(String(ride.status))) {
      await client.query("ROLLBACK");
      return { code: "RIDE_ALREADY_CLOSED", currentStatus: ride.status };
    }

    // Idempotency: أعِد استخدام تذكرة طوارئ مفتوحة لنفس الرحلة/المُبلِّغ إن وُجدت.
    const existing = await client.query(
      `SELECT *
       FROM taxi_ride_emergency
       WHERE ride_request_id = $1
         AND reported_by_user_id = $2
         AND status IN ('open', 'acknowledged')
       ORDER BY created_at DESC
       LIMIT 1`,
      [Number(rideId), Number(reportedByUserId)]
    );

    if (existing.rows[0]) {
      await client.query("COMMIT");
      return {
        code: "OK",
        emergency: existing.rows[0],
        ride,
        alreadyOpen: true,
      };
    }

    const inserted = await client.query(
      `INSERT INTO taxi_ride_emergency
         (ride_request_id, reported_by_user_id, reported_by_role,
          ride_status_at_report, category, message)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [
        Number(rideId),
        Number(reportedByUserId),
        reportedByRole,
        ride.status,
        category,
        message,
      ]
    );

    await client.query("COMMIT");
    return {
      code: "OK",
      emergency: inserted.rows[0],
      ride,
      alreadyOpen: false,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function adminEmergencyCancelRide({
  rideId,
  adminUserId,
  reasonText,
  secondApproverUserId = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const lock = await client.query(
      `SELECT *
       FROM taxi_ride_request
       WHERE id = $1
       FOR UPDATE`,
      [Number(rideId)]
    );

    const ride = lock.rows[0];
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }

    if (["completed", "expired"].includes(String(ride.status))) {
      await client.query("ROLLBACK");
      return { code: "RIDE_ALREADY_CLOSED", currentStatus: ride.status };
    }

    if (ride.status === "cancelled") {
      const full = await queryRideById(client, rideId);
      await client.query("COMMIT");
      return { code: "ALREADY_CANCELLED", ride: full };
    }

    await client.query(
      `UPDATE taxi_ride_request
       SET status = 'cancelled',
           current_bid_id = NULL,
           cancelled_at = NOW(),
           updated_at = NOW(),
           cancelled_by_role = 'admin',
           cancelled_by_user_id = $2,
           cancel_reason_code = 'emergency',
           cancel_reason_text = $3,
           cancel_previous_status = $4,
           cancel_is_emergency = TRUE
       WHERE id = $1`,
      [Number(rideId), Number(adminUserId), reasonText, ride.status]
    );

    await client.query(
      `UPDATE taxi_ride_bid
       SET status = 'expired',
           updated_at = NOW()
       WHERE ride_request_id = $1
         AND status = 'active'`,
      [Number(rideId)]
    );

    await client.query(
      `UPDATE taxi_ride_emergency
       SET status = 'cancelled_ride',
           resolution = 'emergency_cancel',
           resolution_note = $2,
           resolved_by_user_id = $3,
           resolved_at = NOW(),
           second_approver_user_id = COALESCE($4, second_approver_user_id),
           second_approved_at = CASE
             WHEN $4 IS NOT NULL THEN NOW()
             ELSE second_approved_at
           END,
           updated_at = NOW()
       WHERE ride_request_id = $1
         AND status IN ('open', 'acknowledged')`,
      [
        Number(rideId),
        reasonText,
        Number(adminUserId),
        secondApproverUserId ? Number(secondApproverUserId) : null,
      ]
    );

    const full = await queryRideById(client, rideId);

    await client.query("COMMIT");
    return { code: "OK", ride: full, previousStatus: ride.status };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listTaxiEmergencyRecipients({ limit = 50 } = {}) {
  const r = await q(
    `SELECT id
     FROM app_user
     WHERE (is_super_admin = TRUE OR role = 'admin')
       AND COALESCE(is_account_disabled, FALSE) = FALSE
     ORDER BY is_super_admin DESC, id ASC
     LIMIT $1`,
    [Number(limit)]
  );
  return r.rows.map((row) => Number(row.id));
}

export async function listRideEmergencies({
  status = null,
  limit = 100,
} = {}) {
  const safeLimit = Math.max(1, Math.min(500, Number(limit) || 100));
  const params = [];
  let where = "";
  if (status) {
    params.push(String(status));
    where = `WHERE e.status = $${params.length}`;
  }
  params.push(safeLimit);
  const r = await q(
    `SELECT
       e.*,
       r.customer_user_id,
       r.assigned_captain_user_id,
       r.status AS ride_status
     FROM taxi_ride_emergency e
     JOIN taxi_ride_request r ON r.id = e.ride_request_id
     ${where}
     ORDER BY
       CASE e.status WHEN 'open' THEN 0 WHEN 'acknowledged' THEN 1 ELSE 2 END,
       e.created_at DESC
     LIMIT $${params.length}`,
    params
  );
  return r.rows;
}

export async function rateCompletedRideByCustomer({
  rideId,
  customerUserId,
  rating,
  review,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const lock = await client.query(
      `SELECT id, status, customer_user_id, assigned_captain_user_id
       FROM taxi_ride_request
       WHERE id = $1
         AND customer_user_id = $2
       FOR UPDATE`,
      [Number(rideId), Number(customerUserId)]
    );
    const ride = lock.rows[0];
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }

    if (ride.status !== "completed") {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_COMPLETED", currentStatus: ride.status };
    }

    if (!ride.assigned_captain_user_id) {
      await client.query("ROLLBACK");
      return { code: "RIDE_CAPTAIN_NOT_FOUND" };
    }

    const updated = await client.query(
      `UPDATE taxi_ride_request
       SET captain_rating = $3,
           captain_review = NULLIF($4, ''),
           captain_rated_at = NOW(),
           updated_at = NOW()
       WHERE id = $1
         AND customer_user_id = $2
       RETURNING id, assigned_captain_user_id, captain_rating, captain_review, captain_rated_at`,
      [
        Number(rideId),
        Number(customerUserId),
        Number(rating),
        review || "",
      ]
    );
    const rated = updated.rows[0];
    if (!rated) {
      await client.query("ROLLBACK");
      return { code: "RATING_UPDATE_FAILED" };
    }

    const captainUserId = Number(rated.assigned_captain_user_id);

    const agg = await client.query(
      `SELECT
         COALESCE(AVG(captain_rating), 0)::numeric(3,2) AS avg_rating,
         COUNT(*) FILTER (WHERE captain_rating IS NOT NULL)::int AS rated_count,
         COUNT(*)::int AS total_completed_count
       FROM taxi_ride_request
       WHERE assigned_captain_user_id = $1
         AND status = 'completed'`,
      [captainUserId]
    );
    const aggRow = agg.rows[0] || {};

    await client.query(
      `UPDATE taxi_captain_profile
       SET rating_avg = $2,
           rides_count = $3,
           updated_at = NOW()
       WHERE user_id = $1`,
      [
        captainUserId,
        Number(aggRow.avg_rating || 0),
        Number(aggRow.total_completed_count || 0),
      ]
    );

    const fullRide = await queryRideById(client, rideId);

    await client.query("COMMIT");
    return {
      code: "OK",
      ride: fullRide,
      captainUserId,
      rating: Number(rated.captain_rating),
      review: rated.captain_review || null,
      ratedAt: rated.captain_rated_at || null,
      captainRatingAvg: Number(aggRow.avg_rating || 0),
      captainRatedCount: Number(aggRow.rated_count || 0),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function transitionRideStatus({ rideId, captainUserId, nextStatus }) {
  const client = await pool.connect();
  let committed = false;
  try {
    await client.query("BEGIN");

    const lock = await client.query({
      text: `SELECT *
       FROM taxi_ride_request
       WHERE id = $1
       FOR UPDATE`,
      values: [Number(rideId)],
      ...TAXI_STATUS_TRANSITION_QUERY_OPTIONS,
    });

    const ride = lock.rows[0];
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }

    if (Number(ride.assigned_captain_user_id) !== Number(captainUserId)) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_ASSIGNED_TO_CAPTAIN" };
    }

    const current = ride.status;
    const allowed = {
      captain_arriving: ["captain_assigned"],
      ride_started: ["captain_assigned", "captain_arriving"],
      completed: ["ride_started", "captain_arriving"],
    };

    if (!allowed[nextStatus] || !allowed[nextStatus].includes(current)) {
      await client.query("ROLLBACK");
      return { code: "INVALID_STATUS_TRANSITION", currentStatus: current };
    }

    const setParts = ["status = $2", "updated_at = NOW()"];
    const params = [Number(rideId), nextStatus];

    if (nextStatus === "captain_arriving") {
      setParts.push("captain_arriving_at = COALESCE(captain_arriving_at, NOW())");
    }

    if (nextStatus === "ride_started") {
      setParts.push("started_at = COALESCE(started_at, NOW())");
      setParts.push("captain_arriving_at = COALESCE(captain_arriving_at, NOW())");
    }

    if (nextStatus === "completed") {
      setParts.push("completed_at = NOW()");
      setParts.push("started_at = COALESCE(started_at, NOW())");
      setParts.push("captain_arriving_at = COALESCE(captain_arriving_at, NOW())");
    }

    await client.query({
      text: `UPDATE taxi_ride_request
       SET ${setParts.join(", ")}
       WHERE id = $1`,
      values: params,
      ...TAXI_STATUS_TRANSITION_QUERY_OPTIONS,
    });

    await client.query("COMMIT");
    committed = true;
    const full = await queryRideById(
      pool,
      rideId,
      TAXI_STATUS_TRANSITION_QUERY_OPTIONS
    );
    return { code: "OK", ride: full, previousStatus: current };
  } catch (error) {
    if (!committed) {
      try {
        await client.query("ROLLBACK");
      } catch {
        // Ignore rollback failures after upstream query timeouts.
      }
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function acceptRideByCaptain({ rideId, captainUserId }) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const rideLock = await client.query(
      `SELECT *
       FROM taxi_ride_request
       WHERE id = $1
       FOR UPDATE`,
      [Number(rideId)]
    );

    const rideRow = rideLock.rows[0];
    if (!rideRow) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }

    if (rideRow.status !== "searching") {
      await client.query("ROLLBACK");
      return rideRow.assigned_captain_user_id || rideRow.accepted_bid_id
        ? { code: "RIDE_ALREADY_ASSIGNED" }
        : { code: "RIDE_NOT_ACCEPTING_BIDS" };
    }

    await lockCaptainAssignment(client, captainUserId);
    const captainBusyRide = await getCaptainActiveRideForUpdate(
      client,
      captainUserId
    );
    if (captainBusyRide && Number(captainBusyRide.id) !== Number(rideId)) {
      await client.query("ROLLBACK");
      return {
        code: "CAPTAIN_ALREADY_ASSIGNED",
        busyRideId: Number(captainBusyRide.id),
      };
    }

    const acceptedFareIqd = Number(rideRow.proposed_fare_iqd);
    if (!Number.isFinite(acceptedFareIqd) || acceptedFareIqd <= 0) {
      await client.query("ROLLBACK");
      return { code: "INVALID_FARE" };
    }

    const acceptedBidResult = await client.query(
      `INSERT INTO taxi_ride_bid
        (
          ride_request_id,
          captain_user_id,
          offered_fare_iqd,
          eta_minutes,
          note,
          status,
          counter_offer_count,
          last_offer_iqd,
          last_offer_by,
          updated_at
        )
       VALUES ($1,$2,$3,NULL,NULL,'accepted',0,$3,'customer',NOW())
       ON CONFLICT (ride_request_id, captain_user_id)
       DO UPDATE SET
         offered_fare_iqd = EXCLUDED.offered_fare_iqd,
         eta_minutes = NULL,
         note = COALESCE(taxi_ride_bid.note, EXCLUDED.note),
         status = 'accepted',
         counter_offer_count = 0,
         last_offer_iqd = EXCLUDED.offered_fare_iqd,
         last_offer_by = 'customer',
         updated_at = NOW()
       RETURNING *`,
      [Number(rideId), Number(captainUserId), acceptedFareIqd]
    );
    const acceptedBid = normalizeBid(acceptedBidResult.rows[0]);

    await client.query(
      `UPDATE taxi_ride_request
       SET assigned_captain_user_id = $1,
           accepted_bid_id = $2,
           current_bid_id = NULL,
           agreed_fare_iqd = $3,
           status = 'captain_assigned',
           accepted_at = NOW(),
           updated_at = NOW()
       WHERE id = $4`,
      [
        Number(captainUserId),
        Number(acceptedBid.id),
        acceptedFareIqd,
        Number(rideId),
      ]
    );

    await client.query(
      `UPDATE taxi_ride_bid
       SET status = CASE WHEN captain_user_id = $1 THEN 'accepted' ELSE 'rejected' END,
           updated_at = NOW()
       WHERE ride_request_id = $2
         AND status = 'active'`,
      [Number(captainUserId), Number(rideId)]
    );

    const ride = await queryRideById(client, rideId);
    const bidsResult = await client.query(
      `SELECT id, captain_user_id, status
       FROM taxi_ride_bid
       WHERE ride_request_id = $1
       ORDER BY created_at ASC, id ASC`,
      [Number(rideId)]
    );

    await client.query("COMMIT");

    return {
      code: "OK",
      ride,
      acceptedBid,
      bids: bidsResult.rows.map((row) => ({
        id: Number(row.id),
        captainUserId: Number(row.captain_user_id),
        status: row.status,
      })),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function insertRideLocation({
  rideId,
  captainUserId,
  latitude,
  longitude,
  headingDeg,
  speedKmh,
  accuracyM,
  source = "captain_app",
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const rideCheck = await client.query(
      `SELECT id, assigned_captain_user_id, status
       FROM taxi_ride_request
       WHERE id = $1
       FOR UPDATE`,
      [Number(rideId)]
    );

    const ride = rideCheck.rows[0];
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }

    if (Number(ride.assigned_captain_user_id) !== Number(captainUserId)) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_ASSIGNED_TO_CAPTAIN" };
    }

    if (!isTaxiTrackableRideStatus(ride.status)) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_TRACKABLE", currentStatus: ride.status };
    }

    const inserted = await client.query(
      `INSERT INTO taxi_ride_location_log
        (
          ride_request_id,
          captain_user_id,
          latitude,
          longitude,
          heading_deg,
          speed_kmh,
          accuracy_m,
          source
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       RETURNING *`,
      [
        Number(rideId),
        Number(captainUserId),
        Number(latitude),
        Number(longitude),
        headingDeg == null ? null : Number(headingDeg),
        speedKmh == null ? null : Number(speedKmh),
        accuracyM == null ? null : Number(accuracyM),
        source,
      ]
    );

    await client.query(
      `INSERT INTO taxi_captain_presence
        (
          captain_user_id,
          is_online,
          latitude,
          longitude,
          heading_deg,
          speed_kmh,
          accuracy_m,
          last_seen_at,
          updated_at
        )
       VALUES ($1,TRUE,$2,$3,$4,$5,$6,NOW(),NOW())
       ON CONFLICT (captain_user_id)
       DO UPDATE SET
         is_online = TRUE,
         latitude = EXCLUDED.latitude,
         longitude = EXCLUDED.longitude,
         heading_deg = EXCLUDED.heading_deg,
         speed_kmh = EXCLUDED.speed_kmh,
         accuracy_m = EXCLUDED.accuracy_m,
         last_seen_at = NOW(),
         updated_at = NOW()`,
      [
        Number(captainUserId),
        Number(latitude),
        Number(longitude),
        headingDeg == null ? null : Number(headingDeg),
        speedKmh == null ? null : Number(speedKmh),
        accuracyM == null ? null : Number(accuracyM),
      ]
    );

    await client.query("COMMIT");
    return { code: "OK", location: normalizeLocation(inserted.rows[0]) };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function getLatestRideLocation(rideId) {
  const r = await q(
    `SELECT *
     FROM taxi_ride_location_log
     WHERE ride_request_id = $1
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    [Number(rideId)]
  );
  return normalizeLocation(r.rows[0]);
}

export async function listRideEvents(rideId, { limit = 100 } = {}) {
  const r = await q(
    `SELECT *
     FROM taxi_ride_event
     WHERE ride_request_id = $1
     ORDER BY created_at DESC, id DESC
     LIMIT $2`,
    [Number(rideId), Math.max(1, Math.min(500, Number(limit) || 100))]
  );
  return r.rows.map(normalizeEvent);
}

export async function createRideEvent({
  rideRequestId,
  actorUserId,
  eventType,
  message,
  payload,
}) {
  const r = await q(
    `INSERT INTO taxi_ride_event
      (ride_request_id, actor_user_id, event_type, message, payload)
     VALUES ($1,$2,$3,$4,$5::jsonb)
     RETURNING *`,
    [
      Number(rideRequestId),
      actorUserId == null ? null : Number(actorUserId),
      String(eventType || "event"),
      message || null,
      payload ? JSON.stringify(payload) : null,
    ]
  );

  return normalizeEvent(r.rows[0]);
}

export async function listRideChatMessages(rideId, { limit = 80 } = {}) {
  const r = await q(
    `SELECT
       m.*,
       u.full_name AS sender_full_name,
       u.phone AS sender_phone,
       u.image_url AS sender_image_url
     FROM taxi_ride_chat_message m
     JOIN app_user u
       ON u.id = m.sender_user_id
     WHERE m.ride_request_id = $1
     ORDER BY m.id DESC
     LIMIT $2`,
    [Number(rideId), Math.max(1, Math.min(400, Number(limit) || 80))]
  );

  return r.rows.map(normalizeChatMessage);
}

export async function insertRideChatMessage({
  rideRequestId,
  senderUserId,
  senderRole,
  messageType = "text",
  messageText,
  offeredFareIqd = null,
}) {
  const r = await q(
    `INSERT INTO taxi_ride_chat_message
      (
        ride_request_id,
        sender_user_id,
        sender_role,
        message_type,
        message_text,
        offered_fare_iqd
      )
     VALUES ($1,$2,$3,$4,$5,$6)
     RETURNING id, ride_request_id, sender_user_id, sender_role, message_type,
               message_text, offered_fare_iqd, created_at`,
    [
      Number(rideRequestId),
      Number(senderUserId),
      String(senderRole || "system"),
      String(messageType || "text"),
      messageText || null,
      offeredFareIqd == null ? null : Number(offeredFareIqd),
    ]
  );

  const msg = normalizeChatMessage(r.rows[0]);
  if (!msg) return null;

  const sender = await q(
    `SELECT full_name AS sender_full_name, phone AS sender_phone, image_url AS sender_image_url
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(senderUserId)]
  );

  return normalizeChatMessage({
    ...r.rows[0],
    sender_full_name: sender.rows[0]?.sender_full_name || null,
    sender_phone: sender.rows[0]?.sender_phone || null,
    sender_image_url: sender.rows[0]?.sender_image_url || null,
  });
}

export async function getActiveRideCallSession(rideId) {
  const r = await q(
    `SELECT *
     FROM taxi_ride_call_session
     WHERE ride_request_id = $1
       AND status IN ('ringing', 'active')
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    [Number(rideId)]
  );
  return normalizeCallSession(r.rows[0]);
}

export async function getRideCallSessionById(sessionId) {
  const r = await q(
    `SELECT *
     FROM taxi_ride_call_session
     WHERE id = $1
     LIMIT 1`,
    [Number(sessionId)]
  );
  return normalizeCallSession(r.rows[0]);
}

export async function createRideCallSession({
  rideRequestId,
  initiatorUserId,
  receiverUserId,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    await client.query(
      `UPDATE taxi_ride_call_session
       SET status = 'ended',
           ended_at = NOW(),
           ended_by_user_id = $2,
           end_reason = COALESCE(end_reason, 'replaced'),
           updated_at = NOW()
       WHERE ride_request_id = $1
         AND status IN ('ringing', 'active')`,
      [Number(rideRequestId), Number(initiatorUserId)]
    );

    const created = await client.query(
      `INSERT INTO taxi_ride_call_session
        (
          ride_request_id,
          initiator_user_id,
          receiver_user_id,
          status,
          started_at,
          created_at,
          updated_at
        )
       VALUES ($1,$2,$3,'ringing',NOW(),NOW(),NOW())
       RETURNING *`,
      [Number(rideRequestId), Number(initiatorUserId), Number(receiverUserId)]
    );

    await client.query("COMMIT");
    return normalizeCallSession(created.rows[0]);
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function markRideCallAnswered({ sessionId, answeredByUserId }) {
  const r = await q(
    `UPDATE taxi_ride_call_session
     SET status = 'active',
         answered_at = COALESCE(answered_at, NOW()),
         updated_at = NOW()
     WHERE id = $1
       AND status IN ('ringing', 'active')
     RETURNING *`,
    [Number(sessionId)]
  );
  return normalizeCallSession(r.rows[0]);
}

export async function endRideCallSession({
  sessionId,
  endedByUserId,
  endReason = "hangup",
  status = "ended",
}) {
  const normalizedStatus = ["ended", "declined", "missed"].includes(
    String(status || "").toLowerCase()
  )
    ? String(status || "").toLowerCase()
    : "ended";

  const r = await q(
    `UPDATE taxi_ride_call_session
     SET status = $2,
         ended_at = COALESCE(ended_at, NOW()),
         ended_by_user_id = $3,
         end_reason = $4,
         updated_at = NOW()
     WHERE id = $1
       AND status IN ('ringing', 'active')
     RETURNING *`,
    [
      Number(sessionId),
      normalizedStatus,
      endedByUserId == null ? null : Number(endedByUserId),
      endReason || null,
    ]
  );
  return normalizeCallSession(r.rows[0]);
}

export async function endActiveRideCallByRide({
  rideId,
  endedByUserId,
  endReason = "hangup",
  status = "ended",
}) {
  const normalizedStatus = ["ended", "declined", "missed"].includes(
    String(status || "").toLowerCase()
  )
    ? String(status || "").toLowerCase()
    : "ended";

  const r = await q(
    `UPDATE taxi_ride_call_session
     SET status = $2,
         ended_at = COALESCE(ended_at, NOW()),
         ended_by_user_id = $3,
         end_reason = $4,
         updated_at = NOW()
     WHERE ride_request_id = $1
       AND status IN ('ringing', 'active')
     RETURNING *`,
    [
      Number(rideId),
      normalizedStatus,
      endedByUserId == null ? null : Number(endedByUserId),
      endReason || null,
    ]
  );
  return r.rows.map(normalizeCallSession);
}

export async function insertRideCallSignal({
  callSessionId,
  rideRequestId,
  senderUserId,
  signalType,
  signalPayload = null,
}) {
  const r = await q(
    `INSERT INTO taxi_ride_call_signal
      (call_session_id, ride_request_id, sender_user_id, signal_type, signal_payload)
     VALUES ($1,$2,$3,$4,$5::jsonb)
     RETURNING *`,
    [
      Number(callSessionId),
      Number(rideRequestId),
      Number(senderUserId),
      String(signalType || "ice"),
      signalPayload == null ? null : JSON.stringify(signalPayload),
    ]
  );
  return normalizeCallSignal(r.rows[0]);
}

export async function listRideCallSignals(callSessionId, { limit = 160 } = {}) {
  const r = await q(
    `SELECT *
     FROM taxi_ride_call_signal
     WHERE call_session_id = $1
     ORDER BY id DESC
     LIMIT $2`,
    [Number(callSessionId), Math.max(1, Math.min(800, Number(limit) || 160))]
  );
  return r.rows.map(normalizeCallSignal);
}

export async function getRideCallState(rideId, { signalLimit = 160 } = {}) {
  const session = await getActiveRideCallSession(rideId);
  if (!session) return { session: null, signals: [] };
  const signals = await listRideCallSignals(session.id, { limit: signalLimit });
  return { session, signals };
}

export async function listNearbyOpenRidesForCaptain(captainUserId, { radiusM = 15000, limit = 40 } = {}) {
  const presence = await getCaptainPresence(captainUserId);
  if (!presence || !presence.isOnline || presence.latitude == null || presence.longitude == null) {
    return [];
  }

  const distanceExpr = distanceSql(
    "r.pickup_latitude",
    "r.pickup_longitude",
    "$1",
    "$2"
  );

  const r = await q(
    `SELECT
       r.*,
       cu.full_name AS customer_full_name,
       cu.phone AS customer_phone,
       ca.full_name AS captain_full_name,
       ca.phone AS captain_phone,
       cp.profile_image_url AS captain_profile_image_url,
       cp.car_image_url AS captain_car_image_url,
       cp.vehicle_type AS captain_vehicle_type,
       cp.car_make AS captain_car_make,
       cp.car_model AS captain_car_model,
       cp.car_year AS captain_car_year,
       cp.car_color AS captain_car_color,
       cp.plate_number AS captain_plate_number,
       cp.plate_governorate AS captain_plate_governorate,
       cp.plate_category AS captain_plate_category,
       cp.plate_letter AS captain_plate_letter,
       cp.plate_digits AS captain_plate_digits,
       cp.rating_avg AS captain_rating_avg,
       cp.rides_count AS captain_rides_count,
       ${distanceExpr} AS distance_m,
       mb.id AS my_bid_id,
       mb.offered_fare_iqd AS my_offered_fare_iqd,
       mb.eta_minutes AS my_eta_minutes,
       mb.status AS my_bid_status,
       mb.counter_offer_count AS my_counter_offer_count,
       mb.last_offer_iqd AS my_last_offer_iqd,
       mb.last_offer_by AS my_last_offer_by,
       mb.created_at AS my_bid_created_at,
       mb.updated_at AS my_bid_updated_at
     FROM taxi_ride_request r
     LEFT JOIN app_user cu ON cu.id = r.customer_user_id
     LEFT JOIN app_user ca ON ca.id = r.assigned_captain_user_id
     LEFT JOIN taxi_captain_profile cp ON cp.user_id = r.assigned_captain_user_id
     LEFT JOIN taxi_ride_bid mb
       ON mb.ride_request_id = r.id
      AND mb.captain_user_id = $3
     LEFT JOIN taxi_ride_decline td
       ON td.ride_request_id = r.id
      AND td.captain_user_id = $3
      AND COALESCE(td.pricing_round, 1) = COALESCE(r.pricing_round, 1)
     WHERE r.status = 'searching'
       AND td.id IS NULL
       AND ${distanceExpr} <= r.search_radius_m
       AND ${distanceExpr} <= $4
     ORDER BY distance_m ASC, r.created_at DESC
     LIMIT $5`,
    [
      Number(presence.latitude),
      Number(presence.longitude),
      Number(captainUserId),
      Number(radiusM),
      Math.max(1, Math.min(200, Number(limit) || 40)),
    ]
  );

  return r.rows.map(normalizeRide);
}

export function isTaxiTrackableRideStatus(status) {
  return ["captain_assigned", "captain_arriving", "ride_started"].includes(
    String(status || "").trim().toLowerCase()
  );
}

export async function declineRideByCaptain({ rideId, captainUserId }) {
  await ensureSchema();

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const rideLock = await client.query(
      `SELECT id, status, pricing_round
       FROM taxi_ride_request
       WHERE id = $1
       FOR UPDATE`,
      [Number(rideId)]
    );
    const ride = rideLock.rows[0];
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }
    if (ride.status !== "searching") {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_SEARCHING", currentStatus: ride.status };
    }

    const pricingRound = Math.max(1, Number(ride.pricing_round) || 1);
    const insertDecline = await client.query(
      `INSERT INTO taxi_ride_decline (ride_request_id, captain_user_id, pricing_round)
       VALUES ($1, $2, $3)
       ON CONFLICT (ride_request_id, captain_user_id, pricing_round) DO NOTHING
       RETURNING id`,
      [Number(rideId), Number(captainUserId), pricingRound]
    );

    const rejectedCountResult = await client.query(
      `SELECT COUNT(*)::int AS rejected_captains_count
       FROM taxi_ride_decline
       WHERE ride_request_id = $1
         AND COALESCE(pricing_round, 1) = $2`,
      [Number(rideId), pricingRound]
    );
    const rejectedCaptainsCount = Number(
      rejectedCountResult.rows[0]?.rejected_captains_count || 0
    );

    if (rejectedCaptainsCount >= 5) {
      await client.query(
        `UPDATE taxi_ride_bid
         SET status = 'rejected',
             updated_at = NOW()
         WHERE ride_request_id = $1
           AND status = 'active'`,
        [Number(rideId)]
      );
      await client.query(
        `UPDATE taxi_ride_request
         SET status = 'price_raise_required',
             price_raise_required_at = COALESCE(price_raise_required_at, NOW()),
             current_bid_id = NULL,
             rejected_captains_count = $2,
             search_phase = 1,
             next_escalation_at = NULL,
             final_acceptance_deadline_at = NULL,
             search_radius_m = GREATEST(search_radius_m, 15000),
             updated_at = NOW()
         WHERE id = $1`,
        [Number(rideId), rejectedCaptainsCount]
      );
    } else if (insertDecline.rows[0]) {
      await client.query(
        `UPDATE taxi_ride_request
         SET rejected_captains_count = $2,
             updated_at = NOW()
         WHERE id = $1`,
        [Number(rideId), rejectedCaptainsCount]
      );
    }

    const fullRide = await queryRideById(client, rideId);
    await client.query("COMMIT");
    return {
      code: "OK",
      ride: fullRide,
      inserted: !!insertDecline.rows[0],
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function raiseRideFare({
  rideId,
  customerUserId,
  proposedFareIqd,
}) {
  await ensureSchema();

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const rideLock = await client.query(
      `SELECT *
       FROM taxi_ride_request
       WHERE id = $1
         AND customer_user_id = $2
       FOR UPDATE`,
      [Number(rideId), Number(customerUserId)]
    );
    const ride = rideLock.rows[0];
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }

    if (String(ride.status || "").trim().toLowerCase() !== "price_raise_required") {
      await client.query("ROLLBACK");
      return {
        code: "RIDE_NOT_PRICE_RAISE_REQUIRED",
        currentStatus: ride.status,
      };
    }

    const currentFare = Number(ride.proposed_fare_iqd);
    const nextFare = Number(proposedFareIqd);
    if (!Number.isFinite(nextFare) || nextFare <= currentFare) {
      await client.query("ROLLBACK");
      return {
        code: "FARE_NOT_INCREASED",
        currentFare,
      };
    }

    await client.query(
      `UPDATE taxi_ride_bid
       SET status = 'rejected',
           updated_at = NOW()
       WHERE ride_request_id = $1
         AND status = 'active'`,
      [Number(rideId)]
    );

    await client.query(
      `UPDATE taxi_ride_request
       SET previous_proposed_fare_iqd = proposed_fare_iqd,
           proposed_fare_iqd = $2,
           pricing_round = COALESCE(pricing_round, 1) + 1,
           fare_version = COALESCE(fare_version, 1) + 1,
           rejected_captains_count = 0,
           current_bid_id = NULL,
           price_raise_required_at = NULL,
           price_raise_prompted_at = NULL,
           search_phase = 1,
           next_escalation_at = NOW() + INTERVAL '5 minutes',
           final_acceptance_deadline_at = NOW() + INTERVAL '5 minutes',
           search_radius_m = GREATEST(search_radius_m, 15000),
           status = 'searching',
           updated_at = NOW()
       WHERE id = $1`,
      [Number(rideId), nextFare]
    );

    const fullRide = await queryRideById(client, rideId);
    await client.query("COMMIT");
    return {
      code: "OK",
      ride: fullRide,
      previousFareIqd: currentFare,
      nextFareIqd: nextFare,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function markRidePriceRaisePrompted(rideId) {
  const r = await q(
    `UPDATE taxi_ride_request
     SET price_raise_prompted_at = COALESCE(price_raise_prompted_at, NOW()),
         updated_at = NOW()
     WHERE id = $1
       AND price_raise_prompted_at IS NULL
     RETURNING id, customer_user_id`,
    [Number(rideId)]
  );
  if (!r.rows[0]) return { updated: false, customerUserId: null };
  return {
    updated: true,
    customerUserId: Number(r.rows[0].customer_user_id),
  };
}

export async function listRidesReadyForSearchProgression({ limit = 80 } = {}) {
  const r = await q(
    `${RIDE_SELECT}
     WHERE r.status = 'searching'
       AND r.search_phase IN (1, 2)
       AND r.next_escalation_at IS NOT NULL
       AND r.next_escalation_at <= NOW()
     ORDER BY r.next_escalation_at ASC, r.created_at ASC
     LIMIT $1`,
    [Math.max(1, Math.min(500, Number(limit) || 80))]
  );

  return r.rows.map(normalizeRide);
}

export async function hasActiveBids(rideId) {
  const r = await q(
    `SELECT 1
     FROM taxi_ride_bid
     WHERE ride_request_id = $1
       AND status = 'active'
     LIMIT 1`,
    [Number(rideId)]
  );
  return Boolean(r.rows[0]);
}

export async function advanceRideToExpandedSearch({ rideId, expandedRadiusM = 15000 }) {
  const r = await q(
    `UPDATE taxi_ride_request
     SET search_phase = 2,
         search_radius_m = GREATEST(search_radius_m, $2),
         next_escalation_at = NOW() + INTERVAL '5 minutes',
         updated_at = NOW()
     WHERE id = $1
       AND status = 'searching'
       AND search_phase = 1
     RETURNING id`,
    [Number(rideId), Number(expandedRadiusM)]
  );

  if (!r.rows[0]) return null;
  return getRideById(rideId);
}

export async function markRideNoCaptainFound(rideId) {
  const r = await q(
    `UPDATE taxi_ride_request
     SET search_phase = 3,
         no_captain_notified_at = COALESCE(no_captain_notified_at, NOW()),
         next_escalation_at = NULL,
         updated_at = NOW()
     WHERE id = $1
       AND status = 'searching'
       AND search_phase = 2
       AND no_captain_notified_at IS NULL
     RETURNING id`,
    [Number(rideId)]
  );

  if (!r.rows[0]) return null;
  return getRideById(rideId);
}

export async function postponeRideEscalation({ rideId, minutes = 10 }) {
  const safeMinutes = Math.max(1, Math.min(60, Number(minutes) || 10));
  await q(
    `UPDATE taxi_ride_request
     SET next_escalation_at = NOW() + ($2::text || ' minutes')::interval,
         updated_at = NOW()
     WHERE id = $1
       AND status = 'searching'
       AND search_phase = 2`,
    [Number(rideId), String(safeMinutes)]
  );
}

export async function listRidesWithStaleCurrentBid({
  timeoutSeconds = 90,
  limit = 120,
} = {}) {
  const safeTimeout = Math.max(15, Math.min(600, Number(timeoutSeconds) || 90));
  const safeLimit = Math.max(1, Math.min(500, Number(limit) || 120));

  const r = await q(
    `SELECT
       r.id AS ride_id,
       r.customer_user_id,
       r.current_bid_id,
       b.captain_user_id,
       b.updated_at AS bid_updated_at
     FROM taxi_ride_request r
     JOIN taxi_ride_bid b
       ON b.id = r.current_bid_id
      AND b.status = 'active'
     WHERE r.status = 'searching'
       AND r.current_bid_id IS NOT NULL
       AND b.updated_at <= NOW() - ($1::text || ' seconds')::interval
     ORDER BY b.updated_at ASC
     LIMIT $2`,
    [String(safeTimeout), safeLimit]
  );

  return r.rows.map((row) => ({
    rideId: Number(row.ride_id),
    customerUserId: Number(row.customer_user_id),
    currentBidId: Number(row.current_bid_id),
    captainUserId: Number(row.captain_user_id),
    bidUpdatedAt: row.bid_updated_at,
  }));
}

export async function timeoutCurrentRideBidAndPromote({
  rideId,
  expectedBidId = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const rideLock = await client.query(
      `SELECT id, customer_user_id, status, current_bid_id
       FROM taxi_ride_request
       WHERE id = $1
       FOR UPDATE`,
      [Number(rideId)]
    );
    const ride = rideLock.rows[0];
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }
    if (ride.status !== "searching") {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_SEARCHING", currentStatus: ride.status };
    }

    let currentBid = await lockCurrentActiveBid(
      client,
      ride.id,
      ride.current_bid_id
    );
    if (!currentBid) {
      const nextBid = await promoteNextActiveBid(client, ride.id);
      const fullRide = await queryRideById(client, ride.id);
      await client.query("COMMIT");
      return {
        code: "NO_ACTIVE_CURRENT_BID",
        ride: fullRide,
        nextBid,
      };
    }

    if (expectedBidId != null && Number(currentBid.id) !== Number(expectedBidId)) {
      await client.query("ROLLBACK");
      return {
        code: "BID_CHANGED",
        currentBid,
      };
    }

    const timedOut = await client.query(
      `UPDATE taxi_ride_bid
       SET status = 'rejected',
           updated_at = NOW()
       WHERE id = $1
         AND status = 'active'
       RETURNING id`,
      [Number(currentBid.id)]
    );
    if (!timedOut.rows[0]) {
      await client.query("ROLLBACK");
      return { code: "BID_ALREADY_CLOSED" };
    }

    const nextBid = await promoteNextActiveBid(client, ride.id);
    const fullRide = await queryRideById(client, ride.id);
    const bidsResult = await client.query(
      `SELECT id, captain_user_id, status
       FROM taxi_ride_bid
       WHERE ride_request_id = $1`,
      [Number(ride.id)]
    );

    await client.query("COMMIT");

    return {
      code: "OK",
      ride: fullRide,
      timedOutBid: currentBid,
      nextBid,
      bids: bidsResult.rows.map((row) => ({
        id: Number(row.id),
        captainUserId: Number(row.captain_user_id),
        status: row.status,
      })),
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listBidCaptainUserIds(rideId) {
  const r = await q(
    `SELECT DISTINCT captain_user_id
     FROM taxi_ride_bid
     WHERE ride_request_id = $1`,
    [Number(rideId)]
  );
  return r.rows.map((row) => Number(row.captain_user_id));
}

export async function listStaleRingingCallSessions({
  timeoutSeconds = 35,
  limit = 120,
} = {}) {
  const safeTimeout = Math.max(10, Math.min(300, Number(timeoutSeconds) || 35));
  const safeLimit = Math.max(1, Math.min(500, Number(limit) || 120));

  const r = await q(
    `SELECT *
     FROM taxi_ride_call_session
     WHERE status = 'ringing'
       AND started_at <= NOW() - ($1::text || ' seconds')::interval
     ORDER BY started_at ASC, id ASC
     LIMIT $2`,
    [String(safeTimeout), safeLimit]
  );

  return r.rows.map(normalizeCallSession);
}

export async function listCaptainRideHistory(captainUserId, { limit = 20 } = {}) {
  const r = await q(
    `${RIDE_SELECT}
     WHERE r.assigned_captain_user_id = $1
       AND r.status IN ('completed', 'cancelled', 'expired')
     ORDER BY r.created_at DESC
     LIMIT $2`,
    [Number(captainUserId), Math.max(1, Math.min(200, Number(limit) || 20))]
  );

  return r.rows.map(normalizeRide);
}

export async function listCustomerRideHistoryByPeriod(
  customerUserId,
  { period = "month", limit = 40 } = {}
) {
  const normalizedPeriod = ["day", "week", "month", "all"].includes(String(period || "").toLowerCase())
    ? String(period || "").toLowerCase()
    : "month";

  const r = await q(
    `${RIDE_SELECT}
     WHERE r.customer_user_id = $1
       AND r.status IN ('completed', 'cancelled', 'expired')
       AND (
         $3::text = 'all'
         OR ($3::text = 'day' AND r.created_at >= DATE_TRUNC('day', NOW()))
         OR ($3::text = 'week' AND r.created_at >= DATE_TRUNC('week', NOW()))
         OR ($3::text = 'month' AND r.created_at >= DATE_TRUNC('month', NOW()))
       )
     ORDER BY COALESCE(r.completed_at, r.cancelled_at, r.updated_at, r.created_at) DESC
     LIMIT $2`,
    [
      Number(customerUserId),
      Math.max(1, Math.min(300, Number(limit) || 40)),
      normalizedPeriod,
    ]
  );

  return r.rows.map(normalizeRide);
}

export async function ensureCaptainSubscription(captainUserId) {
  await q(
    `INSERT INTO taxi_captain_subscription (captain_user_id)
     VALUES ($1)
     ON CONFLICT (captain_user_id) DO NOTHING`,
    [Number(captainUserId)]
  );
}

export async function getCaptainSubscription(captainUserId) {
  await ensureCaptainSubscription(captainUserId);
  const r = await q(
    `SELECT
       captain_user_id,
       monthly_fee_iqd,
       discount_percent,
       trial_days,
       trial_started_at,
       current_cycle_start_at,
       current_cycle_end_at,
       cash_payment_pending,
       cash_payment_requested_at,
       last_cash_payment_confirmed_at,
       last_payment_approved_by_user_id,
       last_discount_set_by_user_id,
       last_expiry_reminder_on,
       created_at,
       updated_at
     FROM taxi_captain_subscription
     WHERE captain_user_id = $1
     LIMIT 1`,
    [Number(captainUserId)]
  );
  return r.rows[0] || null;
}

export async function updateCaptainSubscriptionReminderDate(captainUserId, reminderOnDate) {
  const normalized = String(reminderOnDate || "").trim();
  const r = await q(
    `UPDATE taxi_captain_subscription
     SET last_expiry_reminder_on = NULLIF($2, '')::date,
         updated_at = NOW()
     WHERE captain_user_id = $1
     RETURNING captain_user_id`,
    [Number(captainUserId), normalized]
  );
  return !!r.rows[0];
}

export async function requestCaptainCashPayment(captainUserId) {
  await ensureCaptainSubscription(captainUserId);
  const r = await q(
    `UPDATE taxi_captain_subscription
     SET cash_payment_pending = TRUE,
         cash_payment_requested_at = NOW(),
         updated_at = NOW()
     WHERE captain_user_id = $1
     RETURNING captain_user_id, cash_payment_pending, cash_payment_requested_at`,
    [Number(captainUserId)]
  );
  return r.rows[0] || null;
}

export async function setCaptainDiscountPercent({
  captainUserId,
  discountPercent,
  updatedByUserId,
}) {
  await ensureCaptainSubscription(captainUserId);
  const r = await q(
    `UPDATE taxi_captain_subscription
     SET discount_percent = $2,
         last_discount_set_by_user_id = $3,
         updated_at = NOW()
     WHERE captain_user_id = $1
     RETURNING captain_user_id, discount_percent, monthly_fee_iqd`,
    [Number(captainUserId), Number(discountPercent), Number(updatedByUserId)]
  );
  return r.rows[0] || null;
}

export async function confirmCaptainCashPayment({
  captainUserId,
  cycleStartAt,
  cycleEndAt,
  approvedByUserId,
}) {
  const r = await q(
    `UPDATE taxi_captain_subscription
     SET current_cycle_start_at = $2,
         current_cycle_end_at = $3,
         cash_payment_pending = FALSE,
         cash_payment_requested_at = NULL,
         last_cash_payment_confirmed_at = NOW(),
         last_payment_approved_by_user_id = $4,
         updated_at = NOW()
     WHERE captain_user_id = $1
     RETURNING captain_user_id, current_cycle_start_at, current_cycle_end_at`,
    [Number(captainUserId), cycleStartAt, cycleEndAt, Number(approvedByUserId)]
  );
  return r.rows[0] || null;
}

export async function getCaptainProfile(captainUserId) {
  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.block,
       u.building_number,
       u.apartment,
       u.image_url,
       u.created_at,
       u.delivery_account_approved,
       u.taxi_account_approved,
       p.profile_image_url,
       p.car_image_url,
       p.vehicle_type,
       p.car_make,
       p.car_model,
       p.car_year,
       p.car_color,
       p.plate_number,
       p.plate_governorate,
       p.plate_category,
       p.plate_letter,
       p.plate_digits,
       p.is_active,
       p.rating_avg,
       p.rides_count
     FROM app_user u
     LEFT JOIN taxi_captain_profile p
       ON p.user_id = u.id
     WHERE u.id = $1
       AND u.role = 'taxi_captain'
     LIMIT 1`,
    [Number(captainUserId)]
  );
  return r.rows[0] || null;
}

export async function setTaxiAccountPendingApproval(userId) {
  await q(
    `UPDATE app_user
     SET taxi_account_approved = FALSE,
         taxi_approved_by_user_id = NULL,
         taxi_approved_at = NULL
     WHERE id = $1
       AND role = 'taxi_captain'`,
    [Number(userId)]
  );
}

export async function createPendingCaptainProfile({
  userId,
  profileImageUrl = null,
  carImageUrl = null,
  vehicleType,
  carMake,
  carModel,
  carYear,
  carColor = null,
  plateNumber,
  plateGovernorate = null,
  plateCategory = null,
  plateLetter = null,
  plateDigits = null,
}) {
  const normalizedPlateDigits =
    String(plateDigits || plateNumber || "").replace(/[^\d]/g, "").slice(0, 20) || null;
  const result = await q(
    `INSERT INTO taxi_captain_profile
      (
        user_id,
        profile_image_url,
        car_image_url,
        vehicle_type,
        car_make,
        car_model,
        car_year,
        car_color,
        plate_number,
        plate_governorate,
        plate_category,
        plate_letter,
        plate_digits,
        is_active,
        rating_avg,
        rides_count,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,TRUE,0,0,NOW(),NOW())
     ON CONFLICT (user_id)
     DO UPDATE SET
       profile_image_url = COALESCE(EXCLUDED.profile_image_url, taxi_captain_profile.profile_image_url),
       car_image_url = COALESCE(EXCLUDED.car_image_url, taxi_captain_profile.car_image_url),
       vehicle_type = EXCLUDED.vehicle_type,
       car_make = EXCLUDED.car_make,
       car_model = EXCLUDED.car_model,
       car_year = EXCLUDED.car_year,
       car_color = EXCLUDED.car_color,
       plate_number = EXCLUDED.plate_number,
       plate_governorate = EXCLUDED.plate_governorate,
       plate_category = EXCLUDED.plate_category,
       plate_letter = EXCLUDED.plate_letter,
       plate_digits = EXCLUDED.plate_digits,
       is_active = TRUE,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(userId),
      profileImageUrl || null,
      carImageUrl || null,
      String(vehicleType || "sedan").trim() || "sedan",
      String(carMake || "").trim(),
      String(carModel || "").trim(),
      Number.isFinite(Number(carYear)) ? Number(carYear) : new Date().getFullYear(),
      carColor ? String(carColor).trim() : null,
      String(plateNumber || "").trim(),
      plateGovernorate ? String(plateGovernorate).trim().slice(0, 80) : null,
      plateCategory ? String(plateCategory).trim().slice(0, 40) : null,
      plateLetter ? String(plateLetter).trim().slice(0, 8) : null,
      normalizedPlateDigits,
    ]
  );
  return result.rows[0] || null;
}

export async function createCaptainProfileEditRequest({
  captainUserId,
  requestedChanges,
  captainNote,
}) {
  const r = await q(
    `INSERT INTO taxi_captain_profile_edit_request
      (captain_user_id, requested_changes, captain_note, status)
     VALUES ($1, $2::jsonb, $3, 'pending')
     RETURNING id, captain_user_id, requested_changes, captain_note, status, requested_at`,
    [
      Number(captainUserId),
      JSON.stringify(requestedChanges || {}),
      captainNote || null,
    ]
  );
  return r.rows[0] || null;
}

export async function listBackofficeUsers() {
  const r = await q(
    `SELECT id
     FROM app_user
     WHERE role IN ('admin', 'deputy_admin')
        OR is_super_admin = TRUE`
  );
  return r.rows.map((row) => Number(row.id)).filter((id) => Number.isFinite(id));
}

export async function listPendingCaptainCashPayments({ limit = 100 } = {}) {
  const r = await q(
    `SELECT
       s.captain_user_id,
       s.monthly_fee_iqd,
       s.discount_percent,
       s.trial_days,
       s.trial_started_at,
       s.current_cycle_start_at,
       s.current_cycle_end_at,
       s.cash_payment_pending,
       s.cash_payment_requested_at,
       s.last_cash_payment_confirmed_at,
       s.last_expiry_reminder_on,
       u.full_name,
       u.phone,
       u.block,
       u.building_number,
       u.apartment,
       p.profile_image_url,
       p.car_image_url,
       p.car_make,
       p.car_model,
       p.car_year,
       p.plate_number,
       p.plate_governorate,
       p.plate_category,
       p.plate_letter,
       p.plate_digits
     FROM taxi_captain_subscription s
     JOIN app_user u
       ON u.id = s.captain_user_id
      AND u.role = 'taxi_captain'
     LEFT JOIN taxi_captain_profile p
       ON p.user_id = s.captain_user_id
     WHERE s.cash_payment_pending = TRUE
     ORDER BY s.cash_payment_requested_at ASC NULLS LAST, s.captain_user_id ASC
     LIMIT $1`,
    [Math.max(1, Math.min(500, Number(limit) || 100))]
  );
  return r.rows;
}

export async function getCaptainDashboardMetrics(captainUserId) {
  const r = await q(
    `SELECT
       COALESCE(
         COUNT(*) FILTER (
           WHERE r.status = 'completed'
             AND COALESCE(r.completed_at, r.updated_at, r.created_at) >= DATE_TRUNC('day', NOW())
         ),
         0
       )::int AS day_completed_count,
       COALESCE(
         SUM(COALESCE(r.agreed_fare_iqd, r.proposed_fare_iqd)) FILTER (
           WHERE r.status = 'completed'
             AND COALESCE(r.completed_at, r.updated_at, r.created_at) >= DATE_TRUNC('day', NOW())
         ),
         0
       )::bigint AS day_earnings_iqd,

       COALESCE(
         COUNT(*) FILTER (
           WHERE r.status = 'completed'
             AND COALESCE(r.completed_at, r.updated_at, r.created_at) >= DATE_TRUNC('week', NOW())
         ),
         0
       )::int AS week_completed_count,
       COALESCE(
         SUM(COALESCE(r.agreed_fare_iqd, r.proposed_fare_iqd)) FILTER (
           WHERE r.status = 'completed'
             AND COALESCE(r.completed_at, r.updated_at, r.created_at) >= DATE_TRUNC('week', NOW())
         ),
         0
       )::bigint AS week_earnings_iqd,

       COALESCE(
         COUNT(*) FILTER (
           WHERE r.status = 'completed'
             AND COALESCE(r.completed_at, r.updated_at, r.created_at) >= DATE_TRUNC('month', NOW())
         ),
         0
       )::int AS month_completed_count,
       COALESCE(
         SUM(COALESCE(r.agreed_fare_iqd, r.proposed_fare_iqd)) FILTER (
           WHERE r.status = 'completed'
             AND COALESCE(r.completed_at, r.updated_at, r.created_at) >= DATE_TRUNC('month', NOW())
         ),
         0
       )::bigint AS month_earnings_iqd,

       COALESCE(COUNT(*), 0)::int AS total_rides_count,
       COALESCE(
         SUM(COALESCE(r.agreed_fare_iqd, r.proposed_fare_iqd)) FILTER (WHERE r.status = 'completed'),
         0
       )::bigint AS total_earnings_iqd
     FROM taxi_ride_request r
     WHERE r.assigned_captain_user_id = $1`,
    [Number(captainUserId)]
  );

  return r.rows[0] || null;
}

export async function listCaptainRideHistoryByPeriod(
  captainUserId,
  { period = "month", limit = 40 } = {}
) {
  const normalizedPeriod = ["day", "week", "month", "all"].includes(String(period || "").toLowerCase())
    ? String(period || "").toLowerCase()
    : "month";

  const r = await q(
    `${RIDE_SELECT}
     WHERE r.assigned_captain_user_id = $1
       AND r.status IN ('completed', 'cancelled', 'expired')
       AND (
         $3::text = 'all'
         OR ($3::text = 'day' AND r.created_at >= DATE_TRUNC('day', NOW()))
         OR ($3::text = 'week' AND r.created_at >= DATE_TRUNC('week', NOW()))
         OR ($3::text = 'month' AND r.created_at >= DATE_TRUNC('month', NOW()))
       )
     ORDER BY r.created_at DESC
     LIMIT $2`,
    [
      Number(captainUserId),
      Math.max(1, Math.min(300, Number(limit) || 40)),
      normalizedPeriod,
    ]
  );

  return r.rows.map(normalizeRide);
}

export async function upsertRideShareToken({ rideId, customerUserId, token }) {
  const r = await q(
    `UPDATE taxi_ride_request
     SET share_token = $3,
         updated_at = NOW()
     WHERE id = $1
       AND customer_user_id = $2
       AND status IN ('captain_assigned', 'captain_arriving', 'ride_started', 'completed')
     RETURNING id, share_token`,
    [Number(rideId), Number(customerUserId), token]
  );

  if (!r.rows[0]) return null;
  return {
    rideId: Number(r.rows[0].id),
    token: r.rows[0].share_token,
  };
}

export async function generateShareToken() {
  return crypto.randomBytes(24).toString("hex");
}

export async function getPublicTrackByToken(token) {
  const r = await q(
    `SELECT
      r.*,
      cu.full_name AS customer_full_name,
      cu.phone AS customer_phone,
      ca.full_name AS captain_full_name,
      ca.phone AS captain_phone,
      cp.profile_image_url AS captain_profile_image_url,
      cp.car_image_url AS captain_car_image_url,
      cp.vehicle_type AS captain_vehicle_type,
      cp.car_make AS captain_car_make,
      cp.car_model AS captain_car_model,
      cp.car_year AS captain_car_year,
      cp.car_color AS captain_car_color,
      cp.plate_number AS captain_plate_number,
      cp.plate_governorate AS captain_plate_governorate,
      cp.plate_category AS captain_plate_category,
      cp.plate_letter AS captain_plate_letter,
      cp.plate_digits AS captain_plate_digits,
      cp.rating_avg AS captain_rating_avg,
      cp.rides_count AS captain_rides_count,
      loc.latitude AS last_latitude,
      loc.longitude AS last_longitude,
      loc.heading_deg AS last_heading_deg,
      loc.speed_kmh AS last_speed_kmh,
      loc.accuracy_m AS last_accuracy_m,
      loc.created_at AS last_location_at
     FROM taxi_ride_request r
     LEFT JOIN app_user cu ON cu.id = r.customer_user_id
     LEFT JOIN app_user ca ON ca.id = r.assigned_captain_user_id
     LEFT JOIN taxi_captain_profile cp ON cp.user_id = r.assigned_captain_user_id
     LEFT JOIN LATERAL (
       SELECT latitude, longitude, heading_deg, speed_kmh, accuracy_m, created_at
       FROM taxi_ride_location_log
       WHERE ride_request_id = r.id
       ORDER BY created_at DESC, id DESC
       LIMIT 1
     ) loc ON TRUE
     WHERE r.share_token = $1
     LIMIT 1`,
    [String(token || "").trim()]
  );

  const ride = normalizeRide(r.rows[0]);
  if (!ride) return null;

  return {
    ride,
    location: r.rows[0]?.last_latitude == null
      ? null
      : {
          latitude: Number(r.rows[0].last_latitude),
          longitude: Number(r.rows[0].last_longitude),
          headingDeg: toNumberOrNull(r.rows[0].last_heading_deg),
          speedKmh: toNumberOrNull(r.rows[0].last_speed_kmh),
          accuracyM: toNumberOrNull(r.rows[0].last_accuracy_m),
          createdAt: r.rows[0].last_location_at,
        },
  };
}

export async function upsertRideFriendShare({
  rideId,
  customerUserId,
  friendUserId,
}) {
  const r = await q(
    `WITH upserted AS (
       INSERT INTO taxi_ride_friend_share
         (
           ride_request_id,
           customer_user_id,
           friend_user_id,
           status,
           shared_at,
           revoked_at,
           updated_at
         )
       VALUES ($1, $2, $3, 'active', NOW(), NULL, NOW())
       ON CONFLICT (ride_request_id, friend_user_id)
       DO UPDATE SET
         customer_user_id = EXCLUDED.customer_user_id,
         status = 'active',
         shared_at = NOW(),
         revoked_at = NULL,
         updated_at = NOW()
       RETURNING *
     )
     SELECT
       u.*,
       f.full_name AS friend_full_name,
       f.phone AS friend_phone
     FROM upserted u
     JOIN app_user f ON f.id = u.friend_user_id
     LIMIT 1`,
    [Number(rideId), Number(customerUserId), Number(friendUserId)]
  );
  return normalizeRideFriendShare(r.rows[0]);
}

export async function listRideFriendShares({ rideId, customerUserId }) {
  const r = await q(
    `SELECT
       s.*,
       f.full_name AS friend_full_name,
       f.phone AS friend_phone
     FROM taxi_ride_friend_share s
     JOIN app_user f ON f.id = s.friend_user_id
     WHERE s.ride_request_id = $1
       AND s.customer_user_id = $2
       AND s.status = 'active'
     ORDER BY s.shared_at DESC, s.id DESC`,
    [Number(rideId), Number(customerUserId)]
  );
  return r.rows.map(normalizeRideFriendShare);
}

export async function getSharedRideTrackForFriend({ rideId, friendUserId }) {
  const shareRes = await q(
    `SELECT
       s.*,
       f.full_name AS friend_full_name,
       f.phone AS friend_phone
     FROM taxi_ride_friend_share s
     JOIN app_user f ON f.id = s.friend_user_id
     WHERE s.ride_request_id = $1
       AND s.friend_user_id = $2
       AND s.status = 'active'
     LIMIT 1`,
    [Number(rideId), Number(friendUserId)]
  );
  const share = normalizeRideFriendShare(shareRes.rows[0]);
  if (!share) return null;

  const [ride, location] = await Promise.all([
    getRideById(rideId),
    getLatestRideLocation(rideId),
  ]);
  if (!ride) return null;
  if (!["captain_assigned", "captain_arriving", "ride_started"].includes(String(ride.status || ""))) {
    await q(
      `UPDATE taxi_ride_friend_share
       SET status = 'expired',
           updated_at = NOW()
       WHERE ride_request_id = $1
         AND friend_user_id = $2
         AND status = 'active'`,
      [Number(rideId), Number(friendUserId)]
    );
    return null;
  }

  return {
    share,
    ride,
    location,
  };
}

export async function assertCaptainRole(userId) {
  const r = await q(
    `SELECT role
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  const role = r.rows[0]?.role;
  return role === "taxi_captain";
}

export async function listPendingCaptainProfileEditRequests({ limit = 100 } = {}) {
  const safeLimit = Math.max(1, Math.min(500, Number(limit) || 100));
  const r = await q(
    `SELECT
       req.id,
       req.captain_user_id,
       req.requested_changes,
       req.captain_note,
       req.status,
       req.admin_note,
       req.reviewed_by_user_id,
       req.requested_at,
       req.reviewed_at,
       u.full_name,
       u.phone,
       u.block,
       u.building_number,
       u.apartment,
       p.profile_image_url,
       p.car_image_url,
       p.vehicle_type,
       p.car_make,
       p.car_model,
       p.car_year,
       p.car_color,
       p.plate_number,
       p.plate_governorate,
       p.plate_category,
       p.plate_letter,
       p.plate_digits
     FROM taxi_captain_profile_edit_request req
     JOIN app_user u
       ON u.id = req.captain_user_id
     LEFT JOIN taxi_captain_profile p
       ON p.user_id = req.captain_user_id
     WHERE req.status = 'pending'
     ORDER BY req.requested_at ASC, req.id ASC
     LIMIT $1`,
    [safeLimit]
  );
  return r.rows;
}

export async function reviewCaptainProfileEditRequestByAdmin({
  requestId,
  decision,
  adminUserId,
  adminNote = null,
}) {
  const safeDecision = String(decision || "").trim().toLowerCase();
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const reqResult = await client.query(
      `SELECT
         req.*,
         u.full_name,
         u.phone,
         u.block,
         u.building_number,
         u.apartment,
         p.profile_image_url,
         p.car_image_url,
         p.vehicle_type,
         p.car_make,
         p.car_model,
         p.car_year,
         p.car_color,
         p.plate_number,
         p.plate_governorate,
         p.plate_category,
         p.plate_letter,
         p.plate_digits
       FROM taxi_captain_profile_edit_request req
       JOIN app_user u
         ON u.id = req.captain_user_id
       LEFT JOIN taxi_captain_profile p
         ON p.user_id = req.captain_user_id
       WHERE req.id = $1
       FOR UPDATE`,
      [Number(requestId)]
    );
    const request = reqResult.rows[0] || null;
    if (!request) {
      await client.query("ROLLBACK");
      return null;
    }

    if (String(request.status || "").trim().toLowerCase() !== "pending") {
      await client.query("ROLLBACK");
      return {
        request,
        captain: null,
        alreadyReviewed: true,
      };
    }

    const requestedChanges =
      request.requested_changes && typeof request.requested_changes === "object"
        ? request.requested_changes
        : {};

    if (safeDecision === "approved") {
      const appUserUpdates = [];
      const appUserParams = [Number(request.captain_user_id)];

      const pushAppUserChange = (jsonKey, columnName) => {
        if (!(jsonKey in requestedChanges)) return;
        const raw = requestedChanges[jsonKey];
        if (raw == null) return;
        const value = String(raw).trim();
        if (!value) return;
        appUserParams.push(value);
        appUserUpdates.push(`${columnName} = $${appUserParams.length}`);
      };

      pushAppUserChange("fullName", "full_name");
      pushAppUserChange("phone", "phone");
      pushAppUserChange("block", "block");
      pushAppUserChange("buildingNumber", "building_number");
      pushAppUserChange("apartment", "apartment");

      if (appUserUpdates.length > 0) {
        await client.query(
          `UPDATE app_user
           SET ${appUserUpdates.join(", ")},
               updated_at = NOW()
           WHERE id = $1`,
          appUserParams
        );
      }

      const profileUpdates = [];
      const profileParams = [Number(request.captain_user_id)];

      const pushProfileChange = (jsonKey, columnName, mapper = null) => {
        if (!(jsonKey in requestedChanges)) return;
        const raw = requestedChanges[jsonKey];
        if (raw == null) return;
        const mapped = mapper ? mapper(raw) : String(raw).trim();
        if (mapped == null || mapped === "") return;
        profileParams.push(mapped);
        profileUpdates.push(`${columnName} = $${profileParams.length}`);
      };

      pushProfileChange("profileImageUrl", "profile_image_url");
      pushProfileChange("carImageUrl", "car_image_url");
      pushProfileChange("vehicleType", "vehicle_type");
      pushProfileChange("carMake", "car_make");
      pushProfileChange("carModel", "car_model");
      pushProfileChange("carColor", "car_color");
      pushProfileChange("plateNumber", "plate_number");
      pushProfileChange("plateGovernorate", "plate_governorate");
      pushProfileChange("plateCategory", "plate_category");
      pushProfileChange("plateLetter", "plate_letter");
      pushProfileChange("plateDigits", "plate_digits", (value) => {
        const digits = String(value || "").replace(/[^\d]/g, "").slice(0, 20);
        return digits || null;
      });
      pushProfileChange("carYear", "car_year", (value) => {
        const n = Number(value);
        if (!Number.isInteger(n) || n < 1950 || n > 2100) return null;
        return n;
      });

      if (profileUpdates.length > 0) {
        await client.query(
          `UPDATE taxi_captain_profile
           SET ${profileUpdates.join(", ")},
               updated_at = NOW()
           WHERE user_id = $1`,
          profileParams
        );
      }
    }

    const updatedReqResult = await client.query(
      `UPDATE taxi_captain_profile_edit_request
       SET status = $2,
           admin_note = $3,
           reviewed_by_user_id = $4,
           reviewed_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        Number(requestId),
        safeDecision,
        adminNote == null ? null : String(adminNote).trim() || null,
        Number(adminUserId),
      ]
    );

    const captainResult = await client.query(
      `SELECT
         u.id,
         u.full_name,
         u.phone,
         u.block,
         u.building_number,
         u.apartment,
         u.image_url,
         p.profile_image_url,
         p.car_image_url,
         p.vehicle_type,
         p.car_make,
         p.car_model,
         p.car_year,
         p.car_color,
         p.plate_number,
         p.plate_governorate,
         p.plate_category,
         p.plate_letter,
         p.plate_digits
       FROM app_user u
       LEFT JOIN taxi_captain_profile p
         ON p.user_id = u.id
       WHERE u.id = $1
       LIMIT 1`,
      [Number(request.captain_user_id)]
    );

    await client.query("COMMIT");
    return {
      request: updatedReqResult.rows[0] || request,
      captain: captainResult.rows[0] || null,
      alreadyReviewed: false,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
