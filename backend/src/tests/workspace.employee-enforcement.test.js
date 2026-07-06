import "dotenv/config";

import assert from "node:assert/strict";
import test from "node:test";

import { q } from "../config/db.js";
import { createUser, createCustomerAddress } from "../modules/auth/auth.repo.js";
import { hashPin } from "../shared/utils/hash.js";
import * as hrController from "../modules/hr/hr.controller.js";
import * as ownerController from "../modules/owner/owner.controller.js";
import * as ownerRepo from "../modules/owner/owner.repo.js";
import * as ownerService from "../modules/owner/owner.service.js";
import * as ordersService from "../modules/orders/orders.service.js";
import * as servicesController from "../modules/services/services.controller.js";
import * as servicesRepo from "../modules/services/services.repo.js";

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
    analyticsConsentVersion: "employee_enforce_v1",
    analyticsConsentGrantedAt: new Date().toISOString(),
    chatQualityReviewConsent: true,
  });
}

function makeReq({
  userId,
  userRole = "owner",
  userIsSuperAdmin = false,
  body = {},
  params = {},
  query = {},
}) {
  return {
    userId,
    userRole,
    userIsSuperAdmin,
    body,
    params,
    query,
    headers: {},
    ip: "127.0.0.1",
    connection: { remoteAddress: "127.0.0.1" },
  };
}

function makeRes() {
  const state = {
    statusCode: 200,
    body: undefined,
    sent: false,
  };

  return {
    state,
    status(code) {
      state.statusCode = code;
      return this;
    },
    json(body) {
      state.body = body;
      state.sent = true;
      return this;
    },
    send(body) {
      state.body = body;
      state.sent = true;
      return this;
    },
  };
}

async function invoke(handler, req) {
  const res = makeRes();
  let nextError = null;
  try {
    await handler(req, res, (error) => {
      nextError = error;
    });
  } catch (error) {
    nextError = error;
  }
  return {
    error: nextError,
    res: res.state,
  };
}

function assertAppError(result, message, status) {
  assert.ok(result.error, "Expected controller to fail");
  assert.equal(result.error.message, message);
  assert.equal(result.error.status, status);
}

