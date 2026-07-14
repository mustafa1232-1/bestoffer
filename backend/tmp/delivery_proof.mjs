// REAL runtime proof against local QA Postgres. Exercises actual backend repo
// functions (no mocks). Seeds its own isolated rows and cleans up after.
import { pool, q } from "../src/config/db.js";
import {
  startPreparingAndRequestCourier,
  listCourierOrders,
  directAssignDeliveryOrderTx,
} from "../src/modules/commerce/commerce.repo.js";
import { upsertCourierPresence } from "../src/modules/orders/orders.repo.js";
import { processDeliveryAssignmentRecoveryBatch } from "../src/modules/orders/delivery-assignment.worker.js";
import * as deliveryService from "../src/modules/delivery/delivery.service.js";
import { courierUpsertPresence } from "../src/modules/commerce/commerce.service.js";
import { requestDeliveryAssignmentRecovery } from "../src/modules/orders/delivery-assignment.worker.js";

const TAG = "PROOF9x"; // unique marker for cleanup
let PASS = 0, FAIL = 0;
function check(name, cond, extra = "") {
  if (cond) { PASS++; console.log(`  ✅ ${name} ${extra}`); }
  else { FAIL++; console.log(`  ❌ ${name} ${extra}`); }
}

async function cleanup() {
  // delete in FK-safe order using our tag
  await q(`DELETE FROM courier_assignment WHERE order_id IN (SELECT id FROM customer_order WHERE customer_full_name LIKE '${TAG}%')`);
  await q(`DELETE FROM customer_order WHERE customer_full_name LIKE '${TAG}%'`);
  await q(`DELETE FROM courier_presence WHERE courier_user_id IN (SELECT id FROM app_user WHERE full_name LIKE '${TAG}%')`);
  await q(`DELETE FROM courier_profile WHERE user_id IN (SELECT id FROM app_user WHERE full_name LIKE '${TAG}%')`);
  await q(`DELETE FROM app_notification WHERE body LIKE '%${TAG}%'`);
  await q(`DELETE FROM merchant WHERE name LIKE '${TAG}%'`);
  await q(`DELETE FROM app_user WHERE full_name LIKE '${TAG}%'`);
}

let _seq = 0;
async function makeUser(role, n) {
  _seq += 1;
  const uniq = `${(Date.now() % 1000000)}${_seq}`;
  const username = `proof9x${role[0]}${uniq}`.toLowerCase().slice(0, 24);
  const phone = `07${uniq}`.slice(0, 15);
  const r = await q(
    `INSERT INTO app_user (full_name, phone, pin_hash, block, building_number, apartment, username, role, delivery_account_approved, is_account_disabled)
     VALUES ($1,$2,'x','A','1','1',$3,$4::user_role, TRUE, FALSE) RETURNING id`,
    [`${TAG}_${role}_${n}`, phone, username, role]
  );
  return Number(r.rows[0].id);
}

async function makeDriver(n) {
  const id = await makeUser("delivery", n);
  await q(
    `INSERT INTO courier_profile (user_id, is_app_courier, is_merchant_courier, driver_type, availability_status, active_status)
     VALUES ($1, TRUE, FALSE, 'app_driver', 'online', TRUE)
     ON CONFLICT (user_id) DO UPDATE SET driver_type='app_driver', availability_status='online', active_status=TRUE`,
    [id]
  );
  return id;
}

async function freshPresence(driverId, online = true) {
  await upsertCourierPresence({ courierUserId: driverId, latitude: 33.1, longitude: 44.2, isOnline: online });
}

async function makeOrder(merchantId, customerId, status = "approved") {
  const r = await q(
    `INSERT INTO customer_order
       (merchant_id, customer_user_id, customer_full_name, customer_phone, customer_block, customer_building_number, customer_apartment, status, delivery_type, delivery_assignment_status)
     VALUES ($1,$2,$3,'07900000000','A','1','1',$4::order_status,'delivery','NOT_REQUIRED') RETURNING id`,
    [merchantId, customerId, `${TAG}_order`, status]
  );
  return Number(r.rows[0].id);
}

async function orderRow(id) {
  const r = await q(`SELECT id, status, delivery_assignment_status, delivery_user_id FROM customer_order WHERE id=$1`, [id]);
  return r.rows[0];
}
async function openAssignments(orderId) {
  const r = await q(`SELECT id, courier_user_id, status, ended_at FROM courier_assignment WHERE order_id=$1 AND ended_at IS NULL`, [orderId]);
  return r.rows;
}

