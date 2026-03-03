import jwt from "jsonwebtoken";
import { env } from "../../config/env.js";

export function signAccessToken(user, session = {}) {
  const payload = {
    sub: user.id,
    role: user.role,
    sa: user.isSuperAdmin === true,
  };
  if (session.sessionId != null) payload.sid = Number(session.sessionId);
  if (session.tokenJti) payload.jti = String(session.tokenJti);
  if (session.deviceFingerprint) {
    payload.dvh = String(session.deviceFingerprint);
  }

  return jwt.sign(
    payload,
    env.jwtSecret,
    {
      expiresIn: env.jwtAccessTtl,
      algorithm: "HS256",
      issuer: env.jwtIssuer || undefined,
      audience: env.jwtAudience || undefined,
    }
  );
}

export function verifyAccessToken(token) {
  const verifyOptions = {
    algorithms: ["HS256"],
    issuer: env.jwtIssuer || undefined,
    audience: env.jwtAudience || undefined,
  };

  try {
    return jwt.verify(token, env.jwtSecret, verifyOptions);
  } catch (error) {
    if (!env.jwtSecretPrevious) throw error;
    return jwt.verify(token, env.jwtSecretPrevious, verifyOptions);
  }
}
