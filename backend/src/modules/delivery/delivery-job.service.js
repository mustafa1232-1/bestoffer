import { AppError } from "../../shared/utils/errors.js";
import { pool } from "../../config/db.js";

/**
 * Grouped multi-store delivery service (delivery closure §3–§10).
 *
 * Authoritative contract:
 *   one order_group → one delivery_job → N delivery_pickup_stop (one per child
 *   customer_order) → one assigned courier → one customer drop-off.
 *
 * This replaces the per-child-order assignment inconsistency: the courier now
 * sees ONE grouped job, and the User/Store "assigned" state is derived from the
 * authoritative delivery_job assignment, never from an optimistic per-child flag.
 */

// Authoritative order_status enum values (see order_status type).
const CANCELLED_CHILD_STATUSES = new Set([
  "cancelled",
  "cancelled_by_store",
  "cancelled_by_customer",
  "cancelled_by_admin",
  "expired",
]);

// Assignment can start once each active store has accepted the child order.
// Actual store collection remains guarded by PICKUP_READY_CHILD_STATUSES.
const ASSIGNMENT_READY_CHILD_STATUSES = new Set([
  "approved",
  "preparing",
  "ready_for_delivery",
  "ready_for_pickup",
  "courier_requested",
  "courier_assigned",
  "picked_up",
  "on_the_way",
  "arrived",
  "delivered",
]);

const PICKUP_READY_CHILD_STATUSES = new Set([
  "ready_for_delivery",
  "ready_for_pickup",
]);

export const DEFAULT_PRESENCE_FRESHNESS_SEC = 90;

function isCancelled(status) {
  return CANCELLED_CHILD_STATUSES.has(String(status || "").trim().toLowerCase());
}
function isAssignmentReady(status) {
  return ASSIGNMENT_READY_CHILD_STATUSES.has(String(status || "").trim().toLowerCase());
}
function canStartPickup(status) {
  return PICKUP_READY_CHILD_STATUSES.has(String(status || "").trim().toLowerCase());
}
function alreadyPastPickupLifecycle(status) {
  return new Set([
    "picked_up",
    "on_the_way",
    "arrived",
    "delivered",
  ]).has(String(status || "").trim().toLowerCase());
}

/**
 * Idempotently create the delivery_job + pickup stops for a group, syncing
 * cancelled children out of the active pickup set. Safe to call repeatedly.
 */
export async function ensureDeliveryJobForGroup(client, orderGroupId) {
  const group = (
    await client.query("SELECT * FROM order_group WHERE id=$1 FOR UPDATE", [
      orderGroupId,
    ])
  ).rows[0];
  if (!group) throw new AppError("ORDER_GROUP_NOT_FOUND", { status: 404 });

  let job = (
    await client.query("SELECT * FROM delivery_job WHERE order_group_id=$1", [
      orderGroupId,
    ])
  ).rows[0];
  if (!job) {
    job = (
      await client.query(
        `INSERT INTO delivery_job (order_group_id, customer_user_id, payment_method)
         VALUES ($1,$2,$3)
         ON CONFLICT (order_group_id) DO UPDATE SET updated_at=NOW()
         RETURNING *`,
        [orderGroupId, group.customer_user_id, group.payment_method || null]
      )
    ).rows[0];
  }

  const children = (
    await client.query(
      `SELECT id, merchant_id, status, customer_phone, customer_block
         FROM customer_order WHERE order_group_id=$1 ORDER BY id`,
      [orderGroupId]
    )
  ).rows;

  let seq = 1;
  for (const ch of children) {
    if (isCancelled(ch.status)) {
      await client.query(
        `UPDATE delivery_pickup_stop
            SET pickup_status='CANCELLED', cancelled_at=NOW(), updated_at=NOW()
          WHERE child_order_id=$1 AND pickup_status<>'CANCELLED'`,
        [ch.id]
      );
      continue;
    }
    await client.query(
      `INSERT INTO delivery_pickup_stop
         (delivery_job_id, child_order_id, store_id, sequence_number, phone_snapshot)
       VALUES ($1,$2,$3,$4,$5)
       ON CONFLICT (child_order_id)
       DO UPDATE SET delivery_job_id=$1, store_id=$3, updated_at=NOW()`,
      [job.id, ch.id, ch.merchant_id, seq++, ch.customer_phone || null]
    );
  }
  return job;
}

/**
 * Transactional readiness recompute. READY_FOR_ASSIGNMENT only when at least one
 * active child order remains and every active child has been accepted.
 */
export async function recomputeGroupReadiness(client, orderGroupId) {
  const children = (
    await client.query(
      "SELECT status FROM customer_order WHERE order_group_id=$1",
      [orderGroupId]
    )
  ).rows;
  const active = children.filter((c) => !isCancelled(c.status));
  const ready =
    active.length > 0 && active.every((c) => isAssignmentReady(c.status));
  // No active child remains (every store cancelled) → the grouped job is dead.
  const next =
    active.length === 0
      ? "CANCELLED"
      : ready
        ? "READY_FOR_ASSIGNMENT"
        : "PENDING_STORES";
  await client.query(
    `UPDATE delivery_job
        SET assignment_status = CASE
              WHEN assignment_status IN ('ASSIGNED','REASSIGNING','FAILED')
              THEN assignment_status ELSE $2 END,
            lifecycle_status = CASE
              WHEN lifecycle_status IN ('ASSIGNED') THEN lifecycle_status ELSE $2 END,
            cancelled_at = CASE WHEN $2 = 'CANCELLED' THEN COALESCE(cancelled_at, NOW()) ELSE cancelled_at END,
            updated_at = NOW()
      WHERE order_group_id=$1`,
    [orderGroupId, next]
  );
  return next;
}

/**
 * Authoritative single-courier eligibility check for (re)assignment (§1A). Runs
 * inside the caller's transaction and LOCKS the courier's account/profile rows so
 * eligibility cannot change between validation and assignment. Throws
 * COURIER_NOT_ELIGIBLE (with a safe reason) when any rule fails; returns the
 * courier id on success. `ignoreDeliveryJobId` lets a courier remain eligible for
 * the very job being reassigned.
 */
