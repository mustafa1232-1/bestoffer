/**
 * Purpose:
 * كتالوج مفاتيح الصلاحيات الدقيقة وقوالب الأدوار (المرحلة 2 - أساس RBAC).
 * مصدر الحقيقة لأسماء المفاتيح الصالحة والنطاقات وقوالب الأدوار الافتراضية.
 *
 * مبدأ: المنع افتراضياً. لا صلاحية إلا إذا مُنحت صراحةً عبر قالب دور أو منحة
 * فردية. Super Admin يتجاوز كل شيء.
 *
 * التطبيق الفعلي (per-request fresh read) في permissions.service.js — لا نُخزّن
 * الصلاحيات داخل التوكن حتى لا تبقى صلاحيات قديمة سارية.
 */

// كل مفاتيح الصلاحيات المعروفة. أي مفتاح خارج هذه المجموعة يُرفض في المنح.
export const PERMISSION_KEYS = Object.freeze([
  "dashboard.command_center.view",

  "taxi.rides.read",
  "taxi.rides.track_live",
  "taxi.rides.history",
  "taxi.rides.messages.read",
  "taxi.rides.emergency_cancel",

  "orders.read",
  "orders.customer_phone.read",
  "orders.modify",
  "orders.cancel",
  "orders.revisions.create",
  "orders.revisions.submit",
  "orders.revisions.apply",
  "orders.refund",
  "orders.messages.read",
  "delivery.couriers.phone.read",

  "services.read",
  "services.messages.case_bound_read",
  "services.modify",
  "real_estate.read",
  "real_estate.contact.read",
  "real_estate.moderate",
  "cars.read",
  "cars.contact.read",
  "cars.moderate",
  "jobs.read",
  "jobs.applications.read",
  "jobs.cv.download",

  "merchants.approve",
  "merchants.financial_terms.send",
  "merchants.financial_terms.approve",
  "taxi.captains.approve",
  "delivery.accounts.create",

  "community.posts.read",
  "community.moderate",
  "community.users.read",
  "community.messages.case_bound_read",

  "support.tickets.read",
  "support.tickets.assign",
  "support.tickets.reply",
  "support.tickets.resolve",
  "support.tickets.escalate",
  "support.sla.manage",

  "ops.alerts.read",
  "ops.alerts.acknowledge",
  "ops.alerts.assign",
  "ops.alerts.resolve",

  "employees.read",
  "employees.create",
  "employees.update",
  "employees.permissions.manage",
  "employees.salary.read",
  "employees.salary.update",

  "attendance.read",
  "attendance.approve",
  "payroll.prepare",
  "payroll.review",
  "payroll.approve",
  "payroll.release",
  "payroll.mark_paid",

  "settings.support_phone.update",
  "settings.themes.manage",
  "settings.guides.manage",

  "accounts.restrict",
  "accounts.suspend",
  "accounts.delete_request",
  "accounts.delete_approve",

  "audit.read",
  "reports.export",

  "coupons.agents.manage",

  // Every super-admin capability is a grantable key (except the chat quality
  // monitor, which is intentionally NOT here — super-admin surface only).
  "merchants.create",
  "jobs.manage",
  "feed.moderate",
  "ads.manage",
  "competitions.manage",
  "coupons.manage",
  "residence.requests.manage",
  "paid_upgrades.manage",
  "companies.manage",
  "sections.availability.manage",
  "customer_reliability.manage",
  "system.notifications.view",
  "system.device_reliability.view",
  "system.crash_center.view",
  "system.feature_flags.manage",
  "system.maintenance.manage",
]);

const PERMISSION_KEY_SET = new Set(PERMISSION_KEYS);

export function isValidPermissionKey(key) {
  return PERMISSION_KEY_SET.has(String(key || "").trim());
}

// نطاقات الوصول مرتّبة تصاعدياً؛ النطاق الأعلى يشمل الأدنى.
export const PERMISSION_SCOPES = Object.freeze([
  "own",
  "assigned",
  "department",
  "all",
]);

const SCOPE_RANK = Object.freeze({
  own: 0,
  assigned: 1,
  department: 2,
  all: 3,
});

export function isValidScope(scope) {
  return Object.prototype.hasOwnProperty.call(SCOPE_RANK, String(scope || ""));
}

/**
 * هل يفي النطاق الممنوح بالنطاق المطلوب؟ (all يفي بكل شيء).
 */
export function scopeSatisfies(grantedScope, requiredScope) {
  const g = SCOPE_RANK[String(grantedScope || "")];
  const r = SCOPE_RANK[String(requiredScope || "")];
  if (g == null || r == null) return false;
  return g >= r;
}

