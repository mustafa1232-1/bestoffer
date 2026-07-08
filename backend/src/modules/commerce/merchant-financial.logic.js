import { q } from "../../config/db.js";

const DEFAULT_MERCHANT_BILLING_PROFILE = Object.freeze({
  commissionType: "percentage",
  commissionValue: 10,
  commissionModel: "percentage",
  monthlySubscriptionAmount: 0,
  serviceFeeType: "fixed",
  serviceFeeValue: 500,
  deliveryFeeMode: "dynamic",
  appDeliveryFeeValue: 1000,
  storeDeliveryFeeValue: 0,
  appDeliveryEnabled: true,
  merchantDeliveryEnabled: true,
  settlementCycle: "weekly",
  distributionPolicy: "commission_service_delivery",
  gracePeriodDays: 0,
  profileVersion: 1,
});

function toNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function roundMoney(value) {
  return Math.round((toNumber(value, 0) + Number.EPSILON) * 100) / 100;
}

function normalizeJsonObject(value) {
  if (!value) return null;
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      return parsed && typeof parsed === "object" && !Array.isArray(parsed)
        ? parsed
        : null;
    } catch {
      return null;
    }
  }
  if (typeof value === "object" && !Array.isArray(value)) return value;
  return null;
}

export function normalizeCommissionType(value) {
  const normalized = String(value || "percentage").trim().toLowerCase();
  return normalized === "fixed" ? "fixed" : "percentage";
}

export function normalizeCommissionModel(value) {
  const normalized = String(value || "percentage").trim().toLowerCase();
  if (normalized === "monthly_subscription") return "monthly_subscription";
  return "percentage";
}

export function normalizeServiceFeeType(value) {
  const normalized = String(value || "fixed").trim().toLowerCase();
  if (["percentage", "per_order", "global_rule"].includes(normalized)) {
    return normalized;
  }
  return "fixed";
}

export function normalizeDeliveryFeeMode(value) {
  const normalized = String(value || "dynamic").trim().toLowerCase();
  if (["app_defined", "store_defined", "dynamic"].includes(normalized)) {
    return normalized;
  }
  if (normalized === "fixed" || normalized === "percentage") {
    return "dynamic";
  }
  return "dynamic";
}

export function normalizeApprovalStatus(value) {
  const normalized = String(value || "pending_admin_review").trim().toLowerCase();
  if (
    [
      "pending_admin_review",
      "awaiting_store_financial_acceptance",
      "approved",
      "rejected",
    ].includes(normalized)
  ) {
    return normalized;
  }
  return "pending_admin_review";
}

