import { q } from "../../config/db.js";
import { AppError } from "../../shared/utils/errors.js";

const DEFAULT_RECENT_AUTH_WINDOW_MS = 10 * 60 * 1000;

export async function markRecentAuthVerified({ userId }) {
  const id = Number(userId);
  if (!id) throw new AppError("RECENT_AUTH_USER_REQUIRED", { status: 400 });
  const r = await q(
    `UPDATE app_user
     SET recent_auth_verified_at = NOW(),
         updated_at = NOW()
     WHERE id=$1
     RETURNING id, recent_auth_verified_at`,
    [id]
  );
  if (!r.rows[0]) throw new AppError("USER_NOT_FOUND", { status: 404 });
  return r.rows[0];
}

export async function assertRecentAuthVerified({
  userId,
  windowMs = DEFAULT_RECENT_AUTH_WINDOW_MS,
}) {
  const id = Number(userId);
  if (!id) throw new AppError("RECENT_AUTH_USER_REQUIRED", { status: 400 });
  const r = await q(
    `SELECT recent_auth_verified_at
     FROM app_user
     WHERE id=$1
     LIMIT 1`,
    [id]
  );
  const value = r.rows[0]?.recent_auth_verified_at;
  if (!value) {
    throw new AppError("RECENT_AUTH_REQUIRED", { status: 403 });
  }
  const verifiedAt = new Date(value).getTime();
  if (!Number.isFinite(verifiedAt) || Date.now() - verifiedAt > Number(windowMs)) {
    throw new AppError("RECENT_AUTH_REQUIRED", { status: 403 });
  }
  return true;
}
