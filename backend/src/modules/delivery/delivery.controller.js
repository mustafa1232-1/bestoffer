import * as service from "./delivery.service.js";
import * as jobs from "./delivery-job.service.js";
import { validateDeliveryRegister } from "./delivery.validators.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";
import { requestDeliveryAssignmentRecovery } from "../orders/delivery-assignment.worker.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";

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
    const customerReceivedActual = Number(req.body?.customerReceivedActual);
    if (!Number.isFinite(customerReceivedActual) || customerReceivedActual < 0) {
      return res.status(400).json({
        message: 'VALIDATION_ERROR',
        fields: ['customerReceivedActual'],
      });
    }
    await service.markDelivered(
      req.userId,
      req.params.orderId,
      customerReceivedActual,
    );
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

export async function endDayReadiness(req, res, next) {
  try {
    const summary = await service.endDayReadiness(req.userId);
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

// ---- Grouped multi-store delivery jobs (delivery closure §8) ----

function expectedVersion(req) {
  const v = req.body?.expectedVersion ?? req.query?.expectedVersion;
  return v == null || v === "" ? null : Number(v);
}

export async function currentGroupedJob(req, res, next) {
  try {
    const job = await jobs.getCourierCurrentGroupedJob(req.userId);
    res.json({ job });
  } catch (e) {
    next(e);
  }
}

export async function listGroupedJobs(req, res, next) {
  try {
    const list = await jobs.listCourierActiveGroupedJobs(req.userId);
    res.json({ jobs: list });
  } catch (e) {
    next(e);
  }
}

export async function groupedJobHistory(req, res, next) {
  try {
    const list = await jobs.listCourierGroupedJobHistory(req.userId, {
      limit: Number(req.query?.limit) || 50,
    });
    res.json({ jobs: list });
  } catch (e) {
    next(e);
  }
}

export async function groupedJobDetails(req, res, next) {
  try {
    const job = await jobs.getCourierGroupedJobDetails(
      req.userId,
      req.params.deliveryJobId
    );
    res.json(job);
  } catch (e) {
    next(e);
  }
}

export async function acknowledgeGroupedJob(req, res, next) {
  try {
    const out = await jobs.acknowledgeGroupedJob({
      courierUserId: req.userId,
      deliveryJobId: req.params.deliveryJobId,
      expectedVersion: expectedVersion(req),
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function groupedHeadingToPickups(req, res, next) {
  try {
    const out = await jobs.headingToPickups({
      courierUserId: req.userId,
      deliveryJobId: req.params.deliveryJobId,
      expectedVersion: expectedVersion(req),
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function groupedStopArrived(req, res, next) {
  try {
    const out = await jobs.markStopArrived({
      courierUserId: req.userId,
      deliveryJobId: req.params.deliveryJobId,
      stopId: req.params.stopId,
      expectedVersion: expectedVersion(req),
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function groupedStopCollected(req, res, next) {
  try {
    const merchantPaidActual = Number(req.body?.merchantPaidActual);
    const withoutReceipt =
      req.body?.withoutReceipt === true ||
      String(req.body?.withoutReceipt || '').toLowerCase() === 'true';
    const receiptUrl = buildUploadedFileUrl(req, req.file);
    if (!Number.isFinite(merchantPaidActual) || merchantPaidActual < 0) {
      return res.status(400).json({
        message: 'VALIDATION_ERROR',
        fields: ['merchantPaidActual'],
      });
    }
    if (!receiptUrl && !withoutReceipt) {
      return res.status(400).json({
        message: 'VALIDATION_ERROR',
        fields: ['receiptFile'],
      });
    }
    const out = await jobs.markStopCollected({
      courierUserId: req.userId,
      deliveryJobId: req.params.deliveryJobId,
      stopId: req.params.stopId,
      expectedVersion: expectedVersion(req),
      merchantPaidActual,
      receiptUrl,
      withoutReceipt,
      merchantPaymentNote: req.body?.merchantPaymentNote || null,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function groupedHeadingToCustomer(req, res, next) {
  try {
    const out = await jobs.headingToCustomer({
      courierUserId: req.userId,
      deliveryJobId: req.params.deliveryJobId,
      expectedVersion: expectedVersion(req),
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function groupedDelivered(req, res, next) {
  try {
    const customerReceivedActual = Number(req.body?.customerReceivedActual);
    if (!Number.isFinite(customerReceivedActual) || customerReceivedActual < 0) {
      return res.status(400).json({
        message: 'VALIDATION_ERROR',
        fields: ['customerReceivedActual'],
      });
    }
    const out = await jobs.markGroupedDelivered({
      courierUserId: req.userId,
      deliveryJobId: req.params.deliveryJobId,
      expectedVersion: expectedVersion(req),
      customerReceivedActual,
    });
    if (out.completedOrders?.length) {
      const notifications = out.completedOrders.flatMap((order) => [
        {
          userId: Number(order.customer_user_id),
          type: "order_status_update",
          title: "اكتمل طلبك",
          body: `تم تسليم الطلب #${order.id} واكتملت دورته.`,
          orderId: Number(order.id),
          merchantId: Number(order.merchant_id),
          payload: {
            target: "order_tracking",
            orderId: Number(order.id),
            status: "delivered",
            requiresAction: false,
          },
        },
        ...(order.owner_user_id
          ? [
              {
                userId: Number(order.owner_user_id),
                type: "owner_order_delivered",
                title: "تم تسليم الطلب للزبون",
                body: `تم تسليم الطلب #${order.id} واكتملت دورته.`,
                orderId: Number(order.id),
                merchantId: Number(order.merchant_id),
                payload: {
                  target: "owner_orders",
                  orderId: Number(order.id),
                  status: "delivered",
                },
              },
            ]
          : []),
      ]);
      void createManyNotifications(notifications).catch((error) => {
        console.error("[delivery] grouped completion notifications failed", error);
      });
    }
    // The courier is free again — dispatch a waiting job to them right away.
    void requestDeliveryAssignmentRecovery({ limit: 25 }).catch(() => {});
    res.json(out);
  } catch (e) {
    next(e);
  }
}
