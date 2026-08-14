import { isValidPermissionKey } from "./permissions.catalog.js";

export const ADMIN_PAGE_PERMISSION_REGISTRY = Object.freeze([
  { id: "dashboard.command_center", page: "CommandCenterScreen", permission: "dashboard.command_center.view" },
  { id: "orders.overview", page: "AdminOrdersOverviewScreen", permission: "orders.read" },
  { id: "support.tickets", page: "AdminSupportTicketsScreen", permission: "support.tickets.read" },
  { id: "support.settings", page: "AdminSupportSettingsScreen", permission: "settings.support_phone.update" },
  { id: "taxi.rides", page: "AdminTaxiGovernanceScreen", permission: "taxi.rides.read" },
  { id: "taxi.captains", page: "AdminTaxiCaptainRequestsScreen", permission: "taxi.rides.read" },
  { id: "finance.receivables", page: "AdminReceivablesScreen", permission: "reports.export" },
  { id: "finance.reports", page: "AdminFinancialReportsHubScreen", permission: "reports.export" },
  { id: "users.customers", page: "AdminCustomerProfilesScreen", permission: "community.users.read" },
  { id: "community.reports", page: "AdminSocialReportsScreen", permission: "community.posts.read" },
  { id: "community.restrictions", page: "AdminSocialRestrictionsScreen", permission: "accounts.restrict" },
  { id: "security.audit", page: "AdminAuditLogScreen", permission: "audit.read" },
  { id: "security.permissions_matrix", page: "AdminPermissionsMatrixScreen", permission: "employees.permissions.manage" },
  { id: "security.roles_permissions", page: "AdminRbacManagementScreen", permission: "employees.permissions.manage" },
  { id: "system.notifications", page: "AdminNotificationsOperationsScreen", permission: "settings.guides.manage" },
  { id: "system.feature_flags", page: "AdminFeatureFlagsCenterScreen", permission: "settings.guides.manage" },
]);

