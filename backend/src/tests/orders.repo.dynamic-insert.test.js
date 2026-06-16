import assert from "node:assert/strict";
import test from "node:test";

import { __ordersRepoTestables } from "../modules/orders/orders.repo.js";

test("buildDynamicInsertParts keeps only existing columns in order", () => {
  const out = __ordersRepoTestables.buildDynamicInsertParts({
    availableColumns: new Set(["a", "c"]),
    candidates: [
      ["a", 1],
      ["b", 2],
      ["c", 3],
    ],
  });

  assert.deepEqual(out.insertColumns, ["a", "c"]);
  assert.deepEqual(out.insertValues, [1, 3]);
  assert.equal(out.placeholders, "$1,$2");
});

test("buildDynamicInsertParts returns empty placeholders when nothing matches", () => {
  const out = __ordersRepoTestables.buildDynamicInsertParts({
    availableColumns: new Set(["x"]),
    candidates: [["a", 1]],
  });

  assert.deepEqual(out.insertColumns, []);
  assert.deepEqual(out.insertValues, []);
  assert.equal(out.placeholders, "");
});
