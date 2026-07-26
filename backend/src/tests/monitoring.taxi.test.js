import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as taxiService from "../modules/taxi/taxi.service.js";
import * as monitoringRepo from "../modules/admin/monitoring.repo.js";

const phoneSalt = Math.floor(Math.random() * 1_000_000);
let phoneSeq = 0;
function makePhone() {
  phoneSeq += 1;
  return `07${String(Date.now() + phoneSeq + phoneSalt).slice(-9)}`;
}
function suffix() {
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

const userIds = [];
const rideIds = [];
const merchantIds = [];
const orderIds = [];
const serviceRequestIds = [];
const serviceOfferingIds = [];
const serviceProviderIds = [];
const serviceCategoryIds = [];
const realEstateListingIds = [];
const carListingIds = [];

async function makeUser(role) {
  const user = await createUser({
    fullName: `MON ${role}`,
    username: `mon_${suffix()}`.slice(0, 32),
    phone: makePhone(),
    pinHash: await hashPin("1234"),
    block: "A",
    buildingNumber: "1",
    apartment: "1",
    imageUrl: null,
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "mon_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
  const id = Number(user.id);
  userIds.push(id);
  return id;
}

async function makeRide({ customerId, captainId = null, status, cancelledNow = false, completedNow = false }) {
  const r = await q(
    `INSERT INTO taxi_ride_request
       (customer_user_id, assigned_captain_user_id, pickup_latitude, pickup_longitude,
        dropoff_latitude, dropoff_longitude, pickup_label, dropoff_label,
        proposed_fare_iqd, status,
        cancelled_at, completed_at)
     VALUES ($1,$2,33.31,44.36,33.32,44.37,'P','D',10000,$3,
        CASE WHEN $4 THEN NOW() ELSE NULL END,
        CASE WHEN $5 THEN NOW() ELSE NULL END)
     RETURNING id`,
    [customerId, captainId, status, cancelledNow, completedNow]
  );
  const id = Number(r.rows[0].id);
  rideIds.push(id);
  return id;
}

async function makeMerchant() {
  const r = await q(
    `INSERT INTO merchant (name, type, phone)
     VALUES ($1, 'restaurant', $2)
     RETURNING id`,
    [`MON Merchant ${suffix()}`, makePhone()]
  );
  const id = Number(r.rows[0].id);
  merchantIds.push(id);
  return id;
}

async function makeOrder({
  merchantId,
  customerId,
  deliveryUserId = null,
  status = "pending",
  deliveryAssignmentStatus = "NOT_REQUIRED",
  totalAmount = 10000,
}) {
  const r = await q(
    `INSERT INTO customer_order
       (merchant_id, customer_user_id, delivery_user_id, status,
        customer_full_name, customer_phone, customer_block, customer_building_number,
        customer_apartment, subtotal, delivery_fee, total_amount,
        delivery_assignment_status, completed_at, delivered_at, cancelled_at)
     VALUES ($1,$2,$3,$4::order_status,$5,$6,'A','1','1',$7,1000,$8,$9,
        CASE WHEN $4::text IN ('completed','received_by_customer') THEN NOW() ELSE NULL END,
        CASE WHEN $4::text IN ('delivered','delivered_by_courier') THEN NOW() ELSE NULL END,
        CASE WHEN $4::text IN ('cancelled','cancelled_by_customer','cancelled_by_store','cancelled_by_admin') THEN NOW() ELSE NULL END)
     RETURNING id`,
    [
      merchantId,
      customerId,
      deliveryUserId,
      status,
      `MON Customer ${suffix()}`,
      makePhone(),
      totalAmount - 1000,
      totalAmount,
      deliveryAssignmentStatus,
    ]
  );
  const id = Number(r.rows[0].id);
  orderIds.push(id);
  await q(
    `INSERT INTO order_item (order_id, product_name, unit_price, quantity, line_total)
     VALUES ($1, 'MON Item', 9000, 1, 9000)`,
    [id]
  );
  return id;
}

async function makeServiceCategory() {
  const r = await q(
    `INSERT INTO service_categories (level, name, sort_order)
     VALUES (1, $1, 999)
     RETURNING id`,
    [`MON Services ${suffix()}`]
  );
  const id = Number(r.rows[0].id);
  serviceCategoryIds.push(id);
  return id;
}

async function makeServiceProvider({ userId, categoryId }) {
  const r = await q(
    `INSERT INTO service_provider_profiles
       (user_id, business_name, main_category_id, phone, city, booking_policy,
        provider_approval_status)
     VALUES ($1,$2,$3,$4,'Baghdad','approval_required','approved')
     RETURNING id`,
    [userId, `MON Provider ${suffix()}`, categoryId, makePhone()]
  );
  const id = Number(r.rows[0].id);
  serviceProviderIds.push(id);
  return id;
}

async function makeServiceOffering({ providerId, categoryId }) {
  const r = await q(
    `INSERT INTO service_offerings
       (provider_id, main_category_id, name, execution_mode, moderation_status)
     VALUES ($1,$2,$3,'home','approved')
     RETURNING id`,
    [providerId, categoryId, `MON Offering ${suffix()}`]
  );
  const id = Number(r.rows[0].id);
  serviceOfferingIds.push(id);
  return id;
}

async function makeServiceRequest({
  customerId,
  providerId,
  offeringId,
  status = "pending",
}) {
  const r = await q(
    `INSERT INTO service_requests
       (request_code, customer_user_id, provider_id, offering_id, status,
        requested_execution_mode, city, area, final_price, completed_at)
     VALUES ($1,$2,$3,$4,$5::varchar,'home','Baghdad','Karrada',25000,
        CASE WHEN $5::text IN ('completed','COMPLETED') THEN NOW() ELSE NULL END)
     RETURNING id`,
    [`MON-${suffix()}`, customerId, providerId, offeringId, status]
  );
  const id = Number(r.rows[0].id);
  serviceRequestIds.push(id);
  return id;
}

async function makeRealEstateListing({ ownerId, status = "active" }) {
  const r = await q(
    `INSERT INTO real_estate_listing
       (owner_user_id, purpose, status, title, description, area_sqm, phone,
        price, city, block, sold_at, rented_at, archived_at)
     VALUES ($1,'sale',$2::varchar,$3,'MON description',120,$4,90000000,'Baghdad','A',
        CASE WHEN $2::text = 'sold' THEN NOW() ELSE NULL END,
        CASE WHEN $2::text = 'rented' THEN NOW() ELSE NULL END,
        CASE WHEN $2::text = 'archived' THEN NOW() ELSE NULL END)
     RETURNING id`,
    [ownerId, status, `MON Estate ${suffix()}`, makePhone()]
  );
  const id = Number(r.rows[0].id);
  realEstateListingIds.push(id);
  return id;
}

async function makeCarListing({ ownerId, status = "active" }) {
  const r = await q(
    `INSERT INTO car_listing
       (owner_user_id, status, title, brand, model, model_year, condition,
        price, city, phone, sold_at, archived_at)
     VALUES ($1,$2::varchar,$3,'Hyundai','Elantra',2023,'used',25000000,'Baghdad',$4,
        CASE WHEN $2::text = 'sold' THEN NOW() ELSE NULL END,
        CASE WHEN $2::text = 'archived' THEN NOW() ELSE NULL END)
     RETURNING id`,
    [ownerId, status, `MON Car ${suffix()}`, makePhone()]
  );
  const id = Number(r.rows[0].id);
  carListingIds.push(id);
  return id;
}

test.after(async () => {
  if (serviceRequestIds.length) {
    await q(`DELETE FROM service_reports WHERE target_type = 'request' AND target_id = ANY($1::bigint[])`, [
      serviceRequestIds,
    ]);
    await q(`DELETE FROM service_request_attachments WHERE request_id = ANY($1::bigint[])`, [
      serviceRequestIds,
    ]);
    await q(`DELETE FROM service_requests WHERE id = ANY($1::bigint[])`, [
      serviceRequestIds,
    ]);
  }
  if (serviceOfferingIds.length) {
    await q(`DELETE FROM service_offerings WHERE id = ANY($1::bigint[])`, [
      serviceOfferingIds,
    ]);
  }
  if (serviceProviderIds.length) {
    await q(`DELETE FROM service_provider_profiles WHERE id = ANY($1::bigint[])`, [
      serviceProviderIds,
    ]);
  }
  if (serviceCategoryIds.length) {
    await q(`DELETE FROM service_categories WHERE id = ANY($1::bigint[])`, [
      serviceCategoryIds,
    ]);
  }
  if (realEstateListingIds.length) {
    await q(`DELETE FROM real_estate_listing_media WHERE listing_id = ANY($1::bigint[])`, [
      realEstateListingIds,
    ]);
    await q(`DELETE FROM real_estate_saved_listing WHERE listing_id = ANY($1::bigint[])`, [
      realEstateListingIds,
    ]);
    await q(`DELETE FROM real_estate_listing WHERE id = ANY($1::bigint[])`, [
      realEstateListingIds,
    ]);
  }
  if (carListingIds.length) {
    await q(`DELETE FROM car_listing_media WHERE listing_id = ANY($1::bigint[])`, [
      carListingIds,
    ]);
    await q(`DELETE FROM car_listing WHERE id = ANY($1::bigint[])`, [
      carListingIds,
    ]);
  }
  if (orderIds.length) {
    await q(`DELETE FROM courier_assignment WHERE order_id = ANY($1::bigint[])`, [
      orderIds,
    ]);
    await q(`DELETE FROM order_item WHERE order_id = ANY($1::bigint[])`, [orderIds]);
    await q(`DELETE FROM customer_order WHERE id = ANY($1::bigint[])`, [orderIds]);
  }
  if (rideIds.length) {
    await q(`DELETE FROM taxi_ride_request WHERE id = ANY($1::bigint[])`, [rideIds]);
  }
  if (userIds.length) {
    await q(`DELETE FROM courier_presence WHERE courier_user_id = ANY($1::bigint[])`, [
      userIds,
    ]);
    await q(`DELETE FROM courier_profile WHERE user_id = ANY($1::bigint[])`, [userIds]);
  }
  if (merchantIds.length) {
    await q(`DELETE FROM merchant WHERE id = ANY($1::bigint[])`, [merchantIds]);
  }
  if (userIds.length) {
    await q(`DELETE FROM app_user WHERE id = ANY($1::bigint[])`, [userIds]);
  }
});

test("taxi monitoring counters reflect newly created rides (delta-based)", async () => {
  const before = await taxiService.getTaxiMonitoringCounters();

  const customerId = await makeUser("user");
  const captainId = await makeUser("taxi_captain");

  await makeRide({ customerId, captainId, status: "ride_started" }); // active
  await makeRide({ customerId, captainId, status: "captain_assigned" }); // active
  await makeRide({ customerId, status: "searching" }); // searching
  const cancelledRide = await makeRide({
    customerId,
    captainId,
    status: "cancelled",
    cancelledNow: true,
  }); // cancelled today
  await makeRide({
    customerId,
    captainId,
    status: "completed",
    completedNow: true,
  }); // completed today

  // open emergency on the active ride
  await taxiService.getTaxiMonitoringCounters(); // warm
  const emRide = await makeRide({ customerId, captainId, status: "ride_started" });
  await q(
    `INSERT INTO taxi_ride_emergency
       (ride_request_id, reported_by_user_id, reported_by_role, ride_status_at_report, category)
     VALUES ($1,$2,'customer','ride_started','safety')`,
    [emRide, customerId]
  );

  const after = await taxiService.getTaxiMonitoringCounters();

  // Deltas use >= so the assertions stay correct even when other test files
  // share this QA database and insert rides concurrently (see the project's
  // per-file-db isolation note). They still fail if a counter under-counts.
  assert.ok(after.active - before.active >= 3, "active +>=3 (two + emergency ride)");
  assert.ok(after.searching - before.searching >= 1, "searching +>=1");
  assert.ok(after.cancelledToday - before.cancelledToday >= 1, "cancelledToday +>=1");
  assert.ok(after.completedToday - before.completedToday >= 1, "completedToday +>=1");
  assert.ok(
    after.openEmergencies - before.openEmergencies >= 1,
    "openEmergencies +>=1"
  );
  assert.ok(cancelledRide > 0);
});

test("taxi monitoring list is server-paginated and filterable by status", async () => {
  const customerId = await makeUser("user");
  const captainId = await makeUser("taxi_captain");
  await makeRide({ customerId, captainId, status: "captain_arriving" });

  const page = await taxiService.listRidesForMonitoring({
    status: "captain_arriving",
    limit: 5,
    offset: 0,
  });
  assert.ok(Array.isArray(page.items));
  assert.equal(page.limit, 5);
  assert.equal(page.offset, 0);
  assert.ok(typeof page.total === "number");
  for (const item of page.items) {
    assert.equal(item.status, "captain_arriving");
  }
});

test("order monitoring counters return a numeric shape", async () => {
  const counters = await monitoringRepo.getOrderMonitoringCounters();
  for (const key of ["active", "completedToday", "cancelledToday"]) {
    assert.equal(typeof counters[key], "number", `${key} should be numeric`);
    assert.ok(counters[key] >= 0);
  }
});

test("order monitoring counters and list use real order rows", async () => {
  const before = await monitoringRepo.getOrderMonitoringCounters();
  const customerId = await makeUser("user");
  const courierId = await makeUser("delivery");
  const merchantId = await makeMerchant();

  await makeOrder({
    merchantId,
    customerId,
    status: "preparing",
  });
  await makeOrder({
    merchantId,
    customerId,
    deliveryUserId: courierId,
    status: "delivered",
    deliveryAssignmentStatus: "COMPLETED",
  });
  await makeOrder({
    merchantId,
    customerId,
    status: "cancelled_by_customer",
    deliveryAssignmentStatus: "CANCELLED",
  });

  const after = await monitoringRepo.getOrderMonitoringCounters();
  assert.ok(after.active - before.active >= 1, "active order counted");
  assert.ok(
    after.completedToday - before.completedToday >= 1,
    "completed today counted"
  );
  assert.ok(
    after.cancelledToday - before.cancelledToday >= 1,
    "cancelled today counted"
  );

  const page = await monitoringRepo.listOrdersForMonitoring({
    status: "preparing",
    search: "MON Customer",
    limit: 5,
    offset: 0,
  });
  assert.equal(page.limit, 5);
  assert.equal(page.offset, 0);
  assert.ok(page.total >= 1);
  for (const item of page.items) {
    assert.equal(item.status, "preparing");
    assert.equal(typeof item.item_count, "number");
  }
});

test("delivery monitoring counters and courier list use presence freshness", async () => {
  const before = await monitoringRepo.getDeliveryMonitoringCounters();
  const customerId = await makeUser("user");
  const courierId = await makeUser("delivery");
  const merchantId = await makeMerchant();
  const orderId = await makeOrder({
    merchantId,
    customerId,
    deliveryUserId: courierId,
    status: "on_the_way",
    deliveryAssignmentStatus: "ASSIGNED",
  });
  await q(
    `INSERT INTO courier_profile
       (user_id, availability_status, coverage_block, vehicle_type, active_status)
     VALUES ($1, 'online', 'A', 'bike', TRUE)
     ON CONFLICT (user_id) DO UPDATE
       SET availability_status='online', coverage_block='A', active_status=TRUE`,
    [courierId]
  );
  await q(
    `INSERT INTO courier_presence
       (courier_user_id, current_order_id, is_online, updated_at, recorded_at)
     VALUES ($1,$2,TRUE,NOW(),NOW())
     ON CONFLICT (courier_user_id) DO UPDATE
       SET current_order_id=EXCLUDED.current_order_id,
           is_online=TRUE,
           updated_at=NOW(),
           recorded_at=NOW()`,
    [courierId, orderId]
  );
  await q(
    `INSERT INTO courier_assignment
       (order_id, courier_user_id, status, assigned_at, requested_at)
     VALUES ($1,$2,'assigned',NOW(),NOW())`,
    [orderId, courierId]
  );

  const after = await monitoringRepo.getDeliveryMonitoringCounters();
  assert.ok(after.available - before.available >= 1, "available courier counted");
  assert.ok(after.onlineFresh - before.onlineFresh >= 1, "fresh presence counted");
  assert.ok(after.active - before.active >= 1, "active delivery counted");

  const page = await monitoringRepo.listCouriersForMonitoring({
    status: "fresh_online",
    search: "MON delivery",
    limit: 10,
    offset: 0,
  });
  assert.equal(page.limit, 10);
  assert.ok(page.total >= 1);
  assert.ok(page.items.some((item) => Number(item.user_id) === courierId));
});

test("services and marketplace monitoring use real rows", async () => {
  const serviceBefore = await monitoringRepo.getServiceMonitoringCounters();
  const estateBefore = await monitoringRepo.getRealEstateMonitoringCounters();
  const carBefore = await monitoringRepo.getCarMonitoringCounters();

  const customerId = await makeUser("user");
  const providerUserId = await makeUser("service_provider");
  const ownerId = await makeUser("user");

  const categoryId = await makeServiceCategory();
  const providerId = await makeServiceProvider({
    userId: providerUserId,
    categoryId,
  });
  const offeringId = await makeServiceOffering({ providerId, categoryId });
  await makeServiceRequest({
    customerId,
    providerId,
    offeringId,
    status: "pending",
  });
  await makeServiceRequest({
    customerId,
    providerId,
    offeringId,
    status: "completed",
  });

  await makeRealEstateListing({ ownerId, status: "active" });
  await makeRealEstateListing({ ownerId, status: "sold" });
  await makeCarListing({ ownerId, status: "active" });
  await makeCarListing({ ownerId, status: "sold" });

  const serviceAfter = await monitoringRepo.getServiceMonitoringCounters();
  const estateAfter = await monitoringRepo.getRealEstateMonitoringCounters();
  const carAfter = await monitoringRepo.getCarMonitoringCounters();

  assert.ok(serviceAfter.active - serviceBefore.active >= 1, "active service request counted");
  assert.ok(
    serviceAfter.completedToday - serviceBefore.completedToday >= 1,
    "completed service request counted"
  );
  assert.ok(estateAfter.active - estateBefore.active >= 1, "active real estate counted");
  assert.ok(
    estateAfter.completedToday - estateBefore.completedToday >= 1,
    "sold real estate counted"
  );
  assert.ok(carAfter.active - carBefore.active >= 1, "active car counted");
  assert.ok(carAfter.completedToday - carBefore.completedToday >= 1, "sold car counted");

  const servicePage = await monitoringRepo.listServiceRequestsForMonitoring({
    status: "pending",
    search: "MON",
    limit: 5,
    offset: 0,
  });
  assert.equal(servicePage.limit, 5);
  assert.ok(servicePage.total >= 1);
  assert.ok(servicePage.items.every((item) => item.status === "pending"));
  assert.ok(!("phone" in servicePage.items[0]), "service DTO does not expose phone");

  const estatePage = await monitoringRepo.listRealEstateListingsForMonitoring({
    status: "active",
    search: "MON Estate",
    limit: 5,
    offset: 0,
  });
  assert.ok(estatePage.total >= 1);
  assert.ok(estatePage.items.every((item) => item.status === "active"));
  assert.ok(!("phone" in estatePage.items[0]), "real estate DTO does not expose phone");

  const carPage = await monitoringRepo.listCarListingsForMonitoring({
    status: "active",
    search: "Hyundai",
    limit: 5,
    offset: 0,
  });
  assert.ok(carPage.total >= 1);
  assert.ok(carPage.items.every((item) => item.status === "active"));
  assert.ok(!("phone" in carPage.items[0]), "car DTO does not expose phone");
});