export async function assertCourierEligibleForAssignment(
  client,
  courierUserId,
  { presenceFreshnessSec = DEFAULT_PRESENCE_FRESHNESS_SEC, ignoreDeliveryJobId = null } = {}
) {
  const uid = Number(courierUserId);
  // Lock the account + profile rows.
  const acct = (
    await client.query(
      `SELECT u.role, u.delivery_account_approved, u.is_account_disabled, u.locked_until,
              cp.is_app_courier, cp.active_status, cp.availability_status
         FROM app_user u
         JOIN courier_profile cp ON cp.user_id=u.id
        WHERE u.id=$1
        FOR UPDATE OF u, cp`,
      [uid]
    )
  ).rows[0];
  const fail = (reason) => {
    throw new AppError("COURIER_NOT_ELIGIBLE", { status: 409, details: { courierUserId: uid, reason } });
  };
  if (!acct) fail("no_courier_profile");
  if (String(acct.role || "").toLowerCase() !== "delivery") fail("not_delivery_role");
  if (acct.delivery_account_approved !== true) fail("account_not_approved");
  if (acct.is_account_disabled === true) fail("account_disabled");
  if (acct.locked_until && new Date(acct.locked_until).getTime() > Date.now()) fail("account_locked");
  if (acct.is_app_courier !== true) fail("not_app_courier");
  if (acct.active_status !== true) fail("account_not_active");
  if (String(acct.availability_status || "").toLowerCase() !== "online") fail("offline");

  // Lock + read the latest presence row.
  const presence = (
    await client.query(
      `SELECT is_online, EXTRACT(EPOCH FROM (NOW()-recorded_at)) AS presence_age
         FROM courier_presence
        WHERE courier_user_id=$1
        ORDER BY recorded_at DESC
        LIMIT 1
        FOR UPDATE`,
      [uid]
    )
  ).rows[0];
  if (!presence || presence.is_online !== true) fail("offline");
  if (Number(presence.presence_age) > presenceFreshnessSec) fail("presence_stale");

  // Busy in ANOTHER active grouped job (ignoring the job under reassignment).
  const groupedBusy = (
    await client.query(
      `SELECT 1 FROM delivery_job
        WHERE delivery_user_id=$1 AND assignment_status='ASSIGNED'
          AND lifecycle_status <> ALL($3::text[])
          AND ($2::bigint IS NULL OR id <> $2)
        LIMIT 1`,
      [uid, ignoreDeliveryJobId == null ? null : Number(ignoreDeliveryJobId), TERMINAL_LIFECYCLE]
    )
  ).rows.length > 0;
  if (groupedBusy) fail("busy_grouped_job");

  // Busy in the legacy per-order flow.
  const legacyBusy =
    (
      await client.query(
        `SELECT 1 FROM courier_assignment
          WHERE courier_user_id=$1 AND order_id IS NOT NULL AND ended_at IS NULL
            AND status IN ('pending','assigned','accepted') LIMIT 1`,
        [uid]
      )
    ).rows.length > 0 ||
    (
      await client.query(
        `SELECT 1 FROM customer_order
          WHERE delivery_user_id=$1 AND delivery_assignment_status='ASSIGNED'
            AND order_group_id IS NULL LIMIT 1`,
        [uid]
      )
    ).rows.length > 0;
  if (legacyBusy) fail("busy_legacy_order");

  return uid;
}

/**
 * Select one eligible app courier, returning explicit (safe, internal) exclusion
 * reasons. No PII in the reasons.
 */
export async function selectEligibleCourier(
  client,
  {
    presenceFreshnessSec = DEFAULT_PRESENCE_FRESHNESS_SEC,
    restrictToCourierUserIds = null,
    excludeCourierUserIds = null,
  } = {}
) {
  // Candidates that already lost an assignment collision this round — never
  // re-select them (§3), so the retry advances to the next eligible courier.
  const excludeSet = new Set(
    (Array.isArray(excludeCourierUserIds) ? excludeCourierUserIds : []).map((v) => Number(v))
  );
  // Optional allow-list: scopes selection to a specific candidate set. Used by
  // targeted/manual dispatch (and to make assignment deterministic in tests
  // that run against a shared database). Production passes nothing → global.
  const scoped =
    Array.isArray(restrictToCourierUserIds) && restrictToCourierUserIds.length > 0
      ? restrictToCourierUserIds.map((v) => Number(v))
      : null;
  const rows = (
    await client.query(
      `SELECT p.courier_user_id,
              cp.is_app_courier, cp.active_status, cp.availability_status,
              p.is_online,
              EXTRACT(EPOCH FROM (NOW()-p.recorded_at)) AS presence_age,
              u.role AS role,
              u.delivery_account_approved,
              u.is_account_disabled,
              u.locked_until
         FROM courier_presence p
         JOIN courier_profile cp ON cp.user_id=p.courier_user_id
         JOIN app_user u ON u.id=p.courier_user_id
        ${scoped ? "WHERE p.courier_user_id = ANY($1)" : ""}
        ORDER BY p.recorded_at DESC`,
      scoped ? [scoped] : []
    )
  ).rows;

  const excluded = [];
  let chosen = null;
  for (const r of rows) {
    const uid = Number(r.courier_user_id);
    if (excludeSet.has(uid)) {
      excluded.push({ courierUserId: uid, reason: "previously_failed_candidate" });
      continue;
    }
    // Account-level authority (§7).
    if (String(r.role || "").toLowerCase() !== "delivery") {
      excluded.push({ courierUserId: uid, reason: "not_delivery_role" });
      continue;
    }
    if (r.delivery_account_approved !== true) {
      excluded.push({ courierUserId: uid, reason: "account_not_approved" });
      continue;
    }
    if (r.is_account_disabled === true) {
      excluded.push({ courierUserId: uid, reason: "account_disabled" });
      continue;
    }
    if (r.locked_until && new Date(r.locked_until).getTime() > Date.now()) {
      excluded.push({ courierUserId: uid, reason: "account_locked" });
      continue;
    }
    // Courier-profile authority.
    if (r.is_app_courier !== true) {
      excluded.push({ courierUserId: uid, reason: "not_app_courier" });
      continue;
    }
    if (r.active_status !== true) {
      excluded.push({ courierUserId: uid, reason: "account_not_active" });
      continue;
    }
    if (
      String(r.availability_status || "").toLowerCase() !== "online" ||
      r.is_online !== true
    ) {
      excluded.push({ courierUserId: uid, reason: "offline" });
      continue;
    }
    if (Number(r.presence_age) > presenceFreshnessSec) {
      excluded.push({ courierUserId: uid, reason: "presence_stale" });
      continue;
    }
    // Busy in an active GROUPED job.
    const groupedBusy =
      (
        await client.query(
          `SELECT 1
             FROM delivery_job
            WHERE delivery_user_id=$1
              AND assignment_status='ASSIGNED'
              AND lifecycle_status <> ALL($2::text[])
            LIMIT 1`,
          [uid, TERMINAL_LIFECYCLE]
        )
      ).rows.length > 0;
    if (groupedBusy) {
      excluded.push({ courierUserId: uid, reason: "busy_grouped_job" });
      continue;
    }
    // Busy in the legacy per-order flow (active courier_assignment on a single
    // order, or a single order still mirrored ASSIGNED to this courier). A
    // courier mid single-order delivery must not also take a grouped job.
    const legacyBusy =
      (
        await client.query(
          `SELECT 1
             FROM courier_assignment
            WHERE courier_user_id=$1
              AND order_id IS NOT NULL
              AND ended_at IS NULL
              AND status IN ('pending','assigned','accepted')
            LIMIT 1`,
          [uid]
        )
      ).rows.length > 0 ||
      (
        await client.query(
          `SELECT 1
             FROM customer_order
            WHERE delivery_user_id=$1
              AND delivery_assignment_status='ASSIGNED'
              AND order_group_id IS NULL
            LIMIT 1`,
          [uid]
        )
      ).rows.length > 0;
    if (legacyBusy) {
      excluded.push({ courierUserId: uid, reason: "busy_legacy_order" });
      continue;
    }
    if (!chosen) chosen = uid;
    else excluded.push({ courierUserId: uid, reason: "not_selected_this_round" });
  }
  return { courierUserId: chosen, excluded };
}

