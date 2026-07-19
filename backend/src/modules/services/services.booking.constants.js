const BOOKING_PRICING_TYPES = [
  'FIXED',
  'HOURLY',
  'PER_VISIT',
  'PER_UNIT',
  'INSPECTION_REQUIRED',
];

const BOOKING_PRICING_TYPE_ALIASES = new Map([
  ['fixed_package', 'FIXED'],
  ['starting_from', 'FIXED'],
  ['fixed', 'FIXED'],
  ['per_hour', 'HOURLY'],
  ['hourly', 'HOURLY'],
  ['per_visit', 'PER_VISIT'],
  ['per_day', 'PER_VISIT'],
  ['per_unit', 'PER_UNIT'],
  ['per_item', 'PER_UNIT'],
  ['per_device', 'PER_UNIT'],
  ['per_room', 'PER_UNIT'],
  ['per_meter', 'PER_UNIT'],
  ['inspection_required', 'INSPECTION_REQUIRED'],
  ['custom_quote', 'INSPECTION_REQUIRED'],
]);

const BOOKING_STATUSES = [
  'PENDING_PROVIDER_CONFIRMATION',
  'CONFIRMED',
  'IN_PROGRESS',
  'PROVIDER_COMPLETED',
  'COMPLETED',
  'REJECTED_BY_PROVIDER',
  'CANCELLED_BY_CUSTOMER',
  'CANCELLED_BY_PROVIDER',
  'CANCELLED_BY_ADMIN',
  'EXPIRED',
  'DISPUTED',
];

const BOOKING_STATUS_ALIASES = new Map([
  ['pending', 'PENDING_PROVIDER_CONFIRMATION'],
  ['awaiting_provider', 'PENDING_PROVIDER_CONFIRMATION'],
  ['accepted', 'CONFIRMED'],
  ['scheduled', 'CONFIRMED'],
  ['in_progress', 'IN_PROGRESS'],
  ['completed', 'COMPLETED'],
  ['cancelled', 'CANCELLED_BY_CUSTOMER'],
  ['rejected', 'REJECTED_BY_PROVIDER'],
]);

const PROMOTION_TYPES = ['PERCENTAGE', 'FIXED_AMOUNT', 'SPECIAL_UNIT_PRICE'];
const PROMOTION_TYPE_ALIASES = new Map([
  ['percentage', 'PERCENTAGE'],
  ['fixed', 'FIXED_AMOUNT'],
  ['special_price', 'SPECIAL_UNIT_PRICE'],
]);

function normalizeKey(value) {
  return String(value || '').trim().toLowerCase();
}

function normalizeFromList(value, canonicalValues, aliases = new Map()) {
  const normalized = normalizeKey(value);
  if (!normalized) return null;
  if (aliases.has(normalized)) {
    return aliases.get(normalized);
  }
  for (const item of canonicalValues) {
    if (normalizeKey(item) === normalized) return item;
  }
  return null;
}

export function normalizeServiceBookingPricingType(value) {
  return normalizeFromList(value, BOOKING_PRICING_TYPES, BOOKING_PRICING_TYPE_ALIASES);
}

export function normalizeServiceBookingStatus(value) {
  return normalizeFromList(value, BOOKING_STATUSES, BOOKING_STATUS_ALIASES);
}

export function normalizeServicePromotionType(value) {
  return normalizeFromList(value, PROMOTION_TYPES, PROMOTION_TYPE_ALIASES);
}

export function bookingStatusVariants() {
  return [...BOOKING_STATUSES];
}

export function bookingPricingTypeVariants() {
  return [...BOOKING_PRICING_TYPES];
}

export function promotionTypeVariants() {
  return [...PROMOTION_TYPES];
}
