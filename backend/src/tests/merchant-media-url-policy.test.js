import assert from "node:assert/strict";
import test from "node:test";

import {
  getTrustedMerchantMediaHosts,
  isTrustedMerchantMediaUrl,
} from "../shared/utils/merchant-media-url-policy.js";

test("merchant media policy allows empty and local upload paths", () => {
  assert.equal(isTrustedMerchantMediaUrl(null), true);
  assert.equal(isTrustedMerchantMediaUrl(""), true);
  assert.equal(isTrustedMerchantMediaUrl("/uploads/store.png"), true);
  assert.equal(isTrustedMerchantMediaUrl("uploads/store.png"), true);
});

test("merchant media policy allows production uploads and rejects external hosts", () => {
  assert.equal(
    isTrustedMerchantMediaUrl("https://bestoffer-production.up.railway.app/uploads/store.png"),
    true
  );
  assert.equal(isTrustedMerchantMediaUrl("https://example.invalid/store.png"), false);
  assert.equal(isTrustedMerchantMediaUrl("javascript:alert(1)"), false);
});

test("merchant media policy exposes configured host set", () => {
  assert.equal(getTrustedMerchantMediaHosts().has("bestoffer-production.up.railway.app"), true);
});