/**
 * The authoritative assignment transaction. Assigns ONE courier to the whole
 * grouped job. Concurrency-safe (row lock + conditional update), idempotent by
 * idempotency_key, and writes the notification-outbox event in the SAME
 * transaction. Never marks ASSIGNED without a courier + active pickups.
 */
export async function assignDeliveryJobTx(
  client,
  { orderGroupId, courierUserId, idempotencyKey = null }
) {
  const job = (
    await client.query(
      "SELECT * FROM delivery_job WHERE order_group_id=$1 FOR UPDATE",
      [orderGroupId]
    )
  ).rows[0];
  if (!job) throw new AppError("DELIVERY_JOB_NOT_FOUND", { status: 404 });

  if (job.assignment_status === "ASSIGNED" && Number(job.delivery_user_id) > 0) {
    return { job, alreadyAssigned: true };
  }
  if (
    !["READY_FOR_ASSIGNMENT", "PENDING_NO_DRIVER"].includes(job.assignment_status)
  ) {
    throw new AppError("DELIVERY_JOB_NOT_READY", {
      status: 409,
      details: { assignmentStatus: job.assignment_status },
    });
  }

  const stops = (
    await client.query(
      `SELECT * FROM delivery_pickup_stop
        WHERE delivery_job_id=$1 AND pickup_status<>'CANCELLED'
        ORDER BY sequence_number`,
      [job.id]
    )
  ).rows;
  if (stops.length === 0) {
    // No active pickup remains — never assign a phantom job.
    await client.query(
      `UPDATE delivery_job SET assignment_status='FAILED', lifecycle_status='FAILED', updated_at=NOW() WHERE id=$1`,
      [job.id]
    );
    throw new AppError("NO_ACTIVE_PICKUPS", { status: 409 });
  }

  // Conditional update: only assign if still unassigned → blocks concurrent
  // workers from double-assigning.
  const updated = (
    await client.query(
      `UPDATE delivery_job
          SET delivery_user_id=$2,
              assignment_status='ASSIGNED', lifecycle_status='ASSIGNED',
              assigned_at=NOW(),
              assignment_attempt_count=assignment_attempt_count+1,
              idempotency_key=COALESCE(idempotency_key,$3),
              version=version+1, updated_at=NOW()
        WHERE id=$1 AND delivery_user_id IS NULL
        RETURNING *`,
      [job.id, courierUserId, idempotencyKey]
    )
  ).rows[0];
  if (!updated) {
    throw new AppError("ASSIGNMENT_CONFLICT", { status: 409 });
  }

  // Legacy compatibility: keep each active child order's delivery_user_id
  // consistent so existing per-order screens/queries also resolve the courier.
  await client.query(
    `UPDATE customer_order
        SET delivery_user_id=$2, delivery_assignment_status='ASSIGNED',
            courier_assigned_at=NOW()
      WHERE id IN (
        SELECT child_order_id FROM delivery_pickup_stop
         WHERE delivery_job_id=$1 AND pickup_status<>'CANCELLED')`,
    [job.id, courierUserId]
  );

  // §6: the ONE authoritative grouped courier_assignment (order_id NULL,
  // delivery_job_id set). Created in the same transaction as the delivery_job
  // ASSIGNED + child mirror + outbox. Not one row per child order. Idempotent
  // via the partial unique index uq_courier_assignment_active_job.
  // Safe contract (§4): never silently replace the courier on an active
  // assignment. Insert; on conflict read the existing active assignment — same
  // courier is idempotent, a different courier is a hard ASSIGNMENT_CONFLICT
  // (legitimate reassignment goes through reassignGroupedJob).
  const inserted = (
    await client.query(
      `INSERT INTO courier_assignment
         (delivery_job_id, courier_user_id, assignment_type, status,
          assigned_at, requested_at, requested_by_user_id, correlation_id)
       VALUES ($1,$2,'grouped','assigned',NOW(),NOW(),NULL,$3)
       ON CONFLICT (delivery_job_id) WHERE delivery_job_id IS NOT NULL AND ended_at IS NULL
       DO NOTHING
       RETURNING id`,
      [job.id, courierUserId, `job-${job.id}-assign`]
    )
  ).rows[0];
  let assignmentId;
  if (inserted) {
    assignmentId = Number(inserted.id);
  } else {
    const existing = (
      await client.query(
        `SELECT id, courier_user_id FROM courier_assignment
          WHERE delivery_job_id=$1 AND ended_at IS NULL`,
        [job.id]
      )
    ).rows[0];
    if (existing && Number(existing.courier_user_id) === Number(courierUserId)) {
      assignmentId = Number(existing.id); // idempotent same-courier re-assign
    } else {
      throw new AppError("ASSIGNMENT_CONFLICT", {
        status: 409,
        details: { activeCourierUserId: existing ? Number(existing.courier_user_id) : null },
      });
    }
  }

  // Notification-outbox event in the SAME transaction (§4/§9/§10). Idempotent.
  // target_surface is the authoritative `delivery` (not `courier`).
  await client.query(
    `INSERT INTO notification_outbox
       (event_id, event_type, recipient_user_id, target_surface,
        target_entity_type, target_entity_id, payload_json, priority)
     VALUES ($1,$2,$3,'delivery','delivery_job',$4,$5,'high')
     ON CONFLICT (event_id) DO NOTHING`,
    [
      // Per-courier event id: a reassignment to a new courier produces a fresh,
      // deliverable event instead of being deduped against the old courier's.
      `deliveryjob-assign-${job.id}-${courierUserId}`,
      stops.length > 1
        ? "COURIER_MULTI_STORE_DELIVERY_ASSIGNED"
        : "COURIER_DELIVERY_ASSIGNED",
      courierUserId,
      job.id,
      JSON.stringify({
        deliveryJobId: job.id,
        orderGroupId,
        assignmentId,
        numberOfStores: stops.length,
        stores: stops.length,
        route: `/delivery/job/${job.id}`,
        requiresAction: true,
      }),
    ]
  );

  return { job: updated, stops, assignmentId, alreadyAssigned: false };
}

