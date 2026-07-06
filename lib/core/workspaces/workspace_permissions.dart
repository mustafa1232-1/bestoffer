import 'package:flutter/widgets.dart';

enum WorkspacePermissionKind {
  merchant,
  serviceProvider,
}

class WorkspacePermissionLabel {
  final String ar;
  final String en;

  const WorkspacePermissionLabel(this.ar, this.en);

  String displayFor(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode.toLowerCase();
    return locale == 'en' ? '$en / $ar' : '$ar / $en';
  }
}

const List<String> merchantWorkspacePermissionCatalog = [
  'view_orders',
  'accept_orders',
  'reject_orders',
  'prepare_orders',
  'mark_order_item_unavailable',
  'assign_delivery',
  'change_order_status',
  'view_products',
  'create_products',
  'edit_products',
  'delete_products',
  'change_product_availability',
  'manage_offers',
  'post_as_store',
  'reply_messages',
  'reply_reviews',
  'view_reports',
  'view_financial_reports',
  'manage_store_profile',
  'manage_employees',
  'view_audit_log',
];

const List<String> serviceProviderWorkspacePermissionCatalog = [
  'view_service_requests',
  'accept_service_requests',
  'reject_service_requests',
  'edit_services',
  'create_services',
  'delete_services',
  'manage_offers',
  'post_as_service',
  'reply_messages',
  'reply_reviews',
  'view_reports',
  'manage_service_profile',
  'manage_employees',
  'view_audit_log',
];

const Map<String, WorkspacePermissionLabel> merchantWorkspacePermissionLabels = {
  'view_orders': WorkspacePermissionLabel('عرض الطلبات', 'View orders'),
  'accept_orders': WorkspacePermissionLabel('قبول الطلبات', 'Accept orders'),
  'reject_orders': WorkspacePermissionLabel('رفض الطلبات', 'Reject orders'),
  'prepare_orders': WorkspacePermissionLabel('تجهيز الطلبات', 'Prepare orders'),
  'mark_order_item_unavailable': WorkspacePermissionLabel(
    'تعطيل صنف في الطلب',
    'Mark order item unavailable',
  ),
  'assign_delivery': WorkspacePermissionLabel('إسناد التوصيل', 'Assign delivery'),
  'change_order_status': WorkspacePermissionLabel('تغيير حالة الطلب', 'Change order status'),
  'view_products': WorkspacePermissionLabel('عرض المنتجات', 'View products'),
  'create_products': WorkspacePermissionLabel('إضافة المنتجات', 'Create products'),
  'edit_products': WorkspacePermissionLabel('تعديل المنتجات', 'Edit products'),
  'delete_products': WorkspacePermissionLabel('حذف المنتجات', 'Delete products'),
  'change_product_availability': WorkspacePermissionLabel(
    'تغيير توفر المنتج',
    'Change product availability',
  ),
  'manage_offers': WorkspacePermissionLabel('إدارة العروض', 'Manage offers'),
  'post_as_store': WorkspacePermissionLabel('النشر باسم المتجر', 'Post as store'),
  'reply_messages': WorkspacePermissionLabel('الرد على الرسائل', 'Reply messages'),
  'reply_reviews': WorkspacePermissionLabel('الرد على التقييمات', 'Reply reviews'),
  'view_reports': WorkspacePermissionLabel('عرض التقارير', 'View reports'),
  'view_financial_reports': WorkspacePermissionLabel(
    'عرض التقارير المالية',
    'View financial reports',
  ),
  'manage_store_profile': WorkspacePermissionLabel(
    'إدارة ملف المتجر',
    'Manage store profile',
  ),
  'manage_employees': WorkspacePermissionLabel('إدارة الموظفين', 'Manage employees'),
  'view_audit_log': WorkspacePermissionLabel('سجل التدقيق', 'Audit log'),
};

const Map<String, WorkspacePermissionLabel> serviceProviderWorkspacePermissionLabels = {
  'view_service_requests': WorkspacePermissionLabel(
    'عرض طلبات الخدمة',
    'View service requests',
  ),
  'accept_service_requests': WorkspacePermissionLabel(
    'قبول طلبات الخدمة',
    'Accept service requests',
  ),
  'reject_service_requests': WorkspacePermissionLabel(
    'رفض طلبات الخدمة',
    'Reject service requests',
  ),
  'edit_services': WorkspacePermissionLabel('تعديل الخدمات', 'Edit services'),
  'create_services': WorkspacePermissionLabel('إضافة الخدمات', 'Create services'),
  'delete_services': WorkspacePermissionLabel('حذف الخدمات', 'Delete services'),
  'manage_offers': WorkspacePermissionLabel('إدارة العروض', 'Manage offers'),
  'post_as_service': WorkspacePermissionLabel(
    'النشر باسم الخدمة',
    'Post as service',
  ),
  'reply_messages': WorkspacePermissionLabel('الرد على الرسائل', 'Reply messages'),
  'reply_reviews': WorkspacePermissionLabel('الرد على التقييمات', 'Reply reviews'),
  'view_reports': WorkspacePermissionLabel('عرض التقارير', 'View reports'),
  'manage_service_profile': WorkspacePermissionLabel(
    'إدارة ملف الخدمة',
    'Manage service profile',
  ),
  'manage_employees': WorkspacePermissionLabel('إدارة الموظفين', 'Manage employees'),
  'view_audit_log': WorkspacePermissionLabel('سجل التدقيق', 'Audit log'),
};

List<String> workspacePermissionCatalog(WorkspacePermissionKind kind) {
  return kind == WorkspacePermissionKind.serviceProvider
      ? serviceProviderWorkspacePermissionCatalog
      : merchantWorkspacePermissionCatalog;
}

Map<String, WorkspacePermissionLabel> workspacePermissionLabels(
  WorkspacePermissionKind kind,
) {
  return kind == WorkspacePermissionKind.serviceProvider
      ? serviceProviderWorkspacePermissionLabels
      : merchantWorkspacePermissionLabels;
}

String workspacePermissionLabelFor(
  BuildContext context,
  String permission, {
  WorkspacePermissionKind kind = WorkspacePermissionKind.merchant,
}) {
  final label = workspacePermissionLabels(kind)[permission];
  return label?.displayFor(context) ?? permission;
}