export function normalizeMerchantBillingProfile(row = {}) {
  const hasRow = row && typeof row === "object" && Object.keys(row).length > 0;
  const commissionRateValue = row.commission_rate ?? row.commissionRate;
  const commissionTypeValue = row.commission_type ?? row.commissionType;
  const commissionValueInput = row.commission_value ?? row.commissionValue;
  const commissionModelInput =
    row.commission_model ?? row.commission_model_type ?? row.commissionModel;
  const monthlySubscriptionAmountInput =
    row.monthly_subscription_amount ?? row.monthlySubscriptionAmount;
  const serviceFeeTypeInput =
    row.service_fee_type ?? row.serviceFeeType ?? row.service_fee_mode ?? row.serviceFeeMode;
  const serviceFeeValueInput = row.service_fee_value ?? row.serviceFeeValue;
  const deliveryFeeModeInput = row.delivery_fee_mode ?? row.deliveryFeeMode;
  const deliveryFeeValueInput = row.delivery_fee_value ?? row.deliveryFeeValue;
  const appDeliveryFeeValueInput =
    row.app_delivery_fee_value ?? row.appDeliveryFeeValue ?? deliveryFeeValueInput;
  const storeDeliveryFeeValueInput =
    row.store_delivery_fee_value ?? row.storeDeliveryFeeValue ?? deliveryFeeValueInput;
  const appDeliveryEnabledInput = row.app_delivery_enabled ?? row.appDeliveryEnabled;
  const merchantDeliveryEnabledInput =
    row.merchant_delivery_enabled ?? row.merchantDeliveryEnabled;
  const settlementCycleInput = row.settlement_cycle ?? row.settlementCycle;
  const distributionPolicyInput = row.distribution_policy ?? row.distributionPolicy;
  const gracePeriodDaysInput = row.grace_period_days ?? row.gracePeriodDays;
  const profileVersionInput = row.profile_version ?? row.profileVersion;
  const effectiveFromInput =
    row.effective_from ??
    row.effectiveFrom ??
    row.updated_at ??
    row.updatedAt ??
    row.created_at ??
    row.createdAt;
  const updatedAtInput = row.updated_at ?? row.updatedAt ?? row.created_at ?? row.createdAt;
  const updatedByUserIdInput = row.updated_by_user_id ?? row.updatedByUserId;
  const merchantIdInput = row.merchant_id ?? row.merchantId;

  const legacyRate = toNumber(
    commissionRateValue,
    DEFAULT_MERCHANT_BILLING_PROFILE.commissionValue / 100
  );
  const commissionModel = normalizeCommissionModel(
    commissionModelInput ??
      (monthlySubscriptionAmountInput != null &&
      Number(monthlySubscriptionAmountInput) > 0
        ? "monthly_subscription"
        : DEFAULT_MERCHANT_BILLING_PROFILE.commissionModel)
  );
  const commissionType = normalizeCommissionType(
    commissionTypeValue ?? DEFAULT_MERCHANT_BILLING_PROFILE.commissionType
  );
  const commissionValue = roundMoney(
    commissionValueInput != null
      ? commissionValueInput
      : commissionModel === "monthly_subscription"
      ? monthlySubscriptionAmountInput != null
        ? monthlySubscriptionAmountInput
        : DEFAULT_MERCHANT_BILLING_PROFILE.monthlySubscriptionAmount
      : commissionType === "percentage"
      ? legacyRate * 100
      : DEFAULT_MERCHANT_BILLING_PROFILE.commissionValue
  );
  const monthlySubscriptionAmount = roundMoney(
    monthlySubscriptionAmountInput != null
      ? monthlySubscriptionAmountInput
      : commissionModel === "monthly_subscription"
      ? commissionValue
      : DEFAULT_MERCHANT_BILLING_PROFILE.monthlySubscriptionAmount
  );
  const serviceFeeType = normalizeServiceFeeType(
    serviceFeeTypeInput ?? DEFAULT_MERCHANT_BILLING_PROFILE.serviceFeeType
  );
  const serviceFeeValue = roundMoney(
    serviceFeeValueInput != null
      ? serviceFeeValueInput
      : DEFAULT_MERCHANT_BILLING_PROFILE.serviceFeeValue
  );
  const deliveryFeeMode = normalizeDeliveryFeeMode(
    deliveryFeeModeInput ?? DEFAULT_MERCHANT_BILLING_PROFILE.deliveryFeeMode
  );
  const appDeliveryFeeValue = roundMoney(
    appDeliveryFeeValueInput != null
      ? appDeliveryFeeValueInput
      : deliveryFeeValueInput != null
      ? deliveryFeeValueInput
      : DEFAULT_MERCHANT_BILLING_PROFILE.appDeliveryFeeValue
  );
  const storeDeliveryFeeValue = roundMoney(
    storeDeliveryFeeValueInput != null
      ? storeDeliveryFeeValueInput
      : deliveryFeeValueInput != null
      ? deliveryFeeValueInput
      : DEFAULT_MERCHANT_BILLING_PROFILE.storeDeliveryFeeValue
  );

  return {
    merchantId: Number(merchantIdInput || 0) || null,
    commissionType,
    commissionModel,
    commissionValue,
    commissionRate:
      commissionType === "percentage"
        ? roundMoney(commissionValue / 100)
        : roundMoney(legacyRate),
    monthlySubscriptionAmount,
    serviceFeeType,
    serviceFeeValue,
    deliveryFeeMode,
    appDeliveryFeeValue,
    storeDeliveryFeeValue,
    appDeliveryEnabled:
      appDeliveryEnabledInput == null
        ? DEFAULT_MERCHANT_BILLING_PROFILE.appDeliveryEnabled
        : appDeliveryEnabledInput !== false,
    merchantDeliveryEnabled:
      merchantDeliveryEnabledInput == null
        ? DEFAULT_MERCHANT_BILLING_PROFILE.merchantDeliveryEnabled
        : merchantDeliveryEnabledInput !== false,
    settlementCycle: String(
      settlementCycleInput ?? DEFAULT_MERCHANT_BILLING_PROFILE.settlementCycle
    )
      .trim()
      .toLowerCase(),
    distributionPolicy: String(
      distributionPolicyInput ?? DEFAULT_MERCHANT_BILLING_PROFILE.distributionPolicy
    )
      .trim()
      .toLowerCase(),
    gracePeriodDays: Math.max(
      0,
      Number(
        gracePeriodDaysInput ?? DEFAULT_MERCHANT_BILLING_PROFILE.gracePeriodDays
      ) || 0
    ),
    profileVersion: Math.max(
      1,
      Number(profileVersionInput ?? DEFAULT_MERCHANT_BILLING_PROFILE.profileVersion) ||
        DEFAULT_MERCHANT_BILLING_PROFILE.profileVersion
    ),
    effectiveFrom:
      effectiveFromInput || new Date().toISOString(),
    updatedAt: updatedAtInput || null,
    updatedByUserId: Number(updatedByUserIdInput || 0) || null,
    raw: hasRow
      ? row
      : { ...DEFAULT_MERCHANT_BILLING_PROFILE, merchant_id: merchantIdInput || null },
  };
}

