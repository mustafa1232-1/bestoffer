import * as service from "./realtime.service.js";

export async function issueRealtimeToken(req, res, next) {
  try {
    res.setHeader("Cache-Control", "no-store, private");
    res.setHeader("Pragma", "no-cache");
    const out = await service.issueRealtimeAccessToken({
      userId: req.userId,
      userRole: req.userRole,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}
