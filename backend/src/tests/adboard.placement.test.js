import assert from "node:assert/strict";
import test from "node:test";

import {
  validateAdBoardCreate,
  validateAdBoardUpdate,
} from "../modules/admin/admin.validators.js";

test("ad create defaults placement to HOME_MAIN and keeps legacy fields", () => {
  const r = validateAdBoardCreate({
    title: "عنوان",
    subtitle: "وصف",
  });
  assert.equal(r.ok, true);
  assert.equal(r.value.placement, "HOME_MAIN");
  assert.equal(r.value.activityType, null);
  assert.equal(r.value.titleAr, null);
});

test("ad create accepts marketplace placements + bilingual + activity", () => {
  const r = validateAdBoardCreate({
    title: "t",
    subtitle: "s",
    placement: "marketplace_category",
    activityType: "fashion_clothing",
    titleAr: "قميص",
    titleEn: "Shirt",
    subtitleAr: "خصم",
    subtitleEn: "Sale",
    ctaLabelAr: "تسوق",
    ctaLabelEn: "Shop",
    mobileImageUrl: "https://cdn.example.com/a.jpg",
  });
  assert.equal(r.ok, true);
  assert.equal(r.value.placement, "MARKETPLACE_CATEGORY");
  assert.equal(r.value.activityType, "fashion_clothing");
  assert.equal(r.value.titleAr, "قميص");
  assert.equal(r.value.ctaLabelEn, "Shop");
  assert.equal(r.value.mobileImageUrl, "https://cdn.example.com/a.jpg");
});

test("ad create rejects an unknown placement", () => {
  const r = validateAdBoardCreate({
    title: "t",
    subtitle: "s",
    placement: "SOMEWHERE_ELSE",
  });
  assert.equal(r.ok, false);
  assert.ok(r.errors.includes("placement"));
});

test("ad update accepts a valid placement change", () => {
  const r = validateAdBoardUpdate({ placement: "marketplace_home" });
  assert.equal(r.ok, true);
  assert.equal(r.value.placement, "MARKETPLACE_HOME");
});

test("ad update rejects an invalid placement", () => {
  const r = validateAdBoardUpdate({ placement: "nope" });
  assert.equal(r.ok, false);
  assert.ok(r.errors.includes("placement"));
});

test("ad update whitelists bilingual + activity fields only when present", () => {
  const r = validateAdBoardUpdate({
    titleAr: "جديد",
    activityType: "supermarket",
  });
  assert.equal(r.ok, true);
  assert.equal(r.value.titleAr, "جديد");
  assert.equal(r.value.activityType, "supermarket");
  assert.equal(Object.prototype.hasOwnProperty.call(r.value, "titleEn"), false);
});
