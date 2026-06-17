import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { issueRequestSigningMaterial } from "./security.service.js";

export const securityRouter = Router();

securityRouter.post("/signing-material", requireAuth, async (req, res, next) => {
  try {
    res.setHeader("Cache-Control", "no-store, private");
    res.setHeader("Pragma", "no-cache");
    const payload = await issueRequestSigningMaterial({
      userId: req.userId,
      sessionId: req.authSessionId,
      deviceFingerprint: req.authDeviceContext?.deviceFingerprint || "",
    });
    res.json(payload);
  } catch (error) {
    next(error);
  }
});
