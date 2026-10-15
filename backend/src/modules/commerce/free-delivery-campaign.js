const STARTS_AT = "2026-10-01T21:00:00.000Z";
const ENDS_AT = "2026-10-09T21:00:00.000Z";

export const FREE_DELIVERY_CAMPAIGN = Object.freeze({
  id: "free_delivery_2026_10_02",
  label: "\u0627\u0644\u062a\u0648\u0635\u064a\u0644 \u0645\u062c\u0627\u0646\u0627",
  labelEn: "Free delivery",
  startsAt: STARTS_AT,
  endsAt: ENDS_AT,
  timeZone: "Asia/Baghdad",
});

function timestampOf(value) {
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  if (typeof value === "string" && value.trim()) return Date.parse(value);
  return Number.NaN;
}

export function getFreeDeliveryCampaignStatus(at = new Date()) {
  const timestamp = timestampOf(at);
  const startsAt = Date.parse(FREE_DELIVERY_CAMPAIGN.startsAt);
  const endsAt = Date.parse(FREE_DELIVERY_CAMPAIGN.endsAt);
  const active =
    Number.isFinite(timestamp) && timestamp >= startsAt && timestamp < endsAt;

  return {
    ...FREE_DELIVERY_CAMPAIGN,
    active,
  };
}

export function isFreeDeliveryCampaignActive(at = new Date()) {
  return getFreeDeliveryCampaignStatus(at).active;
}

export function applyFreeDeliveryCampaignToMerchant(payload, at = new Date()) {
  const campaign = getFreeDeliveryCampaignStatus(at);
  if (!campaign.active || !payload) return payload;

  return {
    ...payload,
    deliveryFee: 0,
    delivery_fee: 0,
    hasFreeDeliveryOffer: true,
    has_free_delivery_offer: true,
    hasActiveOffer: true,
    has_active_offer: true,
    deliveryPromotion: campaign,
  };
}

export function applyFreeDeliveryCampaignToProduct(payload, at = new Date()) {
  const campaign = getFreeDeliveryCampaignStatus(at);
  if (!campaign.active || !payload) return payload;

  return {
    ...payload,
    freeDelivery: true,
    free_delivery: true,
    deliveryPromotion: campaign,
  };
}
