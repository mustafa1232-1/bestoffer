import { Router } from "express";
import * as c from "./commerce.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireOwner } from "../../shared/middleware/owner.middleware.js";
import { requireDeliveryAgent } from "../../shared/middleware/delivery-agent.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import { requireBackoffice } from "../../shared/middleware/backoffice.middleware.js";

export const commerceRouter = Router();

commerceRouter.use(requireAuth);

commerceRouter.get(
  "/search/products",
  requireCustomer,
  c.searchProductsGlobal
);

// Order lifecycle: store side
commerceRouter.post("/orders/:orderId/store/start-preparing", requireOwner, c.ownerStartPreparing);
commerceRouter.post("/orders/:orderId/store/assign-courier", requireOwner, c.ownerAssignCourier);
commerceRouter.post("/orders/:orderId/store/ready-for-pickup", requireOwner, c.ownerReadyForPickup);

// Order lifecycle: courier side
commerceRouter.post("/orders/:orderId/courier/accept", requireDeliveryAgent, c.courierAcceptOrder);
commerceRouter.post("/orders/:orderId/courier/reject", requireDeliveryAgent, c.courierRejectOrder);
commerceRouter.post("/orders/:orderId/courier/picked-up", requireDeliveryAgent, c.courierPickedUpOrder);
commerceRouter.post("/orders/:orderId/courier/arrived", requireDeliveryAgent, c.courierArrivedOrder);
commerceRouter.post("/orders/:orderId/courier/delivered", requireDeliveryAgent, c.courierDeliveredOrder);
commerceRouter.post(
  "/orders/:orderId/courier/request-cancel",
  requireDeliveryAgent,
  c.courierRequestCancelOrder
);

// Order private chat: customer <-> courier (kept for admin audit)
commerceRouter.get("/orders/:orderId/chat/messages", c.orderChatMessages);
commerceRouter.post("/orders/:orderId/chat/messages", c.orderChatSendMessage);

// Courier cancellation review
commerceRouter.post(
  "/orders/:orderId/store/review-cancel-request",
  requireOwner,
  c.ownerReviewCourierCancelRequest
);
commerceRouter.post(
  "/orders/:orderId/admin/review-cancel-request",
  requireBackoffice,
  c.adminReviewCourierCancelRequest
);

// Order lifecycle: customer confirmation
commerceRouter.post("/orders/:orderId/customer/confirm-received", requireCustomer, c.customerConfirmReceived);

// Courier dashboards/reports
commerceRouter.get("/courier/dashboard", requireDeliveryAgent, c.courierDashboard);
commerceRouter.post("/courier/presence", requireDeliveryAgent, c.courierPresence);
commerceRouter.get("/courier/requests", requireDeliveryAgent, c.courierRequests);
commerceRouter.get("/courier/orders", requireDeliveryAgent, c.courierOrders);
commerceRouter.get(
  "/courier/orders/grouped-by-merchant",
  requireDeliveryAgent,
  c.courierOrdersGroupedByMerchant
);
commerceRouter.get("/courier/reports", requireDeliveryAgent, c.courierReports);
commerceRouter.get("/courier/earnings", requireDeliveryAgent, c.courierEarnings);
commerceRouter.get("/courier/competitions", requireDeliveryAgent, c.courierCompetitions);
commerceRouter.get(
  "/courier/competitions/achievements/summary",
  requireDeliveryAgent,
  c.courierCompetitionAchievementsSummary
);
commerceRouter.get(
  "/courier/competitions/:competitionId",
  requireDeliveryAgent,
  c.courierCompetitionDetails
);
commerceRouter.get(
  "/courier/competition-progress",
  requireDeliveryAgent,
  c.courierCompetitionProgress
);

// Merchant dashboards/reports/receivables
commerceRouter.get("/merchant/dashboard", requireOwner, c.merchantDashboard);
commerceRouter.get("/merchant/kpis", requireOwner, c.merchantKpis);
commerceRouter.get("/merchant/top-products", requireOwner, c.merchantTopProducts);
commerceRouter.get("/merchant/top-categories", requireOwner, c.merchantTopCategories);
commerceRouter.get("/merchant/orders/reports", requireOwner, c.merchantOrdersReports);
commerceRouter.get(
  "/merchant/reviews/verified",
  requireOwner,
  c.merchantVerifiedReviews
);
commerceRouter.get(
  "/merchant/customers/:customerUserId/reliability",
  requireOwner,
  c.merchantCustomerReliability
);

commerceRouter.get("/merchant/couriers", requireOwner, c.merchantListCouriers);
commerceRouter.post("/merchant/couriers", requireOwner, c.merchantCreateCourier);
commerceRouter.patch(
  "/merchant/couriers/:courierUserId",
  requireOwner,
  c.merchantPatchCourier
);

