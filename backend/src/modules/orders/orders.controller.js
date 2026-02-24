import * as service from "./orders.service.js";
import {
  validateCreateOrder,
  validateRating,
  validateReorder,
} from "./orders.validators.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";

function normalizeCreateBody(req) {
  const body = { ...req.body };

  if (typeof body.items === "string") {
    try {
      body.items = JSON.parse(body.items);
    } catch (_) {
      body.items = [];
    }
  }

  body.imageUrl = buildUploadedFileUrl(req, req.file) || body.imageUrl;

  return body;
}

export async function create(req, res, next) {
  try {
    const body = normalizeCreateBody(req);
    const v = validateCreateOrder(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const order = await service.createOrder(req.userId, body);
    res.status(201).json(order);
  } catch (e) {
    next(e);
  }
}

export async function listMyOrders(req, res, next) {
  try {
    const data = await service.listMyOrders(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function confirmDelivered(req, res, next) {
  try {
    await service.confirmDelivered(req.userId, req.params.orderId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function rateDelivery(req, res, next) {
  try {
    const v = validateRating(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    await service.rateDelivery(
      req.userId,
      req.params.orderId,
      req.body.rating,
      req.body.review
    );

    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function rateMerchant(req, res, next) {
  try {
    const v = validateRating(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    await service.rateMerchant(
      req.userId,
      req.params.orderId,
      req.body.rating,
      req.body.review
    );

    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function listFavoriteProductIds(req, res, next) {
  try {
    const ids = await service.listFavoriteProductIds(req.userId);
    res.json({ productIds: ids });
  } catch (e) {
    next(e);
  }
}

export async function listFavoriteProducts(req, res, next) {
  try {
    const data = await service.listFavoriteProducts(req.userId, req.query.merchantId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function addFavoriteProduct(req, res, next) {
  try {
    await service.addFavoriteProduct(req.userId, req.params.productId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function removeFavoriteProduct(req, res, next) {
  try {
    await service.removeFavoriteProduct(req.userId, req.params.productId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function reorder(req, res, next) {
  try {
    const v = validateReorder(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const order = await service.reorderOrder(
      req.userId,
      req.params.orderId,
      req.body?.note
    );
    res.status(201).json(order);
  } catch (e) {
    next(e);
  }
}
