import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Arabic localization keeps approved brand and terms', () {
    final root = Directory.current.path.replaceAll('\\', '/');
    final arFile = File('$root/lib/l10n/app_ar.arb');
    final enFile = File('$root/lib/l10n/app_en.arb');

    expect(arFile.existsSync(), isTrue, reason: 'Missing app_ar.arb');
    expect(enFile.existsSync(), isTrue, reason: 'Missing app_en.arb');

    final arData = jsonDecode(arFile.readAsStringSync()) as Map<String, dynamic>;
    final enData = jsonDecode(enFile.readAsStringSync()) as Map<String, dynamic>;

    expect(arData['appName'], 'مسلكي');
    expect(arData['drawerCreateMerchant'], 'إنشاء متجر');
    expect(arData['authCreateOwnerAccount'], 'إنشاء حساب متجر');
    expect(arData['splashBrandName'], 'مسلكي');
    expect(arData['socialReelCommentsTitle'], 'تعليقات الريلز');

    expect(enData['drawerCreateMerchant'], 'Create store');
    expect(enData['authCreateOwnerAccount'], 'Create store account');

    const bannedArabicTerms = <String>[
      'مسلقي',
      'مسكلي',
      'مسلاكي',
      'بكرات',
      'إنشاء تاجر',
    ];

    final findings = <String>[];
    for (final entry in arData.entries) {
      if (entry.key.startsWith('@')) continue;
      final value = entry.value;
      if (value is! String) continue;
      for (final banned in bannedArabicTerms) {
        if (value.contains(banned)) {
          findings.add('${entry.key}: $banned');
        }
      }
    }

    if (findings.isNotEmpty) {
      fail(
        'Detected banned Arabic localization terms:\n'
        '${findings.join('\n')}',
      );
    }
  });
}
