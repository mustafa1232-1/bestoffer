import test from "node:test";
import assert from "node:assert/strict";

import {
  isMerchantOpenForSchedule,
  parseMerchantWorkingHours,
} from "../modules/merchants/merchant-hours.worker.js";

test("merchant hours parse and evaluate 08:00-00:00", () => {
  const schedule = parseMerchantWorkingHours("08:00-00:00");
  assert.deepEqual(schedule, {
    openMinuteOfDay: 8 * 60,
    closeMinuteOfDay: 0,
  });
  assert.equal(
    isMerchantOpenForSchedule(schedule, { hour: 8, minute: 0 }),
    true,
  );
  assert.equal(
    isMerchantOpenForSchedule(schedule, { hour: 23, minute: 59 }),
    true,
  );
  assert.equal(
    isMerchantOpenForSchedule(schedule, { hour: 0, minute: 0 }),
    false,
  );
  assert.equal(
    isMerchantOpenForSchedule(schedule, { hour: 7, minute: 59 }),
    false,
  );
});

test("merchant hours support same-day windows", () => {
  const schedule = parseMerchantWorkingHours("09:30-18:15");
  assert.equal(
    isMerchantOpenForSchedule(schedule, { hour: 9, minute: 29 }),
    false,
  );
  assert.equal(
    isMerchantOpenForSchedule(schedule, { hour: 9, minute: 30 }),
    true,
  );
  assert.equal(
    isMerchantOpenForSchedule(schedule, { hour: 18, minute: 14 }),
    true,
  );
  assert.equal(
    isMerchantOpenForSchedule(schedule, { hour: 18, minute: 15 }),
    false,
  );
});
