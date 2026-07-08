import * as service from "./accountant.service.js";

function actorFromReq(req) {
  return {
    userId: req.userId,
    role: req.userRole,
  };
}

function parsePositiveAmount(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return null;
  return n;
}

function parseNonNegativeAmount(value) {
  if (value == null || `${value}`.trim() === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return null;
  return n;
}

function parseLimit(value, fallback = 100) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) return fallback;
  return Math.max(1, Math.min(300, n));
}

function badRequest(res, fields) {
  return res.status(400).json({
    message: "VALIDATION_ERROR",
    fields,
  });
}

export async function getSummary(req, res, next) {
  try {
    const out = await service.getSummary(actorFromReq(req));
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listPendingSettlements(req, res, next) {
  try {
    const out = await service.listPendingSettlements(actorFromReq(req), {
      limit: parseLimit(req.query?.limit, 100),
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listLedger(req, res, next) {
  try {
    const out = await service.listLedger(actorFromReq(req), {
      limit: parseLimit(req.query?.limit, 100),
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function addOpeningBalance(req, res, next) {
  try {
    const amount = parsePositiveAmount(req.body?.amount);
    if (amount == null) return badRequest(res, ["amount"]);

    const out = await service.addOpeningBalance(actorFromReq(req), {
      amount,
      note: req.body?.note,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function addExpense(req, res, next) {
  try {
    const amount = parsePositiveAmount(req.body?.amount);
    if (amount == null) return badRequest(res, ["amount"]);

    const out = await service.addExpense(actorFromReq(req), {
      amount,
      note: req.body?.note,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function confirmPendingSettlement(req, res, next) {
  try {
    const settlementId = Number(req.params?.settlementId);
    if (!Number.isInteger(settlementId) || settlementId <= 0) {
      return badRequest(res, ["settlementId"]);
    }

    const actualAmount = parseNonNegativeAmount(req.body?.actualAmount);
    if (req.body?.actualAmount != null && `${req.body?.actualAmount}`.trim() !== "" && actualAmount == null) {
      return badRequest(res, ["actualAmount"]);
    }

    const out = await service.confirmSettlement(actorFromReq(req), settlementId, {
      note: req.body?.note,
      actualAmount,
      differenceReason:
        typeof req.body?.differenceReason === "string"
          ? req.body.differenceReason
          : null,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listPendingPayrollBatches(req, res, next) {
  try {
    const out = await service.listPendingPayrollBatches(actorFromReq(req), {
      limit: parseLimit(req.query?.limit, 60),
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getPayrollBatch(req, res, next) {
  try {
    const batchId = Number(req.params?.batchId);
    if (!Number.isInteger(batchId) || batchId <= 0) {
      return badRequest(res, ["batchId"]);
    }
    const out = await service.getPayrollBatch(actorFromReq(req), batchId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function acknowledgePayrollBatch(req, res, next) {
  try {
    const batchId = Number(req.params?.batchId);
    if (!Number.isInteger(batchId) || batchId <= 0) {
      return badRequest(res, ["batchId"]);
    }
    const out = await service.acknowledgePayrollBatch(actorFromReq(req), batchId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function markPayrollItemPaid(req, res, next) {
  try {
    const itemId = Number(req.params?.itemId);
    if (!Number.isInteger(itemId) || itemId <= 0) {
      return badRequest(res, ["itemId"]);
    }
    const out = await service.markPayrollItemPaid(actorFromReq(req), itemId, {
      payoutNote: req.body?.payoutNote,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}
