import crypto from "crypto";

import { pool, q } from "../../config/db.js";

const ACTIVE_RIDE_STATUSES = [
  "searching",
  "captain_assigned",
  "captain_arriving",
  "ride_started",
];

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
    cp.rating_avg AS captain_rating_avg,
    cp.rides_count AS captain_rides_count
  FROM taxi_ride_request r
  LEFT JOIN app_user cu ON cu.id = r.customer_user_id
  LEFT JOIN app_user ca ON ca.id = r.assigned_captain_user_id
  LEFT JOIN taxi_captain_profile cp ON cp.user_id = r.assigned_captain_user_id
`;

function toNumberOrNull(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function toIntOrNull(value) {
  const n = Number(value);
  return Number.isInteger(n) ? n : null;
}

function normalizeRide(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    customerUserId: Number(row.customer_user_id),
    assignedCaptainUserId: toIntOrNull(row.assigned_captain_user_id),
    currentBidId: toIntOrNull(row.current_bid_id),
    pickup: {
      latitude: Number(row.pickup_latitude),
      longitude: Number(row.pickup_longitude),
      label: row.pickup_label,
    },
    dropoff: {
      latitude: Number(row.dropoff_latitude),
      longitude: Number(row.dropoff_longitude),
      label: row.dropoff_label,
    },
    proposedFareIqd: Number(row.proposed_fare_iqd),
    agreedFareIqd: toIntOrNull(row.agreed_fare_iqd),
    searchRadiusM: Number(row.search_radius_m),
    note: row.note || null,
    status: row.status,
    shareToken: row.share_token || null,
    acceptedBidId: toIntOrNull(row.accepted_bid_id),
    expiresAt: row.expires_at,
    searchPhase: toIntOrNull(row.search_phase) || 1,
    nextEscalationAt: row.next_escalation_at || null,
    noCaptainNotifiedAt: row.no_captain_notified_at || null,
    acceptedAt: row.accepted_at,
    captainArrivingAt: row.captain_arriving_at,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    cancelledAt: row.cancelled_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    distanceM: toNumberOrNull(row.distance_m),
    myBid: row.my_bid_id
      ? {
          id: Number(row.my_bid_id),
          offeredFareIqd: Number(row.my_offered_fare_iqd),
          etaMinutes: toIntOrNull(row.my_eta_minutes),
          status: row.my_bid_status,
          counterOfferCount: toIntOrNull(row.my_counter_offer_count) || 0,
          lastOfferIqd: toIntOrNull(row.my_last_offer_iqd),
          lastOfferBy: row.my_last_offer_by || null,
        }
      : null,
    customer: row.customer_full_name
      ? {
          id: Number(row.customer_user_id),
          fullName: row.customer_full_name,
          phone: row.customer_phone || null,
        }
      : null,
    captain: row.captain_full_name
      ? {
          id: toIntOrNull(row.assigned_captain_user_id),
          fullName: row.captain_full_name,
          phone: row.captain_phone || null,
          profileImageUrl: row.captain_profile_image_url || null,
          carImageUrl: row.captain_car_image_url || null,
          vehicleType: row.captain_vehicle_type || null,
          carMake: row.captain_car_make || null,
          carModel: row.captain_car_model || null,
          carYear: toIntOrNull(row.captain_car_year),
          carColor: row.captain_car_color || null,
          plateNumber: row.captain_plate_number || null,
          ratingAvg: toNumberOrNull(row.captain_rating_avg),
          ridesCount: toIntOrNull(row.captain_rides_count) || 0,
        }
      : null,
  };
}

function normalizeBid(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    rideRequestId: Number(row.ride_request_id),
    captainUserId: Number(row.captain_user_id),
    offeredFareIqd: Number(row.offered_fare_iqd),
    etaMinutes: toIntOrNull(row.eta_minutes),
    note: row.note || null,
    status: row.status,
    counterOfferCount: toIntOrNull(row.counter_offer_count) || 0,
    lastOfferIqd: toIntOrNull(row.last_offer_iqd),
    lastOfferBy: row.last_offer_by || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    captain: row.captain_full_name
      ? {
          id: Number(row.captain_user_id),
          fullName: row.captain_full_name,
          phone: row.captain_phone || null,
          profileImageUrl: row.captain_profile_image_url || null,
          carImageUrl: row.captain_car_image_url || null,
          vehicleType: row.captain_vehicle_type || null,
          carMake: row.captain_car_make || null,
          carModel: row.captain_car_model || null,
          carYear: toIntOrNull(row.captain_car_year),
          carColor: row.captain_car_color || null,
          plateNumber: row.captain_plate_number || null,
          ratingAvg: toNumberOrNull(row.captain_rating_avg),
          ridesCount: toIntOrNull(row.captain_rides_count) || 0,
        }
      : null,
  };
}

function normalizeChatMessage(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    rideRequestId: Number(row.ride_request_id),
    senderUserId: Number(row.sender_user_id),
    senderRole: row.sender_role,
    messageType: row.message_type,
    messageText: row.message_text || null,
    offeredFareIqd: toIntOrNull(row.offered_fare_iqd),
    createdAt: row.created_at,
    sender: row.sender_full_name
      ? {
          id: Number(row.sender_user_id),
          fullName: row.sender_full_name,
          phone: row.sender_phone || null,
          imageUrl: row.sender_image_url || null,
        }
      : null,
  };
}

function normalizeCallSession(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    rideRequestId: Number(row.ride_request_id),
    initiatorUserId: Number(row.initiator_user_id),
    receiverUserId: Number(row.receiver_user_id),
    status: row.status,
    startedAt: row.started_at,
    answeredAt: row.answered_at || null,
    endedAt: row.ended_at || null,
    endedByUserId: toIntOrNull(row.ended_by_user_id),
    endReason: row.end_reason || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function normalizeCallSignal(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    callSessionId: Number(row.call_session_id),
    rideRequestId: Number(row.ride_request_id),
    senderUserId: Number(row.sender_user_id),
    signalType: row.signal_type,
    signalPayload: row.signal_payload || null,
    createdAt: row.created_at,
  };
}

function normalizePresence(row) {
  if (!row) return null;
  return {
    captainUserId: Number(row.captain_user_id),
    isOnline: row.is_online === true,
    latitude: toNumberOrNull(row.latitude),
    longitude: toNumberOrNull(row.longitude),
    headingDeg: toNumberOrNull(row.heading_deg),
    speedKmh: toNumberOrNull(row.speed_kmh),
    accuracyM: toNumberOrNull(row.accuracy_m),
    lastSeenAt: row.last_seen_at,
    updatedAt: row.updated_at,
  };
}

function normalizeLocation(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    rideRequestId: Number(row.ride_request_id),
    captainUserId: Number(row.captain_user_id),
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    headingDeg: toNumberOrNull(row.heading_deg),
    speedKmh: toNumberOrNull(row.speed_kmh),
    accuracyM: toNumberOrNull(row.accuracy_m),
    source: row.source,
    createdAt: row.created_at,
  };
}

function normalizeEvent(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    rideRequestId: Number(row.ride_request_id),
    actorUserId: toIntOrNull(row.actor_user_id),
    eventType: row.event_type,
    message: row.message || null,
    payload: row.payload || null,
    createdAt: row.created_at,
  };
}

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

async function queryRideById(client, rideId) {
  const r = await client.query(
    `${RIDE_SELECT}
     WHERE r.id = $1
     LIMIT 1`,
    [Number(rideId)]
  );
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
       AND u.role = 'delivery'
       AND p.latitude IS NOT NULL
       AND p.longitude IS NOT NULL
       AND p.last_seen_at >= NOW() - INTERVAL '3 minutes'
       AND ${distanceExpr} <= $3
     ORDER BY distance_m ASC, p.last_seen_at DESC
     LIMIT $4`,
    [
      Number(pickupLatitude),
      Number(pickupLongitude),
      Number(radiusM),
      Math.max(1, Math.min(200, Number(limit) || 50)),
    ]
  );

  return r.rows.map((row) => ({
    captainUserId: Number(row.captain_user_id),
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
}) {
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
        note,
        status
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,1,NOW() + INTERVAL '5 minutes',$10,'searching')
     RETURNING id`,
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
    ]
  );

  return getRideById(r.rows[0]?.id);
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
    [Number(captainUserId), ACTIVE_RIDE_STATUSES.filter((s) => s !== "searching")]
  );
  return normalizeRide(r.rows[0]);
}

export async function listRideBids(rideId) {
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
       cp.rating_avg AS captain_rating_avg,
       cp.rides_count AS captain_rides_count
     FROM taxi_ride_bid b
     JOIN app_user u ON u.id = b.captain_user_id
     LEFT JOIN taxi_captain_profile cp ON cp.user_id = b.captain_user_id
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
       cp.rating_avg AS captain_rating_avg,
       cp.rides_count AS captain_rides_count
     FROM taxi_ride_request r
     JOIN taxi_ride_bid b
       ON b.id = r.current_bid_id
     JOIN app_user u
       ON u.id = b.captain_user_id
     LEFT JOIN taxi_captain_profile cp
       ON cp.user_id = b.captain_user_id
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
       cp.rating_avg AS captain_rating_avg,
       cp.rides_count AS captain_rides_count
     FROM taxi_ride_bid b
     JOIN app_user u ON u.id = b.captain_user_id
     LEFT JOIN taxi_captain_profile cp ON cp.user_id = b.captain_user_id
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

    await client.query("COMMIT");

    return {
      code: "OK",
      ride,
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

    let currentBid = await lockCurrentActiveBid(
      client,
      ride.id,
      ride.current_bid_id
    );
    if (!currentBid) {
      currentBid = await promoteNextActiveBid(client, ride.id);
    }
    if (!currentBid) {
      await client.query("COMMIT");
      return { code: "NO_ACTIVE_BID", ride: await getRideById(ride.id) };
    }

    await client.query(
      `UPDATE taxi_ride_bid
       SET status = 'rejected',
           updated_at = NOW()
       WHERE id = $1`,
      [Number(currentBid.id)]
    );

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
      rejectedBid: currentBid,
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

    let currentBid = await lockCurrentActiveBid(
      client,
      ride.id,
      ride.current_bid_id
    );
    if (!currentBid) {
      currentBid = await promoteNextActiveBid(client, ride.id);
    }
    if (!currentBid) {
      await client.query("COMMIT");
      return { code: "NO_ACTIVE_BID", ride: await getRideById(ride.id) };
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

export async function cancelRide({ rideId, customerUserId }) {
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

    if (["completed", "cancelled", "expired"].includes(ride.status)) {
      await client.query("ROLLBACK");
      return { code: "RIDE_ALREADY_CLOSED" };
    }

    await client.query(
      `UPDATE taxi_ride_request
       SET status = 'cancelled',
           current_bid_id = NULL,
           cancelled_at = NOW(),
           updated_at = NOW()
       WHERE id = $1`,
      [Number(rideId)]
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
    return { code: "OK", ride: full };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function transitionRideStatus({ rideId, captainUserId, nextStatus }) {
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

    await client.query(
      `UPDATE taxi_ride_request
       SET ${setParts.join(", ")}
       WHERE id = $1`,
      params
    );

    const full = await queryRideById(client, rideId);

    await client.query("COMMIT");
    return { code: "OK", ride: full, previousStatus: current };
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

    if (!["captain_assigned", "captain_arriving", "ride_started"].includes(ride.status)) {
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

export async function listNearbyOpenRidesForCaptain(captainUserId, { radiusM = 3000, limit = 40 } = {}) {
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
       cp.rating_avg AS captain_rating_avg,
       cp.rides_count AS captain_rides_count,
       ${distanceExpr} AS distance_m,
       mb.id AS my_bid_id,
       mb.offered_fare_iqd AS my_offered_fare_iqd,
       mb.eta_minutes AS my_eta_minutes,
       mb.status AS my_bid_status,
       mb.counter_offer_count AS my_counter_offer_count,
       mb.last_offer_iqd AS my_last_offer_iqd,
       mb.last_offer_by AS my_last_offer_by
     FROM taxi_ride_request r
     LEFT JOIN app_user cu ON cu.id = r.customer_user_id
     LEFT JOIN app_user ca ON ca.id = r.assigned_captain_user_id
     LEFT JOIN taxi_captain_profile cp ON cp.user_id = r.assigned_captain_user_id
     LEFT JOIN taxi_ride_bid mb
       ON mb.ride_request_id = r.id
      AND mb.captain_user_id = $3
     WHERE r.status = 'searching'
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

export async function advanceRideToExpandedSearch({ rideId, expandedRadiusM = 4000 }) {
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

export async function listBidCaptainUserIds(rideId) {
  const r = await q(
    `SELECT DISTINCT captain_user_id
     FROM taxi_ride_bid
     WHERE ride_request_id = $1`,
    [Number(rideId)]
  );
  return r.rows.map((row) => Number(row.captain_user_id));
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
       p.profile_image_url,
       p.car_image_url,
       p.vehicle_type,
       p.car_make,
       p.car_model,
       p.car_year,
       p.car_color,
       p.plate_number,
       p.is_active,
       p.rating_avg,
       p.rides_count
     FROM app_user u
     LEFT JOIN taxi_captain_profile p
       ON p.user_id = u.id
     WHERE u.id = $1
       AND u.role = 'delivery'
     LIMIT 1`,
    [Number(captainUserId)]
  );
  return r.rows[0] || null;
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
       p.plate_number
     FROM taxi_captain_subscription s
     JOIN app_user u
       ON u.id = s.captain_user_id
      AND u.role = 'delivery'
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

export async function assertCaptainRole(userId) {
  const r = await q(
    `SELECT role
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  const role = r.rows[0]?.role;
  return role === "delivery";
}
