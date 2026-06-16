import { pool, q } from "../../config/db.js";

const PLAN_COPY = {
  car_seller_monthly: {
    title: "بائع سيارات شهري",
    description:
      "يمنحك نشر وإدارة إعلانات السيارات لمدة 30 يومًا داخل سوق السيارات، مع مساحة لإدارة سياراتك من حسابك.",
    badgeLabel: "بائع سيارات",
  },
  property_seller_monthly: {
    title: "دلال / مؤجر عقارات شهري",
    description:
      "يمنحك نشر وإدارة إعلانات الشقق والعقارات لمدة 30 يومًا داخل عقارات بسماية، مع مساحة لإدارة عقاراتك من حسابك.",
    badgeLabel: "دلال عقارات",
  },
  premium_monthly: {
    title: "بريميوم شهري",
    description:
      "يشمل شارة مستخدم موثق ظاهرة للجميع داخل السوشل، وميزات الحساب المميز، وصلاحية بائع السيارات، وصلاحية دلال أو مؤجر العقارات معًا لمدة 30 يومًا.",
    badgeLabel: "بريميوم",
  },
};

const DEFAULT_PAID_UPGRADE_PLANS = [
  {
    code: "car_seller_monthly",
    monthlyFeeIqd: 75000,
    currency: "IQD",
    sortOrder: 10,
  },
  {
    code: "property_seller_monthly",
    monthlyFeeIqd: 150000,
    currency: "IQD",
    sortOrder: 20,
  },
  {
    code: "premium_monthly",
    monthlyFeeIqd: 200000,
    currency: "IQD",
    sortOrder: 30,
  },
];

function txRunner(client) {
  if (client?.query) {
    return (sql, params = []) => client.query(sql, params);
  }
  return (sql, params = []) => q(sql, params);
}

function asInt(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return Math.floor(parsed);
}

function planPresentation(planCode, fallback = {}) {
  const key = String(planCode || "").trim().toLowerCase();
  const copy = PLAN_COPY[key] || {};
  return {
    title: copy.title || fallback.title || null,
    description: copy.description || fallback.description || null,
    badgeLabel: copy.badgeLabel || fallback.badgeLabel || null,
  };
}

export async function ensureDefaultPlans() {
  for (const seed of DEFAULT_PAID_UPGRADE_PLANS) {
    const copy = planPresentation(seed.code, {});
    await q(
      `INSERT INTO paid_upgrade_plan
        (
          code,
          title,
          description,
          monthly_fee_iqd,
          currency,
          badge_label,
          is_active,
          sort_order
        )
       VALUES ($1,$2,$3,$4,$5,$6,TRUE,$7)
       ON CONFLICT (code)
       DO UPDATE SET
         title = EXCLUDED.title,
         description = EXCLUDED.description,
         monthly_fee_iqd = EXCLUDED.monthly_fee_iqd,
         currency = EXCLUDED.currency,
         badge_label = EXCLUDED.badge_label,
         is_active = TRUE,
         sort_order = EXCLUDED.sort_order,
         updated_at = NOW()`,
      [
        seed.code,
        copy.title || seed.code,
        copy.description || null,
        Number(seed.monthlyFeeIqd || 0),
        String(seed.currency || "IQD"),
        copy.badgeLabel || null,
        Number(seed.sortOrder || 0),
      ]
    );
  }
}

