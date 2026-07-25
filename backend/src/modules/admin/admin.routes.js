import { Router } from "express";
import * as c from "./admin.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireAdmin } from "../../shared/middleware/admin.middleware.js";
import { requireBackoffice } from "../../shared/middleware/backoffice.middleware.js";
import { requireSuperAdmin } from "../../shared/middleware/super-admin.middleware.js";
import { requirePermission } from "../../shared/middleware/permission.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";
import * as taxiAdmin from "../taxi/taxi.admin.controller.js";
import * as ops from "./admin.ops.controller.js";
import * as rbac from "../security/permissions.controller.js";
import * as auditCtrl from "../security/audit.controller.js";
import * as monitoring from "./monitoring.controller.js";

export const adminRouter = Router();

adminRouter.use(requireAuth, requireBackoffice);

adminRouter.get("/analytics", c.analytics);
adminRouter.get("/approval-inbox", c.approvalInbox);
adminRouter.get("/audit-feed", c.auditFeed);
adminRouter.get("/customers/insights", requireSuperAdmin, c.customerInsightsList);
adminRouter.get("/ad-board/items", requireAdmin, c.adBoardItems);
adminRouter.get(
  "/ad-board/merchants/:merchantId/products",
  requireAdmin,
  c.adBoardMerchantProducts
);
adminRouter.get(
  "/customers/:customerUserId/insights",
  requireSuperAdmin,
  c.customerInsightDetails
);
adminRouter.get("/orders/print-report", c.printOrdersReport);
adminRouter.get("/orders/overview", c.adminOrdersOverview);
adminRouter.get("/orders/overview/:merchantId", c.adminMerchantOrdersOverview);
adminRouter.get("/merchants", c.merchants);
adminRouter.get("/store-activities", requireAdmin, c.storeActivities);
adminRouter.get(
  "/store-activities/:activityType/catalog-templates",
  requireAdmin,
  c.storeCatalogTemplates
);
adminRouter.get("/merchants/pending", c.pendingMerchants);
adminRouter.get("/delivery/pending", c.pendingDeliveryAccounts);
adminRouter.get("/taxi-captains/pending", c.pendingTaxiCaptainAccounts);
adminRouter.get("/settlements/pending", c.pendingSettlements);
adminRouter.get("/owners/available", c.availableOwners);
adminRouter.get(
  "/taxi-captains/subscription/pending-payments",
  requireAdmin,
  c.pendingTaxiCaptainCashPayments
);
adminRouter.get(
  "/taxi-captains/profile-edit-requests/pending",
  requireAdmin,
  c.pendingTaxiCaptainProfileEditRequests
);
adminRouter.get("/social-reports/posts", requireAdmin, c.socialPostReports);
adminRouter.get("/social-reports/stories", requireAdmin, c.socialStoryReports);
adminRouter.get("/social-reports/users", requireAdmin, c.socialUserReports);
adminRouter.get("/taxi/coupons", requireAdmin, taxiAdmin.listCoupons);
adminRouter.get(
  "/taxi/coupons/targets/lookups",
  requireAdmin,
  taxiAdmin.couponTargetLookups
);
adminRouter.get(
  "/taxi/captains/:captainUserId/details",
  requireAdmin,
  taxiAdmin.captainDetails
);
adminRouter.get("/taxi/contests", requireAdmin, taxiAdmin.listContests);
adminRouter.get("/taxi/complaints", requireAdmin, taxiAdmin.listComplaints);
// حالات الطوارئ على الرحلات + الإلغاء الطارئ — RBAC دقيق (المرحلة 2).
adminRouter.get(
  "/taxi/rides/emergencies",
  requirePermission("taxi.rides.read"),
  taxiAdmin.listRideEmergencies
);
adminRouter.post(
  "/taxi/rides/:rideId/emergency-cancel",
  requirePermission("taxi.rides.emergency_cancel"),
  taxiAdmin.emergencyCancelRide
);

// لوحة المتابعة الموحدة (المرحلة 3) — البطاقات حسب الصلاحيات + قوائم مُصفّحة.
adminRouter.get(
  "/monitoring/overview",
  requirePermission("dashboard.command_center.view"),
  monitoring.overview
);
adminRouter.get(
  "/monitoring/taxi/rides",
  requirePermission("taxi.rides.read"),
  monitoring.taxiRides
);