// Grouped assignment statuses the production worker is allowed to act on.
const WORKER_ASSIGNABLE_STATUSES = [
  "READY_FOR_ASSIGNMENT",
  "PENDING_NO_DRIVER",
  "REASSIGNING",
];

/**
 * Worker loader (§4). Returns order_group_ids of grouped jobs that still need a
 * courier, locked with FOR UPDATE SKIP LOCKED so parallel workers never contend
 * on the same job. Callers process each id in its own transaction.
 */
export async function loadAssignableGroupOrderIds(
  client,
  limit = 25,
  { orderGroupIds = null } = {}
) {
  const safeLimit = Math.max(1, Math.min(100, Number(limit) || 25));
  const scopedGroups =
    Array.isArray(orderGroupIds) && orderGroupIds.length > 0
      ? orderGroupIds.map((v) => Number(v))
      : null;
  const rows = (
    await client.query(
      `SELECT order_group_id
         FROM delivery_job
        WHERE assignment_status = ANY($1)
          ${scopedGroups ? "AND order_group_id = ANY($3)" : ""}
        ORDER BY updated_at ASC, id ASC
        LIMIT $2
        FOR UPDATE SKIP LOCKED`,
      scopedGroups
        ? [WORKER_ASSIGNABLE_STATUSES, safeLimit, scopedGroups]
        : [WORKER_ASSIGNABLE_STATUSES, safeLimit]
    )
  ).rows;
  return rows.map((r) => Number(r.order_group_id));
}

/**
 * Process ONE grouped job to a terminal per-attempt outcome, inside the caller's
 * transaction (§4). Refreshes the job/stops from the current child-order state,
 * recomputes readiness, selects a single eligible courier, and assigns
 * atomically. On a concurrency conflict it transparently retries with the next
 * eligible courier instead of failing the job. When no courier is eligible the
 * job is parked at PENDING_NO_DRIVER (no false-assigned state).
 *
 * Returns one of:
 *   { status: 'ASSIGNED', courierUserId, job, stops }
 *   { status: 'ALREADY_ASSIGNED', job }
 *   { status: 'PENDING_NO_DRIVER', excluded }
 *   { status: 'CANCELLED' | 'NOT_READY', assignmentStatus }
 */
export async function runGroupedAssignmentForGroupTx(
  client,
  orderGroupId,
  {
    presenceFreshnessSec = DEFAULT_PRESENCE_FRESHNESS_SEC,
    maxCourierAttempts = 5,
    restrictToCourierUserIds = null,
  } = {}
) {
  await ensureDeliveryJobForGroup(client, orderGroupId);
  const readiness = await recomputeGroupReadiness(client, orderGroupId);

  const job = (
    await client.query(
      "SELECT * FROM delivery_job WHERE order_group_id=$1",
      [orderGroupId]
    )
  ).rows[0];
  if (!job) return { status: "NOT_READY", assignmentStatus: null };

  if (job.assignment_status === "ASSIGNED" && Number(job.delivery_user_id) > 0) {
    return { status: "ALREADY_ASSIGNED", job };
  }
  if (readiness === "CANCELLED" || job.assignment_status === "CANCELLED") {
    return { status: "CANCELLED", assignmentStatus: job.assignment_status };
  }
  if (!["READY_FOR_ASSIGNMENT", "PENDING_NO_DRIVER"].includes(job.assignment_status)) {
    return { status: "NOT_READY", assignmentStatus: job.assignment_status };
  }

  const tried = new Set();
  let lastExcluded = [];
  for (let attempt = 0; attempt < maxCourierAttempts; attempt += 1) {
    const { courierUserId, excluded } = await selectEligibleCourier(client, {
      presenceFreshnessSec,
      restrictToCourierUserIds,
      excludeCourierUserIds: [...tried], // §3: never re-pick a collided candidate
    });
    lastExcluded = excluded;
    if (!courierUserId) {
      break;
    }
    tried.add(courierUserId);
    // Savepoint so a collision (ASSIGNMENT_CONFLICT) cleanly rolls back this
    // attempt's partial writes (delivery_job UPDATE + mirror) before the retry
    // selects the next candidate — otherwise the failed attempt's state would
    // make the retry read the job as already assigned to the collided courier.
    await client.query("SAVEPOINT grp_attempt");
    try {
      const result = await assignDeliveryJobTx(client, {
        orderGroupId,
        courierUserId,
        idempotencyKey: `grp-${job.id}`,
      });
      await client.query("RELEASE SAVEPOINT grp_attempt");
      if (result.alreadyAssigned) return { status: "ALREADY_ASSIGNED", job: result.job };
      return {
        status: "ASSIGNED",
        courierUserId,
        job: result.job,
        stops: result.stops,
      };
    } catch (err) {
      await client.query("ROLLBACK TO SAVEPOINT grp_attempt").catch(() => {});
      // Another worker/courier won the row, or the courier just became busy —
      // retry with the next eligible courier rather than failing the job.
      // (NO_ACTIVE_PICKUPS / DELIVERY_JOB_NOT_READY are terminal → rethrow.)
      if (err?.code === "ASSIGNMENT_CONFLICT") {
        continue;
      }
      throw err;
    }
  }

  // No courier could be assigned this round → park at PENDING_NO_DRIVER.
  await client.query(
    `UPDATE delivery_job
        SET assignment_status='PENDING_NO_DRIVER', lifecycle_status='PENDING_NO_DRIVER',
            assignment_attempt_count=assignment_attempt_count+1, updated_at=NOW()
      WHERE order_group_id=$1 AND assignment_status IN ('READY_FOR_ASSIGNMENT','PENDING_NO_DRIVER','REASSIGNING')`,
    [orderGroupId]
  );
  return { status: "PENDING_NO_DRIVER", excluded: lastExcluded };
}

/**
 * The authoritative courier grouped-job query. Joins through delivery_job (NOT a
 * single child order), returning one grouped job with all active pickup stops.
 */
// Terminal lifecycle states — a job in one of these is NOT an active job.
const TERMINAL_LIFECYCLE = ["DELIVERED", "CANCELLED", "FAILED"];

