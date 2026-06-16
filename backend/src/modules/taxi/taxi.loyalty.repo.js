import { pool, q } from "../../config/db.js";

const DEFAULT_TAXI_FARE_IQD = 10000;

function toInt(value) {
  const n = Number(value);
  return Number.isInteger(n) ? n : null;
}

function toNum(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function toPositiveIntOrDefault(value, fallback = DEFAULT_TAXI_FARE_IQD) {
  const n = Number(value);
  if (Number.isInteger(n) && n > 0) return n;
  const f = Number(fallback);
  if (Number.isInteger(f) && f > 0) return f;
  return DEFAULT_TAXI_FARE_IQD;
}

function nowIso() {
  return new Date().toISOString();
}

function normalizePlaceSnapshot(raw) {
  const src = raw && typeof raw === "object" ? raw : {};
  return {
    latitude: toNum(src.latitude),
    longitude: toNum(src.longitude),
    label: String(src.label || "").trim(),
    addressText: String(src.addressText || src.address_text || src.label || "").trim(),
  };
}

function formatResidenceMatchCodes(userRow) {
  const building = String(userRow?.building_number || "").trim().toUpperCase();
  const block = String(userRow?.block || "").trim().toUpperCase();
  const compound = building.length >= 2 ? building.slice(0, 2) : "";
  return { block, building, compound };
}

function mapSavedPlace(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    label: row.label,
    placeType: row.place_type,
    latitude: toNum(row.latitude),
    longitude: toNum(row.longitude),
    addressText: row.address_text,
    note: row.note || null,
    iconName: row.icon_name || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapFavoriteTrip(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    label: row.label,
    pickupSnapshot:
      row.pickup_snapshot && typeof row.pickup_snapshot === "object"
        ? row.pickup_snapshot
        : {},
    dropoffSnapshot:
      row.dropoff_snapshot && typeof row.dropoff_snapshot === "object"
        ? row.dropoff_snapshot
        : {},
    iconName: row.icon_name || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapScheduledRide(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    pickupSnapshot:
      row.pickup_snapshot && typeof row.pickup_snapshot === "object"
        ? row.pickup_snapshot
        : {},
    dropoffSnapshot:
      row.dropoff_snapshot && typeof row.dropoff_snapshot === "object"
        ? row.dropoff_snapshot
        : {},
    proposedFareIqd: toPositiveIntOrDefault(row.proposed_fare_iqd),
    note: row.note || null,
    couponCode: row.coupon_code || null,
    scheduleFor: row.schedule_for || null,
    status: row.status,
    dispatchStartedAt: row.dispatch_started_at || null,
    dispatchedRideRequestId: toInt(row.dispatched_ride_request_id),
    cancelledAt: row.cancelled_at || null,
    completedAt: row.completed_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapCoupon(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    code: row.code,
    title: row.title,
    description: row.description || null,
    isActive: row.is_active === true,
    validFrom: row.valid_from || null,
    validUntil: row.valid_until || null,
    maxTotalUses: row.max_total_uses == null ? null : Number(row.max_total_uses),
    maxUsesPerUser: Number(row.max_uses_per_user || 1),
    applyWholeApp: row.apply_whole_app === true,
    createdByAdminUserId:
      row.created_by_admin_user_id == null ? null : Number(row.created_by_admin_user_id),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapCouponTier(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    couponId: Number(row.coupon_id),
    useIndex: Number(row.use_index),
    discountType: row.discount_type,
    discountValue: Number(row.discount_value),
    createdAt: row.created_at || null,
  };
}

function mapCouponUsage(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    couponId: Number(row.coupon_id),
    userId: Number(row.user_id),
    rideRequestId: Number(row.ride_request_id),
    useIndex: Number(row.use_index),
    discountType: row.discount_type,
    discountValue: Number(row.discount_value),
    fareBeforeDiscountIqd: Number(row.fare_before_discount_iqd),
    discountIqd: Number(row.discount_iqd),
    fareAfterDiscountIqd: Number(row.fare_after_discount_iqd),
    status: row.status,
    settledAt: row.settled_at || null,
    createdAt: row.created_at || null,
  };
}

function mapLedgerRow(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    captainUserId: Number(row.captain_user_id),
    rideRequestId: toInt(row.ride_request_id),
    entryType: row.entry_type,
    amountIqd: Number(row.amount_iqd || 0),
    status: row.status,
    referenceKind: row.reference_kind || null,
    referenceId: toInt(row.reference_id),
    note: row.note || null,
    meta: row.meta && typeof row.meta === "object" ? row.meta : null,
    createdByUserId: toInt(row.created_by_user_id),
    approvedByUserId: toInt(row.approved_by_user_id),
    approvedAt: row.approved_at || null,
    settledAt: row.settled_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapContest(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    title: row.title,
    description: row.description || null,
    startAt: row.start_at || null,
    endAt: row.end_at || null,
    targetType: row.target_type,
    targetValue: Number(row.target_value || 0),
    rewardType: row.reward_type,
    rewardValue: Number(row.reward_value || 0),
    eligibilityRules:
      row.eligibility_rules && typeof row.eligibility_rules === "object"
        ? row.eligibility_rules
        : null,
    isActive: row.is_active === true,
    createdByAdminUserId: toInt(row.created_by_admin_user_id),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapContestTier(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    contestId: Number(row.contest_id),
    targetValue: Number(row.target_value || 0),
    rewardType: row.reward_type,
    rewardValue: Number(row.reward_value || 0),
    createdAt: row.created_at || null,
  };
}

function computeDiscountIqd({ fareBeforeDiscountIqd, discountType, discountValue }) {
  const fare = Math.max(0, Number(fareBeforeDiscountIqd) || 0);
  const type = String(discountType || "").trim().toLowerCase();
  const value = Math.max(0, Number(discountValue) || 0);
  if (fare <= 0 || value <= 0) return 0;
  if (type === "percent") {
    return Math.min(fare, Math.round((fare * value) / 100));
  }
  return Math.min(fare, Math.round(value));
}

export async function listSavedPlaces(userId) {
  const r = await q(
    `SELECT *
     FROM taxi_saved_place
     WHERE user_id = $1
     ORDER BY
       CASE place_type WHEN 'home' THEN 0 WHEN 'work' THEN 1 ELSE 2 END,
       created_at DESC,
       id DESC`,
    [Number(userId)]
  );
  return r.rows.map(mapSavedPlace);
}

export async function createSavedPlace(userId, dto) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    if (dto.placeType === "home" || dto.placeType === "work") {
      await client.query(
        `DELETE FROM taxi_saved_place
         WHERE user_id = $1
           AND place_type = $2`,
        [Number(userId), dto.placeType]
      );
    }

    const inserted = await client.query(
      `INSERT INTO taxi_saved_place
        (
          user_id,
          label,
          place_type,
          latitude,
          longitude,
          address_text,
          note,
          icon_name,
          created_at,
          updated_at
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NOW(),NOW())
       RETURNING *`,
      [
        Number(userId),
        dto.label,
        dto.placeType,
        dto.latitude,
        dto.longitude,
        dto.addressText,
        dto.note,
        dto.iconName,
      ]
    );

    await client.query("COMMIT");
    return mapSavedPlace(inserted.rows[0]);
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function updateSavedPlace(userId, placeId, patch) {
  const updates = [];
  const params = [Number(userId), Number(placeId)];

  const push = (sqlKey, value) => {
    params.push(value);
    updates.push(`${sqlKey} = $${params.length}`);
  };

  if (patch.label !== undefined) push("label", patch.label);
  if (patch.placeType !== undefined) push("place_type", patch.placeType);
  if (patch.latitude !== undefined) push("latitude", patch.latitude);
  if (patch.longitude !== undefined) push("longitude", patch.longitude);
  if (patch.addressText !== undefined) push("address_text", patch.addressText);
  if (patch.note !== undefined) push("note", patch.note);
  if (patch.iconName !== undefined) push("icon_name", patch.iconName);

  if (updates.length === 0) return null;

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const target = await client.query(
      `SELECT id, place_type
       FROM taxi_saved_place
       WHERE user_id = $1
         AND id = $2
       LIMIT 1
       FOR UPDATE`,
      [Number(userId), Number(placeId)]
    );
    const row = target.rows[0];
    if (!row) {
      await client.query("ROLLBACK");
      return null;
    }

    const nextType = patch.placeType ?? row.place_type;
    if (nextType === "home" || nextType === "work") {
      await client.query(
        `DELETE FROM taxi_saved_place
         WHERE user_id = $1
           AND place_type = $2
           AND id <> $3`,
        [Number(userId), nextType, Number(placeId)]
      );
    }

    const out = await client.query(
      `UPDATE taxi_saved_place
       SET ${updates.join(", ")},
           updated_at = NOW()
       WHERE user_id = $1
         AND id = $2
       RETURNING *`,
      params
    );

    await client.query("COMMIT");
    return mapSavedPlace(out.rows[0]);
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function deleteSavedPlace(userId, placeId) {
  const r = await q(
    `DELETE FROM taxi_saved_place
     WHERE user_id = $1
       AND id = $2
     RETURNING id`,
    [Number(userId), Number(placeId)]
  );
  return r.rowCount > 0;
}

export async function importSavedPlacesFromCustomerAddresses(userId) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const addresses = await client.query(
      `SELECT
         id,
         label,
         city,
         block,
         building_number,
         apartment,
         latitude,
         longitude,
         is_default,
         created_at
       FROM customer_address
       WHERE customer_user_id = $1
         AND is_active = TRUE
         AND latitude IS NOT NULL
         AND longitude IS NOT NULL
       ORDER BY is_default DESC, created_at DESC, id DESC`,
      [Number(userId)]
    );

    let insertedCount = 0;
    let assignedHome = false;
    let assignedWork = false;

    for (const row of addresses.rows) {
      const label = String(row.label || "").trim();
      const addressText = `${row.city || ""} ${row.block || ""}-${row.building_number || ""}-${row.apartment || ""}`.trim();
      let placeType = "custom";
      const low = label.toLowerCase();
      if (!assignedHome && (low.includes("home") || low.includes("منزل") || row.is_default === true)) {
        placeType = "home";
        assignedHome = true;
      } else if (!assignedWork && (low.includes("work") || low.includes("عمل"))) {
        placeType = "work";
        assignedWork = true;
      }

      if (placeType === "home" || placeType === "work") {
        await client.query(
          `DELETE FROM taxi_saved_place
           WHERE user_id = $1
             AND place_type = $2`,
          [Number(userId), placeType]
        );
      }

      const out = await client.query(
        `INSERT INTO taxi_saved_place
          (
            user_id,
            label,
            place_type,
            latitude,
            longitude,
            address_text,
            note,
            icon_name,
            created_at,
            updated_at
          )
         VALUES ($1,$2,$3,$4,$5,$6,NULL,NULL,NOW(),NOW())
         ON CONFLICT DO NOTHING
         RETURNING id`,
        [
          Number(userId),
          label || `Address ${row.id}`,
          placeType,
          Number(row.latitude),
          Number(row.longitude),
          addressText || label || "Imported address",
        ]
      );
      if (out.rowCount > 0) insertedCount += 1;
    }

    await client.query("COMMIT");
    return insertedCount;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listFavoriteTrips(userId) {
  const r = await q(
    `SELECT *
     FROM taxi_favorite_trip
     WHERE user_id = $1
     ORDER BY created_at DESC, id DESC`,
    [Number(userId)]
  );
  return r.rows.map(mapFavoriteTrip);
}

export async function createFavoriteTrip(userId, dto) {
  const r = await q(
    `INSERT INTO taxi_favorite_trip
      (
        user_id,
        label,
        pickup_snapshot,
        dropoff_snapshot,
        icon_name,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3::jsonb,$4::jsonb,$5,NOW(),NOW())
     RETURNING *`,
    [
      Number(userId),
      dto.label,
      JSON.stringify(normalizePlaceSnapshot(dto.pickupSnapshot)),
      JSON.stringify(normalizePlaceSnapshot(dto.dropoffSnapshot)),
      dto.iconName,
    ]
  );
  return mapFavoriteTrip(r.rows[0]);
}

export async function updateFavoriteTrip(userId, favoriteTripId, patch) {
  const updates = [];
  const params = [Number(userId), Number(favoriteTripId)];

  const push = (field, value, isJson = false) => {
    params.push(isJson ? JSON.stringify(value) : value);
    updates.push(`${field} = ${isJson ? `$${params.length}::jsonb` : `$${params.length}`}`);
  };

  if (patch.label !== undefined) push("label", patch.label);
  if (patch.iconName !== undefined) push("icon_name", patch.iconName);
  if (patch.pickupSnapshot !== undefined) {
    push("pickup_snapshot", normalizePlaceSnapshot(patch.pickupSnapshot), true);
  }
  if (patch.dropoffSnapshot !== undefined) {
    push("dropoff_snapshot", normalizePlaceSnapshot(patch.dropoffSnapshot), true);
  }
  if (updates.length === 0) return null;

  const r = await q(
    `UPDATE taxi_favorite_trip
     SET ${updates.join(", ")},
         updated_at = NOW()
     WHERE user_id = $1
       AND id = $2
     RETURNING *`,
    params
  );
  return mapFavoriteTrip(r.rows[0]);
}

export async function deleteFavoriteTrip(userId, favoriteTripId) {
  const r = await q(
    `DELETE FROM taxi_favorite_trip
     WHERE user_id = $1
       AND id = $2
     RETURNING id`,
    [Number(userId), Number(favoriteTripId)]
  );
  return r.rowCount > 0;
}

export async function createScheduledRide(userId, dto) {
  const r = await q(
    `INSERT INTO taxi_scheduled_ride
      (
        user_id,
        pickup_snapshot,
        dropoff_snapshot,
        proposed_fare_iqd,
        note,
        coupon_code,
        schedule_for,
        status,
        created_at,
        updated_at
      )
     VALUES ($1,$2::jsonb,$3::jsonb,$4,$5,$6,$7,'scheduled',NOW(),NOW())
     RETURNING *`,
    [
      Number(userId),
      JSON.stringify(normalizePlaceSnapshot(dto.pickupSnapshot)),
      JSON.stringify(normalizePlaceSnapshot(dto.dropoffSnapshot)),
      Number(dto.proposedFareIqd),
      dto.note || null,
      dto.couponCode || null,
      dto.scheduleFor,
    ]
  );
  return mapScheduledRide(r.rows[0]);
}

export async function listScheduledRides(userId, { status = "scheduled", limit = 40 } = {}) {
  const normalizedStatus = String(status || "").trim().toLowerCase();
  const whereStatus =
    normalizedStatus === "all"
      ? "TRUE"
      : "status = $2";
  const params =
    normalizedStatus === "all"
      ? [Number(userId), Math.max(1, Math.min(200, Number(limit) || 40))]
      : [Number(userId), normalizedStatus, Math.max(1, Math.min(200, Number(limit) || 40))];

  const sql =
    normalizedStatus === "all"
      ? `SELECT *
         FROM taxi_scheduled_ride
         WHERE user_id = $1
           AND ${whereStatus}
         ORDER BY schedule_for ASC, id DESC
         LIMIT $2`
      : `SELECT *
         FROM taxi_scheduled_ride
         WHERE user_id = $1
           AND ${whereStatus}
         ORDER BY schedule_for ASC, id DESC
         LIMIT $3`;

  const r = await q(sql, params);
  return r.rows.map(mapScheduledRide);
}

export async function cancelScheduledRide(userId, scheduledRideId) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const lock = await client.query(
      `SELECT *
       FROM taxi_scheduled_ride
       WHERE id = $1
         AND user_id = $2
       FOR UPDATE`,
      [Number(scheduledRideId), Number(userId)]
    );
    const row = lock.rows[0];
    if (!row) {
      await client.query("ROLLBACK");
      return { code: "NOT_FOUND" };
    }
    if (!["scheduled", "pending_dispatch"].includes(row.status)) {
      await client.query("ROLLBACK");
      return { code: "ALREADY_CLOSED", status: row.status };
    }

    const scheduleFor = row.schedule_for ? new Date(row.schedule_for) : null;
    if (scheduleFor && scheduleFor.getTime() <= Date.now() + 5 * 60 * 1000) {
      await client.query("ROLLBACK");
      return { code: "CANCELLATION_WINDOW_CLOSED", status: row.status };
    }

    const updated = await client.query(
      `UPDATE taxi_scheduled_ride
       SET status = 'cancelled',
           cancelled_at = NOW(),
           updated_at = NOW()
       WHERE id = $1
         AND user_id = $2
       RETURNING *`,
      [Number(scheduledRideId), Number(userId)]
    );

    await client.query("COMMIT");
    return { code: "OK", item: mapScheduledRide(updated.rows[0]) };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function takeScheduledRidesReadyForDispatch({
  leadMinutes = 10,
  limit = 40,
} = {}) {
  const safeLead = Math.max(1, Math.min(120, Number(leadMinutes) || 10));
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 40));
  const r = await q(
    `WITH due AS (
       SELECT id
       FROM taxi_scheduled_ride
       WHERE status = 'scheduled'
         AND schedule_for <= (NOW() + (($1::int || ' minutes')::interval))
       ORDER BY schedule_for ASC, id ASC
       LIMIT $2
       FOR UPDATE SKIP LOCKED
     )
     UPDATE taxi_scheduled_ride s
     SET status = 'pending_dispatch',
         dispatch_started_at = NOW(),
         updated_at = NOW()
     FROM due
     WHERE s.id = due.id
     RETURNING s.*`,
    [safeLead, safeLimit]
  );
  return r.rows.map(mapScheduledRide);
}

export async function markScheduledRideDispatched({
  scheduledRideId,
  rideRequestId,
}) {
  const r = await q(
    `UPDATE taxi_scheduled_ride
     SET status = 'assigned',
         dispatched_ride_request_id = $2,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(scheduledRideId), Number(rideRequestId)]
  );
  return mapScheduledRide(r.rows[0]);
}

export async function markScheduledRideDispatchFailed(scheduledRideId) {
  await q(
    `UPDATE taxi_scheduled_ride
     SET status = 'scheduled',
         dispatch_started_at = NULL,
         updated_at = NOW()
     WHERE id = $1
       AND status = 'pending_dispatch'`,
    [Number(scheduledRideId)]
  );
}

export async function syncScheduledRideStatusFromRide({
  rideRequestId,
  nextStatus,
}) {
  const statusMap = {
    captain_assigned: "assigned",
    completed: "completed",
    cancelled: "cancelled",
    expired: "expired",
  };
  const mapped = statusMap[String(nextStatus || "").trim().toLowerCase()];
  if (!mapped) return null;

  const setResolvedAt =
    mapped === "completed"
      ? ", completed_at = COALESCE(completed_at, NOW())"
      : mapped === "cancelled"
      ? ", cancelled_at = COALESCE(cancelled_at, NOW())"
      : "";

  const r = await q(
    `UPDATE taxi_scheduled_ride
     SET status = $2,
         updated_at = NOW()
         ${setResolvedAt}
     WHERE dispatched_ride_request_id = $1
     RETURNING *`,
    [Number(rideRequestId), mapped]
  );
  return mapScheduledRide(r.rows[0]);
}

export async function getUserResidence(userId) {
  const r = await q(
    `SELECT id, role, block, building_number
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function getCouponByCode(code, { forUpdate = false } = {}) {
  const sql = `SELECT *
               FROM taxi_coupon
               WHERE UPPER(code) = UPPER($1)
               LIMIT 1 ${forUpdate ? "FOR UPDATE" : ""}`;
  const r = await q(sql, [String(code || "").trim()]);
  return mapCoupon(r.rows[0]);
}

export async function listCouponTiers(couponId) {
  const r = await q(
    `SELECT *
     FROM taxi_coupon_discount_tier
     WHERE coupon_id = $1
     ORDER BY use_index ASC`,
    [Number(couponId)]
  );
  return r.rows.map(mapCouponTier);
}

export async function countCouponUsages({
  couponId,
  userId = null,
  statuses = ["settled"],
}) {
  const r = await q(
    `SELECT COUNT(*)::int AS count
     FROM taxi_coupon_usage
     WHERE coupon_id = $1
       AND ($2::bigint IS NULL OR user_id = $2)
       AND status = ANY($3::text[])`,
    [Number(couponId), userId == null ? null : Number(userId), statuses]
  );
  return Number(r.rows[0]?.count || 0);
}

export async function isCouponEligibleForUser({ couponId, userId, userResidence = null }) {
  const residence = userResidence || (await getUserResidence(userId)) || {};
  const codes = formatResidenceMatchCodes(residence);
  const r = await q(
    `SELECT
       c.apply_whole_app,
       EXISTS (
         SELECT 1
         FROM taxi_coupon_target_user t
         WHERE t.coupon_id = c.id
           AND t.user_id = $2
       ) AS has_user_target,
       EXISTS (
         SELECT 1
         FROM taxi_coupon_target_building t
         WHERE t.coupon_id = c.id
           AND UPPER(t.building_code) = UPPER($3)
       ) AS has_building_target,
       EXISTS (
         SELECT 1
         FROM taxi_coupon_target_block t
         WHERE t.coupon_id = c.id
           AND UPPER(t.block_code) = UPPER($4)
       ) AS has_block_target,
       EXISTS (
         SELECT 1
         FROM taxi_coupon_target_compound t
         WHERE t.coupon_id = c.id
           AND UPPER(t.compound_code) = UPPER($5)
       ) AS has_compound_target
     FROM taxi_coupon c
     WHERE c.id = $1
     LIMIT 1`,
    [Number(couponId), Number(userId), codes.building || "", codes.block || "", codes.compound || ""]
  );
  const row = r.rows[0];
  if (!row) return false;
  if (row.apply_whole_app === true) return true;
  return (
    row.has_user_target === true ||
    row.has_building_target === true ||
    row.has_block_target === true ||
    row.has_compound_target === true
  );
}

export async function getCouponPreviewForUser({
  userId,
  couponCode,
  proposedFareIqd,
}) {
  const coupon = await getCouponByCode(couponCode);
  if (!coupon) return { code: "COUPON_NOT_FOUND" };

  const now = new Date();
  if (!coupon.isActive) return { code: "COUPON_INACTIVE", coupon };
  if (coupon.validFrom && new Date(coupon.validFrom) > now) {
    return { code: "COUPON_NOT_STARTED", coupon };
  }
  if (coupon.validUntil && new Date(coupon.validUntil) < now) {
    return { code: "COUPON_EXPIRED", coupon };
  }

  const eligible = await isCouponEligibleForUser({
    couponId: coupon.id,
    userId,
  });
  if (!eligible) return { code: "COUPON_NOT_TARGETED", coupon };

  const tiers = await listCouponTiers(coupon.id);
  if (!tiers.length) return { code: "COUPON_NO_TIERS", coupon };

  const settledUserUses = await countCouponUsages({
    couponId: coupon.id,
    userId,
    statuses: ["settled"],
  });
  if (settledUserUses >= coupon.maxUsesPerUser) {
    return { code: "COUPON_USER_LIMIT_REACHED", coupon, settledUserUses };
  }

  const settledTotalUses = await countCouponUsages({
    couponId: coupon.id,
    statuses: ["settled"],
  });
  if (coupon.maxTotalUses != null && settledTotalUses >= coupon.maxTotalUses) {
    return { code: "COUPON_TOTAL_LIMIT_REACHED", coupon, settledTotalUses };
  }

  const useIndex = settledUserUses + 1;
  const tier = tiers.find((item) => Number(item.useIndex) === useIndex);
  if (!tier) {
    return { code: "COUPON_USE_TIER_MISSING", coupon, useIndex };
  }

  const fareBeforeDiscountIqd = Math.max(0, Number(proposedFareIqd) || 0);
  const discountIqd = computeDiscountIqd({
    fareBeforeDiscountIqd,
    discountType: tier.discountType,
    discountValue: tier.discountValue,
  });
  const fareAfterDiscountIqd = Math.max(0, fareBeforeDiscountIqd - discountIqd);

  return {
    code: "OK",
    coupon,
    tier,
    useIndex,
    fareBeforeDiscountIqd,
    discountIqd,
    fareAfterDiscountIqd,
    settledUserUses,
    remainingUses: Math.max(0, coupon.maxUsesPerUser - settledUserUses - 1),
  };
}

export async function listMyCoupons(userId) {
  const residence = await getUserResidence(userId);
  if (!residence) return [];
  const codes = formatResidenceMatchCodes(residence);

  const r = await q(
    `SELECT c.*
     FROM taxi_coupon c
     WHERE c.is_active = TRUE
       AND (
         c.apply_whole_app = TRUE
         OR EXISTS (
           SELECT 1
           FROM taxi_coupon_target_user tu
           WHERE tu.coupon_id = c.id
             AND tu.user_id = $1
         )
         OR EXISTS (
           SELECT 1
           FROM taxi_coupon_target_building tb
           WHERE tb.coupon_id = c.id
             AND UPPER(tb.building_code) = UPPER($2)
         )
         OR EXISTS (
           SELECT 1
           FROM taxi_coupon_target_block tk
           WHERE tk.coupon_id = c.id
             AND UPPER(tk.block_code) = UPPER($3)
         )
         OR EXISTS (
           SELECT 1
           FROM taxi_coupon_target_compound tc
           WHERE tc.coupon_id = c.id
             AND UPPER(tc.compound_code) = UPPER($4)
         )
       )
     ORDER BY c.created_at DESC, c.id DESC`,
    [Number(userId), codes.building || "", codes.block || "", codes.compound || ""]
  );

  const out = [];
  for (const row of r.rows) {
    const coupon = mapCoupon(row);
    if (!coupon) continue;
    const preview = await getCouponPreviewForUser({
      userId,
      couponCode: coupon.code,
      proposedFareIqd: 10000,
    });
    const settledUses = await countCouponUsages({
      couponId: coupon.id,
      userId,
      statuses: ["settled"],
    });
    out.push({
      ...coupon,
      statusCode: preview.code,
      nextUseIndex: preview.useIndex || null,
      nextDiscountType: preview.tier?.discountType || null,
      nextDiscountValue: preview.tier?.discountValue || null,
      settledUses,
      remainingUses: Math.max(0, coupon.maxUsesPerUser - settledUses),
    });
  }
  return out;
}

export async function settleCouponForCompletedRide({
  rideId,
  captainUserId,
  actorUserId = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const lockRide = await client.query(
      `SELECT *
       FROM taxi_ride_request
       WHERE id = $1
       FOR UPDATE`,
      [Number(rideId)]
    );
    const ride = lockRide.rows[0];
    if (!ride) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }
    if (String(ride.status || "").toLowerCase() !== "completed") {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_COMPLETED", status: ride.status };
    }
    if (!ride.coupon_id || ride.coupon_settlement_state === "settled") {
      await client.query("ROLLBACK");
      return { code: "NO_COUPON" };
    }

    const existingUsage = await client.query(
      `SELECT *
       FROM taxi_coupon_usage
       WHERE ride_request_id = $1
       LIMIT 1`,
      [Number(rideId)]
    );
    if (existingUsage.rowCount > 0) {
      await client.query(
        `UPDATE taxi_ride_request
         SET coupon_settlement_state = 'settled',
             updated_at = NOW()
         WHERE id = $1`,
        [Number(rideId)]
      );
      await client.query("COMMIT");
      return {
        code: "ALREADY_SETTLED",
        usage: mapCouponUsage(existingUsage.rows[0]),
      };
    }

    const couponLock = await client.query(
      `SELECT *
       FROM taxi_coupon
       WHERE id = $1
       FOR UPDATE`,
      [Number(ride.coupon_id)]
    );
    const coupon = mapCoupon(couponLock.rows[0]);
    if (!coupon) {
      await client.query(
        `UPDATE taxi_ride_request
         SET coupon_settlement_state = 'cancelled',
             updated_at = NOW()
         WHERE id = $1`,
        [Number(rideId)]
      );
      await client.query("COMMIT");
      return { code: "COUPON_NOT_FOUND" };
    }

    const userUsage = await client.query(
      `SELECT COUNT(*)::int AS count
       FROM taxi_coupon_usage
       WHERE coupon_id = $1
         AND user_id = $2
         AND status = 'settled'`,
      [Number(coupon.id), Number(ride.customer_user_id)]
    );
    const settledUserUses = Number(userUsage.rows[0]?.count || 0);
    if (settledUserUses >= coupon.maxUsesPerUser) {
      await client.query(
        `UPDATE taxi_ride_request
         SET coupon_settlement_state = 'cancelled',
             updated_at = NOW()
         WHERE id = $1`,
        [Number(rideId)]
      );
      await client.query("COMMIT");
      return { code: "COUPON_USER_LIMIT_REACHED" };
    }

    const totalUsage = await client.query(
      `SELECT COUNT(*)::int AS count
       FROM taxi_coupon_usage
       WHERE coupon_id = $1
         AND status = 'settled'`,
      [Number(coupon.id)]
    );
    const settledTotalUses = Number(totalUsage.rows[0]?.count || 0);
    if (coupon.maxTotalUses != null && settledTotalUses >= coupon.maxTotalUses) {
      await client.query(
        `UPDATE taxi_ride_request
         SET coupon_settlement_state = 'cancelled',
             updated_at = NOW()
         WHERE id = $1`,
        [Number(rideId)]
      );
      await client.query("COMMIT");
      return { code: "COUPON_TOTAL_LIMIT_REACHED" };
    }

    const useIndex = settledUserUses + 1;
    const tierQuery = await client.query(
      `SELECT *
       FROM taxi_coupon_discount_tier
       WHERE coupon_id = $1
         AND use_index = $2
       LIMIT 1`,
      [Number(coupon.id), useIndex]
    );
    const tier = mapCouponTier(tierQuery.rows[0]);
    if (!tier) {
      await client.query(
        `UPDATE taxi_ride_request
         SET coupon_settlement_state = 'cancelled',
             updated_at = NOW()
         WHERE id = $1`,
        [Number(rideId)]
      );
      await client.query("COMMIT");
      return { code: "COUPON_TIER_NOT_AVAILABLE", useIndex };
    }

    const fareBeforeDiscountIqd =
      toInt(ride.fare_before_discount_iqd) ??
      toInt(ride.agreed_fare_iqd) ??
      toInt(ride.proposed_fare_iqd) ??
      0;
    const discountIqd = computeDiscountIqd({
      fareBeforeDiscountIqd,
      discountType: tier.discountType,
      discountValue: tier.discountValue,
    });
    const fareAfterDiscountIqd = Math.max(0, fareBeforeDiscountIqd - discountIqd);

    const usageInserted = await client.query(
      `INSERT INTO taxi_coupon_usage
        (
          coupon_id,
          user_id,
          ride_request_id,
          use_index,
          discount_type,
          discount_value,
          fare_before_discount_iqd,
          discount_iqd,
          fare_after_discount_iqd,
          status,
          settled_at,
          created_at,
          updated_at
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'settled',NOW(),NOW(),NOW())
       RETURNING *`,
      [
        Number(coupon.id),
        Number(ride.customer_user_id),
        Number(ride.id),
        Number(useIndex),
        tier.discountType,
        Number(tier.discountValue),
        Number(fareBeforeDiscountIqd),
        Number(discountIqd),
        Number(fareAfterDiscountIqd),
      ]
    );

    await client.query(
      `UPDATE taxi_ride_request
       SET coupon_use_index = $2,
           fare_before_discount_iqd = $3,
           coupon_discount_iqd = $4,
           fare_after_discount_iqd = $5,
           coupon_settlement_state = 'settled',
           updated_at = NOW()
       WHERE id = $1`,
      [
        Number(ride.id),
        Number(useIndex),
        Number(fareBeforeDiscountIqd),
        Number(discountIqd),
        Number(fareAfterDiscountIqd),
      ]
    );

    let ledgerRow = null;
    if (discountIqd > 0) {
      const ledger = await client.query(
        `INSERT INTO taxi_captain_credit_ledger
          (
            captain_user_id,
            ride_request_id,
            entry_type,
            amount_iqd,
            status,
            reference_kind,
            reference_id,
            note,
            meta,
            created_by_user_id,
            approved_by_user_id,
            approved_at,
            created_at,
            updated_at
          )
         VALUES ($1,$2,'coupon_discount',$3,'approved','taxi_coupon_ride',$2,$4,$5::jsonb,$6,$7,NOW(),NOW(),NOW())
         ON CONFLICT (captain_user_id, entry_type, reference_kind, reference_id)
         DO UPDATE SET
           amount_iqd = EXCLUDED.amount_iqd,
           status = EXCLUDED.status,
           approved_by_user_id = EXCLUDED.approved_by_user_id,
           approved_at = NOW(),
           updated_at = NOW()
         RETURNING *`,
        [
          Number(captainUserId),
          Number(ride.id),
          Number(discountIqd),
          `Coupon discount (${coupon.code})`,
          JSON.stringify({
            couponId: coupon.id,
            couponCode: coupon.code,
            useIndex,
            discountType: tier.discountType,
            discountValue: tier.discountValue,
            fareBeforeDiscountIqd,
            fareAfterDiscountIqd,
          }),
          actorUserId == null ? null : Number(actorUserId),
          actorUserId == null ? null : Number(actorUserId),
        ]
      );
      ledgerRow = mapLedgerRow(ledger.rows[0]);
    }

    await client.query("COMMIT");
    return {
      code: "OK",
      usage: mapCouponUsage(usageInserted.rows[0]),
      ledger: ledgerRow,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listCaptainLedger(captainUserId, { limit = 100 } = {}) {
  const r = await q(
    `SELECT *
     FROM taxi_captain_credit_ledger
     WHERE captain_user_id = $1
     ORDER BY created_at DESC, id DESC
     LIMIT $2`,
    [Number(captainUserId), Math.max(1, Math.min(500, Number(limit) || 100))]
  );
  return r.rows.map(mapLedgerRow);
}

export async function getCaptainSubscriptionSummary(captainUserId) {
  const [subscriptionRow, monthAgg] = await Promise.all([
    q(
      `SELECT *
       FROM taxi_captain_subscription
       WHERE captain_user_id = $1
       LIMIT 1`,
      [Number(captainUserId)]
    ),
    q(
      `SELECT
         COALESCE(SUM(amount_iqd) FILTER (
           WHERE status IN ('approved','settled')
             AND entry_type = 'coupon_discount'
             AND created_at >= DATE_TRUNC('month', NOW())
         ), 0)::bigint AS month_coupon_discount_iqd,
         COALESCE(SUM(amount_iqd) FILTER (
           WHERE status IN ('approved','settled')
             AND entry_type IN ('admin_gift','contest_reward','manual_credit')
             AND created_at >= DATE_TRUNC('month', NOW())
         ), 0)::bigint AS month_credits_iqd
       FROM taxi_captain_credit_ledger
       WHERE captain_user_id = $1`,
      [Number(captainUserId)]
    ),
  ]);

  const sub = subscriptionRow.rows[0] || {};
  const monthlySubscriptionAmountIqd = Math.max(0, Number(sub.monthly_fee_iqd || 0));
  const approvedDiscountsIqd = Math.max(0, Number(monthAgg.rows[0]?.month_coupon_discount_iqd || 0));
  const approvedCreditsIqd = Math.max(0, Number(monthAgg.rows[0]?.month_credits_iqd || 0));
  const totalOffsets = approvedDiscountsIqd + approvedCreditsIqd;
  const payableAmountIqd = Math.max(0, monthlySubscriptionAmountIqd - totalOffsets);
  const overflowIqd = Math.max(0, totalOffsets - monthlySubscriptionAmountIqd);

  return {
    captainUserId: Number(captainUserId),
    monthlySubscriptionAmountIqd,
    approvedDiscountsIqd,
    approvedCreditsIqd,
    payableAmountIqd,
    overflowIqd,
    cycleStartAt: sub.current_cycle_start_at || null,
    cycleEndAt: sub.current_cycle_end_at || null,
    cashPaymentPending: sub.cash_payment_pending === true,
    cashPaymentRequestedAt: sub.cash_payment_requested_at || null,
  };
}

async function evaluateContestProgressForCaptain(client, captainUserId, contest) {
  const targetType = String(contest.target_type || "").trim().toLowerCase();
  const startAt = contest.start_at;
  const endAt = contest.end_at;

  if (targetType === "rating_avg") {
    const r = await client.query(
      `SELECT COALESCE(AVG(captain_rating), 0)::numeric(14,3) AS value
       FROM taxi_ride_request
       WHERE assigned_captain_user_id = $1
         AND status = 'completed'
         AND captain_rating IS NOT NULL
         AND completed_at >= $2
         AND completed_at <= $3`,
      [Number(captainUserId), startAt, endAt]
    );
    return Number(r.rows[0]?.value || 0);
  }

  if (targetType === "accepted_bids") {
    const r = await client.query(
      `SELECT COUNT(*)::int AS value
       FROM taxi_ride_bid b
       JOIN taxi_ride_request r
         ON r.accepted_bid_id = b.id
       WHERE b.captain_user_id = $1
         AND r.accepted_at >= $2
         AND r.accepted_at <= $3`,
      [Number(captainUserId), startAt, endAt]
    );
    return Number(r.rows[0]?.value || 0);
  }

  const r = await client.query(
    `SELECT COUNT(*)::int AS value
     FROM taxi_ride_request
     WHERE assigned_captain_user_id = $1
       AND status = 'completed'
       AND completed_at >= $2
       AND completed_at <= $3`,
    [Number(captainUserId), startAt, endAt]
  );
  return Number(r.rows[0]?.value || 0);
}

export async function updateCaptainContestProgressAndRewards({
  captainUserId,
  actorUserId = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const contestsResult = await client.query(
      `SELECT *
       FROM taxi_captain_contest
       WHERE is_active = TRUE
         AND start_at <= NOW()
         AND end_at >= NOW()
       ORDER BY id ASC`
    );

    const newlyCreatedRewards = [];
    for (const contest of contestsResult.rows) {
      const progressValue = await evaluateContestProgressForCaptain(
        client,
        captainUserId,
        contest
      );
      const targetValue = Number(contest.target_value || 0);
      const qualified = progressValue >= targetValue;

      await client.query(
        `INSERT INTO taxi_captain_contest_progress
          (
            contest_id,
            captain_user_id,
            progress_value,
            is_qualified,
            qualified_at,
            last_calculated_at,
            created_at,
            updated_at
          )
         VALUES ($1,$2,$3,$4,$5,NOW(),NOW(),NOW())
         ON CONFLICT (contest_id, captain_user_id)
         DO UPDATE SET
           progress_value = EXCLUDED.progress_value,
           is_qualified = EXCLUDED.is_qualified,
           qualified_at = CASE
             WHEN taxi_captain_contest_progress.qualified_at IS NOT NULL
               THEN taxi_captain_contest_progress.qualified_at
             WHEN EXCLUDED.is_qualified THEN NOW()
             ELSE NULL
           END,
           last_calculated_at = NOW(),
           updated_at = NOW()`,
        [
          Number(contest.id),
          Number(captainUserId),
          Number(progressValue),
          qualified,
          qualified ? nowIso() : null,
        ]
      );

      if (!qualified) continue;

      const existingReward = await client.query(
        `SELECT id
         FROM taxi_captain_reward
         WHERE contest_id = $1
           AND captain_user_id = $2
         LIMIT 1`,
        [Number(contest.id), Number(captainUserId)]
      );
      if (existingReward.rowCount > 0) continue;

      const createdReward = await client.query(
        `INSERT INTO taxi_captain_reward
          (
            contest_id,
            captain_user_id,
            reward_type,
            reward_value,
            source_type,
            note,
            status,
            created_by_user_id,
            approved_by_user_id,
            approved_at,
            created_at,
            updated_at
          )
         VALUES ($1,$2,$3,$4,'contest',$5,'approved',$6,$6,NOW(),NOW(),NOW())
         RETURNING *`,
        [
          Number(contest.id),
          Number(captainUserId),
          String(contest.reward_type || "credit"),
          Number(contest.reward_value || 0),
          `Contest reward: ${contest.title || contest.id}`,
          actorUserId == null ? null : Number(actorUserId),
        ]
      );
      const reward = createdReward.rows[0];
      if (!reward) continue;

      await client.query(
        `INSERT INTO taxi_captain_credit_ledger
          (
            captain_user_id,
            entry_type,
            amount_iqd,
            status,
            reference_kind,
            reference_id,
            note,
            meta,
            created_by_user_id,
            approved_by_user_id,
            approved_at,
            created_at,
            updated_at
          )
         VALUES (
           $1,
           'contest_reward',
           $2,
           'approved',
           'taxi_contest_reward',
           $3,
           $4,
           $5::jsonb,
           $6,
           $6,
           NOW(),
           NOW(),
           NOW()
         )
         ON CONFLICT (captain_user_id, entry_type, reference_kind, reference_id)
         DO NOTHING`,
        [
          Number(captainUserId),
          Number(contest.reward_value || 0),
          Number(reward.id),
          `Contest reward: ${contest.title || contest.id}`,
          JSON.stringify({
            contestId: Number(contest.id),
            contestTitle: contest.title || null,
            rewardType: contest.reward_type || "credit",
          }),
          actorUserId == null ? null : Number(actorUserId),
        ]
      );

      newlyCreatedRewards.push({
        id: Number(reward.id),
        contestId: Number(reward.contest_id),
        rewardType: reward.reward_type,
        rewardValue: Number(reward.reward_value || 0),
      });
    }

    await client.query("COMMIT");
    return newlyCreatedRewards;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listCaptainContests(captainUserId) {
  const r = await q(
    `SELECT
       c.*,
       p.progress_value,
       p.is_qualified,
       p.qualified_at,
       p.last_calculated_at
     FROM taxi_captain_contest c
     LEFT JOIN taxi_captain_contest_progress p
       ON p.contest_id = c.id
      AND p.captain_user_id = $1
     WHERE c.is_active = TRUE
        OR c.end_at >= NOW() - INTERVAL '30 days'
     ORDER BY c.end_at DESC, c.id DESC`,
    [Number(captainUserId)]
  );
  return r.rows.map((row) => ({
    id: Number(row.id),
    title: row.title,
    description: row.description || null,
    startAt: row.start_at || null,
    endAt: row.end_at || null,
    targetType: row.target_type,
    targetValue: Number(row.target_value || 0),
    rewardType: row.reward_type,
    rewardValue: Number(row.reward_value || 0),
    isActive: row.is_active === true,
    progressValue: Number(row.progress_value || 0),
    isQualified: row.is_qualified === true,
    qualifiedAt: row.qualified_at || null,
    lastCalculatedAt: row.last_calculated_at || null,
  }));
}

export async function listCaptainRewards(captainUserId, { limit = 100 } = {}) {
  const r = await q(
    `SELECT
       r.*,
       c.title AS contest_title
     FROM taxi_captain_reward r
     LEFT JOIN taxi_captain_contest c
       ON c.id = r.contest_id
     WHERE r.captain_user_id = $1
     ORDER BY r.created_at DESC, r.id DESC
     LIMIT $2`,
    [Number(captainUserId), Math.max(1, Math.min(500, Number(limit) || 100))]
  );
  return r.rows.map((row) => ({
    id: Number(row.id),
    captainUserId: Number(row.captain_user_id),
    contestId: toInt(row.contest_id),
    contestTitle: row.contest_title || null,
    rewardType: row.reward_type,
    rewardValue: Number(row.reward_value || 0),
    sourceType: row.source_type,
    status: row.status,
    note: row.note || null,
    createdAt: row.created_at || null,
  }));
}

export async function getRideComplaintEligibility({ rideId, riderUserId }) {
  const r = await q(
    `SELECT
       id,
       customer_user_id,
       assigned_captain_user_id,
       status,
       completed_at
     FROM taxi_ride_request
     WHERE id = $1
     LIMIT 1`,
    [Number(rideId)]
  );
  const ride = r.rows[0];
  if (!ride) return { eligible: false, code: "RIDE_NOT_FOUND" };
  if (Number(ride.customer_user_id) !== Number(riderUserId)) {
    return { eligible: false, code: "RIDE_NOT_OWNED_BY_RIDER" };
  }
  if (String(ride.status || "").toLowerCase() !== "completed") {
    return { eligible: false, code: "RIDE_NOT_COMPLETED" };
  }
  if (!ride.assigned_captain_user_id) {
    return { eligible: false, code: "CAPTAIN_NOT_FOUND" };
  }
  if (!ride.completed_at) return { eligible: false, code: "RIDE_NOT_COMPLETED" };
  const completedAt = new Date(ride.completed_at);
  const withinWindow = completedAt.getTime() >= Date.now() - 24 * 60 * 60 * 1000;
  if (!withinWindow) return { eligible: false, code: "COMPLAINT_WINDOW_EXPIRED" };
  return {
    eligible: true,
    code: "OK",
    rideId: Number(ride.id),
    captainId: Number(ride.assigned_captain_user_id),
    completedAt: ride.completed_at,
  };
}

export async function createCaptainComplaint({
  riderUserId,
  tripId,
  category,
  reason,
  details,
  attachmentUrl,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const eligibility = await getRideComplaintEligibility({
      rideId: tripId,
      riderUserId,
    });
    if (!eligibility.eligible) {
      await client.query("ROLLBACK");
      return { code: eligibility.code };
    }

    const open = await client.query(
      `SELECT id
       FROM taxi_captain_complaint
       WHERE trip_id = $1
         AND status IN ('new', 'under_review')
       LIMIT 1`,
      [Number(tripId)]
    );
    if (open.rowCount > 0) {
      await client.query("ROLLBACK");
      return { code: "COMPLAINT_ALREADY_OPEN" };
    }

    const insert = await client.query(
      `INSERT INTO taxi_captain_complaint
        (
          trip_id,
          captain_id,
          rider_id,
          category,
          reason,
          details,
          attachment_url,
          rating_at_time_of_complaint,
          status,
          created_at
        )
       SELECT
         r.id,
         r.assigned_captain_user_id,
         r.customer_user_id,
         $2,
         $3,
         $4,
         $5,
         r.captain_rating,
         'new',
         NOW()
       FROM taxi_ride_request r
       WHERE r.id = $1
       RETURNING *`,
      [Number(tripId), category, reason, details || null, attachmentUrl || null]
    );

    await client.query("COMMIT");
    return { code: "OK", item: insert.rows[0] || null };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listRiderComplaints(riderUserId, { limit = 80 } = {}) {
  const r = await q(
    `SELECT *
     FROM taxi_captain_complaint
     WHERE rider_id = $1
     ORDER BY created_at DESC, id DESC
     LIMIT $2`,
    [Number(riderUserId), Math.max(1, Math.min(300, Number(limit) || 80))]
  );
  return r.rows.map((row) => ({
    id: Number(row.id),
    tripId: Number(row.trip_id),
    captainId: Number(row.captain_id),
    riderId: Number(row.rider_id),
    category: row.category,
    reason: row.reason,
    details: row.details || null,
    attachmentUrl: row.attachment_url || null,
    status: row.status,
    adminNote: row.admin_note || null,
    createdAt: row.created_at || null,
    resolvedAt: row.resolved_at || null,
  }));
}

export async function createRiderReviewByCaptain({
  rideId,
  captainUserId,
  rating,
  category,
  note,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const ride = await client.query(
      `SELECT id, status, assigned_captain_user_id, customer_user_id
       FROM taxi_ride_request
       WHERE id = $1
       FOR UPDATE`,
      [Number(rideId)]
    );
    const row = ride.rows[0];
    if (!row) {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_FOUND" };
    }
    if (String(row.status || "").toLowerCase() !== "completed") {
      await client.query("ROLLBACK");
      return { code: "RIDE_NOT_COMPLETED" };
    }
    if (Number(row.assigned_captain_user_id) !== Number(captainUserId)) {
      await client.query("ROLLBACK");
      return { code: "FORBIDDEN" };
    }

    const out = await client.query(
      `INSERT INTO taxi_rider_review_by_captain
        (
          ride_request_id,
          captain_user_id,
          rider_user_id,
          rating,
          category,
          note,
          created_at
        )
       VALUES ($1,$2,$3,$4,$5,$6,NOW())
       ON CONFLICT (ride_request_id, captain_user_id)
       DO UPDATE SET
         rating = EXCLUDED.rating,
         category = EXCLUDED.category,
         note = EXCLUDED.note
       RETURNING *`,
      [
        Number(rideId),
        Number(captainUserId),
        Number(row.customer_user_id),
        Number(rating),
        category || null,
        note || null,
      ]
    );
    await client.query("COMMIT");
    return { code: "OK", item: out.rows[0] || null };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function issueCaptainWarning({
  captainUserId,
  severity,
  reasonCode,
  reasonText,
  affectsStatus,
  statusEffect,
  adminNote,
  issuedByUserId,
  expiresAt = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const current = await client.query(
      `SELECT governance_status, warning_count
       FROM taxi_captain_profile
       WHERE user_id = $1
       FOR UPDATE`,
      [Number(captainUserId)]
    );
    if (current.rowCount === 0) {
      await client.query("ROLLBACK");
      return { code: "CAPTAIN_NOT_FOUND" };
    }
    const oldStatus = current.rows[0].governance_status || "active";
    const nextStatus = affectsStatus && statusEffect ? statusEffect : oldStatus;
    const warningCount = Number(current.rows[0].warning_count || 0) + 1;

    const warningInsert = await client.query(
      `INSERT INTO taxi_captain_warning
        (
          captain_user_id,
          severity,
          reason_code,
          reason_text,
          affects_status,
          status_effect,
          admin_note,
          issued_by_user_id,
          created_at,
          expires_at
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NOW(),$9)
       RETURNING *`,
      [
        Number(captainUserId),
        severity,
        reasonCode || null,
        reasonText || null,
        affectsStatus === true,
        statusEffect || null,
        adminNote || null,
        Number(issuedByUserId),
        expiresAt,
      ]
    );

    await client.query(
      `UPDATE taxi_captain_profile
       SET governance_status = $2,
           warning_count = $3,
           suspended_until = CASE
             WHEN $2 = 'temporarily_suspended' THEN $4::timestamptz
             WHEN $2 = 'active' THEN NULL
             ELSE suspended_until
           END,
           updated_at = NOW()
       WHERE user_id = $1`,
      [
        Number(captainUserId),
        nextStatus,
        warningCount,
        expiresAt,
      ]
    );

    await client.query(
      `INSERT INTO taxi_captain_status_history
        (
          captain_user_id,
          old_status,
          new_status,
          reason_code,
          note,
          changed_by_user_id,
          created_at
        )
       VALUES ($1,$2,$3,$4,$5,$6,NOW())`,
      [
        Number(captainUserId),
        oldStatus,
        nextStatus,
        reasonCode || null,
        adminNote || null,
        Number(issuedByUserId),
      ]
    );

    await client.query("COMMIT");
    return {
      code: "OK",
      warning: warningInsert.rows[0] || null,
      nextStatus,
      warningCount,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function setCaptainGovernanceStatus({
  captainUserId,
  newStatus,
  reasonCode,
  note,
  changedByUserId,
  suspendedUntil = null,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const lock = await client.query(
      `SELECT governance_status
       FROM taxi_captain_profile
       WHERE user_id = $1
       FOR UPDATE`,
      [Number(captainUserId)]
    );
    if (lock.rowCount === 0) {
      await client.query("ROLLBACK");
      return { code: "CAPTAIN_NOT_FOUND" };
    }
    const oldStatus = lock.rows[0].governance_status || "active";

    const updated = await client.query(
      `UPDATE taxi_captain_profile
       SET governance_status = $2,
           suspended_until = CASE
             WHEN $2 = 'temporarily_suspended' THEN $3::timestamptz
             WHEN $2 = 'active' THEN NULL
             ELSE suspended_until
           END,
           updated_at = NOW()
       WHERE user_id = $1
       RETURNING user_id, governance_status, warning_count, suspended_until`,
      [Number(captainUserId), newStatus, suspendedUntil]
    );

    await client.query(
      `INSERT INTO taxi_captain_status_history
        (
          captain_user_id,
          old_status,
          new_status,
          reason_code,
          note,
          changed_by_user_id,
          created_at
        )
       VALUES ($1,$2,$3,$4,$5,$6,NOW())`,
      [
        Number(captainUserId),
        oldStatus,
        newStatus,
        reasonCode || null,
        note || null,
        Number(changedByUserId),
      ]
    );

    await client.query("COMMIT");
    return { code: "OK", profile: updated.rows[0] || null };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function getCaptainGovernanceStatus(captainUserId) {
  const [profile, warnings] = await Promise.all([
    q(
      `SELECT
         user_id,
         governance_status,
         warning_count,
         suspended_until,
         rating_avg,
         rides_count
       FROM taxi_captain_profile
       WHERE user_id = $1
       LIMIT 1`,
      [Number(captainUserId)]
    ),
    q(
      `SELECT
         id,
         severity,
         reason_code,
         reason_text,
         affects_status,
         status_effect,
         admin_note,
         created_at,
         expires_at,
         revoked_at
       FROM taxi_captain_warning
       WHERE captain_user_id = $1
       ORDER BY created_at DESC, id DESC
       LIMIT 40`,
      [Number(captainUserId)]
    ),
  ]);
  return {
    profile: profile.rows[0] || null,
    warnings: warnings.rows,
  };
}

export async function listAdminComplaints({
  status = "new",
  limit = 120,
}) {
  const normalizedStatus = String(status || "").trim().toLowerCase();
  const where =
    normalizedStatus === "all" ? "TRUE" : "c.status = $1";
  const params =
    normalizedStatus === "all"
      ? [Math.max(1, Math.min(500, Number(limit) || 120))]
      : [normalizedStatus, Math.max(1, Math.min(500, Number(limit) || 120))];

  const sql =
    normalizedStatus === "all"
      ? `SELECT
           c.*,
           rider.full_name AS rider_full_name,
           rider.phone AS rider_phone,
           captain.full_name AS captain_full_name,
           captain.phone AS captain_phone
         FROM taxi_captain_complaint c
         JOIN app_user rider ON rider.id = c.rider_id
         JOIN app_user captain ON captain.id = c.captain_id
         WHERE ${where}
         ORDER BY c.created_at DESC, c.id DESC
         LIMIT $1`
      : `SELECT
           c.*,
           rider.full_name AS rider_full_name,
           rider.phone AS rider_phone,
           captain.full_name AS captain_full_name,
           captain.phone AS captain_phone
         FROM taxi_captain_complaint c
         JOIN app_user rider ON rider.id = c.rider_id
         JOIN app_user captain ON captain.id = c.captain_id
         WHERE ${where}
         ORDER BY c.created_at DESC, c.id DESC
         LIMIT $2`;

  const r = await q(sql, params);
  return r.rows.map((row) => ({
    id: Number(row.id),
    tripId: Number(row.trip_id),
    captainId: Number(row.captain_id),
    captainFullName: row.captain_full_name || null,
    captainPhone: row.captain_phone || null,
    riderId: Number(row.rider_id),
    riderFullName: row.rider_full_name || null,
    riderPhone: row.rider_phone || null,
    category: row.category,
    reason: row.reason,
    details: row.details || null,
    status: row.status,
    adminNote: row.admin_note || null,
    createdAt: row.created_at || null,
    resolvedAt: row.resolved_at || null,
  }));
}

export async function reviewComplaintByAdmin({
  complaintId,
  nextStatus,
  adminNote,
  reviewerUserId,
}) {
  const normalizedStatus = String(nextStatus || "").trim().toLowerCase();
  const allowed = new Set(["under_review", "resolved", "rejected"]);
  if (!allowed.has(normalizedStatus)) return null;

  const r = await q(
    `UPDATE taxi_captain_complaint
     SET status = $2,
         admin_note = $3,
         reviewed_by_user_id = $4,
         resolved_at = CASE
           WHEN $2 IN ('resolved', 'rejected') THEN NOW()
           ELSE resolved_at
         END
     WHERE id = $1
     RETURNING *`,
    [Number(complaintId), normalizedStatus, adminNote || null, Number(reviewerUserId)]
  );
  return r.rows[0] || null;
}

export async function createCaptainGiftReward({
  captainUserId,
  rewardType = "credit",
  rewardValue,
  reason,
  adminNote,
  actorUserId,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const reward = await client.query(
      `INSERT INTO taxi_captain_reward
        (
          contest_id,
          captain_user_id,
          reward_type,
          reward_value,
          source_type,
          note,
          status,
          created_by_user_id,
          approved_by_user_id,
          approved_at,
          created_at,
          updated_at
        )
       VALUES (NULL,$1,$2,$3,'gift',$4,'approved',$5,$5,NOW(),NOW(),NOW())
       RETURNING *`,
      [
        Number(captainUserId),
        rewardType,
        Math.max(0, Number(rewardValue) || 0),
        adminNote || reason || null,
        Number(actorUserId),
      ]
    );

    const rewardRow = reward.rows[0];
    if (rewardRow && Number(rewardRow.reward_value || 0) > 0) {
      await client.query(
        `INSERT INTO taxi_captain_credit_ledger
          (
            captain_user_id,
            entry_type,
            amount_iqd,
            status,
            reference_kind,
            reference_id,
            note,
            meta,
            created_by_user_id,
            approved_by_user_id,
            approved_at,
            created_at,
            updated_at
          )
         VALUES (
           $1,
           'admin_gift',
           $2,
           'approved',
           'taxi_admin_gift',
           $3,
           $4,
           $5::jsonb,
           $6,
           $6,
           NOW(),
           NOW(),
           NOW()
         )
         ON CONFLICT (captain_user_id, entry_type, reference_kind, reference_id)
         DO NOTHING`,
        [
          Number(captainUserId),
          Number(rewardRow.reward_value || 0),
          Number(rewardRow.id),
          reason || "Admin gift",
          JSON.stringify({
            rewardId: Number(rewardRow.id),
            rewardType: rewardType,
            reason: reason || null,
          }),
          Number(actorUserId),
        ]
      );
    }

    await client.query("COMMIT");
    return rewardRow || null;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function listCaptainStatusHistory(captainUserId, { limit = 80 } = {}) {
  const r = await q(
    `SELECT *
     FROM taxi_captain_status_history
     WHERE captain_user_id = $1
     ORDER BY created_at DESC, id DESC
     LIMIT $2`,
    [Number(captainUserId), Math.max(1, Math.min(300, Number(limit) || 80))]
  );
  return r.rows.map((row) => ({
    id: Number(row.id),
    captainUserId: Number(row.captain_user_id),
    oldStatus: row.old_status || null,
    newStatus: row.new_status,
    reasonCode: row.reason_code || null,
    note: row.note || null,
    changedByUserId: toInt(row.changed_by_user_id),
    createdAt: row.created_at || null,
  }));
}

export async function searchCouponTargetUsers({
  query = "",
  limit = 40,
}) {
  const text = `%${String(query || "").trim().toLowerCase()}%`;
  const r = await q(
    `SELECT id, full_name, phone, block, building_number
     FROM app_user
     WHERE role = 'user'
       AND (
         $1 = '%%'
         OR LOWER(full_name) LIKE $1
         OR LOWER(phone) LIKE $1
       )
     ORDER BY id DESC
     LIMIT $2`,
    [text, Math.max(1, Math.min(200, Number(limit) || 40))]
  );
  return r.rows.map((row) => ({
    id: Number(row.id),
    fullName: row.full_name || null,
    phone: row.phone || null,
    block: row.block || null,
    buildingNumber: row.building_number || null,
  }));
}

export async function searchCouponTargetBuildings({
  query = "",
  limit = 40,
}) {
  const text = `%${String(query || "").trim().toUpperCase()}%`;
  const r = await q(
    `SELECT building_number AS code, COUNT(*)::int AS users_count
     FROM app_user
     WHERE building_number IS NOT NULL
       AND TRIM(building_number) <> ''
       AND ($1 = '%%' OR UPPER(building_number) LIKE $1)
     GROUP BY building_number
     ORDER BY users_count DESC, building_number ASC
     LIMIT $2`,
    [text, Math.max(1, Math.min(200, Number(limit) || 40))]
  );
  return r.rows.map((row) => ({
    code: String(row.code || "").trim().toUpperCase(),
    usersCount: Number(row.users_count || 0),
  }));
}

export async function searchCouponTargetBlocks({
  query = "",
  limit = 40,
}) {
  const text = `%${String(query || "").trim().toUpperCase()}%`;
  const r = await q(
    `SELECT block AS code, COUNT(*)::int AS users_count
     FROM app_user
     WHERE block IS NOT NULL
       AND TRIM(block) <> ''
       AND ($1 = '%%' OR UPPER(block) LIKE $1)
     GROUP BY block
     ORDER BY users_count DESC, block ASC
     LIMIT $2`,
    [text, Math.max(1, Math.min(200, Number(limit) || 40))]
  );
  return r.rows.map((row) => ({
    code: String(row.code || "").trim().toUpperCase(),
    usersCount: Number(row.users_count || 0),
  }));
}

export async function searchCouponTargetCompounds({
  query = "",
  limit = 40,
}) {
  const text = `%${String(query || "").trim().toUpperCase()}%`;
  const r = await q(
    `SELECT
       UPPER(SUBSTRING(building_number FROM 1 FOR 2)) AS code,
       COUNT(*)::int AS users_count
     FROM app_user
     WHERE building_number IS NOT NULL
       AND LENGTH(TRIM(building_number)) >= 2
       AND ($1 = '%%' OR UPPER(SUBSTRING(building_number FROM 1 FOR 2)) LIKE $1)
     GROUP BY UPPER(SUBSTRING(building_number FROM 1 FOR 2))
     ORDER BY users_count DESC, code ASC
     LIMIT $2`,
    [text, Math.max(1, Math.min(200, Number(limit) || 40))]
  );
  return r.rows.map((row) => ({
    code: String(row.code || "").trim().toUpperCase(),
    usersCount: Number(row.users_count || 0),
  }));
}

export async function listCouponsForAdmin({ includeInactive = true } = {}) {
  const r = await q(
    `SELECT *
     FROM taxi_coupon
     WHERE ($1::boolean = TRUE OR is_active = TRUE)
     ORDER BY created_at DESC, id DESC`,
    [includeInactive === true]
  );

  const out = [];
  for (const row of r.rows) {
    const coupon = mapCoupon(row);
    const [tiers, targets] = await Promise.all([
      q(
        `SELECT use_index, discount_type, discount_value
         FROM taxi_coupon_discount_tier
         WHERE coupon_id = $1
         ORDER BY use_index ASC`,
        [Number(coupon.id)]
      ),
      q(
        `SELECT
           (SELECT COUNT(*)::int FROM taxi_coupon_target_user u WHERE u.coupon_id = $1) AS users_count,
           (SELECT COUNT(*)::int FROM taxi_coupon_target_building b WHERE b.coupon_id = $1) AS buildings_count,
           (SELECT COUNT(*)::int FROM taxi_coupon_target_block bk WHERE bk.coupon_id = $1) AS blocks_count,
           (SELECT COUNT(*)::int FROM taxi_coupon_target_compound c WHERE c.coupon_id = $1) AS compounds_count`,
        [Number(coupon.id)]
      ),
    ]);

    out.push({
      ...coupon,
      tiers: tiers.rows.map((t) => ({
        useIndex: Number(t.use_index),
        discountType: t.discount_type,
        discountValue: Number(t.discount_value || 0),
      })),
      targets: {
        usersCount: Number(targets.rows[0]?.users_count || 0),
        buildingsCount: Number(targets.rows[0]?.buildings_count || 0),
        blocksCount: Number(targets.rows[0]?.blocks_count || 0),
        compoundsCount: Number(targets.rows[0]?.compounds_count || 0),
      },
    });
  }
  return out;
}

export async function upsertCouponByAdmin({
  couponId = null,
  dto,
  actorUserId,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    let couponRow = null;
    if (couponId == null) {
      const created = await client.query(
        `INSERT INTO taxi_coupon
          (
            code,
            title,
            description,
            is_active,
            valid_from,
            valid_until,
            max_total_uses,
            max_uses_per_user,
            apply_whole_app,
            created_by_admin_user_id,
            created_at,
            updated_at
          )
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,NOW(),NOW())
         RETURNING *`,
        [
          String(dto.code || "").trim().toUpperCase(),
          dto.title,
          dto.description || null,
          dto.isActive !== false,
          dto.validFrom || null,
          dto.validUntil || null,
          dto.maxTotalUses == null ? null : Number(dto.maxTotalUses),
          Number(dto.maxUsesPerUser || 1),
          dto.applyWholeApp === true,
          Number(actorUserId),
        ]
      );
      couponRow = created.rows[0] || null;
    } else {
      const updated = await client.query(
        `UPDATE taxi_coupon
         SET
           code = $2,
           title = $3,
           description = $4,
           is_active = $5,
           valid_from = $6,
           valid_until = $7,
           max_total_uses = $8,
           max_uses_per_user = $9,
           apply_whole_app = $10,
           updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [
          Number(couponId),
          String(dto.code || "").trim().toUpperCase(),
          dto.title,
          dto.description || null,
          dto.isActive !== false,
          dto.validFrom || null,
          dto.validUntil || null,
          dto.maxTotalUses == null ? null : Number(dto.maxTotalUses),
          Number(dto.maxUsesPerUser || 1),
          dto.applyWholeApp === true,
        ]
      );
      couponRow = updated.rows[0] || null;
    }

    if (!couponRow) {
      await client.query("ROLLBACK");
      return null;
    }

    const safeCouponId = Number(couponRow.id);
    await client.query(
      `DELETE FROM taxi_coupon_discount_tier
       WHERE coupon_id = $1`,
      [safeCouponId]
    );

    for (const tier of dto.tiers || []) {
      await client.query(
        `INSERT INTO taxi_coupon_discount_tier
          (
            coupon_id,
            use_index,
            discount_type,
            discount_value,
            created_at
          )
         VALUES ($1,$2,$3,$4,NOW())`,
        [
          safeCouponId,
          Number(tier.useIndex),
          String(tier.discountType || "percent").trim().toLowerCase(),
          Number(tier.discountValue || 0),
        ]
      );
    }

    await client.query(`DELETE FROM taxi_coupon_target_user WHERE coupon_id = $1`, [safeCouponId]);
    await client.query(`DELETE FROM taxi_coupon_target_building WHERE coupon_id = $1`, [safeCouponId]);
    await client.query(`DELETE FROM taxi_coupon_target_block WHERE coupon_id = $1`, [safeCouponId]);
    await client.query(`DELETE FROM taxi_coupon_target_compound WHERE coupon_id = $1`, [safeCouponId]);

    if (dto.applyWholeApp !== true) {
      for (const id of dto.targetUserIds || []) {
        await client.query(
          `INSERT INTO taxi_coupon_target_user (coupon_id, user_id, created_at)
           VALUES ($1,$2,NOW())
           ON CONFLICT (coupon_id, user_id) DO NOTHING`,
          [safeCouponId, Number(id)]
        );
      }
      for (const code of dto.targetBuildings || []) {
        await client.query(
          `INSERT INTO taxi_coupon_target_building (coupon_id, building_code, created_at)
           VALUES ($1,$2,NOW())
           ON CONFLICT (coupon_id, building_code) DO NOTHING`,
          [safeCouponId, String(code).trim().toUpperCase()]
        );
      }
      for (const code of dto.targetBlocks || []) {
        await client.query(
          `INSERT INTO taxi_coupon_target_block (coupon_id, block_code, created_at)
           VALUES ($1,$2,NOW())
           ON CONFLICT (coupon_id, block_code) DO NOTHING`,
          [safeCouponId, String(code).trim().toUpperCase()]
        );
      }
      for (const code of dto.targetCompounds || []) {
        await client.query(
          `INSERT INTO taxi_coupon_target_compound (coupon_id, compound_code, created_at)
           VALUES ($1,$2,NOW())
           ON CONFLICT (coupon_id, compound_code) DO NOTHING`,
          [safeCouponId, String(code).trim().toUpperCase()]
        );
      }
    }

    await client.query("COMMIT");
    return mapCoupon(couponRow);
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function deleteCouponByAdmin(couponId) {
  const r = await q(
    `DELETE FROM taxi_coupon
     WHERE id = $1
     RETURNING id`,
    [Number(couponId)]
  );
  return r.rowCount > 0;
}

export async function listContestsForAdmin({ includeInactive = true } = {}) {
  const r = await q(
    `SELECT *
     FROM taxi_captain_contest
     WHERE ($1::boolean = TRUE OR is_active = TRUE)
     ORDER BY start_at DESC, id DESC`,
    [includeInactive === true]
  );

  const out = [];
  for (const row of r.rows) {
    const contest = mapContest(row);
    const [tiersResult, participantsResult] = await Promise.all([
      q(
        `SELECT *
         FROM taxi_captain_contest_tier
         WHERE contest_id = $1
         ORDER BY target_value ASC, id ASC`,
        [Number(contest.id)]
      ),
      q(
        `SELECT
           COUNT(*)::int AS participants_count,
           COUNT(*) FILTER (WHERE is_qualified = TRUE)::int AS qualified_count
         FROM taxi_captain_contest_progress
         WHERE contest_id = $1`,
        [Number(contest.id)]
      ),
    ]);
    out.push({
      ...contest,
      tiers: tiersResult.rows.map(mapContestTier),
      participantsCount: Number(participantsResult.rows[0]?.participants_count || 0),
      qualifiedCount: Number(participantsResult.rows[0]?.qualified_count || 0),
    });
  }
  return out;
}

export async function upsertContestByAdmin({
  contestId = null,
  dto,
  actorUserId,
}) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    let contestRow = null;
    if (contestId == null) {
      const created = await client.query(
        `INSERT INTO taxi_captain_contest
          (
            title,
            description,
            start_at,
            end_at,
            target_type,
            target_value,
            reward_type,
            reward_value,
            eligibility_rules,
            is_active,
            created_by_admin_user_id,
            created_at,
            updated_at
          )
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10,$11,NOW(),NOW())
         RETURNING *`,
        [
          dto.title,
          dto.description || null,
          dto.startAt,
          dto.endAt,
          dto.targetType,
          Number(dto.targetValue),
          dto.rewardType,
          Number(dto.rewardValue || 0),
          dto.eligibilityRules ? JSON.stringify(dto.eligibilityRules) : null,
          dto.isActive !== false,
          Number(actorUserId),
        ]
      );
      contestRow = created.rows[0] || null;
    } else {
      const updated = await client.query(
        `UPDATE taxi_captain_contest
         SET
           title = $2,
           description = $3,
           start_at = $4,
           end_at = $5,
           target_type = $6,
           target_value = $7,
           reward_type = $8,
           reward_value = $9,
           eligibility_rules = $10::jsonb,
           is_active = $11,
           updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [
          Number(contestId),
          dto.title,
          dto.description || null,
          dto.startAt,
          dto.endAt,
          dto.targetType,
          Number(dto.targetValue),
          dto.rewardType,
          Number(dto.rewardValue || 0),
          dto.eligibilityRules ? JSON.stringify(dto.eligibilityRules) : null,
          dto.isActive !== false,
        ]
      );
      contestRow = updated.rows[0] || null;
    }

    if (!contestRow) {
      await client.query("ROLLBACK");
      return null;
    }

    const safeContestId = Number(contestRow.id);
    await client.query(
      `DELETE FROM taxi_captain_contest_tier
       WHERE contest_id = $1`,
      [safeContestId]
    );

    const tiersInput = Array.isArray(dto.tiers) ? dto.tiers : [];
    for (const tier of tiersInput) {
      await client.query(
        `INSERT INTO taxi_captain_contest_tier
          (
            contest_id,
            target_value,
            reward_type,
            reward_value,
            created_at
          )
         VALUES ($1,$2,$3,$4,NOW())
         ON CONFLICT (contest_id, target_value)
         DO UPDATE SET
           reward_type = EXCLUDED.reward_type,
           reward_value = EXCLUDED.reward_value`,
        [
          safeContestId,
          Number(tier.targetValue),
          String(tier.rewardType || dto.rewardType || "credit").trim().toLowerCase(),
          Number(tier.rewardValue || 0),
        ]
      );
    }

    await client.query("COMMIT");
    return mapContest(contestRow);
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function deleteContestByAdmin(contestId) {
  const r = await q(
    `DELETE FROM taxi_captain_contest
     WHERE id = $1
     RETURNING id`,
    [Number(contestId)]
  );
  return r.rowCount > 0;
}

export async function finalizeContestByAdmin(contestId) {
  const updated = await q(
    `UPDATE taxi_captain_contest
     SET
       is_active = FALSE,
       end_at = CASE WHEN end_at > NOW() THEN NOW() ELSE end_at END,
       updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(contestId)]
  );
  const contest = updated.rows[0] || null;
  if (!contest) return null;

  const participants = await q(
    `SELECT DISTINCT captain_user_id
     FROM taxi_captain_contest_progress
     WHERE contest_id = $1`,
    [Number(contestId)]
  );
  for (const row of participants.rows) {
    await updateCaptainContestProgressAndRewards({
      captainUserId: Number(row.captain_user_id),
      actorUserId: null,
    });
  }
  return mapContest(contest);
}

export async function getCaptainAdminDetails(captainUserId) {
  const [profile, subscription, ledger, contests, rewards, warnings, history, complaints, rides, riderReviews] =
    await Promise.all([
      q(
        `SELECT
           u.id,
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
           p.rating_avg,
           p.rides_count,
           p.governance_status,
           p.warning_count,
           p.suspended_until
         FROM app_user u
         LEFT JOIN taxi_captain_profile p ON p.user_id = u.id
         WHERE u.id = $1
           AND u.role = 'taxi_captain'
         LIMIT 1`,
        [Number(captainUserId)]
      ),
      getCaptainSubscriptionSummary(captainUserId),
      listCaptainLedger(captainUserId, { limit: 120 }),
      listCaptainContests(captainUserId),
      listCaptainRewards(captainUserId, { limit: 120 }),
      getCaptainGovernanceStatus(captainUserId),
      listCaptainStatusHistory(captainUserId, { limit: 120 }),
      q(
        `SELECT *
         FROM taxi_captain_complaint
         WHERE captain_id = $1
         ORDER BY created_at DESC, id DESC
         LIMIT 120`,
        [Number(captainUserId)]
      ),
      q(
        `SELECT
           id,
           customer_user_id,
           status,
           proposed_fare_iqd,
           agreed_fare_iqd,
           coupon_discount_iqd,
           created_at,
           completed_at
         FROM taxi_ride_request
         WHERE assigned_captain_user_id = $1
         ORDER BY created_at DESC, id DESC
         LIMIT 200`,
        [Number(captainUserId)]
      ),
      q(
        `SELECT *
         FROM taxi_rider_review_by_captain
         WHERE captain_user_id = $1
         ORDER BY created_at DESC, id DESC
         LIMIT 120`,
        [Number(captainUserId)]
      ),
    ]);

  return {
    profile: profile.rows[0] || null,
    subscription,
    ledger,
    contests,
    rewards,
    warnings: warnings.warnings || [],
    governance: warnings.profile || null,
    statusHistory: history,
    complaints: complaints.rows,
    rides: rides.rows,
    riderReviews: riderReviews.rows,
  };
}

export async function getTaxiKpiOverview({
  period = "month",
}) {
  const normalized = String(period || "").trim().toLowerCase();
  const rangeSql =
    normalized === "day"
      ? "DATE_TRUNC('day', NOW())"
      : normalized === "week"
      ? "DATE_TRUNC('week', NOW())"
      : "DATE_TRUNC('month', NOW())";

  const [rides, captains, coupons, complaints, warnings] = await Promise.all([
    q(
      `SELECT
         COUNT(*)::int AS total_rides,
         COUNT(*) FILTER (WHERE status = 'completed')::int AS completed_rides,
         COUNT(*) FILTER (WHERE status = 'cancelled')::int AS cancelled_rides,
         COUNT(*) FILTER (WHERE status = 'expired')::int AS expired_rides,
         COALESCE(AVG(
           CASE
             WHEN status = 'completed' AND accepted_at IS NOT NULL AND created_at IS NOT NULL
               THEN EXTRACT(EPOCH FROM (accepted_at - created_at))
             ELSE NULL
           END
         ), 0)::numeric(14,2) AS avg_accept_seconds
       FROM taxi_ride_request
       WHERE created_at >= ${rangeSql}`
    ),
    q(
      `SELECT
         COUNT(*) FILTER (WHERE p.is_active = TRUE)::int AS active_captains,
         COALESCE(AVG(p.rating_avg), 0)::numeric(14,3) AS avg_captain_rating
       FROM taxi_captain_profile p`
    ),
    q(
      `SELECT
         COALESCE(SUM(u.discount_iqd), 0)::bigint AS coupons_discount_iqd
       FROM taxi_coupon_usage u
       WHERE u.status = 'settled'
         AND u.settled_at >= ${rangeSql}`
    ),
    q(
      `SELECT
         COUNT(*)::int AS complaints_total,
         COUNT(*) FILTER (WHERE status IN ('new', 'under_review'))::int AS complaints_open
       FROM taxi_captain_complaint
       WHERE created_at >= ${rangeSql}`
    ),
    q(
      `SELECT
         COUNT(*)::int AS warnings_total
       FROM taxi_captain_warning
       WHERE created_at >= ${rangeSql}`
    ),
  ]);

  const r = rides.rows[0] || {};
  const totalRides = Number(r.total_rides || 0);
  const cancelledRides = Number(r.cancelled_rides || 0);
  const expiredRides = Number(r.expired_rides || 0);
  const cancelledLike = cancelledRides + expiredRides;
  const cancellationRate = totalRides > 0 ? Number(((cancelledLike / totalRides) * 100).toFixed(2)) : 0;

  return {
    period: normalized,
    rides: {
      total: totalRides,
      completed: Number(r.completed_rides || 0),
      cancelled: cancelledRides,
      expired: expiredRides,
      cancellationRatePercent: cancellationRate,
      avgAcceptSeconds: Number(r.avg_accept_seconds || 0),
    },
    captains: {
      active: Number(captains.rows[0]?.active_captains || 0),
      averageRating: Number(captains.rows[0]?.avg_captain_rating || 0),
    },
    coupons: {
      totalDiscountIqd: Number(coupons.rows[0]?.coupons_discount_iqd || 0),
    },
    complaints: {
      total: Number(complaints.rows[0]?.complaints_total || 0),
      open: Number(complaints.rows[0]?.complaints_open || 0),
    },
    warnings: {
      total: Number(warnings.rows[0]?.warnings_total || 0),
    },
  };
}

export async function getTaxiReports({
  type = "captains",
  limit = 200,
}) {
  const safeLimit = Math.max(1, Math.min(500, Number(limit) || 200));
  const key = String(type || "").trim().toLowerCase();

  if (key === "captains") {
    const r = await q(
      `SELECT
         u.id,
         u.full_name,
         u.phone,
         p.rating_avg,
         p.rides_count,
         p.governance_status,
         p.warning_count
       FROM app_user u
       JOIN taxi_captain_profile p ON p.user_id = u.id
       ORDER BY p.rides_count DESC, p.rating_avg DESC, u.id DESC
       LIMIT $1`,
      [safeLimit]
    );
    return { type: key, items: r.rows };
  }

  if (key === "coupons") {
    const r = await q(
      `SELECT
         c.id,
         c.code,
         c.title,
         c.is_active,
         c.max_uses_per_user,
         c.max_total_uses,
         COUNT(u.id)::int AS settled_uses,
         COALESCE(SUM(u.discount_iqd), 0)::bigint AS total_discount_iqd
       FROM taxi_coupon c
       LEFT JOIN taxi_coupon_usage u
         ON u.coupon_id = c.id
        AND u.status = 'settled'
       GROUP BY c.id
       ORDER BY c.created_at DESC
       LIMIT $1`,
      [safeLimit]
    );
    return { type: key, items: r.rows };
  }

  if (key === "contests") {
    const r = await q(
      `SELECT *
       FROM taxi_captain_contest
       ORDER BY created_at DESC, id DESC
       LIMIT $1`,
      [safeLimit]
    );
    return { type: key, items: r.rows };
  }

  if (key === "credits") {
    const r = await q(
      `SELECT *
       FROM taxi_captain_credit_ledger
       ORDER BY created_at DESC, id DESC
       LIMIT $1`,
      [safeLimit]
    );
    return { type: key, items: r.rows };
  }

  if (key === "complaints") {
    const r = await q(
      `SELECT *
       FROM taxi_captain_complaint
       ORDER BY created_at DESC, id DESC
       LIMIT $1`,
      [safeLimit]
    );
    return { type: key, items: r.rows };
  }

  if (key === "captain_ratings") {
    const r = await q(
      `SELECT
         assigned_captain_user_id AS captain_user_id,
         COALESCE(AVG(captain_rating), 0)::numeric(14,3) AS rating_avg,
         COUNT(*) FILTER (WHERE captain_rating IS NOT NULL)::int AS ratings_count
       FROM taxi_ride_request
       WHERE assigned_captain_user_id IS NOT NULL
       GROUP BY assigned_captain_user_id
       ORDER BY ratings_count DESC, rating_avg DESC
       LIMIT $1`,
      [safeLimit]
    );
    return { type: key, items: r.rows };
  }

  if (key === "rider_ratings") {
    const r = await q(
      `SELECT *
       FROM taxi_rider_review_by_captain
       ORDER BY created_at DESC, id DESC
       LIMIT $1`,
      [safeLimit]
    );
    return { type: key, items: r.rows };
  }

  if (key === "warnings") {
    const r = await q(
      `SELECT *
       FROM taxi_captain_warning
       ORDER BY created_at DESC, id DESC
       LIMIT $1`,
      [safeLimit]
    );
    return { type: key, items: r.rows };
  }

  return { type: key, items: [] };
}