export async function getMerchantBillingProfile(merchantId) {
  const result = await q(
    `SELECT *
     FROM merchant_billing_profile
     WHERE merchant_id = $1
     LIMIT 1`,
    [Number(merchantId)]
  );
  return normalizeMerchantBillingProfile(result.rows[0] || { merchant_id: merchantId });
}

function resolveServiceFeeAmount(subtotal, explicitServiceFee, profile) {
  if (explicitServiceFee > 0) return explicitServiceFee;
  if (subtotal <= 0) return 0;
  const value = roundMoney(profile.serviceFeeValue);
  if (value <= 0) return 0;
  if (profile.serviceFeeType === "percentage") {
    return roundMoney((subtotal * value) / 100);
  }
  return value;
}

function resolveCommissionAmount(subtotal, profile) {
  if (profile.commissionModel === "monthly_subscription") {
    return 0;
  }
  const value = roundMoney(profile.commissionValue);
  if (value <= 0 || subtotal <= 0) return 0;
  if (profile.commissionType === "fixed") {
    return value;
  }
  return roundMoney((subtotal * value) / 100);
}

function resolveCouponDiscountTotal(order, subtotal, serviceFeeAmount, deliveryFeeAmount) {
  const explicit = roundMoney(
    order?.coupon_discount_total ?? order?.couponDiscountTotal ?? 0
  );
  if (explicit > 0) return explicit;

  const inferred = roundMoney(
    subtotal + serviceFeeAmount + deliveryFeeAmount - roundMoney(order?.total_amount ?? order?.totalAmount ?? 0)
  );
  if (inferred > 0) return inferred;
  return 0;
}