export async function listCourierGroupedJobs(
  client,
  courierUserId,
  { includeTerminal = false } = {}
) {
  const jobs = (
    await client.query(
      `SELECT j.id AS delivery_job_id, j.order_group_id, j.assignment_status,
              j.lifecycle_status, j.delivery_user_id, j.assigned_at,
              g.public_id, g.is_multi_store, g.stores_count, g.payment_method,
              g.delivery_fee_total, g.raw_delivery_fee_total
         FROM delivery_job j
         JOIN order_group g ON g.id=j.order_group_id
        WHERE j.delivery_user_id=$1 AND j.assignment_status='ASSIGNED'
          ${includeTerminal ? "" : "AND j.lifecycle_status <> ALL($2::text[])"}
        ORDER BY j.assigned_at DESC`,
      includeTerminal ? [courierUserId] : [courierUserId, TERMINAL_LIFECYCLE]
    )
  ).rows;

  for (const j of jobs) {
    j.pickupStops = (
      await client.query(
        `SELECT s.id, s.child_order_id, s.store_id, s.sequence_number,
                s.pickup_status, s.preparation_status, m.name AS store_name
           FROM delivery_pickup_stop s
           LEFT JOIN merchant m ON m.id=s.store_id
          WHERE s.delivery_job_id=$1 AND s.pickup_status<>'CANCELLED'
          ORDER BY s.sequence_number`,
        [j.delivery_job_id]
      )
    ).rows;
    j.numberOfStores = j.pickupStops.length;
  }
  return jobs;
}

/**
 * Normalized assignment view for User/Store surfaces (§7). Reports `active:true`
 * ONLY when the authoritative grouped assignment is complete — preventing the
 * false "Courier assigned" state.
 */
export async function getGroupedAssignmentView(client, orderGroupId) {
  const row = (
    await client.query(
      `SELECT j.id AS delivery_job_id, j.order_group_id, j.assignment_status,
              j.lifecycle_status, j.delivery_user_id, j.assigned_at,
              u.full_name AS courier_name, u.phone AS courier_phone, u.image_url AS courier_photo,
              ca.id AS assignment_id,
              (SELECT COUNT(*)::int FROM delivery_pickup_stop s
                 WHERE s.delivery_job_id=j.id AND s.pickup_status<>'CANCELLED') AS active_stops,
              (SELECT COUNT(*)::int FROM delivery_pickup_stop s
                 WHERE s.delivery_job_id=j.id AND s.pickup_status='COLLECTED') AS collected_stops
         FROM delivery_job j
         LEFT JOIN app_user u ON u.id=j.delivery_user_id
         LEFT JOIN courier_assignment ca
                ON ca.delivery_job_id=j.id AND ca.ended_at IS NULL
        WHERE j.order_group_id=$1`,
      [orderGroupId]
    )
  ).rows[0];
  if (!row) return { active: false, status: "PENDING_STORES", pickupStops: [] };
  // §5: authority comes from the assignment IDENTITY, not from presentation
  // fields. Active when the assignment exists (courier_assignment not ended →
  // assignment_id present), the job is ASSIGNED to a courier, and the job is not
  // in a terminal lifecycle. A null courier display name does NOT deactivate it.
  const active =
    Number(row.assignment_id) > 0 &&
    Number(row.delivery_user_id) > 0 &&
    row.assignment_status === "ASSIGNED" &&
    !TERMINAL_LIFECYCLE.includes(row.lifecycle_status);

  const pickupStops = active
    ? (
        await client.query(
          `SELECT s.id, s.child_order_id, s.store_id, s.sequence_number,
                  s.preparation_status, s.pickup_status, s.arrived_at, s.collected_at,
                  s.latitude, s.longitude, s.address_snapshot_json,
                  m.name AS store_name, m.image_url AS store_photo, m.phone AS store_phone
             FROM delivery_pickup_stop s
             LEFT JOIN merchant m ON m.id=s.store_id
            WHERE s.delivery_job_id=$1 AND s.pickup_status<>'CANCELLED'
            ORDER BY s.sequence_number`,
          [Number(row.delivery_job_id)]
        )
      ).rows.map((s) => ({
        stopId: Number(s.id),
        childOrderId: Number(s.child_order_id),
        storeId: Number(s.store_id),
        storeName: s.store_name || null,
        storePhoto: s.store_photo || null,
        storePhone: s.store_phone || null,
        storeAddress: s.address_snapshot_json || null,
        latitude: s.latitude == null ? null : Number(s.latitude),
        longitude: s.longitude == null ? null : Number(s.longitude),
        sequence: Number(s.sequence_number),
        preparationStatus: s.preparation_status,
        pickupStatus: s.pickup_status,
        arrivedAt: s.arrived_at,
        collectedAt: s.collected_at,
      }))
    : [];

  return {
    active,
    id: active ? Number(row.assignment_id) : null,
    assignmentId: active ? Number(row.assignment_id) : null,
    deliveryJobId: Number(row.delivery_job_id),
    orderGroupId: Number(row.order_group_id),
    status: row.assignment_status,
    assignmentStatus: row.assignment_status,
    lifecycleStatus: row.lifecycle_status,
    courierUserId: active ? Number(row.delivery_user_id) : null,
    // Presentation fields — safe fallbacks; never gate `active`.
    courierName: active ? row.courier_name || "الدلفري" : null,
    courierPhone: active ? row.courier_phone || null : null,
    courierPhoto: active ? row.courier_photo || null : null,
    assignedAt: active ? row.assigned_at : null,
    numberOfStores: Number(row.active_stops || 0),
    pickupProgress: {
      collected: Number(row.collected_stops || 0),
      total: Number(row.active_stops || 0),
    },
    pickupStops,
  };
}

// =========================================================================
// Grouped-job courier lifecycle (§8). Server-enforced transition order:
//   ASSIGNED → ACKNOWLEDGED → HEADING_TO_PICKUPS → (per stop: ARRIVED →
//   COLLECTED) → HEADING_TO_CUSTOMER (only when every active stop COLLECTED)
//   → DELIVERED. Every mutation validates courier ownership; duplicates are
//   idempotent; a stale version cannot reverse a newer state.
// =========================================================================

async function loadOwnedJobForUpdate(client, courierUserId, deliveryJobId, expectedVersion) {
  const job = (
    await client.query("SELECT * FROM delivery_job WHERE id=$1 FOR UPDATE", [
      Number(deliveryJobId),
    ])
  ).rows[0];
  if (!job) throw new AppError("DELIVERY_JOB_NOT_FOUND", { status: 404 });
  if (Number(job.delivery_user_id) !== Number(courierUserId)) {
    throw new AppError("NOT_JOB_OWNER", { status: 403 });
  }
  if (
    expectedVersion != null &&
    Number(expectedVersion) !== Number(job.version)
  ) {
    throw new AppError("STALE_JOB_VERSION", {
      status: 409,
      details: { current: Number(job.version), provided: Number(expectedVersion) },
    });
  }
  return job;
}

async function bumpLifecycle(client, jobId, lifecycle) {
  await client.query(
    `UPDATE delivery_job
        SET lifecycle_status=$2, version=version+1, updated_at=NOW()
      WHERE id=$1`,
    [Number(jobId), lifecycle]
  );
}

