import assert from "node:assert/strict";
import test from "node:test";

import {
  FREE_DELIVERY_CAMPAIGN,
  applyFreeDeliveryCampaignToMerchant,
  applyFreeDeliveryCampaignToProduct,
  isFreeDeliveryCampaignActive,
} from "../modules/commerce/free-delivery-campaign.js";
import { computeOrderFinancialSnapshot } from "../modules/commerce/merchant-financial.logic.js";

const billingProfile = {
  deliveryFeeMode: "dynamic",
  appDeliveryFeeValue: 1000,
  appDeliveryEnabled: true,
};

test("free delivery campaign uses Baghdad midnight boundaries", () => {
  assert.equal(isFreeDeliveryCampaignActive("2026-10-01T20:59:59.999Z"), false);
  assert.equal(isFreeDeliveryCampaignActive(FREE_DELIVERY_CAMPAIGN.startsAt), true);
  assert.equal(isFreeDeliveryCampaignActive("2026-10-09T20:59:59.999Z"), true);
  assert.equal(isFreeDeliveryCampaignActive(FREE_DELIVERY_CAMPAIGN.endsAt), false);
});

test("campaign decorates merchant and product payloads without changing stored data", () => {
  const merchant = applyFreeDeliveryCampaignToMerchant(
    { id: 10, deliveryFee: 1000, hasFreeDeliveryOffer: false },
    FREE_DELIVERY_CAMPAIGN.startsAt,
  );
  const product = applyFreeDeliveryCampaignToProduct(
    { id: 20, freeDelivery: false, free_delivery: false },
    FREE_DELIVERY_CAMPAIGN.startsAt,
  );

  assert.equal(merchant.deliveryFee, 0);
  assert.equal(merchant.hasFreeDeliveryOffer, true);
  assert.equal(merchant.deliveryPromotion.label, "\u0627\u0644\u062a\u0648\u0635\u064a\u0644 \u0645\u062c\u0627\u0646\u0627");
  assert.equal(product.freeDelivery, true);
  assert.equal(product.free_delivery, true);
});

test("campaign charges the customer zero while preserving the raw delivery fee", () => {
  const snapshot = computeOrderFinancialSnapshot(
    {
      subtotal: 10000,
      delivery_type: "delivery",
      courier_source: "app",
      created_at: "2026-10-05T12:00:00.000Z",
    },
    billingProfile,
  );

  assert.equal(snapshot.deliveryFee, 0);
  assert.equal(snapshot.rawDeliveryFee, 1000);
  assert.equal(snapshot.deliverySubsidyAmount, 1000);
  assert.equal(snapshot.freeDeliveryReason, "platform_campaign");
  assert.equal(snapshot.customerTotalAmount, 10500);
});

test("delivery fees return automatically after the campaign", () => {
  const snapshot = computeOrderFinancialSnapshot(
    {
      subtotal: 10000,
      delivery_type: "delivery",
      courier_source: "app",
      created_at: FREE_DELIVERY_CAMPAIGN.endsAt,
    },
    billingProfile,
  );

  assert.equal(snapshot.deliveryFee, 1000);
  assert.equal(snapshot.rawDeliveryFee, 1000);
  assert.equal(snapshot.deliverySubsidyAmount, 0);
  assert.equal(snapshot.freeDeliveryReason, null);
  assert.equal(snapshot.customerTotalAmount, 11500);
});

test("stored campaign snapshots remain free after the campaign closes", () => {
  const original = computeOrderFinancialSnapshot(
    {
      subtotal: 10000,
      delivery_type: "delivery",
      courier_source: "app",
      created_at: "2026-10-03T09:00:00.000Z",
    },
    billingProfile,
  );
  const restored = computeOrderFinancialSnapshot({
    subtotal: original.subtotal,
    service_fee: original.serviceFeeAmount,
    delivery_fee: original.deliveryFee,
    financial_config_snapshot_json: original,
  });

  assert.equal(restored.deliveryFee, 0);
  assert.equal(restored.rawDeliveryFee, 1000);
  assert.equal(restored.freeDeliveryReason, "platform_campaign");
});