function buildCashSettlementAmounts({
  subtotal,
  couponDiscountTotal,
  commissionAmount,
  serviceFeeAmount,
  appDeliveryFeeAmount,
  storeDeliveryFeeAmount,
}) {
  const discountedSubtotal = roundMoney(Math.max(0, subtotal - couponDiscountTotal));
  const appDueFromDelivery = roundMoney(
    commissionAmount + serviceFeeAmount + roundMoney(appDeliveryFeeAmount)
  );
  const storeNetReceivedAmount = roundMoney(
    Math.max(
      0,
      discountedSubtotal -
        commissionAmount -
        serviceFeeAmount -
        roundMoney(appDeliveryFeeAmount) +
        roundMoney(storeDeliveryFeeAmount)
    )
  );
  const customerTotalAmount = roundMoney(
    discountedSubtotal +
      serviceFeeAmount +
      roundMoney(appDeliveryFeeAmount) +
      roundMoney(storeDeliveryFeeAmount)
  );

  return {
    discountedSubtotal,
    storeNetReceivedAmount,
    appDueFromDelivery,
    customerTotalAmount,
  };
}

function resolveDeliveryBreakdown({
  order,
  profile,
  explicitDeliveryFee,
  subtotal,
}) {
  const courierSource = String(
    order?.courier_source || (order?.is_merchant_delivery === true ? "merchant" : "app")
  )
    .trim()
    .toLowerCase();
  const deliveryType = String(order?.delivery_type || "delivery").trim().toLowerCase();

  if (deliveryType === "pickup" || courierSource === "none") {
    return {
      courierSource,
      deliveryType,
      deliveryFee: 0,
      appDeliveryFeeAmount: 0,
      storeDeliveryFeeAmount: 0,
    };
  }

  if (order?.has_free_delivery === true || order?.free_delivery_override === true) {
    return {
      courierSource,
      deliveryType,
      deliveryFee: 0,
      appDeliveryFeeAmount: 0,
      storeDeliveryFeeAmount: 0,
    };
  }

  const baseAppDelivery =
    explicitDeliveryFee > 0
      ? explicitDeliveryFee
      : roundMoney(profile.appDeliveryFeeValue);
  const baseStoreDelivery =
    explicitDeliveryFee > 0
      ? explicitDeliveryFee
      : roundMoney(profile.storeDeliveryFeeValue || profile.appDeliveryFeeValue);

  let appDeliveryFeeAmount = 0;
  let storeDeliveryFeeAmount = 0;

  switch (profile.deliveryFeeMode) {
    case "store_defined":
      storeDeliveryFeeAmount = courierSource === "merchant" || courierSource === "app"
        ? baseStoreDelivery
        : 0;
      break;
    case "app_defined":
      if (courierSource === "app" && profile.appDeliveryEnabled) {
        appDeliveryFeeAmount = baseAppDelivery;
      } else if (courierSource === "merchant" && profile.merchantDeliveryEnabled) {
        storeDeliveryFeeAmount = baseStoreDelivery;
      }
      break;
    case "dynamic":
    default:
      if (courierSource === "app" && profile.appDeliveryEnabled) {
        appDeliveryFeeAmount = baseAppDelivery;
      } else if (courierSource === "merchant" && profile.merchantDeliveryEnabled) {
        storeDeliveryFeeAmount = baseStoreDelivery;
      }
      break;
  }

  const deliveryFee = roundMoney(
    appDeliveryFeeAmount > 0
      ? appDeliveryFeeAmount
      : storeDeliveryFeeAmount > 0
      ? storeDeliveryFeeAmount
      : explicitDeliveryFee > 0
      ? explicitDeliveryFee
      : 0
  );

  return {
    courierSource,
    deliveryType,
    deliveryFee,
    appDeliveryFeeAmount: roundMoney(appDeliveryFeeAmount),
    storeDeliveryFeeAmount: roundMoney(storeDeliveryFeeAmount),
  };
}

