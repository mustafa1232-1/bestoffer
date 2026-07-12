import assert from "node:assert/strict";
import test from "node:test";

import {
  PUBLIC_MERCHANT_CATEGORY_SELECT_COLUMNS,
} from "../modules/merchants/merchants.repo.js";

test("public merchant categories include catalog_type for client-side taxonomy filtering", () => {
  assert.ok(
    PUBLIC_MERCHANT_CATEGORY_SELECT_COLUMNS.includes(
      "c.catalog_type AS catalog_type"
    )
  );
});

