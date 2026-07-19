import crypto from 'node:crypto';

import { AppError } from '../../shared/utils/errors.js';
import {
  normalizeServiceBookingPricingType,
  normalizeServiceBookingStatus,
  normalizeServicePromotionType,
} from './services.booking.constants.js';

function roundMoney(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.round(parsed * 100) / 100;
}

function toNumber(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return parsed;
}

function safeJson(value) {
  if (!value || typeof value !== 'object') return {};
  if (Array.isArray(value)) return [...value];
  return { ...value };
}

function normalizeIqd(value) {
  return roundMoney(toNumber(value, 0));
}

function canonicalizeQuantityAndDuration({
  pricingType,
  quantity,
  durationMinutes,
}) {
  let resolvedQuantity = quantity == null ? null : toNumber(quantity, null);
  let resolvedDurationMinutes =
    durationMinutes == null ? null : Math.round(toNumber(durationMinutes, 0));

  if (pricingType === 'HOURLY') {
    if (resolvedDurationMinutes == null && resolvedQuantity != null) {
      resolvedDurationMinutes = Math.max(1, Math.round(resolvedQuantity * 60));
    }
    if (resolvedQuantity == null && resolvedDurationMinutes != null) {
      resolvedQuantity = resolvedDurationMinutes / 60;
    }
  } else if (pricingType === 'PER_VISIT' || pricingType === 'PER_UNIT') {
    if (resolvedQuantity == null) resolvedQuantity = 1;
    if (resolvedDurationMinutes == null && pricingType === 'PER_VISIT') {
      resolvedDurationMinutes = 0;
    }
  } else if (pricingType === 'FIXED') {
    if (resolvedQuantity == null) resolvedQuantity = 1;
    if (resolvedDurationMinutes == null) resolvedDurationMinutes = 0;
  } else if (pricingType === 'INSPECTION_REQUIRED') {
    if (resolvedQuantity == null) resolvedQuantity = 1;
    if (resolvedDurationMinutes == null) resolvedDurationMinutes = 0;
  }

  return {
    quantity: resolvedQuantity == null ? 1 : resolvedQuantity,
    durationMinutes: resolvedDurationMinutes == null ? 0 : resolvedDurationMinutes,
  };
}

function resolveUnitPriceIqd({
  pricingType,
  pricingOption = null,
  offering = null,
  promotion = null,
}) {
  const fallback = pricingOption?.amount ?? pricingOption?.startsFromPrice ?? offering?.startsFromPrice ?? 0;
  const baseUnit = normalizeIqd(fallback);
  const promotionType = normalizeServicePromotionType(
    promotion?.discountType ?? promotion?.promotionType
  );

  if (pricingType === 'INSPECTION_REQUIRED') {
    return {
      unitPriceIqd: baseUnit > 0 ? baseUnit : 0,
      promotionType,
    };
  }

  if (promotionType === 'SPECIAL_UNIT_PRICE' && promotion?.specialPrice != null) {
    return {
      unitPriceIqd: normalizeIqd(promotion.specialPrice),
      promotionType,
    };
  }

  return {
    unitPriceIqd: baseUnit,
    promotionType,
  };
}

function buildPromotionSnapshot(promotion = null) {
  if (!promotion) return null;
  return {
    id: promotion.id == null ? null : Number(promotion.id),
    title: promotion.title || null,
    description: promotion.description || null,
    discountType: normalizeServicePromotionType(
      promotion.discountType ?? promotion.promotionType
    ),
    discountValue:
      promotion.discountValue == null
        ? null
        : normalizeIqd(promotion.discountValue),
    specialPrice:
      promotion.specialPrice == null ? null : normalizeIqd(promotion.specialPrice),
    startsAt: promotion.startsAt || null,
    endsAt: promotion.endsAt || null,
    badgeColor: promotion.badgeColor || null,
    isActive: promotion.isActive === true,
  };
}

function calculateDiscountIqd({
  pricingType,
  unitPriceIqd,
  quantity,
  subtotalIqd,
  promotion = null,
}) {
  if (!promotion) {
    return {
      unitPriceIqd,
      discountIqd: 0,
      promotionSnapshot: null,
    };
  }

  const snapshot = buildPromotionSnapshot(promotion);
  const type = snapshot.discountType;
  if (type === 'PERCENTAGE' && snapshot.discountValue != null) {
    const discountIqd = normalizeIqd(
      subtotalIqd * (snapshot.discountValue / 100)
    );
    return { unitPriceIqd, discountIqd, promotionSnapshot: snapshot };
  }

  if (type === 'FIXED_AMOUNT' && snapshot.discountValue != null) {
    return {
      unitPriceIqd,
      discountIqd: Math.min(subtotalIqd, normalizeIqd(snapshot.discountValue)),
      promotionSnapshot: snapshot,
    };
  }

  if (type === 'SPECIAL_UNIT_PRICE' && snapshot.specialPrice != null) {
    const adjustedUnit = normalizeIqd(snapshot.specialPrice);
    const adjustedSubtotal =
      pricingType === 'HOURLY'
        ? adjustedUnit * quantity
        : adjustedUnit * quantity;
    const discountIqd = Math.max(0, subtotalIqd - adjustedSubtotal);
    return {
      unitPriceIqd: adjustedUnit,
      discountIqd: normalizeIqd(discountIqd),
      promotionSnapshot: snapshot,
    };
  }

  return {
    unitPriceIqd,
    discountIqd: 0,
    promotionSnapshot: snapshot,
  };
}