async function activeStops(client, jobId) {
  return (
    await client.query(
      `SELECT * FROM delivery_pickup_stop
        WHERE delivery_job_id=$1 AND pickup_status<>'CANCELLED'
        ORDER BY sequence_number`,
      [Number(jobId)]
    )
  ).rows;
}

function withTx(fn) {
  return async (args) => {
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      const out = await fn(client, args);
      await client.query("COMMIT");
      return out;
    } catch (e) {
      await client.query("ROLLBACK").catch(() => {});
      throw e;
    } finally {
      client.release();
    }
  };
}

export const acknowledgeGroupedJob = withTx(async (client, { courierUserId, deliveryJobId, expectedVersion }) => {
  const job = await loadOwnedJobForUpdate(client, courierUserId, deliveryJobId, expectedVersion);
  if (job.assignment_status !== "ASSIGNED") {
    throw new AppError("JOB_NOT_ASSIGNED", { status: 409 });
  }
  // Idempotent: acknowledging twice is a no-op success.
  if (!job.accepted_at) {
    await client.query(
      `UPDATE delivery_job SET accepted_at=NOW(), lifecycle_status='ACKNOWLEDGED', version=version+1, updated_at=NOW() WHERE id=$1`,
      [job.id]
    );
    await client.query(
      `UPDATE courier_assignment SET acknowledged_at=COALESCE(acknowledged_at,NOW()), status='accepted'
         WHERE delivery_job_id=$1 AND ended_at IS NULL`,
      [job.id]
    );
  }
  return { deliveryJobId: Number(job.id), lifecycleStatus: "ACKNOWLEDGED" };
});

export const headingToPickups = withTx(async (client, { courierUserId, deliveryJobId, expectedVersion }) => {
  const job = await loadOwnedJobForUpdate(client, courierUserId, deliveryJobId, expectedVersion);
  if (!["ACKNOWLEDGED", "ASSIGNED", "HEADING_TO_PICKUPS"].includes(job.lifecycle_status)) {
    throw new AppError("INVALID_TRANSITION", { status: 409, details: { from: job.lifecycle_status } });
  }
  if (job.lifecycle_status !== "HEADING_TO_PICKUPS") {
    await bumpLifecycle(client, job.id, "HEADING_TO_PICKUPS");
  }
  return { deliveryJobId: Number(job.id), lifecycleStatus: "HEADING_TO_PICKUPS" };
});

export const markStopArrived = withTx(async (client, { courierUserId, deliveryJobId, stopId, expectedVersion }) => {
  const job = await loadOwnedJobForUpdate(client, courierUserId, deliveryJobId, expectedVersion);
  const stop = (
    await client.query(
      `SELECT * FROM delivery_pickup_stop WHERE id=$1 AND delivery_job_id=$2 FOR UPDATE`,
      [Number(stopId), job.id]
    )
  ).rows[0];
  if (!stop) throw new AppError("PICKUP_STOP_NOT_FOUND", { status: 404 });
  if (stop.pickup_status === "CANCELLED") throw new AppError("STOP_CANCELLED", { status: 409 });
  if (stop.pickup_status === "COLLECTED") {
    return { stopId: Number(stop.id), pickupStatus: "COLLECTED" }; // idempotent
  }
  if (stop.pickup_status !== "COURIER_ARRIVED") {
    await client.query(
      `UPDATE delivery_pickup_stop SET pickup_status='COURIER_ARRIVED', arrived_at=COALESCE(arrived_at,NOW()), updated_at=NOW() WHERE id=$1`,
      [stop.id]
    );
  }
  return { stopId: Number(stop.id), pickupStatus: "COURIER_ARRIVED" };
});

export const markStopCollected = withTx(async (client, { courierUserId, deliveryJobId, stopId, expectedVersion }) => {
  const job = await loadOwnedJobForUpdate(client, courierUserId, deliveryJobId, expectedVersion);
  const stop = (
    await client.query(
      `SELECT * FROM delivery_pickup_stop WHERE id=$1 AND delivery_job_id=$2 FOR UPDATE`,
      [Number(stopId), job.id]
    )
  ).rows[0];
  if (!stop) throw new AppError("PICKUP_STOP_NOT_FOUND", { status: 404 });
  if (stop.pickup_status === "CANCELLED") throw new AppError("STOP_CANCELLED", { status: 409 });
  // Collecting one stop must NOT affect the others.
  if (stop.pickup_status !== "COLLECTED") {
    const child = (
      await client.query(
        `SELECT id, status FROM customer_order WHERE id=$1 FOR UPDATE`,
        [Number(stop.child_order_id)]
      )
    ).rows[0];
    if (!child || !canStartPickup(child.status)) {
      throw new AppError("PICKUP_STOP_NOT_READY", {
        status: 409,
        details: {
          stopId: Number(stop.id),
          childOrderId: Number(stop.child_order_id),
          status: child?.status || null,
          alreadyPastPickupLifecycle: alreadyPastPickupLifecycle(child?.status),
        },
      });
    }
    await client.query(
      `UPDATE delivery_pickup_stop SET pickup_status='COLLECTED', collected_at=COALESCE(collected_at,NOW()), updated_at=NOW() WHERE id=$1`,
      [stop.id]
    );
  }
  const stops = await activeStops(client, job.id);
  const remaining = stops.filter((s) => s.pickup_status !== "COLLECTED").length;
  return {
    stopId: Number(stop.id),
    pickupStatus: "COLLECTED",
    remainingStops: remaining,
    allCollected: remaining === 0,
  };
});

export const headingToCustomer = withTx(async (client, { courierUserId, deliveryJobId, expectedVersion }) => {
  const job = await loadOwnedJobForUpdate(client, courierUserId, deliveryJobId, expectedVersion);
  const stops = await activeStops(client, job.id);
  if (stops.length === 0) throw new AppError("NO_ACTIVE_PICKUPS", { status: 409 });
  const notCollected = stops.filter((s) => s.pickup_status !== "COLLECTED");
  if (notCollected.length > 0) {
    // Cannot head to the customer before every active store is collected.
    throw new AppError("PICKUPS_INCOMPLETE", {
      status: 409,
      details: { pending: notCollected.map((s) => Number(s.id)) },
    });
  }
  if (job.lifecycle_status !== "HEADING_TO_CUSTOMER") {
    await bumpLifecycle(client, job.id, "HEADING_TO_CUSTOMER");
    await client.query(
      `UPDATE customer_order SET status='on_the_way', updated_at=NOW()
        WHERE order_group_id=$1 AND status NOT IN ('cancelled','delivered')`,
      [Number(job.order_group_id)]
    );
  }
  return { deliveryJobId: Number(job.id), lifecycleStatus: "HEADING_TO_CUSTOMER" };
});

