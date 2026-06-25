import * as service from "./delivery.service.js";
import { validateDeliveryRegister } from "./delivery.validators.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";

/**
 * Purpose:
 * controllers الدليفري. تطبع ملفات التسجيل وترسل الطلبات إلى service
 * بصيغة HTTP موحدة لشاشات المندوب.
 */

/**
 * ينفذ تسجيل حساب الدليفري مع صور اختيارية للملف والمركبة.
 */
export async function register(req, res, next) {
  try {
    const files = req.files || {};
    const profileImageFile = Array.isArray(files.profileImageFile)
      ? files.profileImageFile[0]
      : null;
    const carImageFile = Array.isArray(files.carImageFile)
      ? files.carImageFile[0]
      : null;

    const body = {
      ...req.body,
      profileImageUrl:
        buildUploadedFileUrl(req, profileImageFile) ||
        req.body?.profileImageUrl ||
        req.body?.imageUrl,
      carImageUrl: buildUploadedFileUrl(req, carImageFile) || req.body?.carImageUrl,
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

/**
 * يعيد الطلبات الحالية للمندوب الحالي.
 */
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
export async function orderDetail(req, res, next) {
  try {
    const data = await service.orderDetail({
      requestUserId: req.userId,
      requestUserRole: req.userRole,
      userIsSuperAdmin: req.userIsSuperAdmin === true,
      orderId: req.params.orderId,
    });
    res.json(data);
  } catch (e) {
    next(e);
  }
}

/**
 * يحاول claim لطلب توصيل جديد.
 */
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
    await service.startOrder(req.userId, req.params.orderId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

/**
 * يعلن وصول المندوب إلى موقع التسليم.
 */
export async function markArrived(req, res, next) {
  try {
    await service.markArrived(req.userId, req.params.orderId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

/**
 * ينهي الطلب من جهة المندوب.
 */
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

/**
 * يعيد analytics خاصة بالمندوب الحالي.
 */
export async function analytics(req, res, next) {
  try {
    const out = await service.analytics(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function earnings(req, res, next) {
  try {
    const out = await service.earningsReport(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function ratings(req, res, next) {
  try {
    const out = await service.ratingsReport(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}
