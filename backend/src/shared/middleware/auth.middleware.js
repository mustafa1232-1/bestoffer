// src/shared/middleware/auth.middleware.js
import { verifyToken } from "../utils/jwt.js";

export function requireAuth(req, res, next) {
  const h = req.headers.authorization || "";
  const token = h.startsWith("Bearer ") ? h.slice(7) : null;
  if (!token) return res.status(401).json({ message: "NO_TOKEN" });

  try {
    const payload = verifyToken(token);
    req.userId = payload.sub;
    next();
  } catch {
    return res.status(401).json({ message: "INVALID_TOKEN" });
  }
}