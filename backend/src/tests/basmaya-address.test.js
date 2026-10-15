import assert from "node:assert/strict";
import test from "node:test";

import { validateBasmayaAddress } from "../shared/utils/basmaya-address.js";

function address(block, buildingNumber) {
  return validateBasmayaAddress({
    block,
    buildingNumber,
    apartment: "104",
  });
}

test("accepts the highest building number in every Basmaya sector", () => {
  const valid = {
    A1: 12,
    A2: 14,
    A3: 14,
    A4: 12,
    A5: 12,
    A6: 12,
    A7: 13,
    A8: 15,
    A9: 15,
    B1: 12,
    B2: 18,
    B3: 18,
    B4: 12,
    B5: 18,
    B6: 21,
    B7: 16,
    B8: 12,
  };

  for (const [sector, count] of Object.entries(valid)) {
    const result = address(sector, `${sector}${String(count).padStart(2, "0")}`);
    assert.equal(result.ok, true, `${sector} should accept building ${count}`);
  }
});

test("accepts the new A8 building A815 and rejects the next building", () => {
  assert.equal(address("A8", "A815").ok, true);
  assert.equal(address("A8", "A816").ok, false);
});

test("keeps the selected sector and building consistent", () => {
  assert.equal(address("A8", "A715").ok, false);
  assert.equal(address("B6", "B621").ok, true);
  assert.equal(address("B6", "B622").ok, false);
});