export function computeOrderFinancialSnapshot(order, profileInput = {}) {
  const profile = normalizeMerchantBillingProfile(profileInput);
  const snapshotSource = normalizeJsonObject(order?.financial_config_snapshot_json);
  if (snapshotSource?.appReceivableAmount != null) {
    const subtotal = roundMoney(snapshotSource.subtotal ?? order?.subtotal);
    const delivery = roundMoney(snapshotSource.deliveryFee ?? order?.delivery_fee);
    const serviceFeeAmount = roundMoney(snapshotSource.serviceFeeAmount);
    const commissionAmount = roundMoney(snapshotSource.commissionAmount);
    const appDeliveryFeeAmount = roundMoney(snapshotSource.appDeliveryFeeAmount);
    const storeDeliveryFeeAmount = roundMoney(snapshotSource.storeDeliveryFeeAmount);
    const couponDiscountTotal = resolveCouponDiscountTotal(
      order,
      subtotal,
      serviceFeeAmount,
      delivery
    );
    const cashAmounts = buildCashSettlementAmounts({
      subtotal,
      couponDiscountTotal,
      commissionAmount,
      serviceFeeAmount,
      appDeliveryFeeAmount,
      storeDeliveryFeeAmount,
    });
    return {
      ...snapshotSource,
      commissionModel: snapshotSource.commissionModel || profile.commissionModel,
      profileVersion: Math.max(1, Number(snapshotSource.profileVersion || profile.profileVersion) || 1),
      commissionAmount,
      serviceFeeAmount,
      appDeliveryFeeAmount,
      storeDeliveryFeeAmount,
      appReceivableAmount: roundMoney(snapshotSource.appReceivableAmount),
      storeNetAmount: cashAmounts.storeNetReceivedAmount,
      subtotal,
      couponDiscountTotal,
      deliveryFee: delivery,
      customerTotalAmount: cashAmounts.customerTotalAmount,
      storeNetReceivedAmount: cashAmounts.storeNetReceivedAmount,
      appDueFromDelivery: cashAmounts.appDueFromDelivery,
      deliveryCashAmount: delivery,
      monthlySubscriptionAmount: roundMoney(
        snapshotSource.monthlySubscriptionAmount ??
          profile.monthlySubscriptionAmount
      ),
      storeCashConfirmed: snapshotSource.storeCashConfirmed === true,
      storeCashConfirmedAt: snapshotSource.storeCashConfirmedAt || null,
      storeCashConfirmedByUserId:
        snapshotSource.storeCashConfirmedByUserId ??
        snapshotSource.storeCashConfirmedBy ??
        null,
      amountReceivedActual: roundMoney(snapshotSource.amountReceivedActual ?? 0),
      differenceAmount: roundMoney(snapshotSource.differenceAmount ?? 0),
      differenceReason: snapshotSource.differenceReason || null,
      settlementStatus:
        snapshotSource.settlementStatus || "pending_store_confirmation",
    };
  }

  const subtotal = roundMoney(order?.subtotal);
  const explicitServiceFee = roundMoney(order?.service_fee);
  const explicitDeliveryFee = roundMoney(order?.delivery_fee);
  const commissionAmount = resolveCommissionAmount(subtotal, profile);
  const serviceFeeAmount = resolveServiceFeeAmount(subtotal, explicitServiceFee, profile);
  const delivery = resolveDeliveryBreakdown({
    order,
    profile,
    explicitDeliveryFee,
    subtotal,
  });
  const couponDiscountTotal = resolveCouponDiscountTotal(
    order,
    subtotal,
    serviceFeeAmount,
    delivery.deliveryFee
  );
  const cashAmounts = buildCashSettlementAmounts({
    subtotal,
    couponDiscountTotal,
    commissionAmount,
    serviceFeeAmount,
    appDeliveryFeeAmount: delivery.appDeliveryFeeAmount,
    storeDeliveryFeeAmount: delivery.storeDeliveryFeeAmount,
  });
  const appReceivableAmount = roundMoney(
    cashAmounts.appDueFromDelivery
  );
  const storeNetAmount = roundMoney(
    cashAmounts.storeNetReceivedAmount
  );
  const issuedAt =
    order?.customer_confirmed_at ||
    order?.completed_at ||
    order?.delivered_at ||
    order?.updated_at ||
    order?.created_at ||
    new Date().toISOString();

  return {
    subtotal,
    deliveryFee: delivery.deliveryFee,
    courierSource: delivery.courierSource,
    deliveryType: delivery.deliveryType,
    commissionType: profile.commissionType,
    commissionModel: profile.commissionModel,
    commissionValue: profile.commissionValue,
    monthlySubscriptionAmount: profile.monthlySubscriptionAmount,
    commissionAmount,
    serviceFeeType: profile.serviceFeeType,
    serviceFeeValue: profile.serviceFeeValue,
    serviceFeeAmount,
    couponDiscountTotal,
    deliveryFeeMode: profile.deliveryFeeMode,
    appDeliveryFeeValue: profile.appDeliveryFeeValue,
    storeDeliveryFeeValue: profile.storeDeliveryFeeValue,
    appDeliveryFeeAmount: delivery.appDeliveryFeeAmount,
    storeDeliveryFeeAmount: delivery.storeDeliveryFeeAmount,
    appReceivableAmount,
    storeNetAmount,
    customerTotalAmount: cashAmounts.customerTotalAmount,
    storeNetReceivedAmount: cashAmounts.storeNetReceivedAmount,
    appDueFromDelivery: cashAmounts.appDueFromDelivery,
    deliveryCashAmount: delivery.deliveryFee,
    storeCashConfirmed: false,
    storeCashConfirmedAt: null,
    storeCashConfirmedByUserId: null,
    amountReceivedActual: 0,
    differenceAmount: 0,
    differenceReason: null,
    settlementStatus: "pending_store_confirmation",
    settlementCycle: profile.settlementCycle,
    distributionPolicy: profile.distributionPolicy,
    gracePeriodDays: profile.gracePeriodDays,
    profileVersion: profile.profileVersion,
    effectiveFrom: profile.effectiveFrom,
    issuedAt,
  };
}