// إدارة الصلاحيات الدقيقة (RBAC).
adminRouter.get("/me/permissions", rbac.getMyPermissions);
adminRouter.get(
  "/rbac/catalog",
  requirePermission("employees.permissions.manage"),
  rbac.getCatalog
);
adminRouter.get(
  "/rbac/change-log",
  requirePermission("audit.read"),
  rbac.getChangeLog
);
adminRouter.get(
  "/audit/events",
  requirePermission("audit.read"),
  auditCtrl.listAuditEvents
);
adminRouter.get(
  "/rbac/users/:userId/permissions",
  requirePermission("employees.permissions.manage"),
  rbac.getUserPermissions
);
adminRouter.post(
  "/rbac/users/:userId/permissions",
  requirePermission("employees.permissions.manage"),
  rbac.upsertUserPermission
);
adminRouter.delete(
  "/rbac/users/:userId/permissions/:permissionKey",
  requirePermission("employees.permissions.manage"),
  rbac.clearUserPermission
);
adminRouter.post(
  "/rbac/users/:userId/role",
  requirePermission("employees.permissions.manage"),
  rbac.assignAdminRole
);
adminRouter.get("/taxi/kpi/overview", requireAdmin, taxiAdmin.kpiOverview);
adminRouter.get("/taxi/reports", requireAdmin, taxiAdmin.reports);
adminRouter.get("/ops/alerts", requireAdmin, ops.listOpsAlerts);
adminRouter.get(
  "/ops/notifications/overview",
  requireAdmin,
  ops.notificationOperationsOverview
);
adminRouter.get(
  "/ops/device-push-health",
  requireAdmin,
  ops.devicePushReliability
);
adminRouter.get("/ops/crashes", requireAdmin, ops.listCrashEvents);
adminRouter.get("/ops/feature-flags", requireAdmin, ops.listFeatureFlags);
adminRouter.get(
  "/ops/permissions-matrix",
  requireAdmin,
  ops.listPermissionOverrides
);
adminRouter.get(
  "/residence-change-requests",
  requireAdmin,
  c.residenceChangeRequests
);
adminRouter.get(
  "/profile-core-change-requests",
  requireAdmin,
  c.profileCoreChangeRequests
);
adminRouter.get("/social-users", requireAdmin, c.socialUsersForModeration);
adminRouter.get(
  "/social-restrictions/users/:userId",
  requireAdmin,
  c.socialRestrictionsForUser
);

