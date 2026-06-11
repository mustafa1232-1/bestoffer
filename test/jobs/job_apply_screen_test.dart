import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/jobs/models/job_models.dart';
import 'package:maslaki/features/jobs/ui/job_apply_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

JobPostModel _job() {
  return const JobPostModel(
    id: 1,
    title: 'Store Supervisor',
    companyName: 'Basmaya Market',
    companyLogoUrl: null,
    category: 'operations',
    activityType: 'retail',
    department: 'store',
    city: 'Baghdad',
    area: 'Basmaya',
    workplaceType: 'on_site',
    employmentType: 'full_time',
    experienceLevel: 'mid',
    educationLevel: null,
    salaryMin: 750000,
    salaryMax: 950000,
    salaryCurrency: 'IQD',
    salaryPeriod: 'monthly',
    salaryIsNegotiable: false,
    vacancies: 1,
    description: 'Manage the store team and daily operations.',
    requirements: null,
    responsibilities: null,
    benefits: null,
    skills: <String>['Leadership'],
    contactPhone: null,
    contactEmail: null,
    applyUrl: null,
    status: 'active',
    isFeatured: false,
    publishedAt: null,
    expiresAt: null,
    createdAt: null,
    updatedAt: null,
    merchantId: null,
    merchantName: null,
    merchantImageUrl: null,
    hasApplied: false,
    applicationsCount: 0,
    canManage: false,
  );
}

Widget _app({Locale locale = const Locale('en'), String defaultPhone = ''}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: JobApplyScreen(job: _job(), defaultPhone: defaultPhone),
  );
}

void main() {
  testWidgets('job apply screen shows inline phone error on empty submit', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(_app());

    await tester.tap(find.text(l10n.jobApplySubmitApplication));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.validationRequiredField(l10n.jobApplyApplicantPhone)),
      findsOneWidget,
    );
  });

  testWidgets('job apply screen shows inline invalid email error', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(_app(defaultPhone: '07700000000'));

    await tester.enterText(find.byType(TextField).at(1), 'invalid-email');
    await tester.tap(find.text(l10n.jobApplySubmitApplication));
    await tester.pumpAndSettle();

    expect(find.text(l10n.validationInvalidEmail), findsOneWidget);
  });
}
