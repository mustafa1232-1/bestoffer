import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/permissions/maslaki_permission_models.dart';
import 'package:maslaki/core/permissions/maslaki_permission_service.dart';
import 'package:maslaki/features/startup/ui/maslaki_permission_setup_screen.dart';

class _FakePermissionService extends MaslakiPermissionService {
  final Map<MaslakiPermission, MaslakiPermissionStatus> statuses;
  bool completed = false;

  _FakePermissionService(this.statuses);

  @override
  Future<MaslakiPermissionStatus> getStatus(MaslakiPermission permission) async =>
      statuses[permission] ?? MaslakiPermissionStatus.denied;

  @override
  Future<MaslakiPermissionStatus> request(MaslakiPermission permission) async {
    statuses[permission] = MaslakiPermissionStatus.granted;
    return MaslakiPermissionStatus.granted;
  }

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<void> markSetupComplete() async => completed = true;

  @override
  Future<bool> isSetupComplete() async => completed;
}

Widget _wrap(Widget child, {Locale locale = const Locale('ar')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  testWidgets('renders a card per first-run requirement (customer, RTL)',
      (tester) async {
    final fake = _FakePermissionService({
      MaslakiPermission.notifications: MaslakiPermissionStatus.denied,
      MaslakiPermission.locationWhenInUse: MaslakiPermissionStatus.denied,
    });
    await tester.pumpWidget(_wrap(
      MaslakiPermissionSetupScreen(
        role: MaslakiAppRole.customer,
        onComplete: () async {},
        service: fake,
      ),
    ));
    await tester.pumpAndSettle();

    // Header present.
    expect(find.text('تهيئة مسلكي لتجربة كاملة'), findsOneWidget);
    // Customer first-run = notifications + foreground location → 2 enable CTAs.
    expect(find.text('تفعيل'), findsNWidgets(2));
    // RTL by default for Arabic locale.
    expect(Directionality.of(tester.element(find.byType(Scaffold))),
        TextDirection.rtl);
  });

  testWidgets('granted permission shows ready state, no CTA', (tester) async {
    final fake = _FakePermissionService({
      MaslakiPermission.notifications: MaslakiPermissionStatus.granted,
      MaslakiPermission.locationWhenInUse: MaslakiPermissionStatus.granted,
    });
    await tester.pumpWidget(_wrap(
      MaslakiPermissionSetupScreen(
        role: MaslakiAppRole.customer,
        onComplete: () async {},
        service: fake,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('جاهز'), findsNWidgets(2));
    expect(find.text('تفعيل'), findsNothing);
  });

  testWidgets('finish marks setup complete and calls onComplete', (tester) async {
    final fake = _FakePermissionService({
      MaslakiPermission.notifications: MaslakiPermissionStatus.granted,
      MaslakiPermission.locationWhenInUse: MaslakiPermissionStatus.granted,
    });
    var done = false;
    await tester.pumpWidget(_wrap(
      MaslakiPermissionSetupScreen(
        role: MaslakiAppRole.customer,
        onComplete: () async => done = true,
        service: fake,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('متابعة'));
    // Pump frames (not pumpAndSettle): on finish the button shows a spinner the
    // real app dismisses by navigating away, which never happens in this test.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fake.completed, isTrue);
    expect(done, isTrue);
  });
}
