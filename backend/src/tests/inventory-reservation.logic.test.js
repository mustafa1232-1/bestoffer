import test from "node:test";
import assert from "node:assert/strict";

import { __ordersRepoTestables } from "../modules/orders/orders.repo.js";

test("releasing a variant reservation restores the exact variant once", async () => {
  let selectCount = 0;
  const calls = [];
  const client = {
    async query(sql, params) {
      calls.push({ sql, params });
      if (String(sql).includes("SELECT * FROM inventory_reservation")) {
        selectCount += 1;
        return selectCount === 1
          ? { rows: [{ id: 8, order_id: 4, variant_id: 12, product_id: 2, merchant_id: 3, quantity: 2, status: "pending" }] }
          : { rows: [] };
      }
      return { rows: [{ id: 12 }] };
    },
  };

  const first = await __ordersRepoTestables.transitionInventoryReservationsTx(client, 4, "released");
  const second = await __ordersRepoTestables.transitionInventoryReservationsTx(client, 4, "released");
  assert.equal(first, 1);
  assert.equal(second, 0);
  assert.equal(calls.filter((call) => call.sql.includes("stock_quantity = stock_quantity +")).length, 1);
});
