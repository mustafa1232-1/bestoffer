import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/diagnostics/build_identity_guard.dart';

void main() {
  late Map<String, dynamic> matrix;

  setUpAll(() {
    final file = File('tool/release/android_apps.json');
    matrix = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  test('release matrix maps each app to its own target and package', () {
    final apps = matrix['apps'] as Map<String, dynamic>;

    expect(apps['user']['flavor'], 'user');
    expect(apps['user']['target'], 'lib/main.dart');
    expect(apps['user']['applicationId'], 'com.maslaki.user');

    expect(apps['store']['flavor'], 'store');
    expect(apps['store']['target'], 'lib/main_store.dart');
    expect(apps['store']['applicationId'], 'com.maslaki.store');

    expect(apps['delivery']['flavor'], 'delivery');
    expect(apps['delivery']['target'], 'lib/main_delivery.dart');
    expect(apps['delivery']['applicationId'], 'com.maslaki.delivery');

    expect(apps['captain']['flavor'], 'captain');
    expect(apps['captain']['target'], 'lib/main_captain.dart');
    expect(apps['captain']['applicationId'], 'com.maslaki.captain');
  });

  test('non-user release apps are never built from lib/main.dart', () {
    final apps = matrix['apps'] as Map<String, dynamic>;

    for (final key in const ['store', 'delivery', 'captain']) {
      expect(apps[key]['target'], isNot('lib/main.dart'), reason: key);
    }
  });

  test('runtime identity guard uses the same package contract', () {
    final apps = matrix['apps'] as Map<String, dynamic>;

    expect(BuildIdentitySpec.user.applicationId, apps['user']['applicationId']);
    expect(
      BuildIdentitySpec.store.applicationId,
      apps['store']['applicationId'],
    );
    expect(
      BuildIdentitySpec.delivery.applicationId,
      apps['delivery']['applicationId'],
    );
    expect(
      BuildIdentitySpec.captain.applicationId,
      apps['captain']['applicationId'],
    );
  });
}