async function cleanupWorkspace({ merchantIds = [], providerIds = [], userIds = [], orderIds = [] }) {
  const merchants = merchantIds.map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0);
  const providers = providerIds.map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0);
  const users = userIds.map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0);
  const orders = orderIds.map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0);

  if (merchants.length || providers.length || users.length || orders.length) {
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

  if (merchants.length) {
    await q(
      `DELETE FROM merchant
       WHERE id = ANY($1::bigint[])`,
      [merchants]
    );
  }

  if (providers.length) {
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

async function readLatestEmployeeLog({
  workspaceKind,
  workspaceId,
  employeeUserId,
  actionKey,
}) {
  const result = await q(
    `SELECT *
     FROM workspace_employee_activity_log
     WHERE workspace_kind = $1
       AND workspace_id = $2
       AND employee_user_id = $3
       AND action_key = $4
     ORDER BY id DESC
     LIMIT 1`,
    [workspaceKind, Number(workspaceId), Number(employeeUserId), actionKey]
  );
  return result.rows[0] || null;
}

test("workspace employee permission enforcement", async (t) => {
  await t.test("store workspace enforcement", async () => {
    const trackedIds = {
      merchantIds: [],
      providerIds: [],
      userIds: [],
      orderIds: [],
    };

    const storeOwnerPhone = makePhone(11);
    const storeFixtureUser = await createTestUser({
      fullName: "Store Owner",
      phone: storeOwnerPhone,
      role: "owner",
    });
    trackedIds.userIds.push(Number(storeFixtureUser.id));
    const storeMerchantResult = await q(
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
        `Store ${makeSuffix("merchant-")}`,
        "market",
        "supermarket",
        "Workspace permission test store",
        storeOwnerPhone,
        Number(storeFixtureUser.id),
      ]
    );
    const storeFixture = {
      user: storeFixtureUser,
      merchant: storeMerchantResult.rows[0],
    };
    trackedIds.merchantIds.push(Number(storeFixture.merchant.id));
    const storeMerchantId = Number(storeFixture.merchant.id);

    const storeCategory = await ownerService.createOwnerCategory(
      storeFixture.user.id,
      {
        name: `Groceries ${makeSuffix("cat-")}`,
        catalogType: "grocery",
        sortOrder: 1,
      }
    );
    const storeProduct = await ownerService.createOwnerProduct(
      storeFixture.user.id,
      {
        name: `Milk ${makeSuffix("prod-")}`,
        categoryId: storeCategory.id,
        price: 1000,
        description: "Test product",
        isAvailable: true,
        sortOrder: 1,
      }
    );
    trackedIds.orderIds = trackedIds.orderIds || [];

    const customer = await createTestUser({
      fullName: `Customer ${makeSuffix("cus-")}`,
      phone: makePhone(21),
      role: "user",
    });
    trackedIds.userIds.push(Number(customer.id));
    const customerAddress = await createCustomerAddress(customer.id, {
      label: "Home",
      city: "Baghdad",
      block: "B1",
      buildingNumber: "12",
      apartment: "3",
      isDefault: true,
    });

    const deliveryAgent = await ownerService.createDeliveryAgent(
      storeFixture.user.id,
      {
        fullName: `Delivery ${makeSuffix("del-")}`,
        phone: makePhone(31),
        pin: "1234",
        imageUrl: null,
      }
    );
    trackedIds.userIds.push(Number(deliveryAgent.user.id));

    const storeActor = await createTestUser({
      fullName: `Store HR ${makeSuffix("hr-")}`,
      phone: makePhone(41),
      role: "hr",
    });
    const storeDisabledActor = await createTestUser({
      fullName: `Store Disabled ${makeSuffix("hrd-")}`,
      phone: makePhone(42),
      role: "hr",
    });
    const storeUpsertTarget = await createTestUser({
      fullName: `Store Target ${makeSuffix("tgt-")}`,
      phone: makePhone(43),
      role: "user",
    });
    trackedIds.userIds.push(
      Number(storeActor.id),
      Number(storeDisabledActor.id),
      Number(storeUpsertTarget.id)
    );

    await ownerRepo.linkHrToMerchant({
      merchantId: storeMerchantId,
      hrUserId: storeActor.id,
      createdByUserId: storeFixture.user.id,
      source: "owner",
    });
    await ownerRepo.linkHrToMerchant({
      merchantId: storeMerchantId,
      hrUserId: storeDisabledActor.id,
      createdByUserId: storeFixture.user.id,
      source: "owner",
    });

    const createEmployeePayload = {
      merchantId: storeMerchantId,
      employeeUserId: Number(storeActor.id),
      roleTag: "hr",
      displayName: "Store HR",
      contactEmail: "store-hr@example.com",
      employmentType: "full_time",
      baseSalary: 0,
      currency: "IQD",
      workDaysPerWeek: 6,
      shiftStartTime: "09:00",
      shiftEndTime: "17:00",
      isActive: true,
      notes: "Initial profile",
      permissions: [],
    };
    const createDisabledEmployeePayload = {
      ...createEmployeePayload,
      employeeUserId: Number(storeDisabledActor.id),
      displayName: "Store Disabled",
      contactEmail: "store-disabled@example.com",
    };

    const ownerReq = (body = {}, params = {}, query = {}) =>
      makeReq({
        userId: storeFixture.user.id,
        userRole: "owner",
        body,
        params,
        query,
      });
    const actorReq = (body = {}, params = {}, query = {}) =>
      makeReq({
        userId: storeActor.id,
        userRole: "hr",
        body,
        params,
        query,
      });
    const disabledActorReq = (body = {}, params = {}, query = {}) =>
      makeReq({
        userId: storeDisabledActor.id,
        userRole: "hr",
        body,
        params,
        query,
      });

    try {
      const initialActorProfile = await invoke(
        hrController.upsertEmployee,
        ownerReq(createEmployeePayload)
      );
      assert.equal(initialActorProfile.error, null);
      assert.equal(initialActorProfile.res.statusCode, 200);

      const initialDisabledProfile = await invoke(
        hrController.upsertEmployee,
        ownerReq(createDisabledEmployeePayload)
      );
      assert.equal(initialDisabledProfile.error, null);
      assert.equal(initialDisabledProfile.res.statusCode, 200);

      const order = await ordersService.createOrder(customer.id, {
        merchantId: storeMerchantId,
        addressId: customerAddress.id,
        items: [
          {
            productId: storeProduct.id,
            quantity: 1,
          },
        ],
      });
      assert.ok(order && Number.isInteger(Number(order.id)), "Expected a created order id");
      trackedIds.orderIds.push(Number(order.id));

      const blockedAssign = await invoke(
        ownerController.assignDelivery,
        actorReq(
          {
            deliveryUserId: Number(deliveryAgent.user.id),
            assignmentMode: "merchant_delivery",
          },
          { orderId: String(order.id) }
        )
      );
      assertAppError(blockedAssign, "FORBIDDEN_MERCHANT_PERMISSION", 403);

      const blockedPrint = await invoke(
        ownerController.printOrdersReport,
        actorReq({}, {}, { period: "day" })
      );
      assertAppError(blockedPrint, "FORBIDDEN_MERCHANT_PERMISSION", 403);

      const blockedSummary = await invoke(
        ownerController.settlementSummary,
        actorReq()
      );
      assertAppError(blockedSummary, "FORBIDDEN_MERCHANT_PERMISSION", 403);

      const blockedAvailability = await invoke(
        ownerController.updateProductAvailability,
        actorReq(
          {
            isAvailable: false,
            unavailableReason: "Blocked before permission grant",
          },
          { productId: String(storeProduct.id) }
        )
      );
      assertAppError(blockedAvailability, "FORBIDDEN_MERCHANT_PERMISSION", 403);

      const blockedInvite = await invoke(
        hrController.inviteEmployee,
        actorReq({
          merchantId: storeMerchantId,
          fullName: "Blocked Invite",
          phone: makePhone(51),
          pin: "1234",
          roleTag: "staff",
          displayName: "Blocked Invite",
          contactEmail: "blocked@example.com",
          employmentType: "full_time",
          baseSalary: 0,
          currency: "IQD",
          workDaysPerWeek: 6,
          isActive: true,
          permissions: [],
          reason: "permission check",
        })
      );
      assertAppError(blockedInvite, "FORBIDDEN_MERCHANT_PERMISSION", 403);

      const blockedUpsert = await invoke(
        hrController.upsertEmployee,
        actorReq({
          merchantId: storeMerchantId,
          employeeUserId: Number(storeUpsertTarget.id),
          roleTag: "staff",
          displayName: "Blocked Upsert",
          contactEmail: "blocked-upsert@example.com",
          employmentType: "full_time",
          baseSalary: 0,
          currency: "IQD",
          workDaysPerWeek: 6,
          isActive: true,
          permissions: [],
          reason: "permission check",
        })
      );
      assertAppError(blockedUpsert, "FORBIDDEN_MERCHANT_PERMISSION", 403);

      const grantedPermissions = [
        "assign_delivery",
        "view_financial_reports",
        "change_product_availability",
        "manage_employees",
      ];
      const grantPermissions = await invoke(
        hrController.upsertEmployee,
        ownerReq({
          ...createEmployeePayload,
          permissions: grantedPermissions,
          baseSalary: 120000,
          notes: "Permission grant",
        })
      );
      assert.equal(grantPermissions.error, null);
      assert.equal(grantPermissions.res.statusCode, 200);
      assert.deepEqual(
        grantPermissions.res.body.profile.permissions.sort(),
        [...grantedPermissions].sort()
      );

      const grantLog = await readLatestEmployeeLog({
        workspaceKind: "merchant",
        workspaceId: storeMerchantId,
        employeeUserId: storeActor.id,
        actionKey: "merchant.employee.updated",
      });
      assert.ok(grantLog);
      assert.equal(grantLog.actor_user_id, storeFixture.user.id);
      assert.equal(grantLog.actor_role, "owner");
      assert.equal(Number(grantLog.workspace_id), storeMerchantId);
      assert.deepEqual(
        Array.isArray(grantLog.new_value?.permissions)
          ? grantLog.new_value.permissions.sort()
          : [],
        [...grantedPermissions].sort()
      );

      const approvedOrder = await invoke(
        ownerController.updateOrderStatus,
        ownerReq(
          {
            status: "approved",
            estimatedPrepMinutes: 15,
          },
          { orderId: String(order.id) }
        )
      );
      assert.equal(approvedOrder.error, null);
      assert.equal(approvedOrder.res.statusCode, 204);

      const assignedDelivery = await invoke(
        ownerController.assignDelivery,
        actorReq(
          {
            deliveryUserId: Number(deliveryAgent.user.id),
            assignmentMode: "merchant_delivery",
          },
          { orderId: String(order.id) }
        )
      );
      assert.equal(assignedDelivery.error, null);
      assert.equal(assignedDelivery.res.statusCode, 204);
      const assignedRow = await q(
        `SELECT delivery_user_id, status
         FROM customer_order
         WHERE id = $1`,
        [Number(order.id)]
      );
      assert.equal(Number(assignedRow.rows[0]?.delivery_user_id), Number(deliveryAgent.user.id));

      const printReport = await invoke(
        ownerController.printOrdersReport,
        actorReq({}, {}, { period: "day" })
      );
      assert.equal(printReport.error, null);
      assert.equal(printReport.res.statusCode, 200);

      const summary = await invoke(ownerController.settlementSummary, actorReq());
      assert.equal(summary.error, null);
      assert.equal(summary.res.statusCode, 200);

      const availabilityUpdate = await invoke(
        ownerController.updateProductAvailability,
        actorReq(
          {
            isAvailable: false,
            unavailableReason: "Temporarily paused",
            unavailableUntil: null,
          },
          { productId: String(storeProduct.id) }
        )
      );
      assert.equal(availabilityUpdate.error, null);
      assert.equal(availabilityUpdate.res.statusCode, 200);
      const updatedProductRow = await q(
        `SELECT is_available, unavailable_reason
         FROM product
         WHERE id = $1`,
        [Number(storeProduct.id)]
      );
      assert.equal(updatedProductRow.rows[0]?.is_available, false);
      assert.equal(updatedProductRow.rows[0]?.unavailable_reason, "Temporarily paused");

      const invitedEmployee = await invoke(
        hrController.inviteEmployee,
        actorReq({
          merchantId: storeMerchantId,
          fullName: `Invited ${makeSuffix("emp-")}`,
          phone: makePhone(52),
          pin: "1234",
          roleTag: "staff",
          displayName: "Invited Staff",
          contactEmail: "invited@example.com",
          employmentType: "part_time",
          baseSalary: 50000,
          currency: "IQD",
          workDaysPerWeek: 5,
          isActive: true,
          permissions: ["manage_employees"],
          reason: "permission test invite",
        })
      );
      assert.equal(invitedEmployee.error, null);
      assert.equal(invitedEmployee.res.statusCode, 201);
      trackedIds.userIds.push(Number(invitedEmployee.res.body.user.id));

      const invitedLog = await readLatestEmployeeLog({
        workspaceKind: "merchant",
        workspaceId: storeMerchantId,
        employeeUserId: invitedEmployee.res.body.user.id,
        actionKey: "merchant.employee.invited",
      });
      assert.ok(invitedLog);
      assert.equal(invitedLog.actor_user_id, storeActor.id);
      assert.equal(invitedLog.actor_role, "hr");
      assert.equal(Number(invitedLog.workspace_id), storeMerchantId);
      assert.equal(
        Number(invitedLog.employee_user_id),
        Number(invitedEmployee.res.body.user.id)
      );

      const upsertedEmployee = await invoke(
        hrController.upsertEmployee,
        actorReq({
          merchantId: storeMerchantId,
          employeeUserId: Number(storeUpsertTarget.id),
          roleTag: "staff",
          displayName: "Allowed Upsert",
          contactEmail: "allowed-upsert@example.com",
          employmentType: "full_time",
          baseSalary: 75000,
          currency: "IQD",
          workDaysPerWeek: 6,
          isActive: true,
          permissions: ["manage_employees"],
          reason: "permission test upsert",
        })
      );
      assert.equal(upsertedEmployee.error, null);
      assert.equal(upsertedEmployee.res.statusCode, 200);
      const upsertedRow = await q(
        `SELECT merchant_id, employee_user_id, permissions_json
         FROM merchant_employee_profile
         WHERE merchant_id = $1
           AND employee_user_id = $2
         LIMIT 1`,
        [storeMerchantId, Number(storeUpsertTarget.id)]
      );
      assert.equal(Number(upsertedRow.rows[0]?.merchant_id), storeMerchantId);
      assert.equal(Number(upsertedRow.rows[0]?.employee_user_id), Number(storeUpsertTarget.id));

      const crossOwner = await createTestUser({
        fullName: `Cross Owner ${makeSuffix("x-")}`,
        phone: makePhone(53),
        role: "owner",
      });
      trackedIds.userIds.push(Number(crossOwner.id));
      const crossMerchantResult = await q(
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
          `Other Store ${makeSuffix("merchant-")}`,
          "market",
          "supermarket",
          "Cross workspace store",
          makePhone(53),
          Number(crossOwner.id),
        ]
      );
      const crossMerchant = crossMerchantResult.rows[0];
      trackedIds.merchantIds.push(Number(crossMerchant.id));
      const crossTarget = await createTestUser({
        fullName: `Cross Target ${makeSuffix("ct-")}`,
        phone: makePhone(54),
        role: "user",
      });
      trackedIds.userIds.push(Number(crossTarget.id));
      const crossWorkspaceResult = await invoke(
        hrController.upsertEmployee,
        actorReq({
          merchantId: Number(crossMerchant.id),
          employeeUserId: Number(crossTarget.id),
          roleTag: "staff",
          displayName: "Cross Target",
          contactEmail: "cross-target@example.com",
          employmentType: "full_time",
          baseSalary: 1000,
          currency: "IQD",
          workDaysPerWeek: 6,
          isActive: true,
          permissions: ["manage_employees"],
          reason: "cross workspace isolation",
        })
      );
      assert.equal(crossWorkspaceResult.error, null);
      assert.equal(crossWorkspaceResult.res.statusCode, 200);
      assert.equal(Number(crossWorkspaceResult.res.body.merchant.id), storeMerchantId);

      const crossTargetRow = await q(
        `SELECT merchant_id
         FROM merchant_employee_profile
         WHERE employee_user_id = $1
         ORDER BY updated_at DESC, id DESC
         LIMIT 1`,
        [Number(crossTarget.id)]
      );
      assert.equal(Number(crossTargetRow.rows[0]?.merchant_id), storeMerchantId);

      const storeLog = await readLatestEmployeeLog({
        workspaceKind: "merchant",
        workspaceId: storeMerchantId,
        employeeUserId: invitedEmployee.res.body.user.id,
        actionKey: "merchant.employee.invited",
      });
      assert.ok(storeLog);
      assert.equal(storeLog.actor_user_id, storeActor.id);
      assert.equal(storeLog.actor_role, "hr");
      assert.equal(Number(storeLog.workspace_id), storeMerchantId);

      const disableActor = await invoke(
        hrController.upsertEmployee,
        ownerReq({
          ...createDisabledEmployeePayload,
          isActive: false,
          archivedAt: new Date().toISOString(),
          permissions: [],
          reason: "disabled for access block",
        })
      );
      assert.equal(disableActor.error, null);
      assert.equal(disableActor.res.statusCode, 200);
      await q(
        `UPDATE merchant_hr_staff
         SET is_active = FALSE,
             updated_at = NOW()
         WHERE merchant_id = $1
           AND hr_user_id = $2`,
        [storeMerchantId, Number(storeDisabledActor.id)]
      );
      const reenableActor = await invoke(
        hrController.upsertEmployee,
        ownerReq({
          ...createDisabledEmployeePayload,
          isActive: true,
          archivedAt: null,
          permissions: [],
          reason: "reactivated for audit log",
        })
      );
      assert.equal(reenableActor.error, null);
      assert.equal(reenableActor.res.statusCode, 200);
      await q(
        `UPDATE merchant_hr_staff
         SET is_active = TRUE,
             updated_at = NOW()
         WHERE merchant_id = $1
           AND hr_user_id = $2`,
        [storeMerchantId, Number(storeDisabledActor.id)]
      );
      const disableAgain = await invoke(
        hrController.upsertEmployee,
        ownerReq({
          ...createDisabledEmployeePayload,
          isActive: false,
          archivedAt: new Date().toISOString(),
          permissions: [],
          reason: "final disabled state",
        })
      );
      assert.equal(disableAgain.error, null);
      assert.equal(disableAgain.res.statusCode, 200);
      await q(
        `UPDATE merchant_hr_staff
         SET is_active = FALSE,
             updated_at = NOW()
         WHERE merchant_id = $1
           AND hr_user_id = $2`,
        [storeMerchantId, Number(storeDisabledActor.id)]
      );

      const deactivateLogs = await q(
        `SELECT new_value
         FROM workspace_employee_activity_log
         WHERE workspace_kind = 'merchant'
           AND workspace_id = $1
           AND employee_user_id = $2
           AND action_key = 'merchant.employee.updated'
         ORDER BY id DESC`,
        [storeMerchantId, Number(storeDisabledActor.id)]
      );
      const deactivateStates = deactivateLogs.rows.map((row) => row.new_value?.isActive);
      assert.ok(deactivateStates.includes(false));
      assert.ok(deactivateStates.includes(true));

      const blockedDisabledOwner = await invoke(
        ownerController.printOrdersReport,
        disabledActorReq({}, {}, { period: "day" })
      );
      assertAppError(blockedDisabledOwner, "MERCHANT_NOT_FOUND", 404);

      const blockedDisabledHr = await invoke(
        hrController.listEmployees,
        disabledActorReq({}, {}, { merchantId: String(storeMerchantId) })
      );
      assertAppError(blockedDisabledHr, "HR_MERCHANT_NOT_FOUND", 404);
    } finally {
      await cleanupWorkspace(trackedIds);
    }
  });

  await t.test("service workspace enforcement", async () => {
    const trackedIds = {
      merchantIds: [],
      providerIds: [],
      userIds: [],
      orderIds: [],
    };

    const providerOwner = await createTestUser({
      fullName: `Provider Owner ${makeSuffix("po-")}`,
      phone: makePhone(71),
      role: "service_provider",
    });
    trackedIds.userIds.push(Number(providerOwner.id));

    const providerProfile = await servicesRepo.createProviderProfile({
      userId: providerOwner.id,
      dto: {
        businessName: `Provider ${makeSuffix("provider-")}`,
        mainCategoryId: null,
        bio: "Workspace permission test provider",
        phone: makePhone(72),
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
        yearsExperience: 5,
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
        approvedByUserId: providerOwner.id,
        approvedAt: new Date().toISOString(),
      },
    });
    trackedIds.providerIds.push(Number(providerProfile.id));

    const providerActor = await createTestUser({
      fullName: `Provider Employee ${makeSuffix("pe-")}`,
      phone: makePhone(73),
      role: "service_provider",
    });
    const providerDisabledActor = await createTestUser({
      fullName: `Provider Disabled ${makeSuffix("pd-")}`,
      phone: makePhone(74),
      role: "service_provider",
    });
    const providerUpsertTarget = await createTestUser({
      fullName: `Provider Target ${makeSuffix("pt-")}`,
      phone: makePhone(75),
      role: "service_provider",
    });
    trackedIds.userIds.push(
      Number(providerActor.id),
      Number(providerDisabledActor.id),
      Number(providerUpsertTarget.id)
    );

    const providerControllerReq = (body = {}, params = {}, query = {}, userId = providerOwner.id) =>
      makeReq({
        userId,
        userRole: "service_provider",
        body,
        params,
        query,
      });

    try {
      const initialProviderActor = await invoke(
        servicesController.upsertProviderEmployee,
        providerControllerReq(
          {
            employeeUserId: Number(providerActor.id),
            roleTag: "staff",
            displayName: "Provider Employee",
            contactEmail: "provider-employee@example.com",
            permissions: [],
            isActive: true,
            reason: "initial profile",
          },
          {},
          {},
          providerOwner.id
        )
      );
      assert.equal(initialProviderActor.error, null);
      assert.equal(initialProviderActor.res.statusCode, 200);

      const initialProviderDisabled = await invoke(
        servicesController.upsertProviderEmployee,
        providerControllerReq(
          {
            employeeUserId: Number(providerDisabledActor.id),
            roleTag: "staff",
            displayName: "Provider Disabled",
            contactEmail: "provider-disabled@example.com",
            permissions: [],
            isActive: true,
            reason: "initial profile",
          },
          {},
          {},
          providerOwner.id
        )
      );
      assert.equal(initialProviderDisabled.error, null);
      assert.equal(initialProviderDisabled.res.statusCode, 200);

      const blockedInvite = await invoke(
        servicesController.inviteProviderEmployee,
        providerControllerReq(
          {
            fullName: "Blocked Provider Invite",
            phone: makePhone(76),
            pin: "1234",
            roleTag: "staff",
            displayName: "Blocked Provider Invite",
            contactEmail: "blocked-provider@example.com",
            permissions: [],
            isActive: true,
            reason: "permission check",
          },
          {},
          {},
          providerActor.id
        )
      );
      assertAppError(blockedInvite, "FORBIDDEN_SERVICE_PROVIDER_PERMISSION", 403);

      const blockedUpsert = await invoke(
        servicesController.upsertProviderEmployee,
        providerControllerReq(
          {
            employeeUserId: Number(providerUpsertTarget.id),
            roleTag: "staff",
            displayName: "Blocked Provider Upsert",
            contactEmail: "blocked-provider-upsert@example.com",
            permissions: [],
            isActive: true,
            reason: "permission check",
          },
          {},
          {},
          providerActor.id
        )
      );
      assertAppError(blockedUpsert, "FORBIDDEN_SERVICE_PROVIDER_PERMISSION", 403);

      const grantPermissions = await invoke(
        servicesController.upsertProviderEmployee,
        providerControllerReq(
          {
            employeeUserId: Number(providerActor.id),
            roleTag: "manager",
            displayName: "Provider Employee",
            contactEmail: "provider-employee@example.com",
            permissions: ["manage_employees"],
            isActive: true,
            reason: "grant manage employees",
          },
          {},
          {},
          providerOwner.id
        )
      );
      assert.equal(grantPermissions.error, null);
      assert.equal(grantPermissions.res.statusCode, 200);
      assert.deepEqual(
        grantPermissions.res.body.profile.permissions,
        ["manage_employees"]
      );

      const providerGrantLog = await readLatestEmployeeLog({
        workspaceKind: "service_provider",
        workspaceId: providerProfile.id,
        employeeUserId: providerActor.id,
        actionKey: "service_provider.employee.updated",
      });
      assert.ok(providerGrantLog);
      assert.equal(providerGrantLog.actor_user_id, providerOwner.id);
      assert.equal(providerGrantLog.actor_role, "service_provider");
      assert.equal(Number(providerGrantLog.workspace_id), Number(providerProfile.id));
      assert.deepEqual(providerGrantLog.new_value?.permissions, ["manage_employees"]);

      const providerWorkspace = await invoke(
        servicesController.getProviderWorkspace,
        providerControllerReq({}, {}, {}, providerActor.id)
      );
      assert.equal(providerWorkspace.error, null);
      assert.equal(Number(providerWorkspace.res.body.provider.id), Number(providerProfile.id));
      assert.deepEqual(providerWorkspace.res.body.access.permissions, ["manage_employees"]);

      const providerInvite = await invoke(
        servicesController.inviteProviderEmployee,
        providerControllerReq(
          {
            fullName: `Allowed Provider Invite ${makeSuffix("pi-")}`,
            phone: makePhone(77),
            pin: "1234",
            roleTag: "staff",
            displayName: "Allowed Provider Invite",
            contactEmail: "allowed-provider@example.com",
            permissions: ["manage_employees"],
            isActive: true,
            reason: "permission test invite",
          },
          {},
          {},
          providerActor.id
        )
      );
      assert.equal(providerInvite.error, null);
      assert.equal(providerInvite.res.statusCode, 201);
      trackedIds.userIds.push(Number(providerInvite.res.body.user.id));

      const providerInviteLog = await readLatestEmployeeLog({
        workspaceKind: "service_provider",
        workspaceId: providerProfile.id,
        employeeUserId: providerInvite.res.body.user.id,
        actionKey: "service_provider.employee.invited",
      });
      assert.ok(providerInviteLog);
      assert.equal(providerInviteLog.actor_user_id, providerActor.id);
      assert.equal(providerInviteLog.actor_role, "service_provider");
      assert.equal(Number(providerInviteLog.workspace_id), Number(providerProfile.id));

      const providerUpsert = await invoke(
        servicesController.upsertProviderEmployee,
        providerControllerReq(
          {
            employeeUserId: Number(providerUpsertTarget.id),
            roleTag: "staff",
            displayName: "Allowed Provider Upsert",
            contactEmail: "allowed-provider-upsert@example.com",
            permissions: ["manage_employees"],
            isActive: true,
            reason: "permission test upsert",
          },
          {},
          {},
          providerActor.id
        )
      );
      assert.equal(providerUpsert.error, null);
      assert.equal(providerUpsert.res.statusCode, 200);
      const providerUpsertRow = await q(
        `SELECT provider_id, employee_user_id, permissions_json
         FROM service_provider_employee_profile
         WHERE provider_id = $1
           AND employee_user_id = $2
         LIMIT 1`,
        [Number(providerProfile.id), Number(providerUpsertTarget.id)]
      );
      assert.equal(Number(providerUpsertRow.rows[0]?.provider_id), Number(providerProfile.id));
      assert.equal(Number(providerUpsertRow.rows[0]?.employee_user_id), Number(providerUpsertTarget.id));

      const secondProviderOwner = await createTestUser({
        fullName: `Provider Owner 2 ${makeSuffix("po2-")}`,
        phone: makePhone(78),
        role: "service_provider",
      });
      trackedIds.userIds.push(Number(secondProviderOwner.id));
      const secondProviderProfile = await servicesRepo.createProviderProfile({
        userId: secondProviderOwner.id,
        dto: {
          businessName: `Provider 2 ${makeSuffix("provider-")}`,
          mainCategoryId: null,
          bio: "Cross workspace provider",
          phone: makePhone(79),
          whatsappPhone: null,
          city: "Baghdad",
          area: "West",
          addressLine: "Second provider street",
          servesAtHome: true,
          servesAtShop: false,
          servesRemote: false,
          hasEmergencyService: false,
          bookingPolicy: "approval_required",
          pricingMode: "mixed",
          yearsExperience: 2,
          hasTeam: false,
          teamSize: null,
          acceptsCash: true,
          acceptsElectronic: false,
          averageResponseMinutes: 60,
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
          approvedByUserId: secondProviderOwner.id,
          approvedAt: new Date().toISOString(),
        },
      });
      trackedIds.providerIds.push(Number(secondProviderProfile.id));

      const crossWorkspaceMembership = await servicesRepo.upsertProviderEmployeeProfile({
        providerId: secondProviderProfile.id,
        employeeUserId: providerActor.id,
        roleTag: "staff",
        displayName: "Provider Employee",
        contactEmail: "provider-employee@example.com",
        permissions: [],
        isActive: true,
        archivedAt: null,
        notes: "cross workspace membership",
        invitedByUserId: secondProviderOwner.id,
        updatedByUserId: secondProviderOwner.id,
      });
      assert.ok(crossWorkspaceMembership);

      const crossWorkspaceView = await invoke(
        servicesController.getProviderWorkspace,
        providerControllerReq({}, {}, {}, providerActor.id)
      );
      assert.equal(crossWorkspaceView.error, null);
      assert.equal(
        Number(crossWorkspaceView.res.body.provider.id),
        Number(secondProviderProfile.id)
      );
      assert.deepEqual(crossWorkspaceView.res.body.access.permissions, []);

      const crossWorkspaceBlocked = await invoke(
        servicesController.inviteProviderEmployee,
        providerControllerReq(
          {
            fullName: `Blocked Cross Invite ${makeSuffix("pci-")}`,
            phone: makePhone(80),
            pin: "1234",
            roleTag: "staff",
            displayName: "Blocked Cross Invite",
            contactEmail: "blocked-cross@example.com",
            permissions: [],
            isActive: true,
            reason: "cross workspace check",
          },
          {},
          {},
          providerActor.id
        )
      );
      assertAppError(crossWorkspaceBlocked, "FORBIDDEN_SERVICE_PROVIDER_PERMISSION", 403);

      const providerDisabledDeactivate = await invoke(
        servicesController.upsertProviderEmployee,
        providerControllerReq(
          {
            employeeUserId: Number(providerDisabledActor.id),
            roleTag: "staff",
            displayName: "Provider Disabled",
            contactEmail: "provider-disabled@example.com",
            permissions: [],
            isActive: false,
            reason: "disabled for audit log",
          },
          {},
          {},
          providerOwner.id
        )
      );
      assert.equal(providerDisabledDeactivate.error, null);
      assert.equal(providerDisabledDeactivate.res.statusCode, 200);
      const providerDisabledReactivate = await invoke(
        servicesController.upsertProviderEmployee,
        providerControllerReq(
          {
            employeeUserId: Number(providerDisabledActor.id),
            roleTag: "staff",
            displayName: "Provider Disabled",
            contactEmail: "provider-disabled@example.com",
            permissions: [],
            isActive: true,
            reason: "reactivated for audit log",
          },
          {},
          {},
          providerOwner.id
        )
      );
      assert.equal(providerDisabledReactivate.error, null);
      assert.equal(providerDisabledReactivate.res.statusCode, 200);
      const providerDisabledAgain = await invoke(
        servicesController.upsertProviderEmployee,
        providerControllerReq(
          {
            employeeUserId: Number(providerDisabledActor.id),
            roleTag: "staff",
            displayName: "Provider Disabled",
            contactEmail: "provider-disabled@example.com",
            permissions: [],
            isActive: false,
            reason: "final disabled state",
          },
          {},
          {},
          providerOwner.id
        )
      );
      assert.equal(providerDisabledAgain.error, null);
      assert.equal(providerDisabledAgain.res.statusCode, 200);

      const providerDeactivateLogs = await q(
        `SELECT new_value
         FROM workspace_employee_activity_log
         WHERE workspace_kind = 'service_provider'
           AND workspace_id = $1
           AND employee_user_id = $2
           AND action_key = 'service_provider.employee.updated'
         ORDER BY id DESC`,
        [Number(providerProfile.id), Number(providerDisabledActor.id)]
      );
      const providerDeactivateStates = providerDeactivateLogs.rows.map(
        (row) => row.new_value?.isActive
      );
      assert.ok(providerDeactivateStates.includes(false));
      assert.ok(providerDeactivateStates.includes(true));

      const disabledWorkspace = await invoke(
        servicesController.getProviderWorkspace,
        providerControllerReq({}, {}, {}, providerDisabledActor.id)
      );
      assertAppError(
        disabledWorkspace,
        "SERVICE_PROVIDER_PROFILE_NOT_FOUND",
        404
      );

      const disabledInvite = await invoke(
        servicesController.inviteProviderEmployee,
        providerControllerReq(
          {
            fullName: "Disabled Provider Invite",
            phone: makePhone(81),
            pin: "1234",
            roleTag: "staff",
            displayName: "Disabled Invite",
            contactEmail: "disabled@example.com",
            permissions: [],
            isActive: true,
            reason: "disabled state check",
          },
          {},
          {},
          providerDisabledActor.id
        )
      );
      assertAppError(disabledInvite, "SERVICE_PROVIDER_PROFILE_NOT_FOUND", 404);
    } finally {
      await cleanupWorkspace(trackedIds);
    }
  });
});
