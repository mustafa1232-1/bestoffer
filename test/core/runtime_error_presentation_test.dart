import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/errors/app_runtime_error_presentation.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/l10n/app_localizations.dart';

void main() {
  testWidgets('runtime error presentation replaces the red screen widget', (
    tester,
  ) async {
    final originalBuilder = ErrorWidget.builder;
    installAppRuntimeErrorPresentation();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) {
            throw StateError('boom');
          },
        ),
      ),
    );

    expect(tester.takeException(), isA<StateError>());
    await tester.pump();

    expect(find.text('This screen hit an error'), findsOneWidget);
    expect(
      find.textContaining('The red error screen was suppressed'),
      findsOneWidget,
    );

    ErrorWidget.builder = originalBuilder;
  });
}
