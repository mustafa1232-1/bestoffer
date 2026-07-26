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
import * as settings from "../settings/settings.controller.js";
import * as support from "../support/support.controller.js";
import * as employees from "../employees/employees.controller.js";
import * as hradmin from "../employees/hradmin.controller.js";
import * as orderRevisions from "../orders/order-revisions.controller.js";

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
adminRouter.get(
  "/monitoring/taxi/rides/:rideId",
  requirePermission("taxi.rides.read"),
  monitoring.taxiRideDetail
);
adminRouter.get(
  "/monitoring/orders",
  requirePermission("orders.read"),
  monitoring.orders
);
adminRouter.get(
  "/monitoring/orders/:orderId",
  requirePermission("orders.read"),
  monitoring.orderDetail
);
adminRouter.get(
  "/monitoring/delivery/couriers",
  requirePermission("orders.read"),
  monitoring.deliveryCouriers
);
adminRouter.get(
  "/monitoring/delivery/couriers/:courierId",
  requirePermission("orders.read"),
  monitoring.deliveryCourierDetail
);
adminRouter.get(
  "/monitoring/services/requests",
  requirePermission("services.read"),
  monitoring.serviceRequests
);
adminRouter.get(
  "/monitoring/services/requests/:requestId",
  requirePermission("services.read"),
  monitoring.serviceRequestDetail
);
adminRouter.get(
  "/monitoring/real-estate/listings",
  requirePermission("real_estate.read"),
  monitoring.realEstateListings
);
adminRouter.get(
  "/monitoring/real-estate/listings/:listingId",
  requirePermission("real_estate.read"),
  monitoring.realEstateListingDetail
);
adminRouter.get(
  "/monitoring/cars/listings",
  requirePermission("cars.read"),
  monitoring.carListings
);
adminRouter.get(
  "/monitoring/cars/listings/:listingId",
  requirePermission("cars.read"),
  monitoring.carListingDetail
);
adminRouter.get(
  "/monitoring/jobs",
  requirePermission("jobs.read"),
  monitoring.jobs
);
adminRouter.get(
  "/monitoring/jobs/:jobId",
  requirePermission("jobs.read"),
  monitoring.jobDetail
);
adminRouter.get(
  "/monitoring/jobs/:jobId/applications",
  requirePermission("jobs.applications.read"),
  monitoring.jobApplications
);
adminRouter.get(
  "/monitoring/jobs/applications/:applicationId",
  requirePermission("jobs.applications.read"),
  monitoring.jobApplicationDetail
);
adminRouter.get(
  "/monitoring/jobs/applications/:applicationId/cv",
  requirePermission("jobs.cv.download"),
  monitoring.jobApplicationCv
);
adminRouter.get(
  "/monitoring/community/users",
  requirePermission("community.users.read"),
  monitoring.communityUsers
);
adminRouter.get(
  "/monitoring/community/users/:userId",
  requirePermission("community.users.read"),
  monitoring.communityUserDetail
);
adminRouter.get(
  "/monitoring/community/users/:userId/content",
  requirePermission("community.posts.read"),
  monitoring.communityUserContent
);
adminRouter.get(
  "/monitoring/community/users/:userId/reports",
  requirePermission("community.posts.read"),
  monitoring.communityUserReports
);

// إعدادات الدعم المركزية (المرحلة 8).
adminRouter.get(
  "/settings/support",
  requirePermission("settings.support_phone.update"),
  settings.getSupport
);
adminRouter.put(
  "/settings/support",
  requirePermission("settings.support_phone.update"),
  settings.updateSupport
);

// نظام التذاكر الموحّد (المرحلة 4) — إدارة/دعم.
adminRouter.get(
  "/support/tickets",
  requirePermission("support.tickets.read"),
  support.adminListTickets
);
adminRouter.get(
  "/support/tickets/:ticketId",
  requirePermission("support.tickets.read"),
  support.adminGetTicket
);
adminRouter.get(
  "/support/tickets/:ticketId/order-revisions",
  requirePermission("support.tickets.read"),
  requirePermission("orders.read"),
  orderRevisions.adminListForTicket
);
adminRouter.get(
  "/support/tickets/:ticketId/order-context",
  requirePermission("support.tickets.read"),
  requirePermission("orders.read"),
  orderRevisions.adminOrderContextForTicket
);
adminRouter.post(
  "/support/tickets/:ticketId/order-revisions",
  requirePermission("support.tickets.read"),
  requirePermission("orders.read"),
  requirePermission("orders.revisions.create"),
  orderRevisions.adminCreateFromTicket
);
adminRouter.post(
  "/support/tickets/:ticketId/assign",
  requirePermission("support.tickets.assign"),
  support.adminAssign
);
adminRouter.post(
  "/support/tickets/:ticketId/join",
  requirePermission("support.tickets.reply"),
  support.adminJoin
);
adminRouter.post(
  "/support/tickets/:ticketId/messages",
  requirePermission("support.tickets.reply"),
  support.adminReply
);
adminRouter.post(
  "/support/tickets/:ticketId/link",
  requirePermission("support.tickets.assign"),
  support.adminLinkEntity
);
adminRouter.post(
  "/support/tickets/:ticketId/transition",
  requirePermission("support.tickets.reply"),
  support.adminTransition
);
adminRouter.post(
  "/support/tickets/:ticketId/resolve",
  requirePermission("support.tickets.resolve"),
  support.adminResolve
);
adminRouter.post(
  "/support/tickets/:ticketId/escalate",
  requirePermission("support.tickets.escalate"),
  support.adminEscalate
);
adminRouter.get(
  "/orders/:orderId/revisions/:revisionId",
  requirePermission("orders.read"),
  orderRevisions.adminGetRevision
);
adminRouter.patch(
  "/orders/:orderId/revisions/:revisionId",
  requirePermission("support.tickets.read"),
  requirePermission("orders.read"),
  requirePermission("orders.modify"),
  orderRevisions.adminPatchRevision
);
adminRouter.post(
  "/orders/:orderId/revisions/:revisionId/submit",
  requirePermission("support.tickets.read"),
  requirePermission("orders.read"),
  requirePermission("orders.revisions.submit"),
  orderRevisions.adminSubmitRevision
);
adminRouter.post(
  "/orders/:orderId/revisions/:revisionId/apply",
  requirePermission("support.tickets.read"),
  requirePermission("orders.read"),
  requirePermission("orders.revisions.apply"),
  orderRevisions.adminApplyRevision
);