adminRouter.post("/users", requireAdmin, imageUpload.single("imageFile"), c.createUser);
adminRouter.post(
  "/ad-board/items",
  requireAdmin,
  imageUpload.single("imageFile"),
  c.createAdBoardItem
);
adminRouter.patch("/merchants/:merchantId/approve", requireAdmin, c.approveMerchant);
adminRouter.patch(
  "/ad-board/items/:itemId",
  requireAdmin,
  imageUpload.single("imageFile"),
  c.updateAdBoardItem
);
adminRouter.patch(
  "/delivery/:deliveryUserId/approve",
  requireAdmin,
  c.approveDeliveryAccount
);
adminRouter.patch(
  "/delivery/:deliveryUserId/profile",
  requireAdmin,
  c.updateDeliveryDriverProfile
);
adminRouter.patch(
  "/taxi-captains/:captainUserId/approve",
  requireAdmin,
  c.approveTaxiCaptainAccount
);
adminRouter.patch(
  "/taxi-captains/:captainUserId/subscription/confirm-cash-payment",
  requireAdmin,
  c.confirmTaxiCaptainCashPayment
);
adminRouter.patch(
  "/taxi-captains/:captainUserId/subscription/discount",
  requireAdmin,
  c.setTaxiCaptainDiscount
);
adminRouter.patch(
  "/taxi-captains/profile-edit-requests/:requestId/approve",
  requireAdmin,
  c.approveTaxiCaptainProfileEditRequest
);
adminRouter.patch(
  "/taxi-captains/profile-edit-requests/:requestId/reject",
  requireAdmin,
  c.rejectTaxiCaptainProfileEditRequest
);
adminRouter.post(
  "/social-reports/posts/:postId/review",
  requireAdmin,
  c.reviewSocialPostReport
);
adminRouter.post("/taxi/coupons", requireAdmin, taxiAdmin.createCoupon);
adminRouter.post("/ops/feature-flags", requireAdmin, ops.upsertFeatureFlag);
adminRouter.post(
  "/ops/permissions-matrix",
  requireAdmin,
  ops.upsertPermissionOverride
);
adminRouter.post(
  "/ops/test-artifacts/cleanup",
  requireSuperAdmin,
  ops.cleanupTestArtifacts
);
adminRouter.post("/ops/alerts/:alertId/ack", requireAdmin, ops.acknowledgeOpsAlert);
adminRouter.post(
  "/taxi/captains/:captainUserId/gifts",
  requireAdmin,
  taxiAdmin.issueCaptainGift
);
adminRouter.post(
  "/taxi/captains/:captainUserId/warnings",
  requireAdmin,
  taxiAdmin.issueCaptainWarning
);
adminRouter.post("/taxi/contests", requireAdmin, taxiAdmin.createContest);
adminRouter.post(
  "/taxi/contests/:contestId/finalize",
  requireAdmin,
  taxiAdmin.finalizeContest
);
adminRouter.post(
  "/social-reports/stories/:storyId/review",
  requireAdmin,
  c.reviewSocialStoryReport
);
adminRouter.post(
  "/social-reports/posts/:postId/approve-edit",
  requireAdmin,
  c.approveEditedSocialPost
);
adminRouter.post(
  "/social-reports/stories/:storyId/approve-edit",
  requireAdmin,
  c.approveEditedSocialStory
);
adminRouter.post(
  "/social-restrictions/users/:userId",
  requireAdmin,
  c.createSocialRestriction
);
adminRouter.post(
  "/social-restrictions/:restrictionId/revoke",
  requireAdmin,
  c.revokeSocialRestriction
);
adminRouter.post("/store-activities", requireAdmin, c.upsertStoreActivity);
adminRouter.post(
  "/store-activities/:activityType/catalog-templates",
  requireAdmin,
  c.upsertStoreCatalogTemplate
);
adminRouter.patch(
  "/social-users/:userId/account-status",
  requireAdmin,
  c.setSocialUserAccountStatus
);
adminRouter.patch(
  "/store-catalog-templates/:templateId",
  requireAdmin,
  c.updateStoreCatalogTemplate
);
adminRouter.delete(
  "/store-catalog-templates/:templateId",
  requireAdmin,
  c.deleteStoreCatalogTemplate
);
adminRouter.patch(
  "/store-activities/:activityType",
  requireAdmin,
  c.upsertStoreActivity
);
adminRouter.patch(
  "/merchants/:merchantId/profile",
  requireAdmin,
  c.updateMerchantProfile
);
adminRouter.patch(
  "/residence-change-requests/:requestId/approve",
  requireAdmin,
  c.approveResidenceChangeRequest
);
adminRouter.patch(
  "/residence-change-requests/:requestId/reject",
  requireAdmin,
  c.rejectResidenceChangeRequest
);
adminRouter.patch(
  "/profile-core-change-requests/:requestId/approve",
  requireAdmin,
  c.approveProfileCoreChangeRequest
);
adminRouter.patch(
  "/profile-core-change-requests/:requestId/reject",
  requireAdmin,
  c.rejectProfileCoreChangeRequest
);
adminRouter.patch("/taxi/coupons/:id", requireAdmin, taxiAdmin.updateCoupon);
adminRouter.patch(
  "/taxi/captains/:captainUserId/status",
  requireAdmin,
  taxiAdmin.setCaptainStatus
);
adminRouter.patch(
  "/taxi/complaints/:complaintId/review",
  requireAdmin,
  taxiAdmin.reviewComplaint
);
adminRouter.patch(
  "/taxi/contests/:contestId",
  requireAdmin,
  taxiAdmin.updateContest
);
adminRouter.patch(
  "/merchants/:merchantId/disabled",
  requireAdmin,
  c.toggleMerchantDisabled
);
adminRouter.patch(
  "/settlements/:settlementId/approve",
  requireAdmin,
  c.approveSettlement
);
adminRouter.delete("/ad-board/items/:itemId", requireAdmin, c.deleteAdBoardItem);
adminRouter.delete("/taxi/coupons/:id", requireAdmin, taxiAdmin.deleteCoupon);
adminRouter.delete(
  "/taxi/contests/:contestId",
  requireAdmin,
  taxiAdmin.deleteContest
);