function toPlan(row) {
  if (!row) return null;
  const copy = planPresentation(row.code, {
    title: row.title,
    description: row.description,
    badgeLabel: row.badge_label,
  });
  return {
    id: Number(row.id),
    code: String(row.code || ""),
    title: String(copy.title || ""),
    description: copy.description,
    monthlyFeeIqd: Number(row.monthly_fee_iqd || 0),
    currency: String(row.currency || "IQD"),
    badgeLabel: copy.badgeLabel,
    isActive: row.is_active === true,
    sortOrder: Number(row.sort_order || 0),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function toRequest(row) {
  if (!row) return null;
  const copy = planPresentation(row.plan_code, {
    title: row.plan_title,
  });
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    planId: Number(row.plan_id),
    planCode: row.plan_code || null,
    planTitle: copy.title,
    status: String(row.status || ""),
    activityName: row.activity_name || null,
    activityDescription: row.activity_description || null,
    contactPhone: row.contact_phone || null,
    notes: row.notes || null,
    requestMeta: row.request_meta_json || {},
    monthlyFeeIqd: Number(row.monthly_fee_iqd || 0),
    currency: String(row.currency || "IQD"),
    userFullName: row.user_full_name || null,
    userPhone: row.user_phone || null,
    reviewNote: row.review_note || null,
    reviewedByUserId: row.reviewed_by_user_id == null ? null : Number(row.reviewed_by_user_id),
    reviewedAt: row.reviewed_at || null,
    activatedByUserId: row.activated_by_user_id == null ? null : Number(row.activated_by_user_id),
    activatedAt: row.activated_at || null,
    cancelledAt: row.cancelled_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function toSubscription(row) {
  if (!row) return null;
  const copy = planPresentation(row.plan_code, {
    title: row.plan_title,
  });
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    planId: Number(row.plan_id),
    planCode: row.plan_code || null,
    planTitle: copy.title,
    requestId: row.request_id == null ? null : Number(row.request_id),
    status: String(row.status || ""),
    startedAt: row.started_at || null,
    expiresAt: row.expires_at || null,
    activatedByUserId:
      row.activated_by_user_id == null ? null : Number(row.activated_by_user_id),
    expiredAt: row.expired_at || null,
    lastExpiryReminderAt: row.last_expiry_reminder_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

export async function listPlans({ includeInactive = false } = {}) {
  const r = await q(
    `SELECT *
     FROM paid_upgrade_plan
     ${includeInactive ? "" : "WHERE is_active = TRUE"}
     ORDER BY sort_order ASC, id ASC`
  );
  return r.rows.map(toPlan);
}

export async function getPlanByCode(code) {
  const r = await q(
    `SELECT *
     FROM paid_upgrade_plan
     WHERE code = $1
     LIMIT 1`,
    [String(code || "").trim()]
  );
  return toPlan(r.rows[0]);
}

export async function getPlanById(planId) {
  const id = asInt(planId);
  if (!id) return null;
  const r = await q(`SELECT * FROM paid_upgrade_plan WHERE id = $1 LIMIT 1`, [id]);
  return toPlan(r.rows[0]);
}

export async function listBackofficeUserIds(limit = 300) {
  const safeLimit = Math.max(1, Math.min(500, Number(limit) || 300));
  const r = await q(
    `SELECT id
     FROM app_user
     WHERE role IN ('admin', 'deputy_admin')
     ORDER BY id ASC
     LIMIT $1`,
    [safeLimit]
  );
  return r.rows.map((row) => Number(row.id));
}

export async function listMyRequests(userId, { status = "all", limit = 30, offset = 0 } = {}) {
  const params = [Number(userId)];
  const clauses = [`r.user_id = $1`];
  if (status && status !== "all") {
    params.push(status);
    clauses.push(`r.status = $${params.length}`);
  }
  params.push(Math.max(1, Math.min(100, Number(limit) || 30)));
  params.push(Math.max(0, Number(offset) || 0));
  const r = await q(
    `SELECT r.*, p.code AS plan_code, p.title AS plan_title
     FROM paid_upgrade_request r
     JOIN paid_upgrade_plan p ON p.id = r.plan_id
     WHERE ${clauses.join(" AND ")}
     ORDER BY r.created_at DESC, r.id DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  return r.rows.map(toRequest);
}

export async function listMySubscriptions(userId) {
  const r = await q(
    `SELECT s.*, p.code AS plan_code, p.title AS plan_title
     FROM paid_upgrade_subscription s
     JOIN paid_upgrade_plan p ON p.id = s.plan_id
     WHERE s.user_id = $1
     ORDER BY s.status ASC, s.expires_at DESC, s.id DESC`,
    [Number(userId)]
  );
  return r.rows.map(toSubscription);
}

export async function getMySummary(userId) {
  const [plans, requests, subscriptions] = await Promise.all([
    listPlans(),
    listMyRequests(userId, { status: "all", limit: 100, offset: 0 }),
    listMySubscriptions(userId),
  ]);

  const activeSubscriptions = subscriptions.filter((item) => item.status === "active");
  const activePlanCodes = [...new Set(activeSubscriptions.map((item) => item.planCode).filter(Boolean))];
  const premium = activeSubscriptions.find((item) => item.planCode === "premium_monthly") || null;
  const propertySeller =
    activeSubscriptions.find((item) => item.planCode === "property_seller_monthly") || null;
  const carSeller =
    activeSubscriptions.find((item) => item.planCode === "car_seller_monthly") || null;
  const premiumActive = !!premium;
  const propertySellerActive = premiumActive || !!propertySeller;
  const carSellerActive = premiumActive || !!carSeller;

  return {
    plans,
    requests,
    subscriptions,
    activeSubscriptions,
    activePlanCodes,
    premiumBadge: premium
      ? {
          active: true,
          title: premium.planTitle || "Premium",
          planCode: premium.planCode,
          expiresAt: premium.expiresAt,
        }
      : { active: false, title: null, planCode: null, expiresAt: null },
    entitlements: {
      carSellerMonthly: carSellerActive,
      propertySellerMonthly: propertySellerActive,
      premiumMonthly: premiumActive,
    },
  };
}

export async function listPendingRequests({
  status = "pending_admin_review",
  planCode = null,
  limit = 30,
  offset = 0,
} = {}) {
  const params = [];
  const clauses = [];
  if (status && status !== "all") {
    params.push(status);
    clauses.push(`r.status = $${params.length}`);
  }
  if (planCode) {
    params.push(planCode);
    clauses.push(`p.code = $${params.length}`);
  }
  params.push(Math.max(1, Math.min(100, Number(limit) || 30)));
  params.push(Math.max(0, Number(offset) || 0));
  const whereClause = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
  const r = await q(
    `SELECT
       r.*,
       p.code AS plan_code,
       p.title AS plan_title,
       u.full_name AS user_full_name,
       u.phone AS user_phone
     FROM paid_upgrade_request r
     JOIN paid_upgrade_plan p ON p.id = r.plan_id
     JOIN app_user u ON u.id = r.user_id
     ${whereClause}
     ORDER BY r.created_at DESC, r.id DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  return r.rows.map(toRequest);
}

export async function countPendingRequests() {
  const r = await q(
    `SELECT COUNT(*)::int AS total
     FROM paid_upgrade_request
     WHERE status = 'pending_admin_review'`
  );
  return Number(r.rows[0]?.total || 0);
}

export async function getRequestById(requestId) {
  const id = asInt(requestId);
  if (!id) return null;
  const r = await q(
    `SELECT r.*, p.code AS plan_code, p.title AS plan_title
     FROM paid_upgrade_request r
     JOIN paid_upgrade_plan p ON p.id = r.plan_id
     WHERE r.id = $1
     LIMIT 1`,
    [id]
  );
  return toRequest(r.rows[0]);
}

export async function getRequestForUser(requestId, userId) {
  const id = asInt(requestId);
  if (!id) return null;
  const r = await q(
    `SELECT r.*, p.code AS plan_code, p.title AS plan_title
     FROM paid_upgrade_request r
     JOIN paid_upgrade_plan p ON p.id = r.plan_id
     WHERE r.id = $1 AND r.user_id = $2
     LIMIT 1`,
    [id, Number(userId)]
  );
  return toRequest(r.rows[0]);
}

export async function hasPaidUpgrade(userId, planCode, { client = null } = {}) {
  const run = txRunner(client);
  const r = await run(
    `SELECT 1
     FROM paid_upgrade_subscription s
     JOIN paid_upgrade_plan p ON p.id = s.plan_id
     WHERE s.user_id = $1
       AND p.code = $2
       AND s.status = 'active'
       AND s.expires_at > NOW()
     LIMIT 1`,
    [Number(userId), String(planCode || "").trim()]
  );
  return r.rowCount > 0;
}

export async function listActiveSubscriptions(userId) {
  const r = await q(
    `SELECT s.*, p.code AS plan_code, p.title AS plan_title
     FROM paid_upgrade_subscription s
     JOIN paid_upgrade_plan p ON p.id = s.plan_id
     WHERE s.user_id = $1
       AND s.status = 'active'
       AND s.expires_at > NOW()
     ORDER BY s.expires_at DESC, s.id DESC`,
    [Number(userId)]
  );
  return r.rows.map(toSubscription);
}

export async function createRequestsTx(client, userId, planRows, dto) {
  const run = txRunner(client);
  const created = [];
  for (const plan of planRows) {
    const duplicate = await run(
      `SELECT 1
       FROM paid_upgrade_request
       WHERE user_id = $1
         AND plan_id = $2
         AND status = 'pending_admin_review'
       LIMIT 1`,
      [Number(userId), Number(plan.id)]
    );
    if (duplicate.rowCount > 0) {
      const error = new Error("PAID_UPGRADE_REQUEST_ALREADY_PENDING");
      error.status = 409;
      error.code = "PAID_UPGRADE_REQUEST_ALREADY_PENDING";
      throw error;
    }

    const insert = await run(
      `INSERT INTO paid_upgrade_request (
         user_id,
         plan_id,
         status,
         activity_name,
         activity_description,
         contact_phone,
         notes,
         request_meta_json,
         monthly_fee_iqd,
         currency
       )
       VALUES ($1,$2,'pending_admin_review',$3,$4,$5,$6,$7::jsonb,$8,$9)
       RETURNING *`,
      [
        Number(userId),
        Number(plan.id),
        dto.activityName || null,
        dto.activityDescription || null,
        dto.contactPhone || null,
        dto.notes || null,
        JSON.stringify({
          ...(dto.requestMeta || {}),
          planCode: plan.code,
          planTitle: plan.title,
        }),
        Number(plan.monthlyFeeIqd || 0),
        plan.currency || "IQD",
      ]
    );
    created.push(toRequest({
      ...insert.rows[0],
      plan_code: plan.code,
      plan_title: plan.title,
    }));
  }
  return created;
}

export async function cancelRequest(userId, requestId) {
  const id = asInt(requestId);
  if (!id) return null;
  const r = await q(
    `UPDATE paid_upgrade_request
     SET status = 'cancelled',
         cancelled_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
       AND user_id = $2
       AND status = 'pending_admin_review'
     RETURNING *`,
    [id, Number(userId)]
  );
  return toRequest(r.rows[0]);
}

export async function adminReviewRequest(requestId, { status, reviewNote, actorUserId }) {
  const id = asInt(requestId);
  if (!id) return null;
  const r = await q(
    `UPDATE paid_upgrade_request
     SET status = $2,
         review_note = $3,
         reviewed_by_user_id = $4,
         reviewed_at = NOW(),
         updated_at = NOW()
     WHERE id = $1
       AND status = 'pending_admin_review'
     RETURNING *`,
    [id, status, reviewNote || null, Number(actorUserId)]
  );
  return toRequest(r.rows[0]);
}

export async function adminActivateRequest(
  requestId,
  { actorUserId, reviewNote = null, autoApprove = false }
) {
  const id = asInt(requestId);
  if (!id) return null;

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const current = await client.query(
      `SELECT r.*, p.code AS plan_code, p.title AS plan_title
       FROM paid_upgrade_request r
       JOIN paid_upgrade_plan p ON p.id = r.plan_id
       WHERE r.id = $1
       FOR UPDATE`,
      [id]
    );
    let request = current.rows[0] || null;
    if (!request) {
      await client.query("ROLLBACK");
      return null;
    }
    if (request.status === "activated") {
      const existing = await client.query(
        `SELECT s.*, p.code AS plan_code, p.title AS plan_title
         FROM paid_upgrade_subscription s
         JOIN paid_upgrade_plan p ON p.id = s.plan_id
         WHERE s.request_id = $1
         LIMIT 1`,
        [Number(request.id)]
      );
      await client.query("COMMIT");
      const subscription = existing.rows[0] || null;
      return {
        request: toRequest({
          ...request,
          plan_code: request.plan_code,
          plan_title: request.plan_title,
        }),
        subscription: subscription ? toSubscription(subscription) : null,
      };
    }
    if (request.status === "pending_admin_review" && autoApprove) {
      const approved = await client.query(
        `UPDATE paid_upgrade_request
         SET status = 'approved',
             review_note = $2,
             reviewed_by_user_id = $3,
             reviewed_at = NOW(),
             updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [Number(request.id), reviewNote || null, Number(actorUserId)]
      );
      request = {
        ...approved.rows[0],
        plan_code: request.plan_code,
        plan_title: request.plan_title,
      };
    }
    if (request.status !== "approved") {
      const error = new Error("PAID_UPGRADE_REQUEST_NOT_APPROVED");
      error.status = 409;
      error.code = "PAID_UPGRADE_REQUEST_NOT_APPROVED";
      throw error;
    }

    const now = new Date();
    await client.query(
      `UPDATE paid_upgrade_subscription
       SET status = 'expired',
           expired_at = COALESCE(expired_at, $3),
           updated_at = NOW()
       WHERE user_id = $1
         AND plan_id = $2
         AND status = 'active'
         AND expires_at > $3`,
      [Number(request.user_id), Number(request.plan_id), now.toISOString()]
    );

    const expiry = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
    const insert = await client.query(
      `INSERT INTO paid_upgrade_subscription (
         user_id,
         plan_id,
         request_id,
         status,
         started_at,
         expires_at,
         activated_by_user_id
       )
       VALUES ($1,$2,$3,'active',$4,$5,$6)
       RETURNING *`,
      [
        Number(request.user_id),
        Number(request.plan_id),
        Number(request.id),
        now.toISOString(),
        expiry.toISOString(),
        Number(actorUserId),
      ]
    );

    const subscription = insert.rows[0] || null;

    const requestUpdate = await client.query(
      `UPDATE paid_upgrade_request
       SET status = 'activated',
           activated_by_user_id = $2,
           activated_at = NOW(),
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [Number(request.id), Number(actorUserId)]
    );

    await client.query(
      `INSERT INTO paid_upgrade_audit (
         request_id,
         subscription_id,
         actor_user_id,
         action_key,
         note,
         payload_json
       )
       VALUES ($1,$2,$3,$4,$5,$6::jsonb)`,
      [
        Number(request.id),
        Number(subscription.id),
        Number(actorUserId),
        "activated",
        null,
        JSON.stringify({ planCode: request.plan_code, expiresAt: expiry.toISOString() }),
      ]
    );

    await client.query("COMMIT");
    return {
      request: toRequest({
        ...requestUpdate.rows[0],
        plan_code: request.plan_code,
        plan_title: request.plan_title,
      }),
      subscription: toSubscription({
        ...subscription,
        plan_code: request.plan_code,
        plan_title: request.plan_title,
      }),
    };
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function expireDueSubscriptions() {
  const r = await q(
    `UPDATE paid_upgrade_subscription
     SET status = 'expired',
         expired_at = COALESCE(expired_at, NOW()),
         updated_at = NOW()
     WHERE status = 'active'
       AND expires_at <= NOW()
     RETURNING *`
  );
  return r.rows.map(toSubscription);
}