export const ADMIN_ENDPOINT_PERMISSION_REGISTRY = Object.freeze([
  { method: "GET", path: "/api/admin/me/permissions", permission: "dashboard.command_center.view", self: true },
  { method: "GET", path: "/api/admin/rbac/catalog", permission: "employees.create" },
  { method: "GET", path: "/api/admin/rbac/change-log", permission: "audit.read" },
  { method: "GET", path: "/api/admin/rbac/roles", permission: "employees.permissions.manage" },
  { method: "POST", path: "/api/admin/rbac/roles", permission: "employees.permissions.manage" },
  { method: "PUT", path: "/api/admin/rbac/roles/:roleKey", permission: "employees.permissions.manage" },
  { method: "POST", path: "/api/admin/rbac/roles/:roleKey/copy", permission: "employees.permissions.manage" },
  { method: "POST", path: "/api/admin/rbac/roles/:roleKey/archive", permission: "employees.permissions.manage" },
  { method: "GET", path: "/api/admin/rbac/users/:userId/permissions", permission: "employees.permissions.manage" },
  { method: "POST", path: "/api/admin/rbac/users/:userId/permissions", permission: "employees.permissions.manage" },
  { method: "DELETE", path: "/api/admin/rbac/users/:userId/permissions/:permissionKey", permission: "employees.permissions.manage" },
  { method: "POST", path: "/api/admin/rbac/users/:userId/role", permission: "employees.permissions.manage" },
  { method: "GET", path: "/api/admin/support/tickets", permission: "support.tickets.read" },
  { method: "POST", path: "/api/admin/support/tickets", permission: "support.tickets.reply" },
  { method: "GET", path: "/api/admin/support/presence/me", permission: "support.tickets.reply" },
  { method: "PUT", path: "/api/admin/support/presence/me", permission: "support.tickets.reply" },
  { method: "GET", path: "/api/admin/support/presence", permission: "support.tickets.assign" },
  { method: "GET", path: "/api/admin/support/supervisor/overview", permission: "support.tickets.assign" },
  { method: "GET", path: "/api/admin/support/reports/kpis", permission: "support.tickets.assign" },
  { method: "GET", path: "/api/admin/support/canned-responses", permission: "support.tickets.reply" },
  { method: "POST", path: "/api/admin/support/canned-responses", permission: "support.sla.manage" },
  { method: "PUT", path: "/api/admin/support/canned-responses/:responseId", permission: "support.sla.manage" },
  { method: "GET", path: "/api/admin/support/knowledge", permission: "support.tickets.reply" },
  { method: "POST", path: "/api/admin/support/knowledge", permission: "support.sla.manage" },
  { method: "PUT", path: "/api/admin/support/knowledge/:articleId", permission: "support.sla.manage" },
  { method: "GET", path: "/api/admin/support/callbacks", permission: "support.tickets.reply" },
  { method: "PUT", path: "/api/admin/support/callbacks/:callbackId", permission: "support.tickets.reply" },
  { method: "GET", path: "/api/admin/support/tickets/:ticketId/callbacks", permission: "support.tickets.read" },
  { method: "POST", path: "/api/admin/support/tickets/:ticketId/callbacks", permission: "support.tickets.reply" },
  { method: "POST", path: "/api/admin/support/tickets/:ticketId/order-revisions", permission: "orders.revisions.create" },
  { method: "POST", path: "/api/admin/orders/:orderId/revisions/:revisionId/apply", permission: "orders.revisions.apply" },
  { method: "GET", path: "/api/admin/monitoring/taxi/rides", permission: "taxi.rides.read" },
  { method: "GET", path: "/api/admin/monitoring/taxi/rides/:rideId", permission: "taxi.rides.read" },
  { method: "GET", path: "/api/admin/monitoring/orders", permission: "orders.read" },
  { method: "GET", path: "/api/admin/monitoring/orders/:orderId", permission: "orders.read" },
  { method: "GET", path: "/api/admin/monitoring/delivery/couriers", permission: "orders.read" },
  { method: "GET", path: "/api/admin/monitoring/delivery/couriers/:courierId", permission: "orders.read" },
  { method: "GET", path: "/api/admin/monitoring/services/requests", permission: "services.read" },
  { method: "GET", path: "/api/admin/monitoring/services/requests/:requestId", permission: "services.read" },
  { method: "GET", path: "/api/admin/monitoring/real-estate/listings", permission: "real_estate.read" },
  { method: "GET", path: "/api/admin/monitoring/real-estate/listings/:listingId", permission: "real_estate.read" },
  { method: "GET", path: "/api/admin/monitoring/cars/listings", permission: "cars.read" },
  { method: "GET", path: "/api/admin/monitoring/cars/listings/:listingId", permission: "cars.read" },
  { method: "GET", path: "/api/admin/monitoring/jobs", permission: "jobs.read" },
  { method: "GET", path: "/api/admin/monitoring/jobs/:jobId", permission: "jobs.read" },
  { method: "GET", path: "/api/admin/monitoring/jobs/:jobId/applications", permission: "jobs.applications.read" },
  { method: "GET", path: "/api/admin/monitoring/jobs/applications/:applicationId", permission: "jobs.applications.read" },
  { method: "GET", path: "/api/admin/monitoring/jobs/applications/:applicationId/cv", permission: "jobs.cv.download" },
  { method: "GET", path: "/api/admin/monitoring/community/users", permission: "community.users.read" },
  { method: "GET", path: "/api/admin/monitoring/community/users/:userId", permission: "community.users.read" },
  { method: "GET", path: "/api/admin/monitoring/community/users/:userId/content", permission: "community.posts.read" },
  { method: "GET", path: "/api/admin/monitoring/community/users/:userId/reports", permission: "community.posts.read" },
  { method: "GET", path: "/api/admin/ops/alerts", permission: "ops.alerts.read" },
  { method: "POST", path: "/api/admin/ops/alerts/:alertId/ack", permission: "ops.alerts.acknowledge" },
  { method: "POST", path: "/api/admin/ops/alerts/:alertId/assign", permission: "ops.alerts.assign" },
  { method: "POST", path: "/api/admin/ops/alerts/:alertId/resolve", permission: "ops.alerts.resolve" },
]);

export function assertAdminPermissionRegistryValid() {
  const invalid = [
    ...ADMIN_PAGE_PERMISSION_REGISTRY,
    ...ADMIN_ENDPOINT_PERMISSION_REGISTRY,
  ].filter((entry) => !isValidPermissionKey(entry.permission));
  if (invalid.length) {
    const details = invalid
      .map((entry) => `${entry.id || entry.path}:${entry.permission}`)
      .join(", ");
    throw new Error(`INVALID_ADMIN_PERMISSION_REGISTRY:${details}`);
  }
  return true;
}