export const markGroupedDelivered = withTx(async (client, { courierUserId, deliveryJobId, expectedVersion }) => {
  const job = await loadOwnedJobForUpdate(client, courierUserId, deliveryJobId, expectedVersion);
  if (job.lifecycle_status === "DELIVERED") {
    return { deliveryJobId: Number(job.id), lifecycleStatus: "DELIVERED" }; // idempotent
  }
  if (job.lifecycle_status !== "HEADING_TO_CUSTOMER") {
    throw new AppError("MUST_HEAD_TO_CUSTOMER_FIRST", { status: 409, details: { from: job.lifecycle_status } });
  }
  await client.query(
    `UPDATE delivery_job
        SET assignment_status='COMPLETED',
            lifecycle_status='DELIVERED',
            completed_at=NOW(),
            version=version+1,
            updated_at=NOW()
      WHERE id=$1`,
    [job.id]
  );
  await client.query(
    `UPDATE courier_assignment SET status='completed', completed_at=NOW(), ended_at=COALESCE(ended_at,NOW()), ended_reason=COALESCE(ended_reason,'COMPLETED')
       WHERE delivery_job_id=$1 AND ended_at IS NULL`,
    [job.id]
  );
  await client.query(
    `UPDATE customer_order SET status='delivered', delivered_at=COALESCE(delivered_at,NOW()), delivery_assignment_status='COMPLETED', updated_at=NOW()
      WHERE order_group_id=$1 AND status NOT IN ('cancelled','delivered')`,
    [Number(job.order_group_id)]
  );
  await client.query(
    `UPDATE order_group
        SET status='completed', updated_at=NOW()
      WHERE id=$1
        AND NOT EXISTS (
          SELECT 1
          FROM customer_order o
          WHERE o.order_group_id=$1
            AND o.status NOT IN (
              'delivered',
              'delivered_by_courier',
              'received_by_customer',
              'completed',
              'cancelled',
              'cancelled_by_store',
              'cancelled_by_customer',
              'cancelled_by_admin'
            )
        )`,
    [Number(job.order_group_id)]
  );
  await client.query(
    `UPDATE order_group_item_summary s
        SET status=o.status,
            updated_at=NOW()
       FROM customer_order o
      WHERE s.child_order_id=o.id
        AND s.order_group_id=$1`,
    [Number(job.order_group_id)]
  );
  return { deliveryJobId: Number(job.id), lifecycleStatus: "DELIVERED" };
});

/**
 * Courier's current active grouped job. Returns ONLY an active, non-terminal job
 * (never DELIVERED/CANCELLED/FAILED); null when the courier has no active job —
 * so an app restart after delivery does not reopen completed work.
 */
export const reassignGroupedJob = withTx(async (client, { orderGroupId, newCourierUserId, reason = "REASSIGNED" }) => {
  // 1-2. Lock the job and its active assignment.
  const job = (
    await client.query("SELECT * FROM delivery_job WHERE order_group_id=$1 FOR UPDATE", [
      Number(orderGroupId),
    ])
  ).rows[0];
  if (!job) throw new AppError("DELIVERY_JOB_NOT_FOUND", { status: 404 });
  if (job.lifecycle_status === "DELIVERED") {
    throw new AppError("JOB_ALREADY_DELIVERED", { status: 409 });
  }
  if (Number(newCourierUserId) === Number(job.delivery_user_id)) {
    throw new AppError("SAME_COURIER_REASSIGNMENT", { status: 409 });
  }
  await client.query(
    "SELECT id FROM courier_assignment WHERE delivery_job_id=$1 AND ended_at IS NULL FOR UPDATE",
    [job.id]
  );
  // §1A: prove the NEW courier is eligible (with row locks) BEFORE closing the
  // old assignment. If ineligible this throws now, so the job keeps its old
  // courier — a bad newCourierUserId never leaves the job driverless.
  await assertCourierEligibleForAssignment(client, Number(newCourierUserId), {
    ignoreDeliveryJobId: Number(job.id),
  });
  // 3-4. Close the old assignment with an audited ended reason.
  await client.query(
    `UPDATE courier_assignment
        SET ended_at=NOW(), cancelled_at=NOW(), status='released', ended_reason=$2
      WHERE delivery_job_id=$1 AND ended_at IS NULL`,
    [job.id, String(reason).slice(0, 60)]
  );
  // 5-7. Release the job so assignDeliveryJobTx can re-assign it authoritatively.
  await client.query(
    `UPDATE delivery_job
        SET delivery_user_id=NULL, assignment_status='READY_FOR_ASSIGNMENT',
            lifecycle_status='READY_FOR_ASSIGNMENT', version=version+1, updated_at=NOW()
      WHERE id=$1`,
    [job.id]
  );
  // 8. Clear child compatibility fields for the old courier.
  await client.query(
    `UPDATE customer_order
        SET delivery_user_id=NULL, delivery_assignment_status='PENDING_NO_DRIVER', updated_at=NOW()
      WHERE order_group_id=$1 AND status NOT IN ('cancelled','delivered')`,
    [Number(orderGroupId)]
  );
  // 9-11. Assign the new courier (creates assignment + child mirror + outbox).
  const result = await assignDeliveryJobTx(client, {
    orderGroupId: Number(orderGroupId),
    courierUserId: Number(newCourierUserId),
  });
  return {
    deliveryJobId: Number(job.id),
    assignmentId: result.assignmentId,
    courierUserId: Number(newCourierUserId),
  };
});

export async function getCourierCurrentGroupedJob(courierUserId) {
  const client = await pool.connect();
  try {
    const jobs = await listCourierGroupedJobs(client, Number(courierUserId));
    // listCourierGroupedJobs already excludes terminal lifecycle states.
    return jobs[0] || null;
  } finally {
    client.release();
  }
}

/** Active (assigned, non-terminal) grouped jobs for the courier. */
export async function listCourierActiveGroupedJobs(courierUserId) {
  const client = await pool.connect();
  try {
    return await listCourierGroupedJobs(client, Number(courierUserId));
  } finally {
    client.release();
  }
}

/**
 * Grouped-job history for a courier (§1B). Built from courier_assignment, NOT
 * from delivery_job.delivery_user_id (which holds only the CURRENT courier after
 * a reassignment). Each courier sees the assignments they actually held —
 * including ones that were reassigned away — with the ended reason and the final
 * status known to that assignment.
 */
