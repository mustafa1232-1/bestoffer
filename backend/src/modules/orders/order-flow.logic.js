import { AppError } from "../../shared/utils/errors.js";

export const OWNER_ACTIVE_STATUSES = [
  "pending",
  "approved",
  "preparing",
  "ready_for_delivery",
  "on_the_way",
  "arrived",
];

export const DELIVERY_ACTIVE_STATUSES = [
  "approved",
  "preparing",
  "ready_for_delivery",
  "on_the_way",
  "arrived",
];

export const CHAT_ACTIVE_STATUSES = [
  "approved",
  "preparing",
  "ready_for_delivery",
  "on_the_way",
  "arrived",
  "delivered",
];

export function statusText(status) {
  switch (status) {
    case "pending":
      return "قيد الانتظار";
    case "approved":
      return "تمت الموافقة";
    case "preparing":
      return "قيد التحضير";
    case "ready_for_delivery":
      return "جاهز للتوصيل";
    case "on_the_way":
      return "في الطريق";
    case "arrived":
      return "وصل السائق";
    case "delivered":
      return "تم التسليم";
    case "cancelled":
      return "تم الإلغاء";
    default:
      return status;
  }
}

export function isOrderChatStatus(status) {
  return CHAT_ACTIVE_STATUSES.includes(String(status || ""));
}

export function isOwnerCurrentStatus(status, customerConfirmedAt) {
  if (status === "delivered") {
    return customerConfirmedAt == null;
  }
  return OWNER_ACTIVE_STATUSES.includes(String(status || ""));
}

export function isDeliveryCurrentStatus(status, customerConfirmedAt) {
  if (status === "delivered") {
    return customerConfirmedAt == null;
  }
  return DELIVERY_ACTIVE_STATUSES.includes(String(status || ""));
}

export function assertOwnerTransition({
  currentStatus,
  nextStatus,
  deliveryUserId,
  isMerchantDelivery = false,
  hasAppDeliveryAssignment = false,
}) {
  switch (nextStatus) {
    case "approved":
      if (currentStatus !== "pending") {
        throw new AppError("لا يمكن اعتماد الطلب إلا من حالة قيد الانتظار.", {
          status: 400,
        });
      }
      return;

    case "preparing":
      if (currentStatus !== "approved") {
        throw new AppError("لا يمكن بدء التحضير قبل اعتماد الطلب.", {
          status: 400,
        });
      }
      return;

    case "ready_for_delivery":
      if (currentStatus !== "preparing") {
        throw new AppError("لا يمكن تجهيز الطلب للتوصيل قبل بدء التحضير.", {
          status: 400,
        });
      }
      return;

    case "on_the_way":
      if (!isMerchantDelivery) {
        throw new AppError("لا يمكن للمتجر تحديث هذه الحالة إلا بدلفري المتجر.", {
          status: 400,
        });
      }
      if (!deliveryUserId) {
        throw new AppError("يجب تعيين مندوب فعلي قابل للتتبع قبل بدء التوصيل الحي.", {
          status: 400,
        });
      }
      if (currentStatus !== "ready_for_delivery") {
        throw new AppError("لا يمكن جعل الطلب في الطريق قبل حالة جاهز للتوصيل.", {
          status: 400,
        });
      }
      return;

    case "arrived":
      if (!isMerchantDelivery) {
        throw new AppError("لا يمكن للمتجر تحديث هذه الحالة إلا بدلفري المتجر.", {
          status: 400,
        });
      }
      if (!deliveryUserId) {
        throw new AppError("لا يمكن تسجيل الوصول بدون مندوب فعلي مخصص للطلب.", {
          status: 400,
        });
      }
      if (currentStatus !== "on_the_way") {
        throw new AppError("لا يمكن تسجيل الوصول قبل أن تكون الحالة في الطريق.", {
          status: 400,
        });
      }
      return;

    case "delivered":
      if (!isMerchantDelivery) {
        throw new AppError("لا يمكن للمتجر تحديث هذه الحالة إلا بدلفري المتجر.", {
          status: 400,
        });
      }
      if (!deliveryUserId) {
        throw new AppError("لا يمكن إكمال التسليم بدون مندوب فعلي مخصص للطلب.", {
          status: 400,
        });
      }
      if (currentStatus !== "arrived") {
        throw new AppError("لا يمكن تأكيد التسليم قبل حالة وصل السائق.", {
          status: 400,
        });
      }
      return;

    case "cancelled":
      if (
        ["on_the_way", "arrived", "delivered", "cancelled"].includes(
          currentStatus
        )
      ) {
        throw new AppError("لا يمكن إلغاء الطلب بعد خروجه للتوصيل أو بعد اكتماله.", {
          status: 400,
        });
      }
      return;

    default:
      throw new AppError("حالة الانتقال غير مدعومة.", {
        status: 400,
      });
  }
}

export function currentStatusRank(status) {
  switch (status) {
    case "pending":
      return 0;
    case "approved":
      return 1;
    case "preparing":
      return 2;
    case "ready_for_delivery":
      return 3;
    case "on_the_way":
      return 4;
    case "arrived":
      return 5;
    case "delivered":
      return 6;
    default:
      return 99;
  }
}
