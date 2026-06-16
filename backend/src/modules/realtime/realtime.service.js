import { AppError } from "../../shared/utils/errors.js";
import {
  getSupabaseRealtimePublicConfig,
  getSupabaseRealtimeStatus,
  issueSupabaseRealtimeToken,
} from "../../config/supabase.js";

const DEFAULT_REALTIME_TOKEN_TTL_SEC = 15 * 60;

export async function issueRealtimeAccessToken({
  userId,
  userRole,
  expiresInSec = DEFAULT_REALTIME_TOKEN_TTL_SEC,
} = {}) {
  const status = getSupabaseRealtimeStatus();
  if (status.enabled !== true || status.effectiveMode === "sse_only") {
    throw new AppError("REALTIME_DISABLED", {
      status: 503,
      details: {
        requestedMode: status.requestedMode,
        effectiveMode: status.effectiveMode,
        reason: status.reason,
      },
    });
  }
  if (!status.configured) {
    throw new AppError("REALTIME_NOT_CONFIGURED", {
      status: 503,
      details: {
        missingKeys: status.missingKeys,
      },
    });
  }

  const token = issueSupabaseRealtimeToken({
    userId,
    appRole: userRole,
    expiresInSec,
  });
  const publicConfig = getSupabaseRealtimePublicConfig();
  return {
    ...publicConfig,
    realtimeToken: token.token,
    userId: Number(userId),
    expiresIn: token.expiresIn,
  };
}