export function parseStoredFinancialSnapshot(value) {
  const normalized = normalizeJsonObject(value);
  if (!normalized) return null;
  return computeOrderFinancialSnapshot({
    subtotal: normalized.subtotal,
    service_fee: normalized.serviceFeeAmount,
    delivery_fee: normalized.deliveryFee,
    coupon_discount_total: normalized.couponDiscountTotal,
    total_amount: normalized.customerTotalAmount ?? normalized.totalAmount,
    financial_config_snapshot_json: normalized,
  });
}

export function buildDeliveryCashSettlementSnapshot(orderRows = [], profileInput = {}) {
  const profile = normalizeMerchantBillingProfile(profileInput);
  const rows = Array.isArray(orderRows) ? orderRows : [];

  const summary = {
    ordersCount: 0,
    subtotalAmount: 0,
    couponDiscountTotal: 0,
    commissionAmount: 0,
    serviceFeeAmount: 0,
    deliveryFeeAmount: 0,
    customerTotalAmount: 0,
    storeNetReceivedAmount: 0,
    appDueFromDelivery: 0,
    monthlySubscriptionAmount: roundMoney(profile.monthlySubscriptionAmount),
    settlementStatus: "pending_store_confirmation",
  };

  for (const row of rows) {
    const snapshot = computeOrderFinancialSnapshot(row, profile);
    summary.ordersCount += 1;
    summary.subtotalAmount = roundMoney(summary.subtotalAmount + snapshot.subtotal);
    summary.couponDiscountTotal = roundMoney(
      summary.couponDiscountTotal + roundMoney(snapshot.couponDiscountTotal ?? 0)
    );
    summary.commissionAmount = roundMoney(
      summary.commissionAmount + roundMoney(snapshot.commissionAmount ?? 0)
    );
    summary.serviceFeeAmount = roundMoney(
      summary.serviceFeeAmount + roundMoney(snapshot.serviceFeeAmount ?? 0)
    );
    summary.deliveryFeeAmount = roundMoney(
      summary.deliveryFeeAmount + roundMoney(snapshot.deliveryFee ?? 0)
    );
    summary.customerTotalAmount = roundMoney(
      summary.customerTotalAmount + roundMoney(snapshot.customerTotalAmount ?? 0)
    );
    summary.storeNetReceivedAmount = roundMoney(
      summary.storeNetReceivedAmount + roundMoney(snapshot.storeNetReceivedAmount ?? 0)
    );
    summary.appDueFromDelivery = roundMoney(
      summary.appDueFromDelivery + roundMoney(snapshot.appDueFromDelivery ?? 0)
    );
  }

  return {
    ...summary,
    totalAmount: summary.customerTotalAmount,
    storeCashConfirmed: false,
    storeCashConfirmedAt: null,
    storeCashConfirmedByUserId: null,
    amountReceivedActual: 0,
    differenceAmount: 0,
    differenceReason: null,
    commissionModel: profile.commissionModel,
    commissionValue: profile.commissionValue,
    serviceFeeValue: profile.serviceFeeValue,
    deliveryFeeMode: profile.deliveryFeeMode,
    appDeliveryFeeValue: profile.appDeliveryFeeValue,
    storeDeliveryFeeValue: profile.storeDeliveryFeeValue,
    settlementCycle: profile.settlementCycle,
    distributionPolicy: profile.distributionPolicy,
    gracePeriodDays: profile.gracePeriodDays,
    profileVersion: profile.profileVersion,
    effectiveFrom: profile.effectiveFrom,
    issuedAt: rows[0]?.customer_confirmed_at ||
      rows[0]?.completed_at ||
      rows[0]?.delivered_at ||
      rows[0]?.updated_at ||
      rows[0]?.created_at ||
      new Date().toISOString(),
  };
}

