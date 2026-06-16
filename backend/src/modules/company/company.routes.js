import { Router } from "express";
import * as c from "./company.controller.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import {
  requireCompanyAuth,
  requireCompanyRoles,
  resolveCompanyContext,
} from "../../shared/middleware/company.middleware.js";
import { requireAdmin } from "../../shared/middleware/admin.middleware.js";

/**
 * Purpose:
 * مسارات بوابة الشركات الداخلية وإدارة الشركات من الأدمن.
 *
 * Structure:
 * - `/auth/*` لتسجيل الدخول والbootstrap
 * - `/admin/*` لإدارة الشركات وطلبات ربط الفروع من الأدمن فقط
 * - بقية المسارات بعد `resolveCompanyContext` لإدارة الشركة نفسها
 *
 * Critical notes:
 * - هذا router يجمع طبقتين مختلفتين من الصلاحيات: admin backoffice
 *   وcompany membership context.
 * - أي خطأ في ترتيب middleware هنا يؤدي مباشرة إلى access leaks أو 403 خاطئ.
 */
export const companyRouter = Router();

companyRouter.post("/auth/login", c.companyLogin);
companyRouter.get("/auth/bootstrap", requireAuth, requireCompanyAuth, c.companyBootstrap);

// أدوات الإدارة المركزية للشركات: محصورة بالأدمن/السوبر أدمن.
companyRouter.get("/admin/companies", requireAuth, requireAdmin, c.adminListCompanies);
companyRouter.post("/admin/companies", requireAuth, requireAdmin, c.adminCreateCompany);
companyRouter.patch("/admin/companies/:companyId", requireAuth, requireAdmin, c.adminUpdateCompany);
companyRouter.delete("/admin/companies/:companyId", requireAuth, requireAdmin, c.adminDeleteCompany);
companyRouter.post("/admin/companies/:companyId/branches/link", requireAuth, requireAdmin, c.adminLinkBranch);
companyRouter.delete("/admin/companies/:companyId/branches/:merchantId", requireAuth, requireAdmin, c.adminUnlinkBranch);
companyRouter.get("/admin/branch-requests", requireAuth, requireAdmin, c.adminListBranchRequests);
companyRouter.post("/admin/branch-requests/:requestId/approve", requireAuth, requireAdmin, c.adminApproveBranchRequest);
companyRouter.post("/admin/branch-requests/:requestId/reject", requireAuth, requireAdmin, c.adminRejectBranchRequest);

// كل ما بعد هذه النقطة يحتاج عضوية شركة فعلية وسياق شركة محدد.
companyRouter.use(requireAuth, requireCompanyAuth, resolveCompanyContext);

companyRouter.get("/dashboard", c.dashboard);
companyRouter.get("/branches", c.branches);
companyRouter.get("/branches/:merchantId", c.branchDetail);
companyRouter.post("/branches/requests", requireCompanyRoles(["company_owner", "company_manager"]), c.createBranchRequest);
companyRouter.get("/branch-requests", c.listBranchRequests);
companyRouter.post("/products/copy", requireCompanyRoles(["company_owner", "company_manager", "operations_viewer"]), c.copyProducts);
companyRouter.get("/coupons", c.listCoupons);
companyRouter.post("/coupons", requireCompanyRoles(["company_owner", "company_manager"]), c.createCoupon);
companyRouter.get("/campaigns", c.listCampaigns);
companyRouter.post("/campaigns", requireCompanyRoles(["company_owner", "company_manager"]), c.createCampaign);
companyRouter.get("/inventory/overview", c.inventoryOverview);
companyRouter.get("/inventory/branches/:merchantId", c.branchInventory);
companyRouter.patch("/inventory/branches/:merchantId/settings", requireCompanyRoles(["company_owner", "company_manager", "operations_viewer"]), c.patchInventorySettings);
companyRouter.patch("/inventory/branches/:merchantId/items/:productId", requireCompanyRoles(["company_owner", "company_manager", "operations_viewer"]), c.patchInventoryItem);
companyRouter.post("/inventory/branches/:merchantId/daily-check", requireCompanyRoles(["company_owner", "company_manager", "operations_viewer"]), c.confirmDailyCheck);
companyRouter.get("/users", c.listUsers);
companyRouter.post("/users", requireCompanyRoles(["company_owner", "company_manager"]), c.createUser);
companyRouter.patch("/settings/policy", requireCompanyRoles(["company_owner", "company_manager"]), c.updatePolicy);