commerceRouter.get("/merchant/receivables", requireOwner, c.merchantReceivables);
commerceRouter.get(
  "/merchant/receivables/ledger",
  requireOwner,
  c.merchantReceivablesLedger
);
commerceRouter.get(
  "/merchant/receivable-invoices",
  requireOwner,
  c.merchantReceivableInvoices
);
commerceRouter.post(
  "/merchant/payment-requests/preview-selection",
  requireOwner,
  c.merchantPreviewPaymentSelection
);
commerceRouter.get(
  "/merchant/payment-requests",
  requireOwner,
  c.merchantListPaymentRequests
);
commerceRouter.get(
  "/merchant/payment-requests/:paymentRequestId",
  requireOwner,
  c.merchantPaymentRequestDetails
);
commerceRouter.get(
  "/merchant/payment-requests/:paymentRequestId/invoices",
  requireOwner,
  c.merchantPaymentRequestInvoices
);
commerceRouter.post(
  "/merchant/payment-requests",
  requireOwner,
  c.merchantCreatePaymentRequest
);
commerceRouter.patch(
  "/merchant/payment-requests/:paymentRequestId",
  requireOwner,
  c.merchantPatchPaymentRequest
);
commerceRouter.post(
  "/merchant/payment-requests/:paymentRequestId/confirm-received",
  requireOwner,
  c.merchantConfirmPaymentRequestReceived
);
commerceRouter.post(
  "/merchant/payment-requests/:paymentRequestId/report-issue",
  requireOwner,
  c.merchantReportPaymentRequestIssue
);

// Admin receivables + billing profiles
commerceRouter.get(
  "/admin/merchants/receivables",
  requireBackoffice,
  c.adminMerchantsReceivables
);
commerceRouter.get(
  "/admin/merchants/:merchantId/receivables",
  requireBackoffice,
  c.adminMerchantReceivables
);
commerceRouter.patch(
  "/admin/merchants/:merchantId/billing-profile",
  requireBackoffice,
  c.adminPatchMerchantBillingProfile
);
commerceRouter.post(
  "/admin/payment-requests/:paymentRequestId/mark-received",
  requireBackoffice,
  c.adminMarkPaymentReceived
);
commerceRouter.get(
  "/admin/payment-requests/:paymentRequestId/invoices",
  requireBackoffice,
  c.adminPaymentRequestInvoices
);
commerceRouter.post(
  "/admin/payment-requests/:paymentRequestId/approve",
  requireBackoffice,
  c.adminApprovePaymentRequest
);
commerceRouter.post(
  "/admin/payment-requests/:paymentRequestId/assign",
  requireBackoffice,
  c.adminAssignPaymentRequest
);
commerceRouter.post(
  "/admin/payment-requests/:paymentRequestId/mark-paid",
  requireBackoffice,
  c.adminMarkPaymentRequestPaid
);
commerceRouter.post(
  "/admin/payment-requests/:paymentRequestId/return-for-revision",
  requireBackoffice,
  c.adminReturnPaymentRequestForRevision
);
commerceRouter.post(
  "/admin/payment-requests/:paymentRequestId/reject",
  requireBackoffice,
  c.adminRejectPayment
);
commerceRouter.post(
  "/admin/merchants/:merchantId/app-payables/adjustment",
  requireBackoffice,
  c.adminCreateAppPayablesAdjustment
);

// Admin financial KPI + reports
commerceRouter.get(
  "/admin/financial/kpis",
  requireBackoffice,
  c.adminFinancialKpis
);
commerceRouter.get(
  "/admin/customer-reliability/policy",
  requireBackoffice,
  c.adminGetCustomerReliabilityPolicy
);
commerceRouter.put(
  "/admin/customer-reliability/policy",
  requireBackoffice,
  c.adminUpdateCustomerReliabilityPolicy
);
commerceRouter.get(
  "/admin/delivery-dispatch/policy",
  requireBackoffice,
  c.adminGetDeliveryDispatchPolicy
);
commerceRouter.put(
  "/admin/delivery-dispatch/policy",
  requireBackoffice,
  c.adminUpdateDeliveryDispatchPolicy
);
commerceRouter.get(
  "/admin/reports/sales",
  requireBackoffice,
  c.adminSalesReport
);
commerceRouter.get(
  "/admin/reports/sales/:merchantId",
  requireBackoffice,
  c.adminSalesMerchantDetails
);
commerceRouter.get(
  "/admin/reports/collections",
  requireBackoffice,
  c.adminCollectionsReport
);
commerceRouter.get(
  "/admin/reports/collections/:merchantId",
  requireBackoffice,
  c.adminCollectionsMerchantDetails
);
commerceRouter.get(
  "/admin/reports/receivables",
  requireBackoffice,
  c.adminReceivablesReport
);
commerceRouter.get(
  "/admin/reports/receivables/:merchantId/statement",
  requireBackoffice,
  c.adminReceivablesMerchantStatement
);

// Admin competitions + platform KPIs
commerceRouter.get("/admin/competitions", requireBackoffice, c.adminCompetitions);
commerceRouter.post("/admin/competitions", requireBackoffice, c.adminCreateCompetition);
commerceRouter.get(
  "/admin/competitions/:competitionId/winners",
  requireBackoffice,
  c.adminCompetitionWinners
);
commerceRouter.get(
  "/admin/competitions/:competitionId",
  requireBackoffice,
  c.adminCompetitionDetails
);
commerceRouter.post(
  "/admin/competitions/:competitionId/end",
  requireBackoffice,
  c.adminEndCompetition
);
commerceRouter.patch(
  "/admin/competitions/:competitionId",
  requireBackoffice,
  c.adminPatchCompetition
);
commerceRouter.get("/admin/platform-kpis", requireBackoffice, c.adminPlatformKpis);
