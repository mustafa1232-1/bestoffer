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
import * as jobsService from "../modules/jobs/jobs.service.js";

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
      "service_pricing_options",
      `DELETE FROM service_pricing_options
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

async function getFirstServiceCategoryPair(createdByUserId = null) {
  const result = await q(
    `SELECT
       parent.id AS main_category_id,
       child.id AS subcategory_id
     FROM service_categories parent
     JOIN service_categories child ON child.parent_id = parent.id
     WHERE parent.is_active = TRUE
       AND parent.is_public = TRUE
       AND child.is_active = TRUE
       AND child.is_public = TRUE
     ORDER BY parent.sort_order ASC, child.sort_order ASC, parent.id ASC, child.id ASC
     LIMIT 1`
  );
  const row = result.rows[0] || null;
  if (row?.main_category_id && row?.subcategory_id) {
    return {
      mainCategoryId: Number(row.main_category_id),
      subcategoryId: Number(row.subcategory_id),
    };
  }
  const fallback = await q(
    `SELECT id
     FROM service_categories
     WHERE is_active = TRUE
       AND is_public = TRUE
     ORDER BY level ASC, sort_order ASC, id ASC
     LIMIT 2`
  );
  if (fallback.rows.length >= 2) {
    return {
      mainCategoryId: Number(fallback.rows[0].id),
      subcategoryId: Number(fallback.rows[1].id),
    };
  }

  const rootName = `Phase 2A Services Root ${makeSuffix("svc-root-")}`;
  const childName = `Phase 2A Services Child ${makeSuffix("svc-child-")}`;
  const rootInsert = await q(
    `INSERT INTO service_categories
      (
        parent_id,
        level,
        name,
        sort_order,
        is_active,
        is_public,
        created_by_user_id,
        created_at,
        updated_at
      )
     VALUES (NULL,1,$1,1,TRUE,TRUE,$2,NOW(),NOW())
     RETURNING id`,
    [rootName, createdByUserId == null ? null : Number(createdByUserId)]
  );
  const childInsert = await q(
    `INSERT INTO service_categories
      (
        parent_id,
        level,
        name,
        sort_order,
        is_active,
        is_public,
        created_by_user_id,
        created_at,
        updated_at
      )
     VALUES ($1,2,$2,1,TRUE,TRUE,$3,NOW(),NOW())
     RETURNING id`,
    [
      Number(rootInsert.rows[0].id),
      childName,
      createdByUserId == null ? null : Number(createdByUserId),
    ]
  );
  return {
    mainCategoryId: Number(rootInsert.rows[0].id),
    subcategoryId: Number(childInsert.rows[0].id),
  };
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

test("services marketplace request and quote lifecycle keeps authz and notifications intact", async () => {
  const trackedIds = {
    merchantIds: [],
    providerIds: [],
    userIds: [],
    orderIds: [],
  };

  try {
    const admin = await createTestUser({
      fullName: `Services Admin ${makeSuffix("sa-")}`,
      phone: makePhone(81),
      role: "admin",
    });
    const providerOwner = await createTestUser({
      fullName: `Services Provider Owner ${makeSuffix("sp-")}`,
      phone: makePhone(82),
      role: "service_provider",
    });
    const customer = await createTestUser({
      fullName: `Services Customer ${makeSuffix("sc-")}`,
      phone: makePhone(83),
      role: "user",
    });
    trackedIds.userIds.push(Number(admin.id), Number(providerOwner.id), Number(customer.id));

    const provider = await createApprovedProvider(
      providerOwner.id,
      `Phase 2A Services Provider ${makeSuffix("provider-")}`
    );
    trackedIds.providerIds.push(Number(provider.id));

    const categoryPair = await getFirstServiceCategoryPair(admin.id);

    await assert.rejects(
      () =>
        servicesService.getProviderWorkspace({
          userId: customer.id,
          userRole: "user",
        }),
      (error) => {
        assert.equal(error.message, "FORBIDDEN_SERVICE_PROVIDER_ONLY");
        assert.equal(error.status, 403);
        return true;
      }
    );

    const offering = await servicesService.createOffering({
      userId: providerOwner.id,
      userRole: "service_provider",
      dto: {
        mainCategoryId: categoryPair.mainCategoryId,
        subcategoryId: categoryPair.subcategoryId,
        name: `Phase 2A Services Offering ${makeSuffix("off-")}`,
        description: "Phase 2A services offering",
        executionMode: "both",
        requiresSchedule: true,
        requiresProviderApproval: true,
        estimatedDurationMinutes: 90,
        hasFixedPrice: false,
        startsFromPrice: null,
        inspectionRequired: true,
        customQuoteOnly: false,
        workersCount: 1,
        includesText: "Included",
        excludesText: "Excluded",
        materialsText: "Materials",
        notes: "Phase 2A runtime offering",
        supportsHourlyBooking: false,
        supportsDailyBooking: false,
        supportsVisitBooking: true,
        supportsFullDayBooking: false,
        searchText: "Phase 2A services offering",
        pricingOptions: [
          {
            pricingModel: "inspection_required",
            pricingUnit: "visit",
            label: "Inspection visit",
            amount: null,
            minAmount: null,
            maxAmount: null,
            visitFee: 30000,
            currency: "IQD",
            minQuantity: null,
            maxQuantity: null,
            inspectionRequired: true,
            notes: "Inspection fee",
            isDefault: true,
            isActive: true,
            sortOrder: 0,
          },
        ],
      },
      mediaUrls: [],
    });
    assert.ok(offering?.id, "offering id missing");

    await servicesService.adminUpdateOfferingStatus({
      offeringId: offering.id,
      dto: {
        status: "approved",
        note: "Approved for phase 2A runtime",
      },
      adminUserId: admin.id,
    });

    const publicOfferings = await servicesService.searchPublicOfferings(
      {
        q: String(offering.name || ""),
        limit: 20,
        offset: 0,
        sort: "newest",
      },
      customer.id
    );
    assert.ok(
      publicOfferings.some((item) => Number(item.id || 0) === Number(offering.id)),
      "approved offering should be searchable"
    );

    const serviceRequest = await servicesService.createServiceRequest({
      userId: customer.id,
      dto: {
        offeringId: Number(offering.id),
        providerId: Number(provider.id),
        requestedExecutionMode: "home",
        requestedDate: new Date(Date.now() + 24 * 60 * 60 * 1000)
          .toISOString()
          .slice(0, 10),
        requestedTime: "11:00",
        quantity: 2,
        durationHours: 1.5,
        notes: `Need service for ${makeSuffix("request-")}`,
        addressLine: "Phase 2A street",
        city: "Baghdad",
        area: "Bismayah",
        latitude: 33.3152,
        longitude: 44.3661,
        requiresHomeService: true,
        requiresQuote: true,
      },
    });
    assert.ok(serviceRequest?.id, "service request id missing");
    assert.equal(String(serviceRequest.status || ""), "awaiting_provider");

    const providerRequests = await servicesService.listProviderRequests(
      { userId: providerOwner.id, userRole: "service_provider" },
      { limit: 20 }
    );
    assert.ok(
      Array.isArray(providerRequests) &&
        providerRequests.some((item) => Number(item.id || 0) === Number(serviceRequest.id)),
      "provider should see the service request"
    );

    const quote = await servicesService.createQuote({
      userId: providerOwner.id,
      userRole: "service_provider",
      requestId: Number(serviceRequest.id),
      dto: {
        pricingModel: "custom_quote",
        pricingUnit: "visit",
        amount: 45000,
        currency: "IQD",
        note: "Phase 2A runtime quote",
      },
    });
    assert.ok(quote?.id, "quote id missing");

    const customerRequest = await servicesService.getMyRequest({
      userId: customer.id,
      requestId: Number(serviceRequest.id),
    });
    assert.ok(
      customerRequest.quotes.some((item) => Number(item.id || 0) === Number(quote.id)),
      "customer should see the quote"
    );

    const accepted = await servicesService.respondToQuote({
      userId: customer.id,
      requestId: Number(serviceRequest.id),
      quoteId: Number(quote.id),
      dto: {
        action: "accepted",
        note: "Accepted in test",
      },
    });
    assert.equal(String(accepted.status || ""), "accepted");
    assert.equal(Number(accepted.acceptedQuoteId || 0), Number(quote.id));
    assert.equal(Number(accepted.finalPrice || 0), 45000);

    const providerAccepted = await servicesService.updateRequestStatusByProvider({
      userId: providerOwner.id,
      userRole: "service_provider",
      requestId: Number(serviceRequest.id),
      dto: {
        status: "accepted",
        note: "Provider acknowledged the accepted quote",
      },
    });
    assert.equal(String(providerAccepted.status || ""), "accepted");

    const providerInProgress = await servicesService.updateRequestStatusByProvider({
      userId: providerOwner.id,
      userRole: "service_provider",
      requestId: Number(serviceRequest.id),
      dto: {
        status: "in_progress",
        note: "Provider started work",
      },
    });
    assert.equal(String(providerInProgress.status || ""), "in_progress");

    const completed = await servicesService.updateRequestStatusByProvider({
      userId: providerOwner.id,
      userRole: "service_provider",
      requestId: Number(serviceRequest.id),
      dto: {
        status: "completed",
        note: "Provider completed work",
      },
    });
    assert.equal(String(completed.status || ""), "completed");

    const finalRequest = await servicesService.getMyRequest({
      userId: customer.id,
      requestId: Number(serviceRequest.id),
    });
    assert.equal(String(finalRequest.status || ""), "completed");
    assert.equal(Number(finalRequest.finalPrice || 0), 45000);

    await assert.rejects(
      () =>
        servicesService.getProviderWorkspace({
          userId: customer.id,
          userRole: "user",
        }),
      (error) => {
        assert.equal(error.message, "FORBIDDEN_SERVICE_PROVIDER_ONLY");
        assert.equal(error.status, 403);
        return true;
      }
    );

    const providerNotificationRows = await q(
      `SELECT type, payload
       FROM app_notification
       WHERE user_id = $1
         AND type IN ('services.request.created', 'services.request.status.accepted', 'services.request.status.in_progress', 'services.request.status.completed')
       ORDER BY id ASC`,
      [Number(providerOwner.id)]
    );
    assert.ok(
      providerNotificationRows.rows.some((row) => row.type === "services.request.created"),
      "provider notification for new request missing"
    );
    assert.equal(
      providerNotificationRows.rows.every((row) => row.payload?.target === "service_request_details"),
      true,
      "provider notifications should deep-link to service request details"
    );

    const customerNotificationRows = await q(
      `SELECT type, payload
       FROM app_notification
       WHERE user_id = $1
         AND type IN ('services.request.quote_received', 'services.request.status.accepted', 'services.request.status.in_progress', 'services.request.status.completed')
       ORDER BY id ASC`,
      [Number(customer.id)]
    );
    assert.ok(
      customerNotificationRows.rows.some((row) => row.type === "services.request.quote_received"),
      "customer quote notification missing"
    );
    assert.ok(
      customerNotificationRows.rows.some((row) => row.type === "services.request.status.completed"),
      "customer completed notification missing"
    );
    assert.equal(
      customerNotificationRows.rows.every((row) => row.payload?.target === "service_request_details"),
      true,
      "customer notifications should deep-link to service request details"
    );
  } finally {
    await cleanupWorkspace(trackedIds);
  }
});

test("jobs marketplace duplicate apply withdraw and expiry are enforced", async () => {
  const trackedIds = {
    merchantIds: [],
    providerIds: [],
    userIds: [],
    orderIds: [],
  };

  try {
    const owner = await createTestUser({
      fullName: `Jobs Owner ${makeSuffix("jo-")}`,
      phone: makePhone(84),
      role: "owner",
    });
    const candidate = await createTestUser({
      fullName: `Jobs Candidate ${makeSuffix("jc-")}`,
      phone: makePhone(85),
      role: "user",
    });
    trackedIds.userIds.push(Number(owner.id), Number(candidate.id));

    const merchant = await createApprovedMerchant(
      owner.id,
      `Phase 2A Jobs Merchant ${makeSuffix("merchant-")}`
    );
    trackedIds.merchantIds.push(Number(merchant.id));

    const job = await jobsService.createJob(
      {
        title: `Phase 2A Jobs ${makeSuffix("job-")}`,
        category: "Jobs",
        activityType: "restaurant",
        department: "accounting",
        city: "Baghdad",
        area: "Bismayah",
        description: "Phase 2A jobs runtime test",
        requirements: "Experience preferred",
        responsibilities: "Day to day operations",
        benefits: "Stable salary",
        workplaceType: "on_site",
        employmentType: "full_time",
        experienceLevel: "mid",
        salaryPeriod: "monthly",
        salaryCurrency: "IQD",
        salaryIsNegotiable: true,
        isFeatured: false,
        salaryMin: 500000,
        salaryMax: 800000,
        vacancies: 1,
        merchantId: Number(merchant.id),
        status: "active",
      },
      { userId: owner.id, role: "owner", isSuperAdmin: false }
    );
    assert.ok(job.job?.id, "job id missing");
    const jobId = Number(job.job.id);

    const application = await jobsService.applyToJob(
      jobId,
      {
        message: "I can handle the role.",
        phone: candidate.phone,
        email: `candidate.${makeSuffix("jobs-")}@example.com`,
        expectedSalary: 650000,
      },
      { userId: candidate.id, role: "user", isSuperAdmin: false }
    );
    assert.ok(application.application?.id, "application id missing");
    const applicationId = Number(application.application.id);

    await assert.rejects(
      () =>
        jobsService.applyToJob(
          jobId,
          {
            message: "Duplicate application attempt.",
            phone: candidate.phone,
            email: `candidate.${makeSuffix("jobs-dup-")}@example.com`,
            expectedSalary: 650000,
          },
          { userId: candidate.id, role: "user", isSuperAdmin: false }
        ),
      (error) => {
        assert.equal(error.message, "JOB_ALREADY_APPLIED");
        assert.equal(error.status, 409);
        return true;
      }
    );

    const hired = await jobsService.updateJobApplicationStatus(
      jobId,
      applicationId,
      "hired",
      "Selected for phase 2A runtime",
      {
        offerSalary: 700000,
        offerWorkHours: "09:00-17:00",
        offerWorkDays: "Sunday-Thursday",
        offerMessage: "Please accept the offer.",
      },
      { userId: owner.id, role: "owner", isSuperAdmin: false }
    );
    assert.equal(String(hired.application.status || ""), "hired");
    assert.ok(hired.application.offerSentAt, "offerSentAt missing");

    const accepted = await jobsService.acceptMyJobOffer(
      applicationId,
      {},
      { userId: candidate.id, role: "user", isSuperAdmin: false }
    );
    assert.equal(String(accepted.application.status || ""), "hired");
    assert.ok(accepted.workProfile.workTitle, "work title missing");

    await assert.rejects(
      () =>
        jobsService.withdrawMyApplication(
          applicationId,
          "Too late after acceptance",
          { userId: candidate.id, role: "user", isSuperAdmin: false }
        ),
      (error) => {
        assert.equal(error.message, "JOB_APPLICATION_WITHDRAW_AFTER_ACCEPT_NOT_ALLOWED");
        assert.equal(error.status, 400);
        return true;
      }
    );

    const withdrawJob = await jobsService.createJob(
      {
        title: `Withdraw Phase 2A ${makeSuffix("withdraw-")}`,
        category: "Jobs",
        activityType: "restaurant",
        department: "operations",
        city: "Baghdad",
        area: "Bismayah",
        description: "Withdraw test job",
        requirements: "General operations",
        responsibilities: "General operations tasks",
        benefits: "Stable salary",
        workplaceType: "on_site",
        employmentType: "full_time",
        experienceLevel: "mid",
        salaryPeriod: "monthly",
        salaryCurrency: "IQD",
        salaryIsNegotiable: true,
        isFeatured: false,
        salaryMin: 400000,
        salaryMax: 700000,
        vacancies: 1,
        merchantId: Number(merchant.id),
        status: "active",
      },
      { userId: owner.id, role: "owner", isSuperAdmin: false }
    );
    assert.ok(withdrawJob.job?.id, "withdraw job id missing");
    const withdrawJobId = Number(withdrawJob.job.id);

    const withdrawApplication = await jobsService.applyToJob(
      withdrawJobId,
      {
        message: "Applying to later withdraw.",
        phone: candidate.phone,
        email: `candidate.${makeSuffix("jobs-withdraw-")}@example.com`,
        expectedSalary: 500000,
      },
      { userId: candidate.id, role: "user", isSuperAdmin: false }
    );
    const withdrawApplicationId = Number(withdrawApplication.application.id);

    const withdrawn = await jobsService.withdrawMyApplication(
      withdrawApplicationId,
      "No longer needed",
      { userId: candidate.id, role: "user", isSuperAdmin: false }
    );
    assert.equal(String(withdrawn.application.status || ""), "withdrawn");

    const expiredJob = await jobsService.createJob(
      {
        title: `Expired Phase 2A ${makeSuffix("expired-")}`,
        category: "Jobs",
        activityType: "restaurant",
        department: "operations",
        city: "Baghdad",
        area: "Bismayah",
        description: "Expired job test",
        requirements: "General operations",
        responsibilities: "General operations tasks",
        benefits: "Stable salary",
        workplaceType: "on_site",
        employmentType: "full_time",
        experienceLevel: "mid",
        salaryPeriod: "monthly",
        salaryCurrency: "IQD",
        salaryIsNegotiable: true,
        isFeatured: false,
        salaryMin: 400000,
        salaryMax: 700000,
        vacancies: 1,
        merchantId: Number(merchant.id),
        expiresAt: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
        status: "active",
      },
      { userId: owner.id, role: "owner", isSuperAdmin: false }
    );
    assert.ok(expiredJob.job?.id, "expired job id missing");

    await assert.rejects(
      () =>
        jobsService.applyToJob(
          Number(expiredJob.job.id),
          {
            message: "Trying to apply after expiry.",
            phone: candidate.phone,
            email: `candidate.${makeSuffix("jobs-expired-")}@example.com`,
            expectedSalary: 500000,
          },
          { userId: candidate.id, role: "user", isSuperAdmin: false }
        ),
      (error) => {
        assert.equal(error.message, "JOB_NOT_OPEN");
        assert.equal(error.status, 400);
        return true;
      }
    );

    const candidateNotifications = await q(
      `SELECT type
       FROM app_notification
       WHERE user_id = $1
         AND type IN ('jobs.application.submitted', 'jobs.application.status_updated', 'jobs.application.withdrawn')
       ORDER BY id ASC`,
      [Number(candidate.id)]
    );
    assert.ok(
      candidateNotifications.rows.some((row) => row.type === "jobs.application.status_updated"),
      "candidate should receive status update notification"
    );

    const managerNotifications = await q(
      `SELECT type, payload
       FROM app_notification
       WHERE user_id = $1
         AND type IN ('jobs.application.offer_accepted', 'jobs.application.withdrawn')
       ORDER BY id ASC`,
      [Number(owner.id)]
    );
    assert.ok(
      managerNotifications.rows.some((row) => row.type === "jobs.application.offer_accepted"),
      "manager should receive offer-accepted notification"
    );
    assert.ok(
      managerNotifications.rows.some((row) => row.type === "jobs.application.withdrawn"),
      "manager should receive withdrawn notification"
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