export async function listCourierGroupedJobHistory(courierUserId, { limit = 50 } = {}) {
  const client = await pool.connect();
  try {
    const rows = (
      await client.query(
        `SELECT ca.id AS assignment_id, ca.delivery_job_id, ca.status AS assignment_status,
                ca.assigned_at, ca.ended_at, ca.ended_reason, ca.completed_at,
                j.lifecycle_status, j.order_group_id,
                (SELECT COUNT(*)::int FROM delivery_pickup_stop s WHERE s.delivery_job_id=j.id) AS store_count,
                g.public_id
           FROM courier_assignment ca
           JOIN delivery_job j ON j.id=ca.delivery_job_id
           JOIN order_group g ON g.id=j.order_group_id
          WHERE ca.courier_user_id=$1
            AND ca.delivery_job_id IS NOT NULL
            AND (ca.ended_at IS NOT NULL OR j.lifecycle_status = ANY($2::text[]))
          ORDER BY COALESCE(ca.ended_at, ca.completed_at, ca.assigned_at) DESC
          LIMIT $3`,
        [Number(courierUserId), TERMINAL_LIFECYCLE, Math.max(1, Math.min(100, Number(limit) || 50))]
      )
    ).rows;
    return rows.map((r) => ({
      assignmentId: Number(r.assignment_id),
      deliveryJobId: Number(r.delivery_job_id),
      orderGroupId: Number(r.order_group_id),
      assignmentStatus: r.assignment_status,
      lifecycleStatus: r.lifecycle_status,
      storeCount: Number(r.store_count || 0),
      assignedAt: r.assigned_at,
      endedAt: r.ended_at,
      endedReason: r.ended_reason,
      completedAt: r.completed_at,
    }));
  } finally {
    client.release();
  }
}

/** Full grouped-job detail for the owning courier (ownership validated). */
export async function getCourierGroupedJobDetails(courierUserId, deliveryJobId) {
  const client = await pool.connect();
  try {
    const job = (
      await client.query(
        `SELECT j.*, g.public_id, g.is_multi_store, g.stores_count, g.payment_method,
                g.total_amount, ca.id AS assignment_id
           FROM delivery_job j
           JOIN order_group g ON g.id=j.order_group_id
           LEFT JOIN courier_assignment ca ON ca.delivery_job_id=j.id AND ca.ended_at IS NULL
          WHERE j.id=$1`,
        [Number(deliveryJobId)]
      )
    ).rows[0];
    if (!job) throw new AppError("DELIVERY_JOB_NOT_FOUND", { status: 404 });
    if (Number(job.delivery_user_id) !== Number(courierUserId)) {
      throw new AppError("NOT_JOB_OWNER", { status: 403 });
    }
    const stops = (
      await client.query(
        `SELECT s.id, s.child_order_id, s.store_id, s.sequence_number, s.pickup_status,
                s.preparation_status, s.arrived_at, s.collected_at,
                m.name AS store_name, m.image_url AS store_photo, m.phone AS store_phone,
                m.latitude AS store_lat, m.longitude AS store_lng
           FROM delivery_pickup_stop s
           LEFT JOIN merchant m ON m.id=s.store_id
          WHERE s.delivery_job_id=$1 AND s.pickup_status<>'CANCELLED'
          ORDER BY s.sequence_number`,
        [Number(deliveryJobId)]
      )
    ).rows;

    // §1: ONE authoritative customer destination for the whole grouped job —
    // taken from the order_group's customer, not an arbitrary child order.
    // All child orders of a group share the same customer + drop-off address.
    const dest = (
      await client.query(
        `SELECT u.id AS customer_user_id, u.full_name AS customer_name, u.phone AS customer_phone,
                co.customer_full_name, co.customer_phone AS order_phone,
                co.customer_block, co.customer_building_number, co.customer_apartment,
                co.customer_city, co.note,
                g.total_amount, g.delivery_fee_total, g.raw_delivery_fee_total, g.notes AS group_notes
           FROM order_group g
           JOIN app_user u ON u.id=g.customer_user_id
           LEFT JOIN LATERAL (
             SELECT * FROM customer_order c
              WHERE c.order_group_id=g.id AND c.status NOT IN ('cancelled')
              ORDER BY c.id LIMIT 1
           ) co ON TRUE
          WHERE g.id=$1`,
        [Number(job.order_group_id)]
      )
    ).rows[0] || {};

    const payment = String(job.payment_method || "").toLowerCase();
    const isCash = payment.includes("cash");
    const totalAmount = Number(dest.total_amount || 0);
    const displayName = String(dest.customer_full_name || dest.customer_name || "").trim();
    const addressParts = [
      dest.customer_city,
      dest.customer_block ? `بلوك ${dest.customer_block}` : null,
      dest.customer_building_number ? `بناية ${dest.customer_building_number}` : null,
      dest.customer_apartment ? `شقة ${dest.customer_apartment}` : null,
    ].filter(Boolean);

    return {
      deliveryJobId: Number(job.id),
      assignmentId: job.assignment_id ? Number(job.assignment_id) : null,
      orderGroupId: Number(job.order_group_id),
      orderGroupPublicId: job.public_id || null,
      lifecycleStatus: job.lifecycle_status,
      assignmentStatus: job.assignment_status,
      numberOfStores: stops.length,
      paymentMethod: job.payment_method,
      totalAmount,
      amountToCollect: isCash ? totalAmount : 0,
      deliveryFee: Number(dest.delivery_fee_total || 0),
      allocatedDeliveryFee: Number(dest.delivery_fee_total || 0),
      rawDeliveryFee: Number(dest.raw_delivery_fee_total || dest.delivery_fee_total || 0),
      courierEarning: Number(job.courier_earning || 0),
      assignedAt: job.assigned_at || null,
      acceptedAt: job.accepted_at || null,
      completedAt: job.completed_at || null,
      cancelledAt: job.cancelled_at || null,
      version: Number(job.version),
      customer: {
        // The assigned courier is authorized to see the drop-off contact.
        userId: dest.customer_user_id ? Number(dest.customer_user_id) : null,
        displayName: displayName || null,
        phone: (dest.order_phone || dest.customer_phone || null),
        address: addressParts.join("، ") || null,
        block: dest.customer_block || null,
        building: dest.customer_building_number || null,
        apartment: dest.customer_apartment || null,
        city: dest.customer_city || null,
        latitude: job.dropoff_latitude == null ? null : Number(job.dropoff_latitude),
        longitude: job.dropoff_longitude == null ? null : Number(job.dropoff_longitude),
        deliveryNotes: (dest.group_notes || dest.note || null),
      },
      pickupStops: stops.map((s) => ({
        stopId: Number(s.id),
        childOrderId: Number(s.child_order_id),
        storeId: Number(s.store_id),
        storeName: s.store_name,
        storePhoto: s.store_photo,
        storePhone: s.store_phone,
        latitude: s.store_lat == null ? null : Number(s.store_lat),
        longitude: s.store_lng == null ? null : Number(s.store_lng),
        sequence: Number(s.sequence_number),
        preparationStatus: s.preparation_status,
        pickupStatus: s.pickup_status,
        arrivedAt: s.arrived_at,
        collectedAt: s.collected_at,
      })),
    };
  } finally {
    client.release();
  }
}
