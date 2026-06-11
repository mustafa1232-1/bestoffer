import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('No mojibake markers are allowed in targeted UI source files', () {
    final root = Directory.current.path.replaceAll('\\', '/');
    final trackedFiles = <String>{
      'lib/features/taxi/ui/taxi_captain_dashboard_screen.dart',
      'lib/features/customer/ui/ad_campaign_details_screen.dart',
      'lib/features/admin/ui/admin_orders_overview_screen.dart',
      'lib/features/owner/ui/owner_dashboard_screen.dart',
      'lib/features/jobs/ui/job_my_applications_screen.dart',
      'lib/features/notifications/ui/notifications_screen.dart',
      'lib/features/social/ui/social_restrictions_screen.dart',
      'lib/features/admin/ui/admin_social_reports_screen.dart',
      'lib/features/admin/ui/admin_customer_profiles_screen.dart',
      'lib/pages/map_page.dart',
      'lib/features/customer/ui/customer_main_market_screen.dart',
      'lib/features/customer/ui/customer_home_selector_screen.dart',
      'lib/features/customer/ui/customer_account_hub_screen.dart',
      'lib/features/auth/ui/merchants_list_screen.dart',
      'lib/features/merchants/ui/merchant_product_details_screen.dart',
      'lib/features/merchants/ui/merchant_products_screen.dart',
      'lib/features/pharmacy/ui/pharmacy_conversation_screen.dart',
      'lib/features/services/ui/services_marketplace_screen.dart',
      'lib/features/services/ui/service_provider_onboarding_screen.dart',
      'lib/features/services/ui/service_provider_workspace_screen.dart',
      'lib/features/services/ui/service_provider_profile_screen.dart',
      'lib/features/services/ui/service_offering_details_screen.dart',
      'lib/features/services/ui/service_request_create_screen.dart',
    };

    final badMarkerPattern = RegExp(
      r'[\u00D8-\u00DB\u00C3\u00C6\u00C7\u00D0\u00D1\u00DE\uFFFD]',
    );
    final placeholderPattern = RegExp(r'\?{3,}');

    final findings = <String>[];
    for (final relativePath in trackedFiles) {
      final file = File('$root/$relativePath');
      expect(file.existsSync(), isTrue, reason: '$relativePath not found');

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!badMarkerPattern.hasMatch(line) &&
            !placeholderPattern.hasMatch(line)) {
          continue;
        }
        findings.add('$relativePath:${i + 1}: $line');
      }
    }

    if (findings.isNotEmpty) {
      fail(
        'Detected possible broken-encoding markers in source:\n'
        '${findings.join('\n')}\n\n'
        'Fix these strings before shipping.',
      );
    }
  });
}
