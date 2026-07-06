import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/workspaces/workspace_permissions.dart';

void main() {
  test('merchant and service provider permission catalogs do not overlap by section', () {
    expect(merchantWorkspacePermissionCatalog, contains('manage_employees'));
    expect(merchantWorkspacePermissionCatalog, isNot(contains('view_service_requests')));
    expect(serviceProviderWorkspacePermissionCatalog, contains('view_service_requests'));
    expect(serviceProviderWorkspacePermissionCatalog, isNot(contains('view_orders')));
  });

  testWidgets('permission labels render with the active locale', (tester) async {
    late BuildContext capturedContext;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      workspacePermissionLabelFor(
        capturedContext,
        'manage_employees',
        kind: WorkspacePermissionKind.merchant,
      ),
      contains('Manage employees'),
    );
    expect(
      workspacePermissionLabelFor(
        capturedContext,
        'view_service_requests',
        kind: WorkspacePermissionKind.serviceProvider,
      ),
      contains('View service requests'),
    );
  });
}
