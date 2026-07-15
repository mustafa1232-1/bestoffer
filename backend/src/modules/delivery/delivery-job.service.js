import { AppError } from "../../shared/utils/errors.js";

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

// "Accepted and progressing" child states — a group is READY_FOR_ASSIGNMENT only
// when every active child order has reached at least store acceptance.
const ACCEPTED_CHILD_STATUSES = new Set([
  "accepted_by_store",
  "preparing",
  "ready_for_delivery",
  "courier_requested",
  "courier_assigned",
  "picked_up",
  "on_the_way",
  "arrived",
]);

export const DEFAULT_PRESENCE_FRESHNESS_SEC = 90;

function isCancelled(status) {
  return CANCELLED_CHILD_STATUSES.has(String(status || "").trim().toLowerCase());
}
function isAccepted(status) {
  return ACCEPTED_CHILD_STATUSES.has(String(status || "").trim().toLowerCase());
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
    active.length > 0 && active.every((c) => isAccepted(c.status));
  const next = ready ? "READY_FOR_ASSIGNMENT" : "PENDING_STORES";
  await client.query(
    `UPDATE delivery_job
        SET assignment_status = CASE
              WHEN assignment_status IN ('ASSIGNED','REASSIGNING','CANCELLED','FAILED')
              THEN assignment_status ELSE $2 END,
            lifecycle_status = CASE
              WHEN lifecycle_status IN ('ASSIGNED','CANCELLED') THEN lifecycle_status ELSE $2 END,
            updated_at = NOW()
      WHERE order_group_id=$1`,
    [orderGroupId, next]
  );
  return next;
}

/**
 * Select one eligible app courier, returning explicit (safe, internal) exclusion
 * reasons. No PII in the reasons.
 */
export async function selectEligibleCourier(
  client,
  { presenceFreshnessSec = DEFAULT_PRESENCE_FRESHNESS_SEC } = {}
) {
  const rows = (
    await client.query(
      `SELECT p.courier_user_id,
              cp.is_app_courier, cp.active_status, cp.availability_status,
              p.is_online,
              EXTRACT(EPOCH FROM (NOW()-p.recorded_at)) AS presence_age
         FROM courier_presence p
         JOIN courier_profile cp ON cp.user_id=p.courier_user_id
        ORDER BY p.recorded_at DESC`
    )
  ).rows;

  const excluded = [];
  let chosen = null;
  for (const r of rows) {
    const uid = Number(r.courier_user_id);
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
    const busy =
      (
        await client.query(
          `SELECT 1 FROM delivery_job
            WHERE delivery_user_id=$1 AND assignment_status='ASSIGNED' LIMIT 1`,
          [uid]
        )
      ).rows.length > 0;
    if (busy) {
      excluded.push({ courierUserId: uid, reason: "already_assigned" });
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

  // Notification-outbox event in the SAME transaction (§9/§10). Idempotent.
  await client.query(
    `INSERT INTO notification_outbox
       (event_id, event_type, recipient_user_id, target_surface,
        target_entity_type, target_entity_id, payload_json, priority)
     VALUES ($1,$2,$3,'courier','delivery_job',$4,$5,'high')
     ON CONFLICT (event_id) DO NOTHING`,
    [
      `deliveryjob-assign-${job.id}`,
      stops.length > 1
        ? "COURIER_MULTI_STORE_DELIVERY_ASSIGNED"
        : "COURIER_DELIVERY_ASSIGNED",
      courierUserId,
      job.id,
      JSON.stringify({
        deliveryJobId: job.id,
        orderGroupId,
        stores: stops.length,
        route: `/delivery/job/${job.id}`,
      }),
    ]
  );

  return { job: updated, stops, alreadyAssigned: false };
}

/**
 * The authoritative courier grouped-job query. Joins through delivery_job (NOT a
 * single child order), returning one grouped job with all active pickup stops.
 */
export async function listCourierGroupedJobs(client, courierUserId) {
  const jobs = (
    await client.query(
      `SELECT j.id AS delivery_job_id, j.order_group_id, j.assignment_status,
              j.lifecycle_status, j.delivery_user_id, j.assigned_at,
              g.public_id, g.is_multi_store, g.stores_count, g.payment_method
         FROM delivery_job j
         JOIN order_group g ON g.id=j.order_group_id
        WHERE j.delivery_user_id=$1 AND j.assignment_status='ASSIGNED'
        ORDER BY j.assigned_at DESC`,
      [courierUserId]
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
      `SELECT j.id AS delivery_job_id, j.assignment_status, j.delivery_user_id,
              j.assigned_at, u.full_name AS courier_name, u.phone AS courier_phone
         FROM delivery_job j
         LEFT JOIN app_user u ON u.id=j.delivery_user_id
        WHERE j.order_group_id=$1`,
      [orderGroupId]
    )
  ).rows[0];
  if (!row) return { active: false, status: "PENDING_STORES" };
  const active =
    row.assignment_status === "ASSIGNED" &&
    Number(row.delivery_user_id) > 0 &&
    Boolean(row.courier_name);
  return {
    active,
    status: row.assignment_status,
    deliveryJobId: Number(row.delivery_job_id),
    courierUserId: active ? Number(row.delivery_user_id) : null,
    courierName: active ? row.courier_name : null,
    assignedAt: active ? row.assigned_at : null,
  };
}
