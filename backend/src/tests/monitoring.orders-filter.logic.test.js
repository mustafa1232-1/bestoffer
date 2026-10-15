import test from "node:test";
import assert from "node:assert/strict";

import { __monitoringOrdersRepoTestables } from "../modules/admin/monitoring.orders.repo.js";

const { addOrderMonitoringStatusFilter } = __monitoringOrdersRepoTestables;

function build(status) {
  const conds = [];
  const params = [];
  addOrderMonitoringStatusFilter({ conds, params, status });
  return { sql: conds.join(" AND "), params };
}

test("monitoring order filter maps accepted_by_store to approved order status", () => {
  const out = build("accepted_by_store");
  assert.match(out.sql, /o\.status::text = ANY\(\$1::text\[\]\)/);
  assert.deepEqual(out.params, [["approved", "accepted_by_store"]]);
});

test("monitoring order filter maps courier_requested to pending driver assignment", () => {
  const out = build("courier_requested");
  assert.match(out.sql, /delivery_assignment_status = 'PENDING_NO_DRIVER'/);
  assert.match(out.sql, /o\.status::text <> ALL\(\$1::text\[\]\)/);
  assert.ok(out.params[0].includes("cancelled_by_admin"));
  assert.ok(out.params[0].includes("delivered"));
});

test("monitoring order filter maps courier_assigned to active assigned orders", () => {
  const out = build("courier_assigned");
  assert.match(out.sql, /delivery_assignment_status = 'ASSIGNED'/);
  assert.match(out.sql, /o\.status::text <> ALL\(\$1::text\[\]\)/);
  assert.ok(out.params[0].includes("cancelled"));
});

test("monitoring order filter expands completed and cancelled buckets", () => {
  const completed = build("completed");
  const cancelled = build("cancelled");
  assert.deepEqual(completed.params, [["completed", "delivered", "received_by_customer"]]);
  assert.ok(cancelled.params[0].includes("cancelled_by_customer"));
  assert.ok(cancelled.params[0].includes("expired"));
});

test("monitoring order filter keeps real status values exact", () => {
  const out = build("preparing");
  assert.equal(out.sql, "o.status::text = $1");
  assert.deepEqual(out.params, ["preparing"]);
});
