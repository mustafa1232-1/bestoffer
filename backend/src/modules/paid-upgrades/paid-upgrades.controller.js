import * as service from "./paid-upgrades.service.js";
import {
  validateCreatePaidUpgradeRequests,
  validateListMyRequestsQuery,
  validateListPaidUpgradeRequestsQuery,
  validatePaidUpgradeRequestId,
  validatePaidUpgradeReviewBody,
} from "./paid-upgrades.validators.js";

export async function listPlans(req, res, next) {
  try {
    const out = await service.listPlans();
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function me(req, res, next) {
  try {
    const out = await service.getMyPaidUpgradeEntitlements(req.userId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listMyRequests(req, res, next) {
  try {
    const v = validateListMyRequestsQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.listMyPaidUpgradeRequests(req.userId, v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function createRequests(req, res, next) {
  try {
    const v = validateCreatePaidUpgradeRequests(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.createPaidUpgradeRequests(req.userId, v.value);
    res.status(201).json({ requests: out });
  } catch (error) {
    next(error);
  }
}

export async function cancelRequest(req, res, next) {
  try {
    const requestId = validatePaidUpgradeRequestId(req.params.requestId);
    if (!requestId.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: requestId.errors });
    }
    const out = await service.cancelMyPaidUpgradeRequest(req.userId, requestId.value);
    res.json({ request: out });
  } catch (error) {
    next(error);
  }
}

export async function listPendingRequests(req, res, next) {
  try {
    const v = validateListPaidUpgradeRequestsQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.listPendingPaidUpgradeRequests(v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function approveRequest(req, res, next) {
  try {
    const requestId = validatePaidUpgradeRequestId(req.params.requestId);
    if (!requestId.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: requestId.errors });
    }
    const review = validatePaidUpgradeReviewBody(req.body || {});
    if (!review.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: review.errors });
    }
    const out = await service.approvePaidUpgradeRequest(requestId.value, {
      userId: req.userId,
      reviewNote: review.value.reviewNote,
    });
    res.json({ request: out });
  } catch (error) {
    next(error);
  }
}

export async function rejectRequest(req, res, next) {
  try {
    const requestId = validatePaidUpgradeRequestId(req.params.requestId);
    if (!requestId.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: requestId.errors });
    }
    const review = validatePaidUpgradeReviewBody(req.body || {});
    if (!review.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: review.errors });
    }
    const out = await service.rejectPaidUpgradeRequest(requestId.value, {
      userId: req.userId,
      reviewNote: review.value.reviewNote,
    });
    res.json({ request: out });
  } catch (error) {
    next(error);
  }
}

export async function activateRequest(req, res, next) {
  try {
    const requestId = validatePaidUpgradeRequestId(req.params.requestId);
    if (!requestId.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: requestId.errors });
    }
    const out = await service.activatePaidUpgradeRequest(requestId.value, {
      userId: req.userId,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

