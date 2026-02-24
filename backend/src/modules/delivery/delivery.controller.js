import * as service from "./delivery.service.js";
import {
  validateDeliveryRegister,
  validateStartDelivery,
} from "./delivery.validators.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";

export async function register(req, res, next) {
  try {
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
    };

    const v = validateDeliveryRegister(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.registerDelivery(body);
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function currentOrders(req, res, next) {
  try {
    const data = await service.currentOrders(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function history(req, res, next) {
  try {
    const data = await service.history(req.userId, req.query.date);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function claimOrder(req, res, next) {
  try {
    await service.claimOrder(req.userId, req.params.orderId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function startOrder(req, res, next) {
  try {
    const v = validateStartDelivery(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    await service.startOrder(
      req.userId,
      req.params.orderId,
      req.body.estimatedDeliveryMinutes
    );
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function markDelivered(req, res, next) {
  try {
    await service.markDelivered(req.userId, req.params.orderId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function endDay(req, res, next) {
  try {
    const summary = await service.endDay(req.userId, req.body?.date);
    res.json(summary);
  } catch (e) {
    next(e);
  }
}

export async function analytics(req, res, next) {
  try {
    const out = await service.analytics(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}
