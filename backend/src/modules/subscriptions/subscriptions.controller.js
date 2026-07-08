import * as service from "./subscriptions.service.js";

function actorFromReq(req) {
  return {
    userId: Number(req.userId),
    role: String(req.userRole || "admin").trim().toLowerCase() || "admin",
  };
}

function parsePositiveAmount(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return null;
  return n;
}

function parseInvoiceId(req, res) {
  const invoiceId = Number(req.params?.invoiceId);
  if (!Number.isInteger(invoiceId) || invoiceId <= 0) {
    res.status(400).json({ message: "VALIDATION_ERROR", fields: ["invoiceId"] });
    return null;
  }
  return invoiceId;
}

export async function generate(req, res, next) {
  try {
    const actor = actorFromReq(req);
    const out = await service.generateInvoices({
      month: req.body?.month || req.query?.month || null,
      actorUserId: actor.userId,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listInvoices(req, res, next) {
  try {
    const out = await service.listInvoices({
      status: req.query?.status || null,
      billingMonth: req.query?.month || null,
      merchantId: req.query?.merchantId ? Number(req.query.merchantId) : null,
      limit: req.query?.limit ? Number(req.query.limit) : 200,
    });
    return res.json({ invoices: out });
  } catch (error) {
    return next(error);
  }
}

export async function invoiceDetail(req, res, next) {
  try {
    const invoiceId = parseInvoiceId(req, res);
    if (invoiceId == null) return undefined;
    const out = await service.getInvoiceDetail(invoiceId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function recordPayment(req, res, next) {
  try {
    const invoiceId = parseInvoiceId(req, res);
    if (invoiceId == null) return undefined;
    const amount = parsePositiveAmount(req.body?.amount);
    if (amount == null) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["amount"] });
    }
    const actor = actorFromReq(req);
    const out = await service.recordPayment({
      invoiceId,
      amount,
      paymentMethod:
        typeof req.body?.paymentMethod === "string" ? req.body.paymentMethod : "cash",
      notes: typeof req.body?.notes === "string" ? req.body.notes : null,
      actorUserId: actor.userId,
      actorRole: actor.role,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function waiveInvoice(req, res, next) {
  try {
    const invoiceId = parseInvoiceId(req, res);
    if (invoiceId == null) return undefined;
    const reason = typeof req.body?.reason === "string" ? req.body.reason.trim() : "";
    if (!reason) {
      return res
        .status(400)
        .json({ message: "VALIDATION_ERROR", fields: ["reason"] });
    }
    const actor = actorFromReq(req);
    const out = await service.waiveInvoice({
      invoiceId,
      reason,
      actorUserId: actor.userId,
      actorRole: actor.role,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}
