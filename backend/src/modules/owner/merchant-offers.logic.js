function roundMoney(value) {
  const amount = Number(value || 0);
  if (!Number.isFinite(amount)) return 0;
  return Number(amount.toFixed(2));
}

export const merchantOfferTypes = new Set([
  'percentage',
  'fixed_amount',
  'buy_x_get_y',
]);

export const merchantOfferStatuses = new Set([
  'draft',
  'scheduled',
  'active',
  'disabled',
  'expired',
]);

export function normalizeMerchantOfferStatus(value, fallback = 'draft') {
  const normalized = String(value || '').trim().toLowerCase();
  if (!merchantOfferStatuses.has(normalized)) return fallback;
  return normalized;
}

export function computeMerchantOfferState(offer, now = new Date()) {
  const status = normalizeMerchantOfferStatus(offer?.status, 'draft');
  if (status === 'disabled') return 'disabled';
  if (status === 'draft') return 'draft';

  const nowMs = now instanceof Date ? now.getTime() : new Date(now).getTime();
  const startsAt = offer?.starts_at || offer?.startsAt;
  const endsAt = offer?.ends_at || offer?.endsAt;
  const startsMs = startsAt ? new Date(startsAt).getTime() : null;
  const endsMs = endsAt ? new Date(endsAt).getTime() : null;

  if (startsMs != null && Number.isFinite(startsMs) && startsMs > nowMs) {
    return 'scheduled';
  }
  if (endsMs != null && Number.isFinite(endsMs) && endsMs < nowMs) {
    return 'expired';
  }
  return 'active';
}

export function buildMerchantOfferLabel(offer) {
  const title = String(offer?.title || '').trim();
  if (title) return title;

  const type = String(offer?.offer_type || offer?.offerType || '').trim().toLowerCase();
  if (type === 'percentage') {
    return `خصم ${Number(offer?.discount_value ?? offer?.discountValue ?? 0).toFixed(0)}%`;
  }
  if (type === 'fixed_amount') {
    return `خصم ثابت ${Number(offer?.discount_value ?? offer?.discountValue ?? 0).toFixed(0)} د.ع`;
  }
  const buyQuantity = Number(offer?.buy_quantity ?? offer?.buyQuantity ?? 0);
  const getQuantity = Number(offer?.get_quantity ?? offer?.getQuantity ?? 0);
  if (buyQuantity > 0 && getQuantity > 0) {
    return `اشترِ ${buyQuantity} واحصل على ${getQuantity} مجانًا`;
  }
  return 'عرض متجر';
}

