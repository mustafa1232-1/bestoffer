import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createCustomerAddress, createUser } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as hrRepo from "../modules/hr/hr.repo.js";
import * as ownerRepo from "../modules/owner/owner.repo.js";
import * as ownerService from "../modules/owner/owner.service.js";
import * as ordersService from "../modules/orders/orders.service.js";
import * as ordersRepo from "../modules/orders/orders.repo.js";
import * as servicesRepo from "../modules/services/services.repo.js";
import * as servicesService from "../modules/services/services.service.js";

function makeSuffix(prefix = "") {
  return `${prefix}${Date.now().toString(36)}${Math.random()
    .toString(36)
    .slice(2, 8)}`;
}

function makePhone(seed = 0) {
  const tail = String(Date.now() + Number(seed || 0)).slice(-9);
  return `07${tail}`;
}

function makeUsername(prefix = "user") {
  return `${prefix}_${makeSuffix()}`.slice(0, 32);
}

async function createTestUser({
  fullName,
  phone,
  role,
  block = "A",
  buildingNumber = "101",
  apartment = "1",
}) {
  const pinHash = await hashPin("1234");
  return createUser({
    fullName,
    username: makeUsername("user"),
    phone,
    pinHash,
    block,
    buildingNumber,
    apartment,
    imageUrl: null,
    role,
    analyticsConsentGranted: true,
    analyticsConsentVersion: "notification_e2e_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
}

async function cleanupWorkspace({
  merchantIds = [],
  providerIds = [],
  userIds = [],
  orderIds = [],
}) {
  const merchants = merchantIds
    .map((id) => Number(id))
    .filter((id) => Number.isInteger(id) && id > 0);
  const providers = providerIds
    .map((id) => Number(id))
    .filter((id) => Number.isInteger(id) && id > 0);
  const users = userIds
    .map((id) => Number(id))
    .filter((id) => Number.isInteger(id) && id > 0);
  const orders = orderIds
    .map((id) => Number(id))
    .filter((id) => Number.isInteger(id) && id > 0);

  async function deleteIfTableExists(tableName, sql, params) {
    const existsResult = await q(
      "SELECT to_regclass($1)::text AS table_name",
      [`public.${tableName}`]
    );
    if (!existsResult.rows[0]?.table_name) return;
    await q(sql, params);
  }

  if (orders.length || merchants.length || users.length) {
    await q(
      `DELETE FROM app_notification
       WHERE (merchant_id = ANY($1::bigint[]))
          OR (order_id = ANY($2::bigint[]))
          OR (user_id = ANY($3::bigint[]))`,
      [merchants, orders, users]
    );
  }

  if (orders.length || merchants.length) {
    await q(
      `DELETE FROM customer_order
       WHERE id = ANY($1::bigint[])
          OR merchant_id = ANY($2::bigint[])`,
      [orders, merchants]
    );
  }

  if (providers.length) {
    await deleteIfTableExists(
      "service_request_status_history",
      `DELETE FROM service_request_status_history
       WHERE request_id IN (
         SELECT id FROM service_requests
         WHERE provider_id = ANY($1::bigint[])
       )`,
      [providers]
    );
    await deleteIfTableExists(
      "service_request_quotes",
      `DELETE FROM service_request_quotes
       WHERE request_id IN (
         SELECT id FROM service_requests
         WHERE provider_id = ANY($1::bigint[])
       )`,
      [providers]
    );
    await deleteIfTableExists(
      "service_request_attachments",
      `DELETE FROM service_request_attachments
       WHERE request_id IN (
         SELECT id FROM service_requests
         WHERE provider_id = ANY($1::bigint[])
       )`,
      [providers]
    );
    await deleteIfTableExists(
      "service_offering_media",
      `DELETE FROM service_offering_media
       WHERE offering_id IN (
         SELECT id FROM service_offerings
         WHERE provider_id = ANY($1::bigint[])
       )`,
      [providers]
    );
    await deleteIfTableExists(
      "service_offering_pricing",
      `DELETE FROM service_offering_pricing
       WHERE offering_id IN (
         SELECT id FROM service_offerings
         WHERE provider_id = ANY($1::bigint[])
       )`,
      [providers]
    );
    await deleteIfTableExists(
      "service_requests",
      `DELETE FROM service_requests
       WHERE provider_id = ANY($1::bigint[])`,
      [providers]
    );
    await deleteIfTableExists(
      "service_offerings",
      `DELETE FROM service_offerings
       WHERE provider_id = ANY($1::bigint[])`,
      [providers]
    );
  }

  if (merchants.length) {
    await q(
      `DELETE FROM merchant_employee_profile
       WHERE merchant_id = ANY($1::bigint[])`,
      [merchants]
    );
    await q(
      `DELETE FROM merchant_category
       WHERE merchant_id = ANY($1::bigint[])`,
      [merchants]
    );
    await q(
      `DELETE FROM product
       WHERE merchant_id = ANY($1::bigint[])`,
      [merchants]
    );
    await q(
      `DELETE FROM merchant
       WHERE id = ANY($1::bigint[])`,
      [merchants]
    );
  }

  if (providers.length) {
    await q(
      `DELETE FROM service_provider_employee_profile
       WHERE provider_id = ANY($1::bigint[])`,
      [providers]
    );
    await q(
      `DELETE FROM service_provider_profiles
       WHERE id = ANY($1::bigint[])`,
      [providers]
    );
  }

  if (users.length) {
    await q(
      `DELETE FROM app_user
       WHERE id = ANY($1::bigint[])`,
      [users]
    );
  }
}

async function createApprovedMerchant(ownerUserId, name) {
  const result = await q(
    `INSERT INTO merchant
      (
        name,
        type,
        activity_type,
        description,
        phone,
        owner_user_id,
        is_open,
        is_approved,
        approval_status,
        service_flags_json,
        supports_chat,
        supports_attachments,
        supports_pharmacy_workflow,
        badges_json
      )
     VALUES ($1,$2,$3,$4,$5,$6,TRUE,TRUE,'approved','{}'::jsonb,FALSE,FALSE,FALSE,'[]'::jsonb)
     RETURNING *`,
    [
      name,
      "market",
      "supermarket",
      "Notification test store",
      makePhone(1),
      Number(ownerUserId),
    ]
  );
  return result.rows[0];
}

async function createApprovedProvider(ownerUserId, name) {
  return servicesRepo.createProviderProfile({
    userId: ownerUserId,
    dto: {
      businessName: name,
      mainCategoryId: null,
      bio: "Notification test provider",
      phone: makePhone(2),
      whatsappPhone: null,
      city: "Baghdad",
      area: "Center",
      addressLine: "Service street",
      servesAtHome: true,
      servesAtShop: false,
      servesRemote: false,
      hasEmergencyService: false,
      bookingPolicy: "approval_required",
      pricingMode: "mixed",
      yearsExperience: 4,
      hasTeam: false,
      teamSize: null,
      acceptsCash: true,
      acceptsElectronic: false,
      averageResponseMinutes: 30,
      available247: false,
      providerGender: null,
      languages: ["ar"],
      areas: [],
      availabilityRules: [],
    },
    assets: {
      logoUrl: null,
      coverImageUrl: null,
    },
    moderation: {
      approvalStatus: "approved",
      approvedByUserId: ownerUserId,
      approvedAt: new Date().toISOString(),
    },
  });
}

async function latestNotificationsByType({ userId = null, orderId = null, type }) {
  const conditions = ["type = $1"];
  const params = [String(type)];
  let index = 2;
  if (userId != null) {
    conditions.push(`user_id = $${index}`);
    params.push(Number(userId));
    index += 1;
  }
  if (orderId != null) {
    conditions.push(`order_id = $${index}`);
    params.push(Number(orderId));
  }
  const result = await q(
    `SELECT
       id,
       user_id,
       type,
       order_id,
       payload,
       created_at
     FROM app_notification
     WHERE ${conditions.join(" AND ")}
     ORDER BY created_at DESC, id DESC`,
    params
  );
  return result.rows;
}

async function waitForNotificationCount({
  userId = null,
  orderId = null,
  type,
  expectedCount,
  timeoutMs = 3000,
  intervalMs = 50,
}) {
  const deadline = Date.now() + Number(timeoutMs || 0);
  let lastRows = [];
  while (Date.now() <= deadline) {
    lastRows = await latestNotificationsByType({ userId, orderId, type });
    if (lastRows.length === Number(expectedCount)) {
      return lastRows;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return lastRows;
}

test("store order notifications target the owner and permitted employees, and delivery reassignment notifies the right couriers", async () => {
  const trackedIds = {
    merchantIds: [],
    providerIds: [],
    userIds: [],
    orderIds: [],
  };

  try {
    const storeOwner = await createTestUser({
      fullName: `Store Owner ${makeSuffix("store-owner-")}`,
      phone: makePhone(10),
      role: "owner",
    });
    trackedIds.userIds.push(Number(storeOwner.id));

    const merchant = await createApprovedMerchant(
      storeOwner.id,
      `Notifications Store ${makeSuffix("merchant-")}`
    );
    trackedIds.merchantIds.push(Number(merchant.id));

    const customer = await createTestUser({
      fullName: `Store Customer ${makeSuffix("customer-")}`,
      phone: makePhone(11),
      role: "user",
    });
    trackedIds.userIds.push(Number(customer.id));

    const customerAddress = await createCustomerAddress(customer.id, {
      label: "Home",
      city: "Baghdad",
      area: "Center",
      block: "A1",
      buildingNumber: "12",
      apartment: "3",
      latitude: 33.3152,
      longitude: 44.3661,
      isDefault: true,
    });

    const storeEmployeeAllowed = await createTestUser({
      fullName: `Store Employee Allowed ${makeSuffix("se-")}`,
      phone: makePhone(12),
      role: "owner",
    });
    const storeEmployeeDisabled = await createTestUser({
      fullName: `Store Employee Disabled ${makeSuffix("sed-")}`,
      phone: makePhone(13),
      role: "owner",
    });
    const storeEmployeeNoPerm = await createTestUser({
      fullName: `Store Employee No Perm ${makeSuffix("sen-")}`,
      phone: makePhone(14),
      role: "owner",
    });
    trackedIds.userIds.push(
      Number(storeEmployeeAllowed.id),
      Number(storeEmployeeDisabled.id),
      Number(storeEmployeeNoPerm.id)
    );

    await hrRepo.upsertEmployeeProfile({
      merchantId: merchant.id,
      employeeUserId: Number(storeEmployeeAllowed.id),
      roleTag: "cashier",
      displayName: "Allowed Employee",
      contactEmail: "allowed@example.com",
      employmentType: "full_time",
      baseSalary: 0,
      currency: "IQD",
      workDaysPerWeek: 6,
      shiftStartTime: "09:00",
      shiftEndTime: "17:00",
      joinedAt: new Date().toISOString(),
      isActive: true,
      archivedAt: null,
      notes: null,
      permissions: ["view_orders"],
      invitedByUserId: storeOwner.id,
      updatedByUserId: storeOwner.id,
    });
    await hrRepo.upsertEmployeeProfile({
      merchantId: merchant.id,
      employeeUserId: Number(storeEmployeeDisabled.id),
      roleTag: "cashier",
      displayName: "Disabled Employee",
      contactEmail: "disabled@example.com",
      employmentType: "full_time",
      baseSalary: 0,
      currency: "IQD",
      workDaysPerWeek: 6,
      shiftStartTime: "09:00",
      shiftEndTime: "17:00",
      joinedAt: new Date().toISOString(),
      isActive: false,
      archivedAt: null,
      notes: null,
      permissions: ["view_orders"],
      invitedByUserId: storeOwner.id,
      updatedByUserId: storeOwner.id,
    });
    await hrRepo.upsertEmployeeProfile({
      merchantId: merchant.id,
      employeeUserId: Number(storeEmployeeNoPerm.id),
      roleTag: "cashier",
      displayName: "No Permission Employee",
      contactEmail: "noperm@example.com",
      employmentType: "full_time",
      baseSalary: 0,
      currency: "IQD",
      workDaysPerWeek: 6,
      shiftStartTime: "09:00",
      shiftEndTime: "17:00",
      joinedAt: new Date().toISOString(),
      isActive: true,
      archivedAt: null,
      notes: null,
      permissions: [],
      invitedByUserId: storeOwner.id,
      updatedByUserId: storeOwner.id,
    });

    const category = await ownerRepo.createOwnerCategory(storeOwner.id, {
      name: "Groceries",
      sortOrder: 1,
      catalogType: "grocery",
    });
    const product = await ownerRepo.createOwnerProduct(storeOwner.id, {
      categoryId: Number(category.id),
      name: "Milk",
      description: "Notification test product",
      price: 1000,
      discountedPrice: null,
      imageUrl: null,
      freeDelivery: false,
      offerLabel: null,
      isAvailable: true,
      unavailableReason: null,
      unavailableUntil: null,
      requiresPrescription: false,
      requiresReview: false,
      sortOrder: 1,
    });
    assert.ok(product);

    const order = await ordersService.createOrder(customer.id, {
      merchantId: merchant.id,
      addressId: customerAddress.id,
      items: [{ productId: Number(product.id), quantity: 1 }],
    });
    trackedIds.orderIds.push(Number(order.id));

    const orderNotifications = await waitForNotificationCount({
      orderId: Number(order.id),
      type: "owner_new_order",
      expectedCount: 2,
    });
    assert.deepEqual(
      orderNotifications.map((row) => Number(row.user_id)).sort((a, b) => a - b),
      [Number(storeOwner.id), Number(storeEmployeeAllowed.id)]
    );
    assert.equal(
      orderNotifications.every(
        (row) => row.payload?.target === "merchant_order_details"
      ),
      true
    );
    assert.equal(
      Number(
        (
          await q(
            `SELECT COUNT(*)::int AS count
             FROM app_notification
             WHERE order_id = $1
               AND user_id = $2
               AND type = 'owner_new_order'`,
            [Number(order.id), Number(storeEmployeeDisabled.id)]
          )
        ).rows[0].count
      ),
      0
    );
    assert.equal(
      Number(
        (
          await q(
            `SELECT COUNT(*)::int AS count
             FROM app_notification
             WHERE order_id = $1
               AND user_id = $2
               AND type = 'owner_new_order'`,
            [Number(order.id), Number(storeEmployeeNoPerm.id)]
          )
        ).rows[0].count
      ),
      0
    );

    const deliveryA = await createTestUser({
      fullName: `Courier A ${makeSuffix("courier-a-")}`,
      phone: makePhone(15),
      role: "delivery",
    });
    const deliveryB = await createTestUser({
      fullName: `Courier B ${makeSuffix("courier-b-")}`,
      phone: makePhone(16),
      role: "delivery",
    });
    trackedIds.userIds.push(Number(deliveryA.id), Number(deliveryB.id));

    await ordersRepo.ensureDeliveryAccountApproved(deliveryA.id);
    await ordersRepo.ensureDeliveryAccountApproved(deliveryB.id);

    await ownerService.updateOrderStatus(storeOwner.id, order.id, "approved");
    await ownerService.assignDelivery(
      storeOwner.id,
      order.id,
      Number(deliveryA.id),
      "platform_delivery"
    );
    await ownerService.assignDelivery(
      storeOwner.id,
      order.id,
      Number(deliveryB.id),
      "platform_delivery"
    );
    await ownerService.assignDelivery(
      storeOwner.id,
      order.id,
      null,
      "merchant_delivery"
    );

    const deliveryANotifications = await latestNotificationsByType({
      userId: deliveryA.id,
      type: "delivery_assigned_by_owner",
    });
    assert.equal(deliveryANotifications.length, 1);
    assert.equal(deliveryANotifications[0].payload?.target, "delivery_orders");

    const deliveryAReassignNotifications = await latestNotificationsByType({
      userId: deliveryA.id,
      type: "delivery_order_reassigned",
    });
    assert.equal(deliveryAReassignNotifications.length, 1);
    assert.equal(
      deliveryAReassignNotifications[0].payload?.target,
      "courier_notifications"
    );

    const deliveryBAssignedNotifications = await latestNotificationsByType({
      userId: deliveryB.id,
      type: "delivery_assigned_by_owner",
    });
    assert.equal(deliveryBAssignedNotifications.length, 1);
    const deliveryBRemovedNotifications = await latestNotificationsByType({
      userId: deliveryB.id,
      type: "delivery_order_removed",
    });
    assert.equal(deliveryBRemovedNotifications.length, 1);
    assert.equal(
      deliveryBRemovedNotifications[0].payload?.target,
      "courier_notifications"
    );
  } finally {
    await cleanupWorkspace(trackedIds);
  }
});

test("service request notifications target the provider owner and permitted employees", async () => {
  const trackedIds = {
    merchantIds: [],
    providerIds: [],
    userIds: [],
    orderIds: [],
  };

  try {
    const providerOwner = await createTestUser({
      fullName: `Provider Owner ${makeSuffix("provider-owner-")}`,
      phone: makePhone(31),
      role: "service_provider",
    });
    trackedIds.userIds.push(Number(providerOwner.id));

    const provider = await createApprovedProvider(
      providerOwner.id,
      `Notifications Provider ${makeSuffix("provider-")}`
    );
    trackedIds.providerIds.push(Number(provider.id));

    const providerEmployeeAllowed = await createTestUser({
      fullName: `Provider Employee Allowed ${makeSuffix("pea-")}`,
      phone: makePhone(32),
      role: "service_provider",
    });
    const providerEmployeeDisabled = await createTestUser({
      fullName: `Provider Employee Disabled ${makeSuffix("ped-")}`,
      phone: makePhone(33),
      role: "service_provider",
    });
    const providerEmployeeNoPerm = await createTestUser({
      fullName: `Provider Employee No Perm ${makeSuffix("pen-")}`,
      phone: makePhone(34),
      role: "service_provider",
    });
    trackedIds.userIds.push(
      Number(providerEmployeeAllowed.id),
      Number(providerEmployeeDisabled.id),
      Number(providerEmployeeNoPerm.id)
    );

    await servicesRepo.upsertProviderEmployeeProfile({
      providerId: provider.id,
      employeeUserId: Number(providerEmployeeAllowed.id),
      roleTag: "staff",
      displayName: "Allowed Provider Employee",
      contactEmail: "allowed-provider@example.com",
      permissions: ["view_service_requests"],
      isActive: true,
      archivedAt: null,
      notes: null,
      invitedByUserId: providerOwner.id,
      updatedByUserId: providerOwner.id,
    });
    await servicesRepo.upsertProviderEmployeeProfile({
      providerId: provider.id,
      employeeUserId: Number(providerEmployeeDisabled.id),
      roleTag: "staff",
      displayName: "Disabled Provider Employee",
      contactEmail: "disabled-provider@example.com",
      permissions: ["view_service_requests"],
      isActive: false,
      archivedAt: null,
      notes: null,
      invitedByUserId: providerOwner.id,
      updatedByUserId: providerOwner.id,
    });
    await servicesRepo.upsertProviderEmployeeProfile({
      providerId: provider.id,
      employeeUserId: Number(providerEmployeeNoPerm.id),
      roleTag: "staff",
      displayName: "No Perm Provider Employee",
      contactEmail: "noperm-provider@example.com",
      permissions: [],
      isActive: true,
      archivedAt: null,
      notes: null,
      invitedByUserId: providerOwner.id,
      updatedByUserId: providerOwner.id,
    });

    const offering = await servicesRepo.createOfferingForProvider({
      userId: providerOwner.id,
      dto: {
        name: "Service Notification Test Offering",
        description: "Notification test offering",
        executionMode: "both",
        requiresSchedule: false,
        requiresProviderApproval: false,
        hasFixedPrice: false,
        pricingOptions: [],
      },
      mediaUrls: [],
    });
    assert.ok(offering);

    const customer = await createTestUser({
      fullName: `Service Customer ${makeSuffix("service-customer-")}`,
      phone: makePhone(35),
      role: "user",
    });
    trackedIds.userIds.push(Number(customer.id));

    const request = await servicesService.createServiceRequest({
      userId: customer.id,
      dto: {
        providerId: Number(provider.id),
        offeringId: Number(offering.id),
        addressLine: "Notification street 1",
        city: "Baghdad",
        area: "Center",
        requiresHomeService: true,
      },
    });
    assert.ok(request);

    const requestNotifications = await q(
      `SELECT user_id, payload
       FROM app_notification
       WHERE type = 'services.request.created'
         AND payload->>'requestId' = $1
       ORDER BY user_id ASC`,
      [String(request.id)]
    );
    assert.equal(requestNotifications.rowCount, 2);
    assert.deepEqual(
      requestNotifications.rows.map((row) => Number(row.user_id)),
      [Number(providerOwner.id), Number(providerEmployeeAllowed.id)]
    );
    assert.equal(
      requestNotifications.rows.every(
        (row) => row.payload?.target === "service_request_details"
      ),
      true
    );
    assert.equal(
      Number(
        (
          await q(
            `SELECT COUNT(*)::int AS count
             FROM app_notification
             WHERE type = 'services.request.created'
               AND payload->>'requestId' = $1
               AND user_id = $2`,
            [String(request.id), Number(providerEmployeeDisabled.id)]
          )
        ).rows[0].count
      ),
      0
    );
    assert.equal(
      Number(
        (
          await q(
            `SELECT COUNT(*)::int AS count
             FROM app_notification
             WHERE type = 'services.request.created'
               AND payload->>'requestId' = $1
               AND user_id = $2`,
            [String(request.id), Number(providerEmployeeNoPerm.id)]
          )
        ).rows[0].count
      ),
      0
    );
  } finally {
    await cleanupWorkspace(trackedIds);
  }
});
