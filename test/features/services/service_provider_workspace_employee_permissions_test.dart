import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/services/models/service_models.dart';
import 'package:maslaki/features/services/state/service_provider_workspace_controller.dart';
import 'package:maslaki/features/services/ui/service_provider_workspace_screen.dart';
import 'package:maslaki/core/workspaces/workspace_permissions.dart';

class _FakeServiceProviderWorkspaceController
    extends ServiceProviderWorkspaceController {
  _FakeServiceProviderWorkspaceController(
    super.ref,
    ServiceProviderWorkspaceState initialState,
  ) {
    state = initialState;
  }

  @override
  Future<void> loadWorkspace() async {}

  @override
  Future<void> loadRequests({String? status}) async {}
}

ServiceProviderWorkspaceModel _workspace() {
  return ServiceProviderWorkspaceModel.fromJson(
    <String, dynamic>{
      'provider': <String, dynamic>{
        'id': 88,
        'userId': 7,
        'businessName': 'Atlas Services',
        'logoUrl': null,
        'coverImageUrl': null,
        'mainCategoryName': 'Services',
        'bio': 'Workspace for testing',
        'phone': '07712345678',
        'whatsappPhone': null,
        'city': 'Baghdad',
        'area': 'Karrada',
        'addressLine': 'Main street',
        'servesAtHome': true,
        'servesAtShop': true,
        'servesRemote': false,
        'hasEmergencyService': false,
        'providerApprovalStatus': 'approved',
        'completedOrdersCount': 4,
        'ratingAvg': 4.8,
        'ratingCount': 10,
        'averageResponseMinutes': 15,
        'areas': const <Map<String, dynamic>>[],
        'availabilityRules': const <Map<String, dynamic>>[],
        'offerings': const <Map<String, dynamic>>[],
        'activePromotions': const <Map<String, dynamic>>[],
        'portfolio': const <Map<String, dynamic>>[],
        'reviews': const <Map<String, dynamic>>[],
      },
      'requestCounts': <String, int>{
        'pending': 0,
        'awaiting_provider': 0,
        'accepted': 0,
        'scheduled': 0,
        'in_progress': 0,
        'completed': 0,
      },
      'promotions': const <Map<String, dynamic>>[],
      'access': <String, dynamic>{
        'isOwner': true,
        'permissions': const <String>[],
        'permissionMap': <String, bool>{
          'view_service_requests': true,
          'create_services': true,
          'edit_services': true,
          'manage_employees': true,
          'view_audit_log': true,
        },
        'employeeProfile': null,
      },
      'employees': const <Map<String, dynamic>>[],
      'activityLogs': const <Map<String, dynamic>>[],
      'availablePermissions': workspacePermissionCatalog(
        WorkspacePermissionKind.serviceProvider,
      ),
      'areas': const <Map<String, dynamic>>[],
      'availabilityRules': const <Map<String, dynamic>>[],
      'offerings': const <Map<String, dynamic>>[],
      'portfolio': const <Map<String, dynamic>>[],
    },
  );
}

void main() {
  testWidgets(
    'service provider employee dialog uses service permissions only',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serviceProviderWorkspaceControllerProvider.overrideWith(
              (ref) => _FakeServiceProviderWorkspaceController(
                ref,
                ServiceProviderWorkspaceState(workspace: _workspace()),
              ),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            home: ServiceProviderWorkspaceScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inviteButton = find.byIcon(Icons.person_add_alt_1_outlined);
      expect(inviteButton, findsOneWidget);
      await tester.ensureVisible(inviteButton);
      await tester.tap(inviteButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Invite employee'), findsOneWidget);
      expect(find.textContaining('View service requests'), findsWidgets);
      expect(find.textContaining('Manage employees'), findsWidgets);
      expect(find.textContaining('View orders'), findsNothing);
    },
  );
}
