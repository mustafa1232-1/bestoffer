import * as service from "./behavior.service.js";

export async function track(req, res, next) {
  try {
    await service.trackCustomEvent(req.userId, req.userRole, req.body || {}, req);
    res.status(204).send();
  } catch (error) {
    next(error);
  }
}

export async function myEvents(req, res, next) {
  try {
    const out = await service.listMyActivityEvents(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function myInsights(req, res, next) {
  try {
    const out = await service.getCustomerFullInsight(Number(req.userId));
    res.json(out);
  } catch (error) {
    next(error);
  }
}