function computePriceVersion({
  offeringId,
  providerId,
  pricingOptionId,
  pricingType,
  unitPriceIqd,
  quantity,
  durationMinutes,
  subtotalIqd,
  discountIqd,
  serviceFeeIqd,
  totalIqd,
  promotionSnapshot,
}) {
  const payload = JSON.stringify({
    offeringId: Number(offeringId),
    providerId: Number(providerId),
    pricingOptionId: pricingOptionId == null ? null : Number(pricingOptionId),
    pricingType,
    unitPriceIqd: normalizeIqd(unitPriceIqd),
    quantity: normalizeIqd(quantity),
    durationMinutes: Math.round(toNumber(durationMinutes, 0)),
    subtotalIqd: normalizeIqd(subtotalIqd),
    discountIqd: normalizeIqd(discountIqd),
    serviceFeeIqd: normalizeIqd(serviceFeeIqd),
    totalIqd: normalizeIqd(totalIqd),
    promotionSnapshot: promotionSnapshot ? safeJson(promotionSnapshot) : null,
  });
  return crypto.createHash('sha256').update(payload).digest('hex').slice(0, 24);
}

export function assertValidServiceBookingTransition(expectedVersion, idempotencyKey) {
  const version = Number(expectedVersion ?? 0);
  const key = String(idempotencyKey || '').trim();
  const errors = [];
  if (!Number.isInteger(version) || version < 0) errors.push('expectedVersion');
  if (!key) errors.push('idempotencyKey');
  if (errors.length) {
    throw new AppError('VALIDATION_ERROR', {
      status: 400,
      details: { fields: errors },
    });
  }
  return {
    expectedVersion: version,
    idempotencyKey: key,
  };
}

export function buildServiceBookingPreview({
  offering,
  pricingOption = null,
  pricingType: inputPricingType = null,
  quantity = null,
  durationMinutes = null,
  promotion = null,
  serviceFeeIqd = 0,
  expiresAt = null,
}) {
  const pricingType =
    normalizeServiceBookingPricingType(
      inputPricingType || pricingOption?.pricingModel || pricingOption?.pricingType
    ) || 'FIXED';
  const resolved = canonicalizeQuantityAndDuration({
    pricingType,
    quantity,
    durationMinutes,
  });
  const { unitPriceIqd: baseUnitPriceIqd, promotionType } = resolveUnitPriceIqd({
    pricingType,
    pricingOption,
    offering,
    promotion,
  });

  const resolvedQuantity = resolved.quantity;
  const resolvedDurationMinutes = resolved.durationMinutes;
  const subtotalIqd = normalizeIqd(
    pricingType === 'HOURLY'
      ? baseUnitPriceIqd * resolvedQuantity
      : baseUnitPriceIqd * resolvedQuantity
  );
  const fee = normalizeIqd(serviceFeeIqd);
  const discountStage = calculateDiscountIqd({
    pricingType,
    unitPriceIqd: baseUnitPriceIqd,
    quantity: resolvedQuantity,
    subtotalIqd,
    promotion,
  });
  const discountIqd = normalizeIqd(discountStage.discountIqd);
  const adjustedUnitPriceIqd = normalizeIqd(discountStage.unitPriceIqd);
  const totalIqd = normalizeIqd(Math.max(0, subtotalIqd - discountIqd + fee));
  const promotionSnapshot =
    discountStage.promotionSnapshot || buildPromotionSnapshot(promotion);
  const priceVersion = computePriceVersion({
    offeringId: offering?.id ?? 0,
    providerId: offering?.providerId ?? offering?.provider_id ?? 0,
    pricingOptionId: pricingOption?.id ?? null,
    pricingType,
    unitPriceIqd: adjustedUnitPriceIqd,
    quantity: resolvedQuantity,
    durationMinutes: resolvedDurationMinutes,
    subtotalIqd,
    discountIqd,
    serviceFeeIqd: fee,
    totalIqd,
    promotionSnapshot,
  });

  return {
    pricingType,
    priceVersion,
    unitPriceIqd: adjustedUnitPriceIqd,
    quantity: normalizeIqd(resolvedQuantity),
    durationMinutes: Math.round(resolvedDurationMinutes),
    subtotalIqd,
    discountIqd,
    serviceFeeIqd: fee,
    totalIqd,
    promotionSnapshot,
    expiresAt:
      expiresAt ||
      new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    promotionType: promotionType || null,
  };
}

export function normalizeServiceBookingState(value) {
  return normalizeServiceBookingStatus(value);
}