export function resolveStoreCashConfirmationSnapshot({
  expectedAmount,
  actualAmount,
  reason = null,
  actorUserId = null,
}) {
  const expected = roundMoney(expectedAmount);
  const actual = roundMoney(actualAmount);
  const differenceAmount = roundMoney(actual - expected);
  return {
    storeCashConfirmed: true,
    storeCashConfirmedAt: new Date().toISOString(),
    storeCashConfirmedByUserId: actorUserId == null ? null : Number(actorUserId),
    amountReceivedActual: actual,
    differenceAmount,
    differenceReason: reason ? String(reason).trim().slice(0, 1000) || null : null,
    settlementStatus: Math.abs(differenceAmount) > 0
      ? "difference_review"
      : "received",
  };
}

export function evaluateCourierEndDayReadiness(settlements = []) {
  const rows = Array.isArray(settlements) ? settlements : [];
  const openSettlements = rows.filter((row) => {
    const status = String(row.status || "").trim().toLowerCase();
    const settlementStatus = String(row.settlementStatus || row.settlement_status || "")
      .trim()
      .toLowerCase();
    return status === "pending" && settlementStatus !== "closed" && settlementStatus !== "cancelled";
  });
  const outstandingAmount = roundMoney(
    openSettlements.reduce(
      (sum, row) =>
        sum +
        roundMoney(
          row.appDueFromDelivery ??
            row.app_due_from_delivery ??
            row.totalAmount ??
            row.total_amount ??
            0
        ),
      0
    )
  );
  return {
    canEndDay: openSettlements.length === 0,
    outstandingAmount,
    openSettlements: openSettlements.map((row) => ({
      id: Number(row.id || 0) || null,
      archiveDate: row.archiveDate || row.archive_date || null,
      totalAmount: roundMoney(row.totalAmount ?? row.total_amount ?? 0),
      appDueFromDelivery: roundMoney(
        row.appDueFromDelivery ?? row.app_due_from_delivery ?? 0
      ),
      settlementStatus:
        row.settlementStatus || row.settlement_status || "pending_store_confirmation",
      status: String(row.status || "").trim().toLowerCase() || "pending",
    })),
  };
}

export { roundMoney, toNumber };