// العلامة الخاصة للصلاحية الكاملة (Super Admin وقالب super_admin).
export const WILDCARD_PERMISSION = "*";

/**
 * قوالب الأدوار الافتراضية: role_key -> مصفوفة مفاتيح صلاحيات (أو ["*"]).
 * قابلة للتعديل عبر جدول role_permission_override (enable/disable) لكل capability.
 * الأدوار الوظيفية (taxi_monitoring...) تُسنَد للموظف عبر app_user.admin_role_key.
 */
export const ROLE_TEMPLATES = Object.freeze({
  super_admin: [WILDCARD_PERMISSION],

  admin: [
    "dashboard.command_center.view",
    "taxi.rides.read",
    "taxi.rides.track_live",
    "taxi.rides.history",
    "orders.read",
    "orders.modify",
    "orders.cancel",
    "orders.revisions.create",
    "orders.revisions.submit",
    "orders.revisions.apply",
    "services.read",
    "real_estate.read",
    "cars.read",
    "jobs.read",
    "merchants.approve",
    "merchants.financial_terms.send",
    "merchants.financial_terms.approve",
    "taxi.captains.approve",
    "delivery.accounts.create",
    "community.posts.read",
    "community.users.read",
    "support.tickets.read",
    "support.tickets.assign",
    "support.tickets.reply",
    "support.tickets.resolve",
    "support.sla.manage",
    "ops.alerts.read",
    "ops.alerts.acknowledge",
    "ops.alerts.assign",
    "ops.alerts.resolve",
    "employees.read",
    "attendance.read",
    "audit.read",
    "reports.export",
  ],

  // مدير عمليات الموظفين: دور وظيفي مقيّد يرى ويعمل فقط ضمن 7 مجالات:
  // (1) إضافة/تعديل موظف، (2) كوبونات الموظفين، (3) الحضور والمكافآت/الخصومات
  // والرواتب، (4) حالات الحضور اليدوية، (5) متابعة الطلبات والمبيعات (قراءة)،
  // (6) تعديل صلاحيات الموظفين، (7) تعطيل الزبائن والشكاوى وخدمة العملاء.
  // كل ما عداها مخفي. لاحظ: امتلاك مفتاح حسّاس (كـ employees.permissions.manage /
  // payroll.approve/release) يسمح لها بالاستخدام، لكن *منح* المفاتيح الحسّاسة
  // لغيرها يبقى للسوبر أدمن فقط (assertActorCanManagePermission).
  staff_ops_manager: [
    "dashboard.command_center.view",
    // (1) حسابات الموظفين
    "employees.read",
    "employees.create",
    "employees.update",
    // (6) صلاحيات الموظفين
    "employees.permissions.manage",
    // (3) الرواتب والحضور والمكافآت/الخصومات + (4) الحالات اليدوية
    "employees.salary.read",
    "employees.salary.update",
    "attendance.read",
    "attendance.approve",
    "payroll.prepare",
    "payroll.review",
    "payroll.approve",
    "payroll.release",
    "payroll.mark_paid",
    // (5) متابعة الطلبات والمبيعات — قراءة فقط
    "orders.read",
    "reports.export",
    // (2) كوبونات الموظفين
    "coupons.agents.manage",
    // (7) تعطيل الزبائن + الشكاوى + خدمة العملاء
    "accounts.suspend",
    "community.users.read",
    "support.tickets.read",
    "support.tickets.assign",
    "support.tickets.reply",
    "support.tickets.resolve",
  ],

  // ── الوظائف الافتراضية (يمكن تعديل صلاحيات أي موظف فردياً فوقها) ──
  follow_up_manager: [
    "dashboard.command_center.view",
    "orders.read",
    "orders.modify",
    "orders.cancel",
    "orders.revisions.create",
    "orders.revisions.submit",
    "orders.revisions.apply",
    "orders.messages.read",
    "support.tickets.read",
    "support.tickets.assign",
    "support.tickets.reply",
    "support.tickets.resolve",
    "support.tickets.escalate",
    "support.sla.manage",
    "ops.alerts.read",
    "ops.alerts.acknowledge",
    "ops.alerts.assign",
    "ops.alerts.resolve",
    "employees.read",
    "employees.create",
    "employees.update",
    "employees.permissions.manage",
    "employees.salary.read",
    "employees.salary.update",
    "attendance.read",
    "attendance.approve",
    "payroll.prepare",
    "payroll.review",
    "payroll.approve",
    "payroll.release",
    "payroll.mark_paid",
    "coupons.agents.manage",
    "reports.export",
    "audit.read",
    "community.users.read",
  ],

  sales_agent: [
    "dashboard.command_center.view",
    "orders.read",
    "reports.export",
    "coupons.agents.manage",
    "community.users.read",
  ],

  marketing_agent: [
    "dashboard.command_center.view",
    "ads.manage",
    "competitions.manage",
    "coupons.manage",
    "coupons.agents.manage",
    "reports.export",
  ],

  subscriptions_monitor: [
    "dashboard.command_center.view",
    "taxi.rides.read",
    "taxi.captains.approve",
    "merchants.approve",
    "merchants.financial_terms.send",
    "merchants.financial_terms.approve",
    "reports.export",
  ],

  residents_moderator: [
    "dashboard.command_center.view",
    "community.users.read",
    "community.posts.read",
    "community.moderate",
    "accounts.restrict",
    "accounts.suspend",
    "support.tickets.read",
  ],

  taxi_monitoring: [
    "dashboard.command_center.view",
    "taxi.rides.read",
    "taxi.rides.track_live",
    "taxi.rides.history",
    "support.tickets.read",
    "ops.alerts.read",
    "ops.alerts.acknowledge",
  ],

  order_monitoring: [
    "dashboard.command_center.view",
    "orders.read",
    "orders.revisions.create",
    "orders.revisions.submit",
    "orders.messages.read",
    "support.tickets.read",
    "ops.alerts.read",
  ],

  delivery_monitoring: [
    "dashboard.command_center.view",
    "orders.read",
    "orders.revisions.create",
    "orders.revisions.submit",
    "support.tickets.read",
    "ops.alerts.read",
  ],

  service_monitoring: [
    "dashboard.command_center.view",
    "services.read",
    "real_estate.read",
    "cars.read",
    "jobs.read",
    "support.tickets.read",
    "ops.alerts.read",
  ],

  community_moderator: [
    "dashboard.command_center.view",
    "community.posts.read",
    "community.moderate",
    "community.users.read",
    "support.tickets.read",
    "ops.alerts.read",
  ],

  call_center_agent: [
    "dashboard.command_center.view",
    "support.tickets.read",
    "support.tickets.reply",
    "support.tickets.resolve",
    "ops.alerts.read",
    "ops.alerts.acknowledge",
    "taxi.rides.read",
    "orders.read",
    "orders.revisions.create",
    "orders.revisions.submit",
  ],

  call_center_supervisor: [
    "dashboard.command_center.view",
    "support.tickets.read",
    "support.tickets.assign",
    "support.tickets.reply",
    "support.tickets.resolve",
    "support.tickets.escalate",
    "support.sla.manage",
    "ops.alerts.read",
    "ops.alerts.acknowledge",
    "ops.alerts.assign",
    "ops.alerts.resolve",
    "taxi.rides.read",
    "taxi.rides.track_live",
    "taxi.rides.emergency_cancel",
    "orders.read",
    "orders.revisions.create",
    "orders.revisions.submit",
    "orders.revisions.apply",
    "reports.export",
  ],

  hr: [
    "dashboard.command_center.view",
    "employees.read",
    "employees.create",
    "employees.update",
    "attendance.read",
    "attendance.approve",
    "audit.read",
  ],

  payroll_officer: [
    "dashboard.command_center.view",
    "employees.salary.read",
    "attendance.read",
    "payroll.prepare",
    "payroll.review",
  ],

  payroll_approver: [
    "dashboard.command_center.view",
    "employees.salary.read",
    "payroll.review",
    "payroll.approve",
    "payroll.release",
    "payroll.mark_paid",
  ],

  support_ticket_manager: [
    "dashboard.command_center.view",
    "support.tickets.read",
    "support.tickets.assign",
    "support.tickets.reply",
    "support.tickets.resolve",
    "support.tickets.escalate",
    "support.sla.manage",
    "ops.alerts.read",
    "ops.alerts.acknowledge",
    "ops.alerts.assign",
    "ops.alerts.resolve",
  ],
});

export const ROLE_TEMPLATE_KEYS = Object.freeze(Object.keys(ROLE_TEMPLATES));

/**
 * يربط app_user.role الخام بقالب دور افتراضي عندما لا يوجد admin_role_key صريح.
 */
export function defaultRoleTemplateForBaseRole(baseRole) {
  const role = String(baseRole || "").trim().toLowerCase();
  if (role === "admin" || role === "deputy_admin") return "admin";
  return null;
}
