export const SERVICE_PRICING_MODELS = [
  'per_hour',
  'per_visit',
  'per_day',
  'per_device',
  'per_room',
  'per_meter',
  'per_item',
  'fixed_package',
  'starting_from',
  'inspection_required',
  'custom_quote',
];

export const SERVICE_PRICING_UNITS = [
  'hour',
  'visit',
  'day',
  'device',
  'room',
  'meter',
  'item',
  'package',
  'job',
  'custom',
];

export const SERVICE_EXECUTION_MODES = [
  'home',
  'provider_location',
  'both',
  'remote',
];

export const SERVICE_BOOKING_POLICIES = ['instant', 'approval_required'];

export const SERVICE_REQUEST_STATUSES = [
  'pending',
  'awaiting_provider',
  'accepted',
  'scheduled',
  'in_progress',
  'completed',
  'cancelled',
  'rejected',
];

export const PROVIDER_APPROVAL_STATUSES = [
  'pending',
  'approved',
  'rejected',
  'suspended',
];

export const OFFERING_MODERATION_STATUSES = [
  'pending',
  'approved',
  'rejected',
  'changes_requested',
  'hidden',
];

export const CATEGORY_SUGGESTION_STATUSES = [
  'pending',
  'approved',
  'rejected',
  'merged',
];

export const QUOTE_STATUSES = [
  'pending_customer',
  'accepted',
  'rejected',
  'expired',
  'cancelled',
];

export const PROMOTION_TYPES = ['percentage', 'fixed', 'special_price'];

export const SERVICE_PROVIDER_SUBSCRIPTION_REQUEST_STATUSES = [
  'pending_offer',
  'offer_sent',
  'offer_accepted',
  'offer_rejected',
  'payment_pending_confirmation',
  'payment_confirmed',
  'account_created',
  'cancelled',
  'rejected',
];

export const SERVICE_PROVIDER_SUBSCRIPTION_OFFER_STATUSES = [
  'pending_provider',
  'accepted',
  'rejected',
  'superseded',
  'cancelled',
  'expired',
];

export const PRICING_MODE_TO_CTA = {
  per_hour: 'احجز بالساعة',
  per_visit: 'احجز زيارة',
  per_day: 'احجز باليوم',
  per_device: 'احجز للجهاز',
  per_room: 'احجز للغرفة',
  per_meter: 'اطلب بالمتر',
  per_item: 'اطلب للقطعة',
  fixed_package: 'احجز الباقة',
  starting_from: 'اطلب تسعير',
  inspection_required: 'طلب معاينة',
  custom_quote: 'اطلب تسعير',
};