export function applyMerchantOfferPricing({
  baseUnitPrice,
  quantity,
  offer = null,
  fallbackDiscountedPrice = null,
}) {
  const basePrice = roundMoney(baseUnitPrice);
  const qty = Math.max(1, Number(quantity || 1));
  const fallbackUnitPrice =
    fallbackDiscountedPrice == null ? null : roundMoney(fallbackDiscountedPrice);

  const legacyUnitPrice =
    fallbackUnitPrice != null && fallbackUnitPrice > 0 && fallbackUnitPrice < basePrice
      ? fallbackUnitPrice
      : basePrice;

  if (!offer) {
    const grossLineTotal = roundMoney(basePrice * qty);
    const lineTotal = roundMoney(legacyUnitPrice * qty);
    return {
      offerApplied: false,
      offerId: null,
      offerType: null,
      offerLabel: null,
      unitPrice: legacyUnitPrice,
      displayDiscountedUnitPrice: legacyUnitPrice < basePrice ? legacyUnitPrice : null,
      quantity: qty,
      freeUnits: 0,
      grossLineTotal,
      lineDiscountTotal: roundMoney(grossLineTotal - lineTotal),
      lineTotal,
      pricingBreakdown: {
        baseUnitPrice: basePrice,
        finalUnitPrice: legacyUnitPrice,
        quantity: qty,
        grossLineTotal,
        lineDiscountTotal: roundMoney(grossLineTotal - lineTotal),
        lineTotal,
      },
    };
  }

  const offerId = Number(offer.id || 0) || null;
  const offerType = String(offer.offer_type || offer.offerType || '').trim().toLowerCase();
  const offerLabel = buildMerchantOfferLabel(offer);
  const grossLineTotal = roundMoney(basePrice * qty);

  if (offerType === 'percentage') {
    const discountValue = Math.max(0, Number(offer.discount_value ?? offer.discountValue ?? 0));
    const unitDiscount = roundMoney((basePrice * discountValue) / 100);
    const unitPrice = roundMoney(Math.max(0, basePrice - unitDiscount));
    const lineTotal = roundMoney(unitPrice * qty);
    const lineDiscountTotal = roundMoney(grossLineTotal - lineTotal);
    return {
      offerApplied: lineDiscountTotal > 0,
      offerId,
      offerType,
      offerLabel,
      unitPrice,
      displayDiscountedUnitPrice: unitPrice,
      quantity: qty,
      freeUnits: 0,
      grossLineTotal,
      lineDiscountTotal,
      lineTotal,
      pricingBreakdown: {
        offerId,
        offerType,
        offerLabel,
        discountValue,
        baseUnitPrice: basePrice,
        finalUnitPrice: unitPrice,
        quantity: qty,
        grossLineTotal,
        lineDiscountTotal,
        lineTotal,
      },
    };
  }

  if (offerType === 'fixed_amount') {
    const discountValue = Math.max(0, Number(offer.discount_value ?? offer.discountValue ?? 0));
    const unitPrice = roundMoney(Math.max(0, basePrice - discountValue));
    const lineTotal = roundMoney(unitPrice * qty);
    const lineDiscountTotal = roundMoney(grossLineTotal - lineTotal);
    return {
      offerApplied: lineDiscountTotal > 0,
      offerId,
      offerType,
      offerLabel,
      unitPrice,
      displayDiscountedUnitPrice: unitPrice,
      quantity: qty,
      freeUnits: 0,
      grossLineTotal,
      lineDiscountTotal,
      lineTotal,
      pricingBreakdown: {
        offerId,
        offerType,
        offerLabel,
        discountValue,
        baseUnitPrice: basePrice,
        finalUnitPrice: unitPrice,
        quantity: qty,
        grossLineTotal,
        lineDiscountTotal,
        lineTotal,
      },
    };
  }

  if (offerType === 'buy_x_get_y') {
    const buyQuantity = Math.max(1, Number(offer.buy_quantity ?? offer.buyQuantity ?? 0));
    const getQuantity = Math.max(1, Number(offer.get_quantity ?? offer.getQuantity ?? 0));
    const bundleSize = buyQuantity + getQuantity;
    const freeUnits = bundleSize > 0 ? Math.floor(qty / bundleSize) * getQuantity : 0;
    const lineDiscountTotal = roundMoney(basePrice * freeUnits);
    const lineTotal = roundMoney(grossLineTotal - lineDiscountTotal);
    const averageUnitPrice = qty > 0 ? roundMoney(lineTotal / qty) : basePrice;
    return {
      offerApplied: lineDiscountTotal > 0,
      offerId,
      offerType,
      offerLabel,
      unitPrice: averageUnitPrice,
      displayDiscountedUnitPrice: null,
      quantity: qty,
      freeUnits,
      grossLineTotal,
      lineDiscountTotal,
      lineTotal,
      pricingBreakdown: {
        offerId,
        offerType,
        offerLabel,
        buyQuantity,
        getQuantity,
        freeUnits,
        baseUnitPrice: basePrice,
        finalUnitPrice: averageUnitPrice,
        quantity: qty,
        grossLineTotal,
        lineDiscountTotal,
        lineTotal,
      },
    };
  }

  return applyMerchantOfferPricing({
    baseUnitPrice: basePrice,
    quantity: qty,
    offer: null,
    fallbackDiscountedPrice,
  });
}
