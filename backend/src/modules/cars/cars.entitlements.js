import { hasPaidUpgrade } from "../paid-upgrades/paid-upgrades.repo.js";

export async function getCarsEntitlementSummary(userId) {
  const [carSellerMonthly, premiumMonthly] = await Promise.all([
    hasPaidUpgrade(userId, "car_seller_monthly"),
    hasPaidUpgrade(userId, "premium_monthly"),
  ]);
  const canPostCars = carSellerMonthly || premiumMonthly;

  return {
    carSellerMonthly,
    premiumMonthly,
    canPostCars,
    cta: canPostCars
      ? null
      : {
          title: "اشترك كبائع سيارات",
          target: "paid_upgrades_home",
        },
  };
}