async function main() {
  console.log("DB:", (process.env.DATABASE_URL || "").split("@")[1]);
  await cleanup();

  // merchant type enum first value
  const et = await q(`SELECT e.enumlabel FROM pg_type t JOIN pg_enum e ON t.oid=e.enumtypid WHERE t.typname='merchant_type' ORDER BY e.enumsortorder LIMIT 1`);
  const merchantType = et.rows[0]?.enumlabel || "grocery";

  const owner = await makeUser("owner", 1);
  const mr = await q(
    `INSERT INTO merchant (name, type, owner_user_id, is_open, is_approved, is_disabled)
     VALUES ($1,$2::merchant_type,$3,TRUE,TRUE,FALSE) RETURNING id`,
    [`${TAG}_merchant`, merchantType, owner]
  );
  const merchantId = Number(mr.rows[0].id);
  const customer = await makeUser("user", 1);

  console.log("\n=== TEST A: correctly-provisioned idle available driver gets auto-assigned (store start-preparing) ===");
  const driver = await makeDriver(1);
  await freshPresence(driver);
  const orderA = await makeOrder(merchantId, customer, "approved");
  const resA = await startPreparingAndRequestCourier({ ownerUserId: owner, orderId: orderA, preferredCourierUserId: null });
  const rowA = await orderRow(orderA);
  const openA = await openAssignments(orderA);
  check("assignmentCreated", resA.assignmentCreated === true, `status=${resA.assignmentStatus}`);
  check("order ASSIGNED", rowA.delivery_assignment_status === "ASSIGNED");
  check("delivery_user_id == driver", Number(rowA.delivery_user_id) === driver, `(got ${rowA.delivery_user_id}, want ${driver})`);
  check("exactly one open courier_assignment", openA.length === 1, `(got ${openA.length})`);
  check("open assignment courier == driver", openA[0] && Number(openA[0].courier_user_id) === driver);

  console.log("\n=== TEST B: assigned-only API returns it to the driver, and only that driver ===");
  const listDriver = await listCourierOrders(driver, {});
  const otherDriver = await makeDriver(2);
  const listOther = await listCourierOrders(otherDriver, {});
  check("driver sees the assigned order", (listDriver.orders || []).some((o) => Number(o.id) === orderA));
  check("other driver sees nothing", !(listOther.orders || []).some((o) => Number(o.id) === orderA), `(other count=${(listOther.orders||[]).length})`);

  console.log("\n=== TEST C: no fresh presence => PENDING_NO_DRIVER (deadlock symptom) ===");
  // make a driver with stale presence (older than freshness window)
  const driverStale = await makeDriver(3);
  await q(`UPDATE courier_presence SET updated_at = NOW() - INTERVAL '10 minutes', recorded_at = NOW() - INTERVAL '10 minutes' WHERE courier_user_id=$1`, [driverStale]);
  // ensure driver1/driver2 are busy or absent: they must NOT be eligible for this order.
  // driver1 already has an active ASSIGNED order (orderA). driver2 has none + fresh? driver2 had no presence -> ineligible.
  const orderC = await makeOrder(merchantId, customer, "approved");
  const resC = await startPreparingAndRequestCourier({ ownerUserId: owner, orderId: orderC, preferredCourierUserId: null });
  const rowC = await orderRow(orderC);
  check("no eligible driver => PENDING_NO_DRIVER", rowC.delivery_assignment_status === "PENDING_NO_DRIVER", `(got ${rowC.delivery_assignment_status})`);
  check("no open assignment for pending order", (await openAssignments(orderC)).length === 0);

  console.log("\n=== TEST D: driver becomes available (fresh presence) => recovery assigns oldest pending ===");
  await freshPresence(driverStale); // now fresh + online
  const recap = await processDeliveryAssignmentRecoveryBatch({ limit: 25 });
  const rowC2 = await orderRow(orderC);
  const openC2 = await openAssignments(orderC);
  check("recovery batch ran", recap && recap.locked === true, JSON.stringify(recap));
  check("pending order now ASSIGNED", rowC2.delivery_assignment_status === "ASSIGNED", `(got ${rowC2.delivery_assignment_status})`);
  check("assigned to the newly-available driver", Number(rowC2.delivery_user_id) === driverStale, `(got ${rowC2.delivery_user_id}, want ${driverStale})`);
  check("exactly one open assignment after recovery", openC2.length === 1);

  console.log("\n=== TEST E: concurrency — 1 free driver, 2 new orders => exactly one ASSIGNED, one PENDING ===");
  const driverE = await makeDriver(4);
  await freshPresence(driverE);
  const o1 = await makeOrder(merchantId, customer, "approved");
  const o2 = await makeOrder(merchantId, customer, "approved");
  await startPreparingAndRequestCourier({ ownerUserId: owner, orderId: o1, preferredCourierUserId: null });
  await startPreparingAndRequestCourier({ ownerUserId: owner, orderId: o2, preferredCourierUserId: null });
  const r1 = await orderRow(o1), r2 = await orderRow(o2);
  const assignedCount = [r1, r2].filter((r) => r.delivery_assignment_status === "ASSIGNED").length;
  const pendingCount = [r1, r2].filter((r) => r.delivery_assignment_status === "PENDING_NO_DRIVER").length;
  check("exactly one ASSIGNED", assignedCount === 1, `(o1=${r1.delivery_assignment_status}, o2=${r2.delivery_assignment_status})`);
  check("exactly one PENDING_NO_DRIVER", pendingCount === 1);
  check("driverE has only one active assigned order", (await q(`SELECT count(*)::int n FROM customer_order WHERE delivery_user_id=$1 AND delivery_assignment_status='ASSIGNED'`, [driverE])).rows[0].n === 1);

  console.log("\n=== TEST F: real self-registration (registerDelivery) produces an ELIGIBLE, assignable delivery account after approval ===");
  const regPhone = `07${(Date.now() % 100000000)}`.slice(0, 11);
  const regOut = await deliveryService.registerDelivery({
    fullName: `${TAG}_selfreg`,
    phone: regPhone,
    pin: "1234",
    block: "A7",
    buildingNumber: "A701",
    apartment: "101",
    vehicleType: "sedan",
    carMake: "Toyota",
    carModel: "Corolla",
    carYear: 2020,
    plateNumber: "12345",
    analyticsConsentAccepted: true,
  });
  const regId = Number(regOut.user.id);
  const shape = await q(
    `SELECT u.role,
            u.delivery_account_approved,
            EXISTS(SELECT 1 FROM courier_profile cp WHERE cp.user_id=u.id) AS has_courier_profile,
            (SELECT driver_type FROM courier_profile cp WHERE cp.user_id=u.id) AS driver_type,
            EXISTS(SELECT 1 FROM taxi_captain_profile t WHERE t.user_id=u.id) AS has_taxi_profile
     FROM app_user u WHERE u.id=$1`, [regId]
  );
  const s = shape.rows[0];
  check("registered role == delivery", s.role === "delivery", `(got ${s.role})`);
  check("registered has courier_profile (app_driver)", s.has_courier_profile && s.driver_type === "app_driver", `(driver_type=${s.driver_type})`);
  check("registered has NO taxi_captain_profile", s.has_taxi_profile === false);
  check("registered starts pending (approved=FALSE)", s.delivery_account_approved === false);
  // pre-approval: must NOT be eligible even with fresh presence
  await freshPresence(regId);
  const orderPre = await makeOrder(merchantId, customer, "approved");
  await startPreparingAndRequestCourier({ ownerUserId: owner, orderId: orderPre, preferredCourierUserId: null });
  const rowPre = await orderRow(orderPre);
  check("pending (unapproved) account is NOT assigned", Number(rowPre.delivery_user_id || 0) !== regId, `(das=${rowPre.delivery_assignment_status}, driver=${rowPre.delivery_user_id})`);
  // admin approval: set approved=TRUE (mirrors approveDeliveryAccount) then it becomes eligible
  await q(`UPDATE app_user SET delivery_account_approved=TRUE WHERE id=$1`, [regId]);
  await freshPresence(regId);
  // make all other drivers ineligible by ending their presence, so this account is the only candidate
  await q(`UPDATE courier_presence SET is_online=FALSE WHERE courier_user_id <> $1 AND courier_user_id IN (SELECT id FROM app_user WHERE full_name LIKE '${TAG}%')`, [regId]);
  const orderPost = await makeOrder(merchantId, customer, "approved");
  const resPost = await startPreparingAndRequestCourier({ ownerUserId: owner, orderId: orderPost, preferredCourierUserId: null });
  const rowPost = await orderRow(orderPost);
  check("approved self-registered account IS auto-assigned", Number(rowPost.delivery_user_id || 0) === regId, `(das=${rowPost.delivery_assignment_status}, driver=${rowPost.delivery_user_id}, want ${regId})`);

  console.log("\n=== TEST G: order with a STALE open courier_assignment row (stuck-order repro) still auto-assigns ===");
  // Reproduce the 'stuck order' state: a leftover OPEN row (ended_at NULL) that
  // the open-order unique index would have made INSERT 23505 on.
  const driverG = await makeDriver(9);
  await freshPresence(driverG);
  await q(`UPDATE courier_presence SET is_online=FALSE WHERE courier_user_id <> $1 AND courier_user_id IN (SELECT id FROM app_user WHERE full_name LIKE '${TAG}%')`, [driverG]);
  const ghost = await makeUser("delivery", 91); // ghost courier holding a stale open row
  const orderG = await makeOrder(merchantId, customer, "approved");
  await q(
    `INSERT INTO courier_assignment (order_id, courier_user_id, assignment_type, status, requested_at, ended_at)
     VALUES ($1,$2,'broadcast','cancelled',NOW(),NULL)`,
    [orderG, ghost]
  );
  const staleBefore = await openAssignments(orderG);
  const resG = await startPreparingAndRequestCourier({ ownerUserId: owner, orderId: orderG, preferredCourierUserId: null });
  const rowG = await orderRow(orderG);
  const openG = await openAssignments(orderG);
  check("had a stale open row before", staleBefore.length === 1);
  check("order now ASSIGNED (no 23505 stuck)", rowG.delivery_assignment_status === "ASSIGNED", `(got ${rowG.delivery_assignment_status})`);
  check("assigned to the eligible driver", Number(rowG.delivery_user_id) === driverG);
  check("exactly one open assignment (stale closed)", openG.length === 1 && Number(openG[0].courier_user_id) === driverG, `(open=${openG.length})`);

  console.log("\n=== TEST H: coord-less idle heartbeat (no GPS) makes an 'offline' driver eligible + triggers recovery ===");
  const driverH = await makeDriver(20);
  await q(`UPDATE courier_profile SET availability_status='offline' WHERE user_id=$1`, [driverH]);
  // ensure only driverH can be the candidate
  await q(`UPDATE courier_presence SET is_online=FALSE WHERE courier_user_id IN (SELECT id FROM app_user WHERE full_name LIKE '${TAG}%') AND courier_user_id <> $1`, [driverH]);
  // clear leftover pending orders from earlier tests so orderH is the oldest/only pending
  await q(`UPDATE customer_order SET status='cancelled'::order_status, delivery_assignment_status='CANCELLED' WHERE customer_full_name LIKE '${TAG}%' AND delivery_assignment_status='PENDING_NO_DRIVER'`);
  const orderH = await makeOrder(merchantId, customer, "approved");
  const resHpending = await startPreparingAndRequestCourier({ ownerUserId: owner, orderId: orderH, preferredCourierUserId: null });
  check("order starts PENDING (offline driver, no presence)", resHpending.assignmentStatus === "PENDING_NO_DRIVER");
  // real service-level presence call with NO coordinates
  await courierUpsertPresence(driverH, { isOnline: true });
  const presRow = (await q(`SELECT is_online, latitude, longitude, updated_at, (updated_at >= NOW() - INTERVAL '90 seconds') AS fresh FROM courier_presence WHERE courier_user_id=$1`, [driverH])).rows[0];
  const availRow = (await q(`SELECT availability_status FROM courier_profile WHERE user_id=$1`, [driverH])).rows[0];
  check("presence row written without coordinates", presRow && presRow.is_online === true && presRow.latitude == null && presRow.longitude == null && presRow.fresh === true);
  check("availability flipped to online by heartbeat", availRow && String(availRow.availability_status).toLowerCase() === "online", `(got ${availRow?.availability_status})`);
  // recovery-on-heartbeat: the oldest pending order should now be assignable
  await requestDeliveryAssignmentRecovery({ limit: 5 });
  const rowH2 = await orderRow(orderH);
  check("pending order assigned after coord-less heartbeat", rowH2.delivery_assignment_status === "ASSIGNED" && Number(rowH2.delivery_user_id) === driverH, `(das=${rowH2.delivery_assignment_status}, driver=${rowH2.delivery_user_id}, want ${driverH})`);

  console.log(`\n=== RESULT: ${PASS} passed, ${FAIL} failed ===`);
  await cleanup();
  await pool.end();
  process.exit(FAIL === 0 ? 0 : 1);
}

main().catch(async (e) => {
  console.error("FATAL", e);
  try { await cleanup(); await pool.end(); } catch {}
  process.exit(2);
});