// إدارة موظفي الشركة (المرحلة 6).
adminRouter.get(
  "/employees",
  requirePermission("employees.read"),
  employees.listEmployees
);
adminRouter.get(
  "/employees/:userId",
  requirePermission("employees.read"),
  employees.getEmployee
);
adminRouter.post(
  "/employees",
  requirePermission("employees.create"),
  employees.saveEmployee
);
adminRouter.put(
  "/employees/:userId",
  requirePermission("employees.update"),
  employees.saveEmployee
);
adminRouter.get(
  "/employees/:userId/salary",
  requirePermission("employees.salary.read"),
  employees.getSalary
);
adminRouter.put(
  "/employees/:userId/salary",
  requirePermission("employees.salary.update"),
  employees.updateSalary
);

// الحضور والمصاريف (المرحلة 7).
adminRouter.get("/attendance", requirePermission("attendance.read"), hradmin.listAttendance);
adminRouter.post(
  "/attendance/:attendanceId/correct",
  requirePermission("attendance.approve"),
  hradmin.correctAttendance
);
adminRouter.get("/expenses", requirePermission("attendance.read"), hradmin.listExpenses);
adminRouter.post(
  "/expenses/:expenseId/review",
  requirePermission("attendance.approve"),
  hradmin.reviewExpense
);

// دورة الرواتب (المرحلة 7) — صلاحية مستقلة لكل مرحلة.
adminRouter.get("/payroll/runs", requirePermission("employees.salary.read"), hradmin.listRuns);
adminRouter.post("/payroll/runs", requirePermission("payroll.prepare"), hradmin.createRun);
adminRouter.get("/payroll/runs/:runId", requirePermission("employees.salary.read"), hradmin.getRun);
adminRouter.post(
  "/payroll/runs/:runId/calculate",
  requirePermission("payroll.prepare"),
  hradmin.calculateRun
);
adminRouter.post(
  "/payroll/runs/:runId/submit",
  requirePermission("payroll.review"),
  hradmin.submitRunForReview
);
adminRouter.post(
  "/payroll/runs/:runId/approve",
  requirePermission("payroll.approve"),
  hradmin.approveRun
);
adminRouter.post(
  "/payroll/runs/:runId/release",
  requirePermission("payroll.release"),
  hradmin.releaseRun
);
adminRouter.post(
  "/payroll/runs/:runId/mark-paid",
  requirePermission("payroll.mark_paid"),
  hradmin.markRunPaid
);
adminRouter.post(
  "/payroll/runs/:runId/acknowledge",
  requirePermission("payroll.review"),
  hradmin.acknowledgeRun
);
adminRouter.post(
  "/payroll/runs/:runId/archive",
  requirePermission("payroll.review"),
  hradmin.archiveRun
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
  "/rbac/roles",
  requirePermission("employees.permissions.manage"),
  rbac.listRoles
);
adminRouter.post(
  "/rbac/roles",
  requirePermission("employees.permissions.manage"),
  rbac.createRole
);
adminRouter.put(
  "/rbac/roles/:roleKey",
  requirePermission("employees.permissions.manage"),
  rbac.updateRole
);
adminRouter.post(
  "/rbac/roles/:roleKey/copy",
  requirePermission("employees.permissions.manage"),
  rbac.copyRole
);
adminRouter.post(
  "/rbac/roles/:roleKey/archive",
  requirePermission("employees.permissions.manage"),
  rbac.archiveRole
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
adminRouter.get(
  "/ops/alerts",
  requirePermission("ops.alerts.read"),
  ops.listOpsAlerts
);
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
adminRouter.post(
  "/ops/alerts/:alertId/ack",
  requirePermission("ops.alerts.acknowledge"),
  ops.acknowledgeOpsAlert
);
adminRouter.post(
  "/ops/alerts/:alertId/assign",
  requirePermission("ops.alerts.assign"),
  ops.assignOpsAlert
);
adminRouter.post(
  "/ops/alerts/:alertId/resolve",
  requirePermission("ops.alerts.resolve"),
  ops.resolveOpsAlert
);
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
