import * as service from "./commerce.service.js";
import {
  validateAdminAppPayablesAdjustment,
  validateAdminFinancialWindowQuery,
  validateAdminMerchantFinancialDetailsQuery,
  validateAdminPaymentRequestApprove,
  validateAdminPaymentRequestAssign,
  validateAdminPaymentRequestMarkPaid,
  validateAdminPaymentRequestReturnForRevision,
  validatePaymentSelectionPreview,
  validateMerchantPaymentRequestConfirm,
  validateMerchantPaymentRequestIssue,
  validateMerchantPaymentRequestPatch,
  validatePaymentRequestListQuery,
  parseOrderId,
  validateBillingProfilePatch,
  validateCompetitionCreate,
  validateCompetitionPatch,
  validateCourierCancelRequest,
  validateCourierAction,
  validateMerchantCourierPatch,
  validateMerchantCourierUpsert,
  validateOrderChatMessage,
  validateOwnerAssignCourier,
  validateOwnerStartPreparing,
  validateCancelRequestReview,
  validatePaymentRequest,
  validateReadyForPickup,
} from "./commerce.validators.js";

function asPositiveInt(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}

function sendValidation(res, errors) {
  return res.status(400).json({ message: "VALIDATION_ERROR", fields: errors });
}

function parseFiniteNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export async function searchProductsGlobal(req, res, next) {
  try {
    const q = String(req.query?.q || "").trim();
    if (!q) {
      return sendValidation(res, ["q"]);
    }
    const limitRaw = asPositiveInt(req.query?.limit);
    const offsetRaw = asPositiveInt(req.query?.offset);
    const minPriceRaw = Number(req.query?.minPrice);
    const maxPriceRaw = Number(req.query?.maxPrice);
    const minRatingRaw = Number(req.query?.minRating);
    const out = await service.searchProductsGlobal(req.userId, {
      q,
      sort: String(req.query?.sort || "best_offers"),
      merchantType: req.query?.merchantType || null,
      onlyAvailable:
        String(req.query?.onlyAvailable || "").toLowerCase() === "true",
      onlyDiscounted:
        String(req.query?.onlyDiscounted || "").toLowerCase() === "true",
      city: req.query?.city || null,
      block: req.query?.block || null,
      minPrice: Number.isFinite(minPriceRaw) ? minPriceRaw : null,
      maxPrice: Number.isFinite(maxPriceRaw) ? maxPriceRaw : null,
      minRating: Number.isFinite(minRatingRaw) ? minRatingRaw : null,
      limit: limitRaw == null ? 40 : Math.min(120, limitRaw),
      offset: offsetRaw == null ? 0 : Math.max(0, offsetRaw),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function ownerStartPreparing(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);

    const v = validateOwnerStartPreparing(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.ownerStartPreparing(req.userId, orderParsed.value, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function ownerAssignCourier(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);

    const v = validateOwnerAssignCourier(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.ownerAssignCourier(req.userId, orderParsed.value, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function ownerReadyForPickup(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);

    const v = validateReadyForPickup(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.ownerReadyForPickup(req.userId, orderParsed.value, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierAcceptOrder(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);

    const v = validateCourierAction(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.courierAcceptOrder(req.userId, orderParsed.value, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierRejectOrder(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);

    const v = validateCourierAction(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.courierRejectOrder(req.userId, orderParsed.value, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierPickedUpOrder(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);

    const v = validateCourierAction(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.courierPickedUpOrder(req.userId, orderParsed.value, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierArrivedOrder(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);

    const v = validateCourierAction(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.courierArrivedOrder(req.userId, orderParsed.value, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierDeliveredOrder(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);

    const v = validateCourierAction(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.courierDeliveredOrder(req.userId, orderParsed.value, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierRequestCancelOrder(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);

    const v = validateCourierCancelRequest(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.courierRequestCancelOrder(
      req.userId,
      orderParsed.value,
      v.data
    );
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function ownerReviewCourierCancelRequest(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);
    const v = validateCancelRequestReview(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.ownerReviewCourierCancelRequest(
      req.userId,
      orderParsed.value,
      v.data
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminReviewCourierCancelRequest(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);
    const v = validateCancelRequestReview(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.adminReviewCourierCancelRequest(
      req.userId,
      orderParsed.value,
      v.data
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function orderChatMessages(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);

    const limitRaw = asPositiveInt(req.query?.limit);
    const beforeIdRaw = asPositiveInt(req.query?.beforeId);

    const out = await service.listOrderChatMessages({
      userId: req.userId,
      userRole: req.userRole,
      orderId: orderParsed.value,
      limit: limitRaw == null ? 120 : Math.min(300, limitRaw),
      beforeId: beforeIdRaw,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function orderChatSendMessage(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);
    const v = validateOrderChatMessage(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.sendOrderChatMessage({
      userId: req.userId,
      userRole: req.userRole,
      orderId: orderParsed.value,
      message: v.data.message,
    });
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function customerConfirmReceived(req, res, next) {
  try {
    const orderParsed = parseOrderId(req.params);
    if (!orderParsed.ok) return sendValidation(res, orderParsed.errors);

    const v = validateCourierAction(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.customerConfirmReceived(req.userId, orderParsed.value, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierDashboard(req, res, next) {
  try {
    const out = await service.getCourierDashboard(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierPresence(req, res, next) {
  try {
    const latitude = parseFiniteNumber(req.body?.latitude);
    const longitude = parseFiniteNumber(req.body?.longitude);
    const orderId = asPositiveInt(req.body?.orderId);
    if (latitude == null || longitude == null) {
      return sendValidation(res, ["latitude", "longitude"]);
    }
    const out = await service.courierUpsertPresence(req.userId, {
      orderId,
      latitude,
      longitude,
      headingDeg: parseFiniteNumber(req.body?.headingDeg),
      speedKmh: parseFiniteNumber(req.body?.speedKmh),
      accuracyM: parseFiniteNumber(req.body?.accuracyM),
      isOnline: req.body?.isOnline !== false,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierOrders(req, res, next) {
  try {
    const out = await service.getCourierOrders(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierRequests(req, res, next) {
  try {
    const out = await service.getCourierRequests(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierOrdersGroupedByMerchant(req, res, next) {
  try {
    const out = await service.getCourierOrdersGroupedByMerchant(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierReports(req, res, next) {
  try {
    const out = await service.getCourierReports(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierEarnings(req, res, next) {
  try {
    const out = await service.getCourierEarnings(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierCompetitions(req, res, next) {
  try {
    const out = await service.getCourierCompetitions(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierCompetitionDetails(req, res, next) {
  try {
    const competitionId = asPositiveInt(req.params?.competitionId);
    if (!competitionId) return sendValidation(res, ["competitionId"]);
    const out = await service.getCourierCompetitionDetails(req.userId, competitionId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierCompetitionAchievementsSummary(req, res, next) {
  try {
    const out = await service.getCourierCompetitionAchievementsSummary(req.userId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function courierCompetitionProgress(req, res, next) {
  try {
    const out = await service.getCourierCompetitionProgress(req.userId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantDashboard(req, res, next) {
  try {
    const out = await service.getMerchantDashboard(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantKpis(req, res, next) {
  try {
    const out = await service.getMerchantKpis(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantTopProducts(req, res, next) {
  try {
    const out = await service.getMerchantTopProducts(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantTopCategories(req, res, next) {
  try {
    const out = await service.getMerchantTopCategories(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantOrdersReports(req, res, next) {
  try {
    const out = await service.getMerchantOrdersReports(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantVerifiedReviews(req, res, next) {
  try {
    const limitRaw = asPositiveInt(req.query?.limit);
    const offsetRaw = asPositiveInt(req.query?.offset);
    const out = await service.getMerchantVerifiedReviews(req.userId, {
      limit: limitRaw == null ? 40 : Math.min(120, limitRaw),
      offset: offsetRaw == null ? 0 : Math.max(0, offsetRaw),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantCustomerReliability(req, res, next) {
  try {
    const customerUserId = asPositiveInt(req.params?.customerUserId);
    if (!customerUserId) return sendValidation(res, ["customerUserId"]);
    const out = await service.getMerchantCustomerReliability(
      req.userId,
      customerUserId
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminGetCustomerReliabilityPolicy(req, res, next) {
  try {
    const out = await service.getCustomerReliabilityPolicy();
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminUpdateCustomerReliabilityPolicy(req, res, next) {
  try {
    const body = req.body || {};
    const out = await service.updateCustomerReliabilityPolicy(req.userId, body);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminGetDeliveryDispatchPolicy(req, res, next) {
  try {
    const out = await service.getDeliveryDispatchPolicy();
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminUpdateDeliveryDispatchPolicy(req, res, next) {
  try {
    const body = req.body || {};
    const out = await service.updateDeliveryDispatchPolicy(req.userId, body);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantListCouriers(req, res, next) {
  try {
    const out = await service.listMerchantCouriers(req.userId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantCreateCourier(req, res, next) {
  try {
    const v = validateMerchantCourierUpsert(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);
    if (!v.data.deliveryUserId) return sendValidation(res, ["deliveryUserId"]);

    const out = await service.createMerchantCourier(req.userId, v.data);
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantPatchCourier(req, res, next) {
  try {
    const courierUserId = asPositiveInt(req.params?.courierUserId);
    if (!courierUserId) return sendValidation(res, ["courierUserId"]);

    const v = validateMerchantCourierPatch(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.updateMerchantCourier(req.userId, courierUserId, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantReceivables(req, res, next) {
  try {
    const out = await service.getMerchantReceivables(req.userId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantReceivablesLedger(req, res, next) {
  try {
    const out = await service.getMerchantReceivablesLedger(req.userId, req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantReceivableInvoices(req, res, next) {
  try {
    const q = validateAdminMerchantFinancialDetailsQuery(req.query || {});
    if (!q.ok) return sendValidation(res, q.errors);
    const out = await service.listMerchantReceivableInvoices(req.userId, q.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantPreviewPaymentSelection(req, res, next) {
  try {
    const v = validatePaymentSelectionPreview(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.previewMerchantPaymentSelection(req.userId, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantCreatePaymentRequest(req, res, next) {
  try {
    const v = validatePaymentRequest(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.createMerchantPaymentRequest(req.userId, v.data);
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantListPaymentRequests(req, res, next) {
  try {
    const v = validatePaymentRequestListQuery(req.query || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.listMerchantPaymentRequests(req.userId, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantPaymentRequestDetails(req, res, next) {
  try {
    const paymentRequestId = asPositiveInt(req.params?.paymentRequestId);
    if (!paymentRequestId) return sendValidation(res, ["paymentRequestId"]);
    const out = await service.getMerchantPaymentRequestDetails(
      req.userId,
      paymentRequestId
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantPaymentRequestInvoices(req, res, next) {
  try {
    const paymentRequestId = asPositiveInt(req.params?.paymentRequestId);
    if (!paymentRequestId) return sendValidation(res, ["paymentRequestId"]);
    const out = await service.getMerchantPaymentRequestInvoices(
      req.userId,
      paymentRequestId
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantPatchPaymentRequest(req, res, next) {
  try {
    const paymentRequestId = asPositiveInt(req.params?.paymentRequestId);
    if (!paymentRequestId) return sendValidation(res, ["paymentRequestId"]);
    const v = validateMerchantPaymentRequestPatch(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.updateMerchantPaymentRequest(
      req.userId,
      paymentRequestId,
      v.data
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantConfirmPaymentRequestReceived(req, res, next) {
  try {
    const paymentRequestId = asPositiveInt(req.params?.paymentRequestId);
    if (!paymentRequestId) return sendValidation(res, ["paymentRequestId"]);
    const v = validateMerchantPaymentRequestConfirm(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.confirmMerchantPaymentRequestReceived(
      req.userId,
      paymentRequestId,
      v.data
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function merchantReportPaymentRequestIssue(req, res, next) {
  try {
    const paymentRequestId = asPositiveInt(req.params?.paymentRequestId);
    if (!paymentRequestId) return sendValidation(res, ["paymentRequestId"]);
    const v = validateMerchantPaymentRequestIssue(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.reportMerchantPaymentRequestIssue(
      req.userId,
      paymentRequestId,
      v.data
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminMerchantsReceivables(req, res, next) {
  try {
    const out = await service.getAdminMerchantsReceivables(req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminMerchantReceivables(req, res, next) {
  try {
    const merchantId = asPositiveInt(req.params?.merchantId);
    if (!merchantId) return sendValidation(res, ["merchantId"]);

    const out = await service.getAdminMerchantReceivables(merchantId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminPaymentRequestInvoices(req, res, next) {
  try {
    const paymentRequestId = asPositiveInt(req.params?.paymentRequestId);
    if (!paymentRequestId) return sendValidation(res, ["paymentRequestId"]);
    const out = await service.getAdminPaymentRequestInvoices(paymentRequestId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminPatchMerchantBillingProfile(req, res, next) {
  try {
    const merchantId = asPositiveInt(req.params?.merchantId);
    if (!merchantId) return sendValidation(res, ["merchantId"]);

    const v = validateBillingProfilePatch(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.patchAdminMerchantBillingProfile(req.userId, merchantId, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminMarkPaymentReceived(req, res, next) {
  try {
    const paymentRequestId = asPositiveInt(req.params?.paymentRequestId);
    if (!paymentRequestId) return sendValidation(res, ["paymentRequestId"]);

    const v = validateCourierAction(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.adminMarkPaymentRequestReceived(req.userId, paymentRequestId, {
      reviewNote: v.data.note,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminApprovePaymentRequest(req, res, next) {
  try {
    const paymentRequestId = asPositiveInt(req.params?.paymentRequestId);
    if (!paymentRequestId) return sendValidation(res, ["paymentRequestId"]);
    const v = validateAdminPaymentRequestApprove(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.adminApprovePaymentRequest(
      req.userId,
      paymentRequestId,
      v.data
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminAssignPaymentRequest(req, res, next) {
  try {
    const paymentRequestId = asPositiveInt(req.params?.paymentRequestId);
    if (!paymentRequestId) return sendValidation(res, ["paymentRequestId"]);
    const v = validateAdminPaymentRequestAssign(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.adminAssignPaymentRequest(
      req.userId,
      paymentRequestId,
      v.data
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminMarkPaymentRequestPaid(req, res, next) {
  try {
    const paymentRequestId = asPositiveInt(req.params?.paymentRequestId);
    if (!paymentRequestId) return sendValidation(res, ["paymentRequestId"]);
    const v = validateAdminPaymentRequestMarkPaid(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.adminMarkPaymentRequestPaid(
      req.userId,
      paymentRequestId,
      v.data
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminReturnPaymentRequestForRevision(req, res, next) {
  try {
    const paymentRequestId = asPositiveInt(req.params?.paymentRequestId);
    if (!paymentRequestId) return sendValidation(res, ["paymentRequestId"]);
    const v = validateAdminPaymentRequestReturnForRevision(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.adminReturnPaymentRequestForRevision(
      req.userId,
      paymentRequestId,
      v.data
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminRejectPayment(req, res, next) {
  try {
    const paymentRequestId = asPositiveInt(req.params?.paymentRequestId);
    if (!paymentRequestId) return sendValidation(res, ["paymentRequestId"]);

    const v = validateCourierAction(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.adminRejectPaymentRequest(req.userId, paymentRequestId, {
      reviewNote: v.data.note,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminCreateAppPayablesAdjustment(req, res, next) {
  try {
    const merchantId = asPositiveInt(req.params?.merchantId);
    if (!merchantId) return sendValidation(res, ["merchantId"]);
    const v = validateAdminAppPayablesAdjustment(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.adminCreateAppPayablesAdjustment(
      req.userId,
      merchantId,
      v.data
    );
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminCompetitions(req, res, next) {
  try {
    const out = await service.getAdminCompetitions(req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminCompetitionDetails(req, res, next) {
  try {
    const competitionId = asPositiveInt(req.params?.competitionId);
    if (!competitionId) return sendValidation(res, ["competitionId"]);
    const out = await service.getAdminCompetitionDetails(competitionId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminCompetitionWinners(req, res, next) {
  try {
    const competitionId = asPositiveInt(req.params?.competitionId);
    if (!competitionId) return sendValidation(res, ["competitionId"]);
    const out = await service.getAdminCompetitionWinners(competitionId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminCreateCompetition(req, res, next) {
  try {
    const v = validateCompetitionCreate(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.createAdminCompetition(req.userId, v.data);
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminPatchCompetition(req, res, next) {
  try {
    const competitionId = asPositiveInt(req.params?.competitionId);
    if (!competitionId) return sendValidation(res, ["competitionId"]);

    const v = validateCompetitionPatch(req.body || {});
    if (!v.ok) return sendValidation(res, v.errors);

    const out = await service.updateAdminCompetition(competitionId, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminEndCompetition(req, res, next) {
  try {
    const competitionId = asPositiveInt(req.params?.competitionId);
    if (!competitionId) return sendValidation(res, ["competitionId"]);
    const out = await service.endAdminCompetition(competitionId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminPlatformKpis(req, res, next) {
  try {
    const out = await service.getAdminPlatformKpis(req.query || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminFinancialKpis(req, res, next) {
  try {
    const v = validateAdminFinancialWindowQuery(req.query || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.getAdminFinancialKpis(v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminSalesReport(req, res, next) {
  try {
    const v = validateAdminFinancialWindowQuery(req.query || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.getAdminSalesReport(v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminSalesMerchantDetails(req, res, next) {
  try {
    const merchantId = asPositiveInt(req.params?.merchantId);
    if (!merchantId) return sendValidation(res, ["merchantId"]);
    const v = validateAdminMerchantFinancialDetailsQuery(req.query || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.getAdminSalesMerchantDetails(merchantId, v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminCollectionsReport(req, res, next) {
  try {
    const v = validateAdminFinancialWindowQuery(req.query || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.getAdminCollectionsReport(v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminCollectionsMerchantDetails(req, res, next) {
  try {
    const merchantId = asPositiveInt(req.params?.merchantId);
    if (!merchantId) return sendValidation(res, ["merchantId"]);
    const v = validateAdminMerchantFinancialDetailsQuery(req.query || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.getAdminCollectionsMerchantDetails(
      merchantId,
      v.data
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminReceivablesReport(req, res, next) {
  try {
    const v = validateAdminFinancialWindowQuery(req.query || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.getAdminReceivablesReport(v.data);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminReceivablesMerchantStatement(req, res, next) {
  try {
    const merchantId = asPositiveInt(req.params?.merchantId);
    if (!merchantId) return sendValidation(res, ["merchantId"]);
    const v = validateAdminMerchantFinancialDetailsQuery(req.query || {});
    if (!v.ok) return sendValidation(res, v.errors);
    const out = await service.getAdminReceivablesMerchantStatement(
      merchantId,
      v.data
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}
