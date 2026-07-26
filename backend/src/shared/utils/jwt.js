import jwt from "jsonwebtoken";
import { env } from "../../config/env.js";

function buildJwtClaimsOptions() {
  const options = {};

  if (typeof env.jwtIssuer === "string" && env.jwtIssuer.trim()) {
    options.issuer = env.jwtIssuer.trim();
  }
  if (typeof env.jwtAudience === "string" && env.jwtAudience.trim()) {
    options.audience = env.jwtAudience.trim();
  }

  return options;
}

export function signAccessToken(user, session = {}) {
  const payload = {
    sub: user.id,
    role: user.role,
    sa: user.isSuperAdmin === true,
    tc: user.isTaxiCaptain === true,
  };
  if (user.permissionVersion != null) {
    payload.pv = Number(user.permissionVersion) || 1;
  }
  if (user.appSurface) payload.appSurface = String(user.appSurface);
  if (session.sessionId != null) payload.sid = Number(session.sessionId);
  if (session.tokenJti) payload.jti = String(session.tokenJti);
  if (session.deviceFingerprint) {
    payload.dvh = String(session.deviceFingerprint);
  }

  const claimsOptions = buildJwtClaimsOptions();

  return jwt.sign(
    payload,
    env.jwtSecret,
    {
      expiresIn: env.jwtAccessTtl,
      algorithm: "HS256",
      ...claimsOptions,
    }
  );
}

export function verifyAccessToken(token) {
  const verifyOptions = {
    algorithms: ["HS256"],
    ...buildJwtClaimsOptions(),
  };

  try {
    return jwt.verify(token, env.jwtSecret, verifyOptions);
  } catch (error) {
    if (!env.jwtSecretPrevious) throw error;
    return jwt.verify(token, env.jwtSecretPrevious, verifyOptions);
  }
}
