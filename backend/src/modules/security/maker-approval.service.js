import { pool, q } from "../../config/db.js";
import { AppError } from "../../shared/utils/errors.js";
import { checkPermission } from "./permissions.service.js";
import { isValidPermissionKey } from "./permissions.catalog.js";

export const MAKER_APPROVAL_STATUS = Object.freeze({
  PENDING: "PENDING",
  APPROVED: "APPROVED",
  REJECTED: "REJECTED",
  CANCELLED: "CANCELLED",
  EXECUTED: "EXECUTED",
  EXPIRED: "EXPIRED",
});

function normalizeOperationKey(value) {
  const key = String(value || "").trim();
  if (!/^[a-z][a-z0-9_.:-]{2,96}$/.test(key)) {
    throw new AppError("INVALID_APPROVAL_OPERATION_KEY", { status: 400 });
  }
  return key;
}

function normalizePermissionKey(value) {
  const permissionKey = String(value || "").trim();
  if (!isValidPermissionKey(permissionKey)) {
    throw new AppError("INVALID_APPROVAL_PERMISSION", { status: 400 });
  }
  return permissionKey;
}

function normalizeReason(value) {
  const reason = String(value || "").trim();
  if (reason.length < 3) {
    throw new AppError("APPROVAL_REASON_REQUIRED", { status: 400 });
  }
  return reason;
}

export async function createMakerApprovalRequest({
  operationKey,
  entityType,
  entityId = null,
  payload,
  reason,
  makerUserId,
  approvalPermissionKey,
  expiresAt = null,
  idempotencyKey = null,
}) {
  const normalizedOperationKey = normalizeOperationKey(operationKey);
  const permissionKey = normalizePermissionKey(approvalPermissionKey);
  const normalizedReason = normalizeReason(reason);
  const makerId = Number(makerUserId);
  if (!makerId) throw new AppError("MAKER_USER_REQUIRED", { status: 400 });
  const r = await q(
    `INSERT INTO maker_approval_request
       (operation_key, entity_type, entity_id, payload_json, reason, maker_user_id,
        approval_permission_key, expires_at, idempotency_key)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
     ON CONFLICT (operation_key, idempotency_key)
     WHERE idempotency_key IS NOT NULL
     DO UPDATE SET updated_at = maker_approval_request.updated_at
     RETURNING *`,
    [
      normalizedOperationKey,
      String(entityType || "unknown").trim() || "unknown",
      entityId == null ? null : String(entityId),
      JSON.stringify(payload ?? {}),
      normalizedReason,
      makerId,
      permissionKey,
      expiresAt,
      idempotencyKey ? String(idempotencyKey) : null,
    ]
  );
  return r.rows[0];
}

export async function approveMakerApprovalRequest({
  requestId,
  approverUserId,
  decision,
  reason,
}) {
  const id = Number(requestId);
  const approverId = Number(approverUserId);
  if (!id || !approverId) {
    throw new AppError("APPROVAL_REQUEST_REQUIRED", { status: 400 });
  }
  const status =
    decision === MAKER_APPROVAL_STATUS.REJECTED
      ? MAKER_APPROVAL_STATUS.REJECTED
      : MAKER_APPROVAL_STATUS.APPROVED;
  const normalizedReason = normalizeReason(reason);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const existing = await client.query(
      `SELECT * FROM maker_approval_request WHERE id=$1 FOR UPDATE`,
      [id]
    );
    const row = existing.rows[0];
    if (!row) throw new AppError("APPROVAL_REQUEST_NOT_FOUND", { status: 404 });
    if (row.status !== MAKER_APPROVAL_STATUS.PENDING) {
      throw new AppError("APPROVAL_REQUEST_NOT_PENDING", { status: 409 });
    }
    if (Number(row.maker_user_id) === approverId) {
      throw new AppError("MAKER_APPROVER_MUST_DIFFER", { status: 403 });
    }
    const permission = await checkPermission(
      approverId,
      row.approval_permission_key,
      "all"
    );
    if (!permission.allowed) {
      throw new AppError("APPROVAL_PERMISSION_DENIED", { status: 403 });
    }
    const updated = await client.query(
      `UPDATE maker_approval_request
       SET status=$2,
           approver_user_id=$3,
           approver_reason=$4,
           decided_at = NOW(),
           updated_at=NOW()
       WHERE id=$1
       RETURNING *`,
      [id, status, approverId, normalizedReason]
    );
    await client.query("COMMIT");
    return updated.rows[0];
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function markMakerApprovalExecuted({ requestId, executorUserId }) {
  const id = Number(requestId);
  const executorId = Number(executorUserId);
  if (!id || !executorId) {
    throw new AppError("APPROVAL_EXECUTION_REQUIRED", { status: 400 });
  }
  const r = await q(
    `UPDATE maker_approval_request
     SET status='EXECUTED',
         executed_by_user_id=$2,
         executed_at=NOW(),
         updated_at=NOW()
     WHERE id=$1
       AND status='APPROVED'
     RETURNING *`,
    [id, executorId]
  );
  if (!r.rows[0]) {
    throw new AppError("APPROVAL_REQUEST_NOT_APPROVED", { status: 409 });
  }
  return r.rows[0];
}
