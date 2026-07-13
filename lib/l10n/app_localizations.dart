import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Maslaki'**
  String get appName;

  /// No description provided for @commonLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get commonLanguage;

  /// No description provided for @commonArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get commonArabic;

  /// No description provided for @commonEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get commonEnglish;

  /// No description provided for @commonSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get commonSettings;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// No description provided for @commonReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get commonReset;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get commonFilters;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get commonPreview;

  /// No description provided for @commonPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get commonPublish;

  /// No description provided for @commonShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get commonShare;

  /// No description provided for @commonCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get commonCall;

  /// No description provided for @commonMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get commonMessage;

  /// No description provided for @commonComments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get commonComments;

  /// No description provided for @commonReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get commonReply;

  /// No description provided for @commonMerchant.
  ///
  /// In en, this message translates to:
  /// **'Merchant'**
  String get commonMerchant;

  /// No description provided for @commonJob.
  ///
  /// In en, this message translates to:
  /// **'Job'**
  String get commonJob;

  /// No description provided for @commonCompany.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get commonCompany;

  /// No description provided for @commonSalary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get commonSalary;

  /// No description provided for @commonWorkHours.
  ///
  /// In en, this message translates to:
  /// **'Work hours'**
  String get commonWorkHours;

  /// No description provided for @commonWorkDays.
  ///
  /// In en, this message translates to:
  /// **'Work days'**
  String get commonWorkDays;

  /// No description provided for @commonReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get commonReport;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get commonLoading;

  /// No description provided for @commonNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results found.'**
  String get commonNoResults;

  /// No description provided for @commonTryAgainLater.
  ///
  /// In en, this message translates to:
  /// **'Please try again later.'**
  String get commonTryAgainLater;

  /// No description provided for @commonNoInternet.
  ///
  /// In en, this message translates to:
  /// **'Unable to connect to the server. Check your internet connection and try again.'**
  String get commonNoInternet;

  /// No description provided for @commonNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get commonNow;

  /// No description provided for @commonRequiredField.
  ///
  /// In en, this message translates to:
  /// **'This field is required.'**
  String get commonRequiredField;

  /// No description provided for @commonOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get commonOptional;

  /// No description provided for @commonStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get commonStatus;

  /// No description provided for @commonUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknown;

  /// No description provided for @commonAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get commonAll;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get commonCreate;

  /// No description provided for @commonUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get commonUpdate;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get commonOpen;

  /// No description provided for @commonChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get commonChoose;

  /// No description provided for @commonId.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get commonId;

  /// No description provided for @commonApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get commonApprove;

  /// No description provided for @commonReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get commonReject;

  /// No description provided for @commonSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get commonSend;

  /// No description provided for @commonNoData.
  ///
  /// In en, this message translates to:
  /// **'No data.'**
  String get commonNoData;

  /// No description provided for @commonVehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get commonVehicle;

  /// No description provided for @commonModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get commonModel;

  /// No description provided for @commonPlate.
  ///
  /// In en, this message translates to:
  /// **'Plate'**
  String get commonPlate;

  /// No description provided for @commonBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get commonBlock;

  /// No description provided for @commonLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get commonLogout;

  /// No description provided for @commonCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get commonCopied;

  /// No description provided for @commonSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String commonSelectedCount(int count);

  /// No description provided for @commonDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get commonDay;

  /// No description provided for @commonWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get commonWeek;

  /// No description provided for @commonYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get commonYesterday;

  /// No description provided for @commonPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get commonPeriod;

  /// No description provided for @commonCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get commonCustomer;

  /// No description provided for @commonYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get commonYou;

  /// No description provided for @commonOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get commonOwner;

  /// No description provided for @commonSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get commonSubtotal;

  /// No description provided for @commonDeliveryFee.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee'**
  String get commonDeliveryFee;

  /// No description provided for @commonServiceFee.
  ///
  /// In en, this message translates to:
  /// **'Service fee'**
  String get commonServiceFee;

  /// No description provided for @commonItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get commonItems;

  /// No description provided for @commonNoItems.
  ///
  /// In en, this message translates to:
  /// **'No items.'**
  String get commonNoItems;

  /// No description provided for @commonTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get commonTotal;

  /// No description provided for @commonAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get commonAmount;

  /// No description provided for @commonOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get commonOrders;

  /// No description provided for @commonOperations.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get commonOperations;

  /// No description provided for @commonMerchantsCount.
  ///
  /// In en, this message translates to:
  /// **'Merchants count'**
  String get commonMerchantsCount;

  /// No description provided for @commonSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get commonSales;

  /// No description provided for @commonCollected.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get commonCollected;

  /// No description provided for @commonNet.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get commonNet;

  /// No description provided for @commonOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get commonOutstanding;

  /// No description provided for @commonMetric.
  ///
  /// In en, this message translates to:
  /// **'Metric'**
  String get commonMetric;

  /// No description provided for @commonMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get commonMethod;

  /// No description provided for @commonRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get commonRemaining;

  /// No description provided for @commonCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get commonCustom;

  /// No description provided for @commonCustomRange.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get commonCustomRange;

  /// No description provided for @commonThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get commonThisWeek;

  /// No description provided for @commonThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get commonThisMonth;

  /// No description provided for @commonThisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get commonThisYear;

  /// No description provided for @commonAllTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get commonAllTime;

  /// No description provided for @commonLinkedInvoices.
  ///
  /// In en, this message translates to:
  /// **'Linked invoices'**
  String get commonLinkedInvoices;

  /// No description provided for @commonConfirmedPaid.
  ///
  /// In en, this message translates to:
  /// **'Confirmed paid'**
  String get commonConfirmedPaid;

  /// No description provided for @commonTotalDue.
  ///
  /// In en, this message translates to:
  /// **'Total due'**
  String get commonTotalDue;

  /// No description provided for @commonSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get commonSummary;

  /// No description provided for @commonCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get commonCompleted;

  /// No description provided for @commonPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get commonPending;

  /// No description provided for @commonRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get commonRejected;

  /// No description provided for @commonCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get commonCancelled;

  /// No description provided for @commonInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get commonInProgress;

  /// No description provided for @commonTotalOrders.
  ///
  /// In en, this message translates to:
  /// **'Total orders'**
  String get commonTotalOrders;

  /// No description provided for @mainChooseLoginMode.
  ///
  /// In en, this message translates to:
  /// **'Choose Login Mode'**
  String get mainChooseLoginMode;

  /// No description provided for @mainChooseHowToContinue.
  ///
  /// In en, this message translates to:
  /// **'Choose how you want to continue in this session'**
  String get mainChooseHowToContinue;

  /// No description provided for @mainContinueAsCustomer.
  ///
  /// In en, this message translates to:
  /// **'Continue as Customer'**
  String get mainContinueAsCustomer;

  /// No description provided for @mainContinueAsRole.
  ///
  /// In en, this message translates to:
  /// **'Continue as {role}'**
  String mainContinueAsRole(String role);

  /// No description provided for @mainStaffDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get mainStaffDelivery;

  /// No description provided for @mainStaffAccountant.
  ///
  /// In en, this message translates to:
  /// **'Accountant'**
  String get mainStaffAccountant;

  /// No description provided for @mainStaffHr.
  ///
  /// In en, this message translates to:
  /// **'HR'**
  String get mainStaffHr;

  /// No description provided for @mainEmployeePortal.
  ///
  /// In en, this message translates to:
  /// **'Employee Portal (Attendance & Leave)'**
  String get mainEmployeePortal;

  /// No description provided for @settingsMoreLanguageOptions.
  ///
  /// In en, this message translates to:
  /// **'More language options'**
  String get settingsMoreLanguageOptions;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsThemeAndFonts.
  ///
  /// In en, this message translates to:
  /// **'Theme and fonts'**
  String get settingsThemeAndFonts;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// No description provided for @settingsSecurityAndPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Security & privacy'**
  String get settingsSecurityAndPrivacy;

  /// No description provided for @settingsGuide.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get settingsGuide;

  /// No description provided for @settingsInterfaceTutorials.
  ///
  /// In en, this message translates to:
  /// **'Interface tutorials'**
  String get settingsInterfaceTutorials;

  /// No description provided for @settingsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsSupport;

  /// No description provided for @settingsSystemHelp.
  ///
  /// In en, this message translates to:
  /// **'System help'**
  String get settingsSystemHelp;

  /// No description provided for @settingsMyActivityLog.
  ///
  /// In en, this message translates to:
  /// **'My Activity Log'**
  String get settingsMyActivityLog;

  /// No description provided for @settingsLatestEvents.
  ///
  /// In en, this message translates to:
  /// **'Latest events recorded for your account'**
  String get settingsLatestEvents;

  /// No description provided for @settingsCurrentLanguage.
  ///
  /// In en, this message translates to:
  /// **'Current language'**
  String get settingsCurrentLanguage;

  /// No description provided for @settingsLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'Change app language'**
  String get settingsLanguageHint;

  /// No description provided for @settingsAppearanceHint.
  ///
  /// In en, this message translates to:
  /// **'Animation, weather effects, and visual options'**
  String get settingsAppearanceHint;

  /// No description provided for @settingsAnimation.
  ///
  /// In en, this message translates to:
  /// **'Animation'**
  String get settingsAnimation;

  /// No description provided for @settingsAnimationHint.
  ///
  /// In en, this message translates to:
  /// **'Enable or disable interface motion and animated effects.'**
  String get settingsAnimationHint;

  /// No description provided for @settingsWeatherEffects.
  ///
  /// In en, this message translates to:
  /// **'Weather effects'**
  String get settingsWeatherEffects;

  /// No description provided for @settingsWeatherEffectsHint.
  ///
  /// In en, this message translates to:
  /// **'Show weather-inspired visual effects when available.'**
  String get settingsWeatherEffectsHint;

  /// No description provided for @settingsResetVisual.
  ///
  /// In en, this message translates to:
  /// **'Reset visual defaults'**
  String get settingsResetVisual;

  /// No description provided for @settingsResetVisualHint.
  ///
  /// In en, this message translates to:
  /// **'Restore appearance settings to their default values.'**
  String get settingsResetVisualHint;

  /// No description provided for @settingsColorPresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Color preset'**
  String get settingsColorPresetTitle;

  /// No description provided for @settingsColorPresetHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the app color style.'**
  String get settingsColorPresetHint;

  /// No description provided for @settingsColorPresetMidnightBlue.
  ///
  /// In en, this message translates to:
  /// **'Midnight Blue'**
  String get settingsColorPresetMidnightBlue;

  /// No description provided for @settingsColorPresetRoyalIndigo.
  ///
  /// In en, this message translates to:
  /// **'Royal Indigo'**
  String get settingsColorPresetRoyalIndigo;

  /// No description provided for @settingsColorPresetEmeraldNight.
  ///
  /// In en, this message translates to:
  /// **'Emerald Night'**
  String get settingsColorPresetEmeraldNight;

  /// No description provided for @settingsColorPresetSunsetNeon.
  ///
  /// In en, this message translates to:
  /// **'Sunset Neon'**
  String get settingsColorPresetSunsetNeon;

  /// No description provided for @settingsAccountSecurity.
  ///
  /// In en, this message translates to:
  /// **'Account & Security'**
  String get settingsAccountSecurity;

  /// No description provided for @settingsSupportAndSystem.
  ///
  /// In en, this message translates to:
  /// **'Support & System'**
  String get settingsSupportAndSystem;

  /// No description provided for @settingsSupportAndSystemHint.
  ///
  /// In en, this message translates to:
  /// **'Contact and help information'**
  String get settingsSupportAndSystemHint;

  /// No description provided for @settingsAccountSecurityHintAuthed.
  ///
  /// In en, this message translates to:
  /// **'Update phone number and PIN'**
  String get settingsAccountSecurityHintAuthed;

  /// No description provided for @settingsLoginRequiredAccount.
  ///
  /// In en, this message translates to:
  /// **'Please login first to edit account data'**
  String get settingsLoginRequiredAccount;

  /// No description provided for @notificationsUnableToOpenTarget.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the linked page.'**
  String get notificationsUnableToOpenTarget;

  /// No description provided for @notificationsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load notifications.'**
  String get notificationsLoadFailed;

  /// No description provided for @notificationsSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get notificationsSessionExpired;

  /// No description provided for @notificationsValidationError.
  ///
  /// In en, this message translates to:
  /// **'Please review the entered information.'**
  String get notificationsValidationError;

  /// No description provided for @notificationsNoNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get notificationsNoNotifications;

  /// No description provided for @notificationsNoGeneral.
  ///
  /// In en, this message translates to:
  /// **'No app notifications'**
  String get notificationsNoGeneral;

  /// No description provided for @notificationsNoSocial.
  ///
  /// In en, this message translates to:
  /// **'No social activity'**
  String get notificationsNoSocial;

  /// No description provided for @notificationsAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get notificationsAll;

  /// No description provided for @notificationsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get notificationsGeneral;

  /// No description provided for @notificationsSocial.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get notificationsSocial;

  /// No description provided for @notificationsMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get notificationsMessages;

  /// No description provided for @notificationsUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get notificationsUnread;

  /// No description provided for @notificationsReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get notificationsReconnect;

  /// No description provided for @notificationsMarkAll.
  ///
  /// In en, this message translates to:
  /// **'Mark all'**
  String get notificationsMarkAll;

  /// No description provided for @notificationsApp.
  ///
  /// In en, this message translates to:
  /// **'App notifications'**
  String get notificationsApp;

  /// No description provided for @notificationsSocialActivity.
  ///
  /// In en, this message translates to:
  /// **'Social activity'**
  String get notificationsSocialActivity;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get notificationsConnected;

  /// No description provided for @notificationsReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get notificationsReconnecting;

  /// No description provided for @notificationsConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get notificationsConnecting;

  /// No description provided for @notificationsOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get notificationsOffline;

  /// No description provided for @notificationsGeneralEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Orders, taxi, jobs, and system updates will appear here.'**
  String get notificationsGeneralEmptyBody;

  /// No description provided for @notificationsSocialEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Likes, comments, mentions, and relation activity will appear here.'**
  String get notificationsSocialEmptyBody;

  /// No description provided for @notificationsAllEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'New updates will appear here.'**
  String get notificationsAllEmptyBody;

  /// No description provided for @notificationsMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String notificationsMinutesAgo(int count);

  /// No description provided for @adminOrdersOverviewLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the orders overview right now.'**
  String get adminOrdersOverviewLoadFailed;

  /// No description provided for @adminOrdersOverviewTitleCompletedOrders.
  ///
  /// In en, this message translates to:
  /// **'Completed orders'**
  String get adminOrdersOverviewTitleCompletedOrders;

  /// No description provided for @adminOrdersOverviewTitleCancelledOrders.
  ///
  /// In en, this message translates to:
  /// **'Cancelled orders'**
  String get adminOrdersOverviewTitleCancelledOrders;

  /// No description provided for @adminOrdersOverviewTitleInProgressOrders.
  ///
  /// In en, this message translates to:
  /// **'In-progress orders'**
  String get adminOrdersOverviewTitleInProgressOrders;

  /// No description provided for @adminOrdersOverviewTitleAllOrders.
  ///
  /// In en, this message translates to:
  /// **'All orders'**
  String get adminOrdersOverviewTitleAllOrders;

  /// No description provided for @adminOrdersOverviewSearchMerchants.
  ///
  /// In en, this message translates to:
  /// **'Search merchants'**
  String get adminOrdersOverviewSearchMerchants;

  /// No description provided for @adminOrdersOverviewNoMerchantsMatch.
  ///
  /// In en, this message translates to:
  /// **'No merchants match this filter.'**
  String get adminOrdersOverviewNoMerchantsMatch;

  /// No description provided for @adminOrdersOverviewOwnerLabel.
  ///
  /// In en, this message translates to:
  /// **'Owner: {owner}'**
  String adminOrdersOverviewOwnerLabel(String owner);

  /// No description provided for @adminOrdersOverviewOrdersCount.
  ///
  /// In en, this message translates to:
  /// **'Orders: {count}'**
  String adminOrdersOverviewOrdersCount(int count);

  /// No description provided for @adminOrdersOverviewMerchantOrdersLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load this merchant orders right now.'**
  String get adminOrdersOverviewMerchantOrdersLoadFailed;

  /// No description provided for @adminOrdersOverviewOrderDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Order #{id}'**
  String adminOrdersOverviewOrderDetailsTitle(int id);

  /// No description provided for @adminOrdersOverviewNoOrdersForFilter.
  ///
  /// In en, this message translates to:
  /// **'No orders for this filter.'**
  String get adminOrdersOverviewNoOrdersForFilter;

  /// No description provided for @adminOrdersOverviewOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'Order #{id}'**
  String adminOrdersOverviewOrderTitle(int id);

  /// No description provided for @adminOrdersOverviewAmountsSummary.
  ///
  /// In en, this message translates to:
  /// **'Subtotal {subtotal} - Total {total}'**
  String adminOrdersOverviewAmountsSummary(String subtotal, String total);

  /// No description provided for @ownerFinancialReportLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load the financial report.'**
  String get ownerFinancialReportLoadFailed;

  /// No description provided for @ownerFinancialReportTitleSales.
  ///
  /// In en, this message translates to:
  /// **'Total Sales Report'**
  String get ownerFinancialReportTitleSales;

  /// No description provided for @ownerFinancialReportTitleCommission.
  ///
  /// In en, this message translates to:
  /// **'Commission Report'**
  String get ownerFinancialReportTitleCommission;

  /// No description provided for @ownerFinancialReportTitleServiceFee.
  ///
  /// In en, this message translates to:
  /// **'Service Fees Report'**
  String get ownerFinancialReportTitleServiceFee;

  /// No description provided for @ownerFinancialReportTitleAppDelivery.
  ///
  /// In en, this message translates to:
  /// **'App Delivery Report'**
  String get ownerFinancialReportTitleAppDelivery;

  /// No description provided for @ownerFinancialReportTitleStoreDelivery.
  ///
  /// In en, this message translates to:
  /// **'Store Delivery Report'**
  String get ownerFinancialReportTitleStoreDelivery;

  /// No description provided for @ownerFinancialReportTitleNetSales.
  ///
  /// In en, this message translates to:
  /// **'Net Sales Report'**
  String get ownerFinancialReportTitleNetSales;

  /// No description provided for @ownerFinancialReportTitleAppDue.
  ///
  /// In en, this message translates to:
  /// **'App Due Report'**
  String get ownerFinancialReportTitleAppDue;

  /// No description provided for @ownerFinancialReportTitlePaidAmount.
  ///
  /// In en, this message translates to:
  /// **'Paid Amount Report'**
  String get ownerFinancialReportTitlePaidAmount;

  /// No description provided for @ownerFinancialReportTitleRemaining.
  ///
  /// In en, this message translates to:
  /// **'Outstanding Report'**
  String get ownerFinancialReportTitleRemaining;

  /// No description provided for @ownerFinancialReportDueAndPaidSummary.
  ///
  /// In en, this message translates to:
  /// **'Due and paid summary'**
  String get ownerFinancialReportDueAndPaidSummary;

  /// No description provided for @ownerFinancialReportNoConfirmedPayments.
  ///
  /// In en, this message translates to:
  /// **'There are no confirmed payments in this period.'**
  String get ownerFinancialReportNoConfirmedPayments;

  /// No description provided for @ownerFinancialReportNoDataForPeriod.
  ///
  /// In en, this message translates to:
  /// **'No data is available for this period.'**
  String get ownerFinancialReportNoDataForPeriod;

  /// No description provided for @socialPostDetailsInvalidContent.
  ///
  /// In en, this message translates to:
  /// **'Unable to identify the requested content.'**
  String get socialPostDetailsInvalidContent;

  /// No description provided for @socialPostDetailsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load content.'**
  String get socialPostDetailsLoadFailed;

  /// No description provided for @socialPostDetailsPostComments.
  ///
  /// In en, this message translates to:
  /// **'Post comments'**
  String get socialPostDetailsPostComments;

  /// No description provided for @socialPostDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Post details'**
  String get socialPostDetailsTitle;

  /// No description provided for @socialPostDetailsCommentsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load comments.'**
  String get socialPostDetailsCommentsLoadFailed;

  /// No description provided for @socialPostDetailsCommentSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to send the comment.'**
  String get socialPostDetailsCommentSendFailed;

  /// No description provided for @socialPostDetailsLikeUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the like.'**
  String get socialPostDetailsLikeUpdateFailed;

  /// No description provided for @socialPostDetailsEditCommentTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit comment'**
  String get socialPostDetailsEditCommentTitle;

  /// No description provided for @socialPostDetailsEditCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Edit your comment'**
  String get socialPostDetailsEditCommentHint;

  /// No description provided for @socialPostDetailsEditCommentFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to edit the comment.'**
  String get socialPostDetailsEditCommentFailed;

  /// No description provided for @socialPostDetailsDeleteCommentTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete comment'**
  String get socialPostDetailsDeleteCommentTitle;

  /// No description provided for @socialPostDetailsDeleteCommentMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this comment?'**
  String get socialPostDetailsDeleteCommentMessage;

  /// No description provided for @socialPostDetailsDeleteCommentFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete the comment.'**
  String get socialPostDetailsDeleteCommentFailed;

  /// No description provided for @socialPostDetailsActionRemoveLike.
  ///
  /// In en, this message translates to:
  /// **'Remove like'**
  String get socialPostDetailsActionRemoveLike;

  /// No description provided for @socialPostDetailsActionLike.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get socialPostDetailsActionLike;

  /// No description provided for @socialPostDetailsActionLikedCount.
  ///
  /// In en, this message translates to:
  /// **'Liked ({count})'**
  String socialPostDetailsActionLikedCount(int count);

  /// No description provided for @socialPostDetailsActionLikeCount.
  ///
  /// In en, this message translates to:
  /// **'Like ({count})'**
  String socialPostDetailsActionLikeCount(int count);

  /// No description provided for @socialPostDetailsEdited.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get socialPostDetailsEdited;

  /// No description provided for @socialPostDetailsNoComments.
  ///
  /// In en, this message translates to:
  /// **'No comments yet.'**
  String get socialPostDetailsNoComments;

  /// No description provided for @socialPostDetailsReplyingTo.
  ///
  /// In en, this message translates to:
  /// **'Replying to {name}'**
  String socialPostDetailsReplyingTo(String name);

  /// No description provided for @socialPostDetailsComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Write a comment... use @ for mentions and # for tags'**
  String get socialPostDetailsComposerHint;

  /// No description provided for @adminReceivablesReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Receivables Report'**
  String get adminReceivablesReportTitle;

  /// No description provided for @adminReceivablesReportLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load receivables report'**
  String get adminReceivablesReportLoadFailed;

  /// No description provided for @adminReceivablesReportSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Receivables Summary'**
  String get adminReceivablesReportSummaryTitle;

  /// No description provided for @adminReceivablesReportTotalSales.
  ///
  /// In en, this message translates to:
  /// **'Total Sales'**
  String get adminReceivablesReportTotalSales;

  /// No description provided for @adminReceivablesReportTotalCollected.
  ///
  /// In en, this message translates to:
  /// **'Total Collected'**
  String get adminReceivablesReportTotalCollected;

  /// No description provided for @adminReceivablesReportNetReceivables.
  ///
  /// In en, this message translates to:
  /// **'Net Receivables'**
  String get adminReceivablesReportNetReceivables;

  /// No description provided for @adminReceivablesReportOutstandingToCollect.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get adminReceivablesReportOutstandingToCollect;

  /// No description provided for @adminReceivablesReportNoData.
  ///
  /// In en, this message translates to:
  /// **'No receivables data'**
  String get adminReceivablesReportNoData;

  /// No description provided for @adminReceivablesActionCompleted.
  ///
  /// In en, this message translates to:
  /// **'Action completed'**
  String get adminReceivablesActionCompleted;

  /// No description provided for @adminReceivablesActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Action failed'**
  String get adminReceivablesActionFailed;

  /// No description provided for @adminReceivablesAddAdjustmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Add adjustment'**
  String get adminReceivablesAddAdjustmentTitle;

  /// No description provided for @adminReceivablesDebit.
  ///
  /// In en, this message translates to:
  /// **'Debit'**
  String get adminReceivablesDebit;

  /// No description provided for @adminReceivablesCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get adminReceivablesCredit;

  /// No description provided for @adminReceivablesAdjustmentAdded.
  ///
  /// In en, this message translates to:
  /// **'Adjustment added'**
  String get adminReceivablesAdjustmentAdded;

  /// No description provided for @adminReceivablesAdjustmentFailed.
  ///
  /// In en, this message translates to:
  /// **'Adjustment failed'**
  String get adminReceivablesAdjustmentFailed;

  /// No description provided for @adminReceivablesOutstandingToApp.
  ///
  /// In en, this message translates to:
  /// **'Outstanding to app'**
  String get adminReceivablesOutstandingToApp;

  /// No description provided for @adminReceivablesOutstandingToStore.
  ///
  /// In en, this message translates to:
  /// **'Outstanding to store'**
  String get adminReceivablesOutstandingToStore;

  /// No description provided for @adminReceivablesAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get adminReceivablesAdjustment;

  /// No description provided for @adminReceivablesNoRequests.
  ///
  /// In en, this message translates to:
  /// **'No requests'**
  String get adminReceivablesNoRequests;

  /// No description provided for @adminReceivablesTitle.
  ///
  /// In en, this message translates to:
  /// **'Merchants receivables'**
  String get adminReceivablesTitle;

  /// No description provided for @adminReceivablesTabStorePaysApp.
  ///
  /// In en, this message translates to:
  /// **'Store pays app'**
  String get adminReceivablesTabStorePaysApp;

  /// No description provided for @adminReceivablesTabAppPaysStore.
  ///
  /// In en, this message translates to:
  /// **'App pays store'**
  String get adminReceivablesTabAppPaysStore;

  /// No description provided for @adminReceivablesTabAwaitingStore.
  ///
  /// In en, this message translates to:
  /// **'Awaiting store'**
  String get adminReceivablesTabAwaitingStore;

  /// No description provided for @adminReceivablesNoData.
  ///
  /// In en, this message translates to:
  /// **'No data available'**
  String get adminReceivablesNoData;

  /// No description provided for @adminReceivablesStoreOwesApp.
  ///
  /// In en, this message translates to:
  /// **'Store owes app'**
  String get adminReceivablesStoreOwesApp;

  /// No description provided for @adminReceivablesAppOwesStore.
  ///
  /// In en, this message translates to:
  /// **'App owes store'**
  String get adminReceivablesAppOwesStore;

  /// No description provided for @adminReceivablesPendingIncoming.
  ///
  /// In en, this message translates to:
  /// **'Pending incoming'**
  String get adminReceivablesPendingIncoming;

  /// No description provided for @adminReceivablesPendingOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Pending outgoing'**
  String get adminReceivablesPendingOutgoing;

  /// No description provided for @ownerReceivablesTitle.
  ///
  /// In en, this message translates to:
  /// **'Receivables and settlements'**
  String get ownerReceivablesTitle;

  /// No description provided for @ownerReceivablesTabStorePays.
  ///
  /// In en, this message translates to:
  /// **'Store pays'**
  String get ownerReceivablesTabStorePays;

  /// No description provided for @ownerReceivablesTabAppPays.
  ///
  /// In en, this message translates to:
  /// **'App pays'**
  String get ownerReceivablesTabAppPays;

  /// No description provided for @ownerReceivablesNewRequest.
  ///
  /// In en, this message translates to:
  /// **'New request'**
  String get ownerReceivablesNewRequest;

  /// No description provided for @ownerReceivablesSubmitSuccess.
  ///
  /// In en, this message translates to:
  /// **'The settlement request was submitted successfully.'**
  String get ownerReceivablesSubmitSuccess;

  /// No description provided for @ownerReceivablesSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit the settlement request.'**
  String get ownerReceivablesSubmitFailed;

  /// No description provided for @ownerReceivablesUpdateSuccess.
  ///
  /// In en, this message translates to:
  /// **'The request was updated successfully.'**
  String get ownerReceivablesUpdateSuccess;

  /// No description provided for @ownerReceivablesUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update the request.'**
  String get ownerReceivablesUpdateFailed;

  /// No description provided for @ownerReceivablesConfirmReceiptSuccess.
  ///
  /// In en, this message translates to:
  /// **'Receipt confirmed.'**
  String get ownerReceivablesConfirmReceiptSuccess;

  /// No description provided for @ownerReceivablesConfirmReceiptFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to confirm receipt.'**
  String get ownerReceivablesConfirmReceiptFailed;

  /// No description provided for @ownerReceivablesIssueReportSuccess.
  ///
  /// In en, this message translates to:
  /// **'The issue report was sent.'**
  String get ownerReceivablesIssueReportSuccess;

  /// No description provided for @ownerReceivablesIssueReportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send the issue report.'**
  String get ownerReceivablesIssueReportFailed;

  /// No description provided for @ownerReceivablesSectionStoreDebtTitle.
  ///
  /// In en, this message translates to:
  /// **'Store debt to the app'**
  String get ownerReceivablesSectionStoreDebtTitle;

  /// No description provided for @ownerReceivablesSectionAppDebtTitle.
  ///
  /// In en, this message translates to:
  /// **'App debt to the store'**
  String get ownerReceivablesSectionAppDebtTitle;

  /// No description provided for @ownerReceivablesOpenInvoices.
  ///
  /// In en, this message translates to:
  /// **'Open invoices'**
  String get ownerReceivablesOpenInvoices;

  /// No description provided for @ownerReceivablesAwaitingConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Awaiting confirmation'**
  String get ownerReceivablesAwaitingConfirmation;

  /// No description provided for @ownerReceivablesStatusAwaitingAdminApproval.
  ///
  /// In en, this message translates to:
  /// **'Awaiting admin approval'**
  String get ownerReceivablesStatusAwaitingAdminApproval;

  /// No description provided for @ownerReceivablesStatusAwaitingReview.
  ///
  /// In en, this message translates to:
  /// **'Awaiting review'**
  String get ownerReceivablesStatusAwaitingReview;

  /// No description provided for @ownerReceivablesStatusReturnedForRevision.
  ///
  /// In en, this message translates to:
  /// **'Returned for revision'**
  String get ownerReceivablesStatusReturnedForRevision;

  /// No description provided for @ownerReceivablesStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get ownerReceivablesStatusApproved;

  /// No description provided for @ownerReceivablesStatusAssignedForPayment.
  ///
  /// In en, this message translates to:
  /// **'Assigned for payment'**
  String get ownerReceivablesStatusAssignedForPayment;

  /// No description provided for @ownerReceivablesStatusAwaitingStoreConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Awaiting store confirmation'**
  String get ownerReceivablesStatusAwaitingStoreConfirmation;

  /// No description provided for @ownerReceivablesStatusConfirmedByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Confirmed by admin'**
  String get ownerReceivablesStatusConfirmedByAdmin;

  /// No description provided for @ownerReceivablesStatusReceiptConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Receipt confirmed'**
  String get ownerReceivablesStatusReceiptConfirmed;

  /// No description provided for @ownerReceivablesStatusIssueReported.
  ///
  /// In en, this message translates to:
  /// **'Issue reported'**
  String get ownerReceivablesStatusIssueReported;

  /// No description provided for @ownerReceivablesTotalDebit.
  ///
  /// In en, this message translates to:
  /// **'Total debit'**
  String get ownerReceivablesTotalDebit;

  /// No description provided for @ownerReceivablesTotalCredit.
  ///
  /// In en, this message translates to:
  /// **'Total credit'**
  String get ownerReceivablesTotalCredit;

  /// No description provided for @ownerReceivablesNoRequestsInSection.
  ///
  /// In en, this message translates to:
  /// **'There are no requests in this section.'**
  String get ownerReceivablesNoRequestsInSection;

  /// No description provided for @notificationsHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String notificationsHoursAgo(int count);

  /// No description provided for @notificationsDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String notificationsDaysAgo(int count);

  /// No description provided for @apiInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Phone number or PIN is incorrect.'**
  String get apiInvalidCredentials;

  /// No description provided for @apiInvalidCurrentPin.
  ///
  /// In en, this message translates to:
  /// **'The current PIN is incorrect.'**
  String get apiInvalidCurrentPin;

  /// No description provided for @apiPhoneExists.
  ///
  /// In en, this message translates to:
  /// **'This phone number is already registered.'**
  String get apiPhoneExists;

  /// No description provided for @apiValidationError.
  ///
  /// In en, this message translates to:
  /// **'Please review the entered information.'**
  String get apiValidationError;

  /// No description provided for @apiInvalidToken.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get apiInvalidToken;

  /// No description provided for @apiNoToken.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get apiNoToken;

  /// No description provided for @apiServerError.
  ///
  /// In en, this message translates to:
  /// **'A server error occurred. Please try again later.'**
  String get apiServerError;

  /// No description provided for @apiRouteNotFound.
  ///
  /// In en, this message translates to:
  /// **'The requested service is unavailable.'**
  String get apiRouteNotFound;

  /// No description provided for @apiPropertySellerRequired.
  ///
  /// In en, this message translates to:
  /// **'A property seller or premium subscription is required to publish real estate listings.'**
  String get apiPropertySellerRequired;

  /// No description provided for @apiRealEstateNotFound.
  ///
  /// In en, this message translates to:
  /// **'The real estate listing was not found.'**
  String get apiRealEstateNotFound;

  /// No description provided for @apiListingSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save the listing.'**
  String get apiListingSaveFailed;

  /// No description provided for @apiEmptyFieldValidation.
  ///
  /// In en, this message translates to:
  /// **'Please review the required fields.'**
  String get apiEmptyFieldValidation;

  /// No description provided for @realEstateMarketplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Basmaya Real Estate'**
  String get realEstateMarketplaceTitle;

  /// No description provided for @realEstateWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Real Estate Workspace'**
  String get realEstateWorkspaceTitle;

  /// No description provided for @realEstateSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved Listings'**
  String get realEstateSavedTitle;

  /// No description provided for @realEstateDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Property Details'**
  String get realEstateDetailsTitle;

  /// No description provided for @realEstateAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Real Estate Listing'**
  String get realEstateAddTitle;

  /// No description provided for @realEstateEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Real Estate Listing'**
  String get realEstateEditTitle;

  /// No description provided for @realEstateSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by title, block, city, or features'**
  String get realEstateSearchHint;

  /// No description provided for @realEstateFilterResults.
  ///
  /// In en, this message translates to:
  /// **'{count} results'**
  String realEstateFilterResults(int count);

  /// No description provided for @realEstateSale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get realEstateSale;

  /// No description provided for @realEstateRent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get realEstateRent;

  /// No description provided for @realEstateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get realEstateAvailable;

  /// No description provided for @realEstateSold.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get realEstateSold;

  /// No description provided for @realEstateRented.
  ///
  /// In en, this message translates to:
  /// **'Rented'**
  String get realEstateRented;

  /// No description provided for @realEstateArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get realEstateArchived;

  /// No description provided for @realEstatePendingReview.
  ///
  /// In en, this message translates to:
  /// **'Pending review'**
  String get realEstatePendingReview;

  /// No description provided for @realEstateFeatured.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get realEstateFeatured;

  /// No description provided for @realEstateNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get realEstateNew;

  /// No description provided for @realEstateFurnished.
  ///
  /// In en, this message translates to:
  /// **'Furnished'**
  String get realEstateFurnished;

  /// No description provided for @realEstateUnfurnished.
  ///
  /// In en, this message translates to:
  /// **'Unfurnished'**
  String get realEstateUnfurnished;

  /// No description provided for @realEstateAllFurnishing.
  ///
  /// In en, this message translates to:
  /// **'All furnishing'**
  String get realEstateAllFurnishing;

  /// No description provided for @realEstateCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get realEstateCash;

  /// No description provided for @realEstateInstallments.
  ///
  /// In en, this message translates to:
  /// **'Installments'**
  String get realEstateInstallments;

  /// No description provided for @realEstateNegotiable.
  ///
  /// In en, this message translates to:
  /// **'Negotiable'**
  String get realEstateNegotiable;

  /// No description provided for @realEstatePaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get realEstatePaymentMethod;

  /// No description provided for @realEstateSettlementMode.
  ///
  /// In en, this message translates to:
  /// **'Bank settlement'**
  String get realEstateSettlementMode;

  /// No description provided for @realEstateSettlementNone.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get realEstateSettlementNone;

  /// No description provided for @realEstateSettlementPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial settlement'**
  String get realEstateSettlementPartial;

  /// No description provided for @realEstateSettlementFull.
  ///
  /// In en, this message translates to:
  /// **'Full settlement'**
  String get realEstateSettlementFull;

  /// No description provided for @realEstateArea.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get realEstateArea;

  /// No description provided for @realEstatePrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get realEstatePrice;

  /// No description provided for @realEstateLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get realEstateLocation;

  /// No description provided for @realEstateCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get realEstateCity;

  /// No description provided for @realEstateBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get realEstateBlock;

  /// No description provided for @realEstateBuildingNumber.
  ///
  /// In en, this message translates to:
  /// **'Building number'**
  String get realEstateBuildingNumber;

  /// No description provided for @realEstateApartmentNumber.
  ///
  /// In en, this message translates to:
  /// **'Apartment number'**
  String get realEstateApartmentNumber;

  /// No description provided for @realEstateRooms.
  ///
  /// In en, this message translates to:
  /// **'Rooms'**
  String get realEstateRooms;

  /// No description provided for @realEstateBathrooms.
  ///
  /// In en, this message translates to:
  /// **'Bathrooms'**
  String get realEstateBathrooms;

  /// No description provided for @realEstateFloor.
  ///
  /// In en, this message translates to:
  /// **'Floor'**
  String get realEstateFloor;

  /// No description provided for @realEstatePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get realEstatePhone;

  /// No description provided for @realEstateDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get realEstateDescription;

  /// No description provided for @realEstatePublisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get realEstatePublisher;

  /// No description provided for @realEstateContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get realEstateContact;

  /// No description provided for @realEstateSimilar.
  ///
  /// In en, this message translates to:
  /// **'Similar listings'**
  String get realEstateSimilar;

  /// No description provided for @realEstateMostViewed.
  ///
  /// In en, this message translates to:
  /// **'Most viewed'**
  String get realEstateMostViewed;

  /// No description provided for @realEstateNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get realEstateNewest;

  /// No description provided for @realEstateOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get realEstateOldest;

  /// No description provided for @realEstateLowestPrice.
  ///
  /// In en, this message translates to:
  /// **'Lowest price'**
  String get realEstateLowestPrice;

  /// No description provided for @realEstateHighestPrice.
  ///
  /// In en, this message translates to:
  /// **'Highest price'**
  String get realEstateHighestPrice;

  /// No description provided for @realEstateOnlyAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available only'**
  String get realEstateOnlyAvailable;

  /// No description provided for @realEstateFeaturedOnly.
  ///
  /// In en, this message translates to:
  /// **'Featured only'**
  String get realEstateFeaturedOnly;

  /// No description provided for @realEstateClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get realEstateClearFilters;

  /// No description provided for @realEstateApplyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply filters'**
  String get realEstateApplyFilters;

  /// No description provided for @realEstateNoListings.
  ///
  /// In en, this message translates to:
  /// **'No listings available right now.'**
  String get realEstateNoListings;

  /// No description provided for @realEstateNoFilterResults.
  ///
  /// In en, this message translates to:
  /// **'No listings match the current filters.'**
  String get realEstateNoFilterResults;

  /// No description provided for @realEstateNoSaved.
  ///
  /// In en, this message translates to:
  /// **'You have no saved properties yet.'**
  String get realEstateNoSaved;

  /// No description provided for @realEstateLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load real estate listings.'**
  String get realEstateLoadFailed;

  /// No description provided for @realEstateWorkspaceLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load the real estate workspace.'**
  String get realEstateWorkspaceLoadFailed;

  /// No description provided for @realEstateSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save the listing.'**
  String get realEstateSaveFailed;

  /// No description provided for @realEstateStatusUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update listing status.'**
  String get realEstateStatusUpdateFailed;

  /// No description provided for @realEstateActivatePlan.
  ///
  /// In en, this message translates to:
  /// **'Activate the property plan'**
  String get realEstateActivatePlan;

  /// No description provided for @realEstatePlanInactive.
  ///
  /// In en, this message translates to:
  /// **'The property plan is not active'**
  String get realEstatePlanInactive;

  /// No description provided for @realEstatePlanInactiveBody.
  ///
  /// In en, this message translates to:
  /// **'You cannot publish a new listing until the property seller plan is active.'**
  String get realEstatePlanInactiveBody;

  /// No description provided for @realEstateOpenUpgrades.
  ///
  /// In en, this message translates to:
  /// **'Open upgrade plans'**
  String get realEstateOpenUpgrades;

  /// No description provided for @realEstateListingsSummary.
  ///
  /// In en, this message translates to:
  /// **'Listings summary'**
  String get realEstateListingsSummary;

  /// No description provided for @realEstateAddListing.
  ///
  /// In en, this message translates to:
  /// **'Add listing'**
  String get realEstateAddListing;

  /// No description provided for @realEstateCreateListing.
  ///
  /// In en, this message translates to:
  /// **'Create listing'**
  String get realEstateCreateListing;

  /// No description provided for @realEstateSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get realEstateSaveChanges;

  /// No description provided for @realEstateBasicStep.
  ///
  /// In en, this message translates to:
  /// **'Basics'**
  String get realEstateBasicStep;

  /// No description provided for @realEstatePricingStep.
  ///
  /// In en, this message translates to:
  /// **'Pricing'**
  String get realEstatePricingStep;

  /// No description provided for @realEstateSpecsStep.
  ///
  /// In en, this message translates to:
  /// **'Specifications'**
  String get realEstateSpecsStep;

  /// No description provided for @realEstateContactStep.
  ///
  /// In en, this message translates to:
  /// **'Location & contact'**
  String get realEstateContactStep;

  /// No description provided for @realEstateImagesStep.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get realEstateImagesStep;

  /// No description provided for @realEstatePreviewStep.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get realEstatePreviewStep;

  /// No description provided for @realEstateTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Listing title'**
  String get realEstateTitleLabel;

  /// No description provided for @realEstatePurposeLabel.
  ///
  /// In en, this message translates to:
  /// **'Listing purpose'**
  String get realEstatePurposeLabel;

  /// No description provided for @realEstateAreaLabel.
  ///
  /// In en, this message translates to:
  /// **'Area (sqm)'**
  String get realEstateAreaLabel;

  /// No description provided for @realEstatePriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Required price'**
  String get realEstatePriceLabel;

  /// No description provided for @realEstateBankAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Bank settlement amount'**
  String get realEstateBankAmountLabel;

  /// No description provided for @realEstateFurnishingDescription.
  ///
  /// In en, this message translates to:
  /// **'Furnishing details'**
  String get realEstateFurnishingDescription;

  /// No description provided for @realEstateAddImage.
  ///
  /// In en, this message translates to:
  /// **'Add image'**
  String get realEstateAddImage;

  /// No description provided for @realEstateAddImages.
  ///
  /// In en, this message translates to:
  /// **'Add images'**
  String get realEstateAddImages;

  /// No description provided for @realEstateImagesHint.
  ///
  /// In en, this message translates to:
  /// **'Add up to 10 images. The first image will be used as the cover.'**
  String get realEstateImagesHint;

  /// No description provided for @realEstateExistingImagesHint.
  ///
  /// In en, this message translates to:
  /// **'If you do not add new images, the current images will remain unchanged.'**
  String get realEstateExistingImagesHint;

  /// No description provided for @realEstatePublishPreview.
  ///
  /// In en, this message translates to:
  /// **'Review the listing details before publishing.'**
  String get realEstatePublishPreview;

  /// No description provided for @realEstateListingPublished.
  ///
  /// In en, this message translates to:
  /// **'The listing has been published successfully.'**
  String get realEstateListingPublished;

  /// No description provided for @realEstateListingUpdated.
  ///
  /// In en, this message translates to:
  /// **'The listing has been updated successfully.'**
  String get realEstateListingUpdated;

  /// No description provided for @realEstateSaved.
  ///
  /// In en, this message translates to:
  /// **'Listing saved.'**
  String get realEstateSaved;

  /// No description provided for @realEstateUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Listing removed from saved items.'**
  String get realEstateUnsaved;

  /// No description provided for @realEstateMissingImages.
  ///
  /// In en, this message translates to:
  /// **'Please select at least one image.'**
  String get realEstateMissingImages;

  /// No description provided for @realEstateMissingRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Please review the required fields.'**
  String get realEstateMissingRequiredFields;

  /// No description provided for @realEstateSearchSectionNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get realEstateSearchSectionNewest;

  /// No description provided for @realEstateSearchSectionRent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get realEstateSearchSectionRent;

  /// No description provided for @realEstateSearchSectionSale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get realEstateSearchSectionSale;

  /// No description provided for @realEstateSearchSectionFurnished.
  ///
  /// In en, this message translates to:
  /// **'Furnished'**
  String get realEstateSearchSectionFurnished;

  /// No description provided for @realEstateSearchSectionFeatured.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get realEstateSearchSectionFeatured;

  /// No description provided for @realEstateSaveListing.
  ///
  /// In en, this message translates to:
  /// **'Save listing'**
  String get realEstateSaveListing;

  /// No description provided for @realEstateRemoveSavedListing.
  ///
  /// In en, this message translates to:
  /// **'Remove from saved'**
  String get realEstateRemoveSavedListing;

  /// No description provided for @realEstateShareListing.
  ///
  /// In en, this message translates to:
  /// **'Share listing'**
  String get realEstateShareListing;

  /// No description provided for @realEstateMessageOwner.
  ///
  /// In en, this message translates to:
  /// **'Message owner'**
  String get realEstateMessageOwner;

  /// No description provided for @realEstateCallOwner.
  ///
  /// In en, this message translates to:
  /// **'Call owner'**
  String get realEstateCallOwner;

  /// No description provided for @realEstateReviewStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get realEstateReviewStatusActive;

  /// No description provided for @realEstateReviewStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get realEstateReviewStatusPending;

  /// No description provided for @realEstateReviewStatusHiddenByExpiry.
  ///
  /// In en, this message translates to:
  /// **'Hidden by expiry'**
  String get realEstateReviewStatusHiddenByExpiry;

  /// No description provided for @realEstateReviewStatusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get realEstateReviewStatusArchived;

  /// No description provided for @realEstateSearchFiltersActive.
  ///
  /// In en, this message translates to:
  /// **'Active filters'**
  String get realEstateSearchFiltersActive;

  /// No description provided for @realEstatePriceRange.
  ///
  /// In en, this message translates to:
  /// **'Price range'**
  String get realEstatePriceRange;

  /// No description provided for @realEstateAreaRange.
  ///
  /// In en, this message translates to:
  /// **'Area range'**
  String get realEstateAreaRange;

  /// No description provided for @realEstateRoomsAtLeast.
  ///
  /// In en, this message translates to:
  /// **'Minimum rooms'**
  String get realEstateRoomsAtLeast;

  /// No description provided for @realEstateBathroomsAtLeast.
  ///
  /// In en, this message translates to:
  /// **'Minimum bathrooms'**
  String get realEstateBathroomsAtLeast;

  /// No description provided for @realEstateFloorAtLeast.
  ///
  /// In en, this message translates to:
  /// **'Floor from'**
  String get realEstateFloorAtLeast;

  /// No description provided for @realEstateFloorAtMost.
  ///
  /// In en, this message translates to:
  /// **'Floor to'**
  String get realEstateFloorAtMost;

  /// No description provided for @realEstateResultsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Results count'**
  String get realEstateResultsCountLabel;

  /// No description provided for @realEstateFeaturedOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Show featured listings only'**
  String get realEstateFeaturedOnlyHint;

  /// No description provided for @realEstateAvailableOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Show available listings only'**
  String get realEstateAvailableOnlyHint;

  /// No description provided for @realEstateSellerIdentity.
  ///
  /// In en, this message translates to:
  /// **'Publisher identity'**
  String get realEstateSellerIdentity;

  /// No description provided for @realEstateDescriptionPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Write a clear description of the property, location, and important advantages.'**
  String get realEstateDescriptionPlaceholder;

  /// No description provided for @realEstatePhonePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter a contact phone number'**
  String get realEstatePhonePlaceholder;

  /// No description provided for @realEstateCityPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Example: Baghdad'**
  String get realEstateCityPlaceholder;

  /// No description provided for @realEstateBlockPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Example: B2'**
  String get realEstateBlockPlaceholder;

  /// No description provided for @realEstateBuildingPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Example: 711'**
  String get realEstateBuildingPlaceholder;

  /// No description provided for @realEstateApartmentPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Example: 12'**
  String get realEstateApartmentPlaceholder;

  /// No description provided for @realEstateTitlePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Example: Furnished 120 sqm apartment in block B2'**
  String get realEstateTitlePlaceholder;

  /// No description provided for @realEstateRoomsLabel.
  ///
  /// In en, this message translates to:
  /// **'Rooms'**
  String get realEstateRoomsLabel;

  /// No description provided for @realEstateBathroomsLabel.
  ///
  /// In en, this message translates to:
  /// **'Bathrooms'**
  String get realEstateBathroomsLabel;

  /// No description provided for @realEstateFloorLabel.
  ///
  /// In en, this message translates to:
  /// **'Floor'**
  String get realEstateFloorLabel;

  /// No description provided for @realEstatePaymentMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get realEstatePaymentMethodLabel;

  /// No description provided for @realEstateAvailableStatus.
  ///
  /// In en, this message translates to:
  /// **'Property status'**
  String get realEstateAvailableStatus;

  /// No description provided for @realEstateNoImages.
  ///
  /// In en, this message translates to:
  /// **'This property has no images yet.'**
  String get realEstateNoImages;

  /// No description provided for @realEstatePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review listing'**
  String get realEstatePreviewTitle;

  /// No description provided for @realEstatePreviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm the listing details before publishing.'**
  String get realEstatePreviewSubtitle;

  /// No description provided for @realEstateEditImagesOrder.
  ///
  /// In en, this message translates to:
  /// **'You can remove images or change their order before publishing.'**
  String get realEstateEditImagesOrder;

  /// No description provided for @realEstateKeepCurrentImages.
  ///
  /// In en, this message translates to:
  /// **'Current images will remain if you do not add new ones.'**
  String get realEstateKeepCurrentImages;

  /// No description provided for @realEstateListingOwnerUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown publisher'**
  String get realEstateListingOwnerUnknown;

  /// No description provided for @realEstateStartChatFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open a chat with the publisher.'**
  String get realEstateStartChatFailed;

  /// No description provided for @realEstateCallFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the phone call.'**
  String get realEstateCallFailed;

  /// No description provided for @realEstateShareText.
  ///
  /// In en, this message translates to:
  /// **'Check this property on Maslaki: {title}'**
  String realEstateShareText(String title);

  /// No description provided for @realEstateFilterPurposeAll.
  ///
  /// In en, this message translates to:
  /// **'Sale & rent'**
  String get realEstateFilterPurposeAll;

  /// No description provided for @realEstateMinPrice.
  ///
  /// In en, this message translates to:
  /// **'Min price'**
  String get realEstateMinPrice;

  /// No description provided for @realEstateMaxPrice.
  ///
  /// In en, this message translates to:
  /// **'Max price'**
  String get realEstateMaxPrice;

  /// No description provided for @realEstateMinArea.
  ///
  /// In en, this message translates to:
  /// **'Min area'**
  String get realEstateMinArea;

  /// No description provided for @realEstateMaxArea.
  ///
  /// In en, this message translates to:
  /// **'Max area'**
  String get realEstateMaxArea;

  /// No description provided for @realEstateFilterSort.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get realEstateFilterSort;

  /// No description provided for @realEstateFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Property filters'**
  String get realEstateFilterTitle;

  /// No description provided for @realEstateSavedEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Save properties you like so you can revisit them quickly.'**
  String get realEstateSavedEmptyHint;

  /// No description provided for @realEstateFilterApplySummary.
  ///
  /// In en, this message translates to:
  /// **'Filters applied'**
  String get realEstateFilterApplySummary;

  /// No description provided for @realEstateValidationTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Listing title is required.'**
  String get realEstateValidationTitleRequired;

  /// No description provided for @realEstateValidationAreaRequired.
  ///
  /// In en, this message translates to:
  /// **'Area is required and must be greater than zero.'**
  String get realEstateValidationAreaRequired;

  /// No description provided for @realEstateValidationPriceRequired.
  ///
  /// In en, this message translates to:
  /// **'Price is required and must be valid.'**
  String get realEstateValidationPriceRequired;

  /// No description provided for @realEstateValidationPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required.'**
  String get realEstateValidationPhoneRequired;

  /// No description provided for @realEstateValidationFurnishingDetails.
  ///
  /// In en, this message translates to:
  /// **'Please add furnishing details for furnished listings.'**
  String get realEstateValidationFurnishingDetails;

  /// No description provided for @realEstateValidationImagesRequired.
  ///
  /// In en, this message translates to:
  /// **'Please add at least one image.'**
  String get realEstateValidationImagesRequired;

  /// No description provided for @realEstateValidationRangeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please review the entered filter ranges.'**
  String get realEstateValidationRangeInvalid;

  /// No description provided for @settingsActivityLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load activity log right now.'**
  String get settingsActivityLoadFailed;

  /// No description provided for @settingsActivityLoadMoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load more activity.'**
  String get settingsActivityLoadMoreFailed;

  /// No description provided for @settingsActivityNoEntries.
  ///
  /// In en, this message translates to:
  /// **'No activity yet.'**
  String get settingsActivityNoEntries;

  /// No description provided for @settingsActivityEndOfLog.
  ///
  /// In en, this message translates to:
  /// **'End of log'**
  String get settingsActivityEndOfLog;

  /// No description provided for @settingsActivityLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get settingsActivityLoadMore;

  /// No description provided for @settingsActivityEventLabel.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get settingsActivityEventLabel;

  /// No description provided for @settingsActivityCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get settingsActivityCategoryLabel;

  /// No description provided for @settingsActivityActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get settingsActivityActionLabel;

  /// No description provided for @settingsActivityTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get settingsActivityTimeLabel;

  /// No description provided for @settingsAccountUpgrades.
  ///
  /// In en, this message translates to:
  /// **'Account upgrades'**
  String get settingsAccountUpgrades;

  /// No description provided for @settingsAccountUpgradesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load current upgrade status.'**
  String get settingsAccountUpgradesLoadFailed;

  /// No description provided for @settingsManageUpgrades.
  ///
  /// In en, this message translates to:
  /// **'Manage upgrades'**
  String get settingsManageUpgrades;

  /// No description provided for @settingsActiveSessions.
  ///
  /// In en, this message translates to:
  /// **'Active Sessions'**
  String get settingsActiveSessions;

  /// No description provided for @settingsSessionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sessions'**
  String settingsSessionsCount(int count);

  /// No description provided for @settingsNoActiveSessions.
  ///
  /// In en, this message translates to:
  /// **'No active sessions found.'**
  String get settingsNoActiveSessions;

  /// No description provided for @settingsProcessingRequest.
  ///
  /// In en, this message translates to:
  /// **'Processing request...'**
  String get settingsProcessingRequest;

  /// No description provided for @settingsLogoutOtherDevices.
  ///
  /// In en, this message translates to:
  /// **'Sign out from all other devices'**
  String get settingsLogoutOtherDevices;

  /// No description provided for @settingsPremiumActive.
  ///
  /// In en, this message translates to:
  /// **'Premium active'**
  String get settingsPremiumActive;

  /// No description provided for @settingsPremiumInactive.
  ///
  /// In en, this message translates to:
  /// **'Premium inactive'**
  String get settingsPremiumInactive;

  /// No description provided for @settingsPropertySellerActive.
  ///
  /// In en, this message translates to:
  /// **'Property seller active'**
  String get settingsPropertySellerActive;

  /// No description provided for @settingsPropertySellerInactive.
  ///
  /// In en, this message translates to:
  /// **'Property seller inactive'**
  String get settingsPropertySellerInactive;

  /// No description provided for @settingsCarSellerActive.
  ///
  /// In en, this message translates to:
  /// **'Car seller active'**
  String get settingsCarSellerActive;

  /// No description provided for @settingsCarSellerInactive.
  ///
  /// In en, this message translates to:
  /// **'Car seller inactive'**
  String get settingsCarSellerInactive;

  /// No description provided for @settingsNearestExpiry.
  ///
  /// In en, this message translates to:
  /// **'Nearest expiry: {date}'**
  String settingsNearestExpiry(String date);

  /// No description provided for @settingsNoActiveSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'There are no active subscriptions at the moment.'**
  String get settingsNoActiveSubscriptions;

  /// No description provided for @settingsThisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get settingsThisDevice;

  /// No description provided for @settingsOtherDevice.
  ///
  /// In en, this message translates to:
  /// **'Other device'**
  String get settingsOtherDevice;

  /// No description provided for @settingsLastActivity.
  ///
  /// In en, this message translates to:
  /// **'Last activity'**
  String get settingsLastActivity;

  /// No description provided for @settingsRevokedSessions.
  ///
  /// In en, this message translates to:
  /// **'{count} session(s) were terminated.'**
  String settingsRevokedSessions(int count);

  /// No description provided for @customerHomeWelcomeMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning, every service is ready in one tap.'**
  String get customerHomeWelcomeMorning;

  /// No description provided for @customerHomeWelcomeAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon, choose your path and start instantly.'**
  String get customerHomeWelcomeAfternoon;

  /// No description provided for @customerHomeWelcomeEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening, shopping, taxi, community, and jobs in one place.'**
  String get customerHomeWelcomeEvening;

  /// No description provided for @customerHomeWelcomeNight.
  ///
  /// In en, this message translates to:
  /// **'Late night mode, the app is ready for your needs.'**
  String get customerHomeWelcomeNight;

  /// No description provided for @customerHomeDrawerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unified experience for your daily services.'**
  String get customerHomeDrawerSubtitle;

  /// No description provided for @customerHomePaidUpgrades.
  ///
  /// In en, this message translates to:
  /// **'Paid upgrades'**
  String get customerHomePaidUpgrades;

  /// No description provided for @customerHomeRealEstate.
  ///
  /// In en, this message translates to:
  /// **'Real estate'**
  String get customerHomeRealEstate;

  /// No description provided for @customerHomeCarsMarket.
  ///
  /// In en, this message translates to:
  /// **'Cars market'**
  String get customerHomeCarsMarket;

  /// No description provided for @customerHomeWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get customerHomeWelcome;

  /// No description provided for @customerHomeHiName.
  ///
  /// In en, this message translates to:
  /// **'Hi {name}'**
  String customerHomeHiName(String name);

  /// No description provided for @customerHomeLiveNow.
  ///
  /// In en, this message translates to:
  /// **'Live Now'**
  String get customerHomeLiveNow;

  /// No description provided for @customerHomeInstantUpdates.
  ///
  /// In en, this message translates to:
  /// **'Instant Updates'**
  String get customerHomeInstantUpdates;

  /// No description provided for @customerHomeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search for a store or service quickly'**
  String get customerHomeSearchHint;

  /// No description provided for @customerHomeQuickShop.
  ///
  /// In en, this message translates to:
  /// **'Quick Shop'**
  String get customerHomeQuickShop;

  /// No description provided for @customerHomeBookTaxi.
  ///
  /// In en, this message translates to:
  /// **'Book Taxi'**
  String get customerHomeBookTaxi;

  /// No description provided for @customerHomeYourCommunity.
  ///
  /// In en, this message translates to:
  /// **'Your Community'**
  String get customerHomeYourCommunity;

  /// No description provided for @customerHomeMainTitle.
  ///
  /// In en, this message translates to:
  /// **'Main Home'**
  String get customerHomeMainTitle;

  /// No description provided for @customerHomeChooseSection.
  ///
  /// In en, this message translates to:
  /// **'Choose Section'**
  String get customerHomeChooseSection;

  /// No description provided for @customerHomeChooseSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A premium home with six clear sections.'**
  String get customerHomeChooseSectionSubtitle;

  /// No description provided for @customerHomeTaxiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fast booking and direct fare negotiation.'**
  String get customerHomeTaxiSubtitle;

  /// No description provided for @customerHomeCommunityTitle.
  ///
  /// In en, this message translates to:
  /// **'Shdysir'**
  String get customerHomeCommunityTitle;

  /// No description provided for @customerHomeCommunitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Posts, interaction, and community chats.'**
  String get customerHomeCommunitySubtitle;

  /// No description provided for @customerHomeShoppingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restaurants, stores, and daily offers.'**
  String get customerHomeShoppingSubtitle;

  /// No description provided for @customerHomeJobsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Professional opportunities with smart filtering.'**
  String get customerHomeJobsSubtitle;

  /// No description provided for @customerHomeCarsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cars marketplace, recommendations, and direct selling.'**
  String get customerHomeCarsSubtitle;

  /// No description provided for @customerHomeRealEstateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Property listings, rentals, and sales inside Basmaya.'**
  String get customerHomeRealEstateSubtitle;

  /// No description provided for @customerHomeOpenTrack.
  ///
  /// In en, this message translates to:
  /// **'Open Track'**
  String get customerHomeOpenTrack;

  /// No description provided for @customerHomeTaxiTitle.
  ///
  /// In en, this message translates to:
  /// **'Taxi'**
  String get customerHomeTaxiTitle;

  /// No description provided for @customerHomeShoppingTitle.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get customerHomeShoppingTitle;

  /// No description provided for @customerHomeJobsTitle.
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get customerHomeJobsTitle;

  /// No description provided for @customerHomeCarsTitle.
  ///
  /// In en, this message translates to:
  /// **'Cars'**
  String get customerHomeCarsTitle;

  /// No description provided for @customerDiscoveryOrders.
  ///
  /// In en, this message translates to:
  /// **'My orders'**
  String get customerDiscoveryOrders;

  /// No description provided for @customerDiscoveryCart.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get customerDiscoveryCart;

  /// No description provided for @customerDiscoveryFavoriteProducts.
  ///
  /// In en, this message translates to:
  /// **'Favorite products'**
  String get customerDiscoveryFavoriteProducts;

  /// No description provided for @customerDiscoveryDeliveryAddresses.
  ///
  /// In en, this message translates to:
  /// **'Delivery addresses'**
  String get customerDiscoveryDeliveryAddresses;

  /// No description provided for @customerDiscoveryTaxi.
  ///
  /// In en, this message translates to:
  /// **'Taxi'**
  String get customerDiscoveryTaxi;

  /// No description provided for @customerDiscoveryBasmayaFeed.
  ///
  /// In en, this message translates to:
  /// **'Basmaya feed'**
  String get customerDiscoveryBasmayaFeed;

  /// No description provided for @customerDiscoverySocialSearch.
  ///
  /// In en, this message translates to:
  /// **'Social search'**
  String get customerDiscoverySocialSearch;

  /// No description provided for @customerDiscoveryChats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get customerDiscoveryChats;

  /// No description provided for @customerDiscoveryResetPersonalization.
  ///
  /// In en, this message translates to:
  /// **'Reset personalization'**
  String get customerDiscoveryResetPersonalization;

  /// No description provided for @customerDiscoveryResultsFor.
  ///
  /// In en, this message translates to:
  /// **'Results for \"{query}\"'**
  String customerDiscoveryResultsFor(String query);

  /// No description provided for @customerDiscoveryMerchants.
  ///
  /// In en, this message translates to:
  /// **'Merchants'**
  String get customerDiscoveryMerchants;

  /// No description provided for @customerDiscoveryOpenNow.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get customerDiscoveryOpenNow;

  /// No description provided for @customerDiscoveryOpenStores.
  ///
  /// In en, this message translates to:
  /// **'Open stores'**
  String get customerDiscoveryOpenStores;

  /// No description provided for @customerDiscoveryOpenMerchants.
  ///
  /// In en, this message translates to:
  /// **'Open merchants'**
  String get customerDiscoveryOpenMerchants;

  /// No description provided for @customerDiscoveryOffers.
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get customerDiscoveryOffers;

  /// No description provided for @customerDiscoveryCurrentDiscounts.
  ///
  /// In en, this message translates to:
  /// **'Current discounts'**
  String get customerDiscoveryCurrentDiscounts;

  /// No description provided for @customerDiscoveryTodayOffers.
  ///
  /// In en, this message translates to:
  /// **'Today offers'**
  String get customerDiscoveryTodayOffers;

  /// No description provided for @customerDiscoveryRestaurants.
  ///
  /// In en, this message translates to:
  /// **'Restaurants'**
  String get customerDiscoveryRestaurants;

  /// No description provided for @customerDiscoveryAllInOnePlace.
  ///
  /// In en, this message translates to:
  /// **'All in one place'**
  String get customerDiscoveryAllInOnePlace;

  /// No description provided for @customerDiscoveryStores.
  ///
  /// In en, this message translates to:
  /// **'Stores'**
  String get customerDiscoveryStores;

  /// No description provided for @customerDiscoverySupermarketsAndMore.
  ///
  /// In en, this message translates to:
  /// **'Supermarkets and more'**
  String get customerDiscoverySupermarketsAndMore;

  /// No description provided for @customerDiscoveryQuickRequest.
  ///
  /// In en, this message translates to:
  /// **'Quick request'**
  String get customerDiscoveryQuickRequest;

  /// No description provided for @customerDiscoveryMainCategories.
  ///
  /// In en, this message translates to:
  /// **'Main categories'**
  String get customerDiscoveryMainCategories;

  /// No description provided for @customerDiscoveryMarketTitle.
  ///
  /// In en, this message translates to:
  /// **'Maslaki | Market'**
  String get customerDiscoveryMarketTitle;

  /// No description provided for @customerDiscoveryMarketSubtitle.
  ///
  /// In en, this message translates to:
  /// **'From Basmaya for your daily needs: markets, restaurants, and taxi'**
  String get customerDiscoveryMarketSubtitle;

  /// No description provided for @commonOpenLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the link.'**
  String get commonOpenLinkFailed;

  /// No description provided for @customerDiscoveryTopRated.
  ///
  /// In en, this message translates to:
  /// **'Top rated'**
  String get customerDiscoveryTopRated;

  /// No description provided for @customerDiscoverySearchQueryOpenNow.
  ///
  /// In en, this message translates to:
  /// **'open now'**
  String get customerDiscoverySearchQueryOpenNow;

  /// No description provided for @customerDiscoverySearchQueryOffers.
  ///
  /// In en, this message translates to:
  /// **'offers'**
  String get customerDiscoverySearchQueryOffers;

  /// No description provided for @customerDiscoverySearchQueryTopRated.
  ///
  /// In en, this message translates to:
  /// **'top rated'**
  String get customerDiscoverySearchQueryTopRated;

  /// No description provided for @customerDiscoveryHeroWith.
  ///
  /// In en, this message translates to:
  /// **'With '**
  String get customerDiscoveryHeroWith;

  /// No description provided for @customerDiscoveryHeroCloserTagline.
  ///
  /// In en, this message translates to:
  /// **'Everything is closer to you, from where you are.'**
  String get customerDiscoveryHeroCloserTagline;

  /// No description provided for @customerDiscoveryLiveMarketPulse.
  ///
  /// In en, this message translates to:
  /// **'Live market pulse'**
  String get customerDiscoveryLiveMarketPulse;

  /// No description provided for @customerDiscoveryActiveOffers.
  ///
  /// In en, this message translates to:
  /// **'Active offers'**
  String get customerDiscoveryActiveOffers;

  /// No description provided for @customerDiscoveryMarkets.
  ///
  /// In en, this message translates to:
  /// **'Markets'**
  String get customerDiscoveryMarkets;

  /// No description provided for @customerDiscoveryTaxiSpotlightTitle.
  ///
  /// In en, this message translates to:
  /// **'Maslaki Taxi'**
  String get customerDiscoveryTaxiSpotlightTitle;

  /// No description provided for @customerDiscoveryTaxiSpotlightBody.
  ///
  /// In en, this message translates to:
  /// **'Set pickup and drop-off, choose your price, and nearby captains respond instantly.'**
  String get customerDiscoveryTaxiSpotlightBody;

  /// No description provided for @customerDiscoveryTaxiSpotlightAction.
  ///
  /// In en, this message translates to:
  /// **'Request a taxi now'**
  String get customerDiscoveryTaxiSpotlightAction;

  /// No description provided for @customerDiscoverySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search for a restaurant, market, or product'**
  String get customerDiscoverySearchHint;

  /// No description provided for @customerDiscoveryFastestDelivery.
  ///
  /// In en, this message translates to:
  /// **'Fastest delivery'**
  String get customerDiscoveryFastestDelivery;

  /// No description provided for @customerDiscoveryBestPrice.
  ///
  /// In en, this message translates to:
  /// **'Best price'**
  String get customerDiscoveryBestPrice;

  /// No description provided for @customerDiscoveryRequestTaxi.
  ///
  /// In en, this message translates to:
  /// **'Request taxi'**
  String get customerDiscoveryRequestTaxi;

  /// No description provided for @customerDiscoveryReorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get customerDiscoveryReorder;

  /// No description provided for @customerDiscoveryLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Failed to load the screen'**
  String get customerDiscoveryLoadFailedTitle;

  /// No description provided for @customerDiscoveryLoadFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get customerDiscoveryLoadFailedBody;

  /// No description provided for @customerDiscoveryGreetingMorningTitle.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get customerDiscoveryGreetingMorningTitle;

  /// No description provided for @customerDiscoveryGreetingMorningTagline.
  ///
  /// In en, this message translates to:
  /// **'Everything is ready. Order what you like and have it delivered.'**
  String get customerDiscoveryGreetingMorningTagline;

  /// No description provided for @customerDiscoveryGreetingNoonTitle.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get customerDiscoveryGreetingNoonTitle;

  /// No description provided for @customerDiscoveryGreetingNoonTagline.
  ///
  /// In en, this message translates to:
  /// **'If you are hungry or need something, your order can start right now.'**
  String get customerDiscoveryGreetingNoonTagline;

  /// No description provided for @customerDiscoveryGreetingAfternoonTitle.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get customerDiscoveryGreetingAfternoonTitle;

  /// No description provided for @customerDiscoveryGreetingAfternoonTagline.
  ///
  /// In en, this message translates to:
  /// **'Offers are live, and your order arrives without extra delay.'**
  String get customerDiscoveryGreetingAfternoonTagline;

  /// No description provided for @customerDiscoveryGreetingEveningTitle.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get customerDiscoveryGreetingEveningTitle;

  /// No description provided for @customerDiscoveryGreetingEveningTagline.
  ///
  /// In en, this message translates to:
  /// **'Take your time and pick what you need for the evening.'**
  String get customerDiscoveryGreetingEveningTagline;

  /// No description provided for @customerDiscoveryGreetingNightTitle.
  ///
  /// In en, this message translates to:
  /// **'Late night'**
  String get customerDiscoveryGreetingNightTitle;

  /// No description provided for @customerDiscoveryGreetingNightTagline.
  ///
  /// In en, this message translates to:
  /// **'If you need a late order, we are still with you.'**
  String get customerDiscoveryGreetingNightTagline;

  /// No description provided for @customerDiscoveryBannerOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Maslaki brings the offer to you'**
  String get customerDiscoveryBannerOfferTitle;

  /// No description provided for @customerDiscoveryBannerOfferSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Real daily offers from Basmaya stores and restaurants'**
  String get customerDiscoveryBannerOfferSubtitle;

  /// No description provided for @customerDiscoveryBannerUnifiedMarketTitle.
  ///
  /// In en, this message translates to:
  /// **'A complete market in one place'**
  String get customerDiscoveryBannerUnifiedMarketTitle;

  /// No description provided for @customerDiscoveryBannerUnifiedMarketSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restaurants, home shopping, cars, and taxi in one app'**
  String get customerDiscoveryBannerUnifiedMarketSubtitle;

  /// No description provided for @customerDiscoveryBannerTaxiTitle.
  ///
  /// In en, this message translates to:
  /// **'Maslaki Taxi all day long'**
  String get customerDiscoveryBannerTaxiTitle;

  /// No description provided for @customerDiscoveryBannerTaxiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set your ride price and captains respond instantly'**
  String get customerDiscoveryBannerTaxiSubtitle;

  /// No description provided for @customerDiscoveryHubStyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Fashion market'**
  String get customerDiscoveryHubStyleTitle;

  /// No description provided for @customerDiscoveryHubStyleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Women, men, shoes, and bags'**
  String get customerDiscoveryHubStyleSubtitle;

  /// No description provided for @customerDiscoveryHubFoodTitle.
  ///
  /// In en, this message translates to:
  /// **'Food and drinks'**
  String get customerDiscoveryHubFoodTitle;

  /// No description provided for @customerDiscoveryHubFoodSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restaurants, desserts, pastries, and coffee'**
  String get customerDiscoveryHubFoodSubtitle;

  /// No description provided for @customerDiscoveryHubHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home shopping'**
  String get customerDiscoveryHubHomeTitle;

  /// No description provided for @customerDiscoveryHubHomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Markets, meats, produce, cleaning, stationery, and gifts'**
  String get customerDiscoveryHubHomeSubtitle;

  /// No description provided for @customerDiscoveryHubElectronicsTitle.
  ///
  /// In en, this message translates to:
  /// **'Electrical essentials'**
  String get customerDiscoveryHubElectronicsTitle;

  /// No description provided for @customerDiscoveryHubElectronicsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Devices, accessories, and home electrical items'**
  String get customerDiscoveryHubElectronicsSubtitle;

  /// No description provided for @customerDiscoveryHubCarsTitle.
  ///
  /// In en, this message translates to:
  /// **'Cars market'**
  String get customerDiscoveryHubCarsTitle;

  /// No description provided for @customerDiscoveryHubCarsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'New and used by make, model, and year'**
  String get customerDiscoveryHubCarsSubtitle;

  /// No description provided for @customerDiscoveryHubPharmacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Pharmacies'**
  String get customerDiscoveryHubPharmacyTitle;

  /// No description provided for @customerDiscoveryHubPharmacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prescriptions, supplements, and medical supplies'**
  String get customerDiscoveryHubPharmacySubtitle;

  /// No description provided for @customerDiscoveryHubMainMarketTitle.
  ///
  /// In en, this message translates to:
  /// **'Main market'**
  String get customerDiscoveryHubMainMarketTitle;

  /// No description provided for @customerDiscoveryHubMainMarketSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All categories in one place'**
  String get customerDiscoveryHubMainMarketSubtitle;

  /// No description provided for @customerDiscoveryCategoryRestaurantsTitle.
  ///
  /// In en, this message translates to:
  /// **'Restaurants'**
  String get customerDiscoveryCategoryRestaurantsTitle;

  /// No description provided for @customerDiscoveryCategoryRestaurantsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily meals and a variety of cuisines'**
  String get customerDiscoveryCategoryRestaurantsSubtitle;

  /// No description provided for @customerDiscoveryCategoryWomenFashionTitle.
  ///
  /// In en, this message translates to:
  /// **'Women fashion'**
  String get customerDiscoveryCategoryWomenFashionTitle;

  /// No description provided for @customerDiscoveryCategoryWomenFashionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clothing, bags, care, and beauty'**
  String get customerDiscoveryCategoryWomenFashionSubtitle;

  /// No description provided for @customerDiscoveryCategoryMenFashionTitle.
  ///
  /// In en, this message translates to:
  /// **'Men fashion'**
  String get customerDiscoveryCategoryMenFashionTitle;

  /// No description provided for @customerDiscoveryCategoryMenFashionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clothing, shoes, and men fragrances'**
  String get customerDiscoveryCategoryMenFashionSubtitle;

  /// No description provided for @customerDiscoveryCategoryDessertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Desserts and pastries'**
  String get customerDiscoveryCategoryDessertsTitle;

  /// No description provided for @customerDiscoveryCategoryDessertsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cake, baklava, and fresh pastries'**
  String get customerDiscoveryCategoryDessertsSubtitle;

  /// No description provided for @customerDiscoveryCategoryMarketsCleaningTitle.
  ///
  /// In en, this message translates to:
  /// **'Markets and cleaning'**
  String get customerDiscoveryCategoryMarketsCleaningTitle;

  /// No description provided for @customerDiscoveryCategoryMarketsCleaningSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Groceries, home goods, and cleaning in one place'**
  String get customerDiscoveryCategoryMarketsCleaningSubtitle;

  /// No description provided for @customerDiscoveryCategoryFruitVegetablesTitle.
  ///
  /// In en, this message translates to:
  /// **'Fruit and vegetables'**
  String get customerDiscoveryCategoryFruitVegetablesTitle;

  /// No description provided for @customerDiscoveryCategoryFruitVegetablesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fresh daily produce'**
  String get customerDiscoveryCategoryFruitVegetablesSubtitle;

  /// No description provided for @customerDiscoveryCategoryMeatPoultryTitle.
  ///
  /// In en, this message translates to:
  /// **'Meat and poultry'**
  String get customerDiscoveryCategoryMeatPoultryTitle;

  /// No description provided for @customerDiscoveryCategoryMeatPoultrySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Butcher, chicken, and frozen items'**
  String get customerDiscoveryCategoryMeatPoultrySubtitle;

  /// No description provided for @customerDiscoveryCategoryCoffeeDrinksTitle.
  ///
  /// In en, this message translates to:
  /// **'Coffee and drinks'**
  String get customerDiscoveryCategoryCoffeeDrinksTitle;

  /// No description provided for @customerDiscoveryCategoryCoffeeDrinksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hot and cold coffee with juices'**
  String get customerDiscoveryCategoryCoffeeDrinksSubtitle;

  /// No description provided for @customerDiscoveryCategoryElectricalSuppliesTitle.
  ///
  /// In en, this message translates to:
  /// **'Electrical supplies'**
  String get customerDiscoveryCategoryElectricalSuppliesTitle;

  /// No description provided for @customerDiscoveryCategoryElectricalSuppliesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Devices and home electrical parts'**
  String get customerDiscoveryCategoryElectricalSuppliesSubtitle;

  /// No description provided for @customerDiscoveryCategoryHomeEssentialsTitle.
  ///
  /// In en, this message translates to:
  /// **'Home essentials'**
  String get customerDiscoveryCategoryHomeEssentialsTitle;

  /// No description provided for @customerDiscoveryCategoryHomeEssentialsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Kitchen and home essentials'**
  String get customerDiscoveryCategoryHomeEssentialsSubtitle;

  /// No description provided for @customerDiscoveryCategoryPersonalCareTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal care'**
  String get customerDiscoveryCategoryPersonalCareTitle;

  /// No description provided for @customerDiscoveryCategoryPersonalCareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily essentials and fragrances'**
  String get customerDiscoveryCategoryPersonalCareSubtitle;

  /// No description provided for @customerDiscoveryCategoryStationeryGiftsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stationery and gifts'**
  String get customerDiscoveryCategoryStationeryGiftsTitle;

  /// No description provided for @customerDiscoveryCategoryStationeryGiftsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stationery, wrapping, and gifts'**
  String get customerDiscoveryCategoryStationeryGiftsSubtitle;

  /// No description provided for @drawerGroupSocial.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get drawerGroupSocial;

  /// No description provided for @drawerGroupCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get drawerGroupCommunity;

  /// No description provided for @drawerProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get drawerProfile;

  /// No description provided for @drawerNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get drawerNotifications;

  /// No description provided for @drawerNotificationsSub.
  ///
  /// In en, this message translates to:
  /// **'Open all alerts and notifications'**
  String get drawerNotificationsSub;

  /// No description provided for @drawerUserSearch.
  ///
  /// In en, this message translates to:
  /// **'Search users'**
  String get drawerUserSearch;

  /// No description provided for @drawerUserSearchSub.
  ///
  /// In en, this message translates to:
  /// **'Search by name or phone number in the app'**
  String get drawerUserSearchSub;

  /// No description provided for @drawerFriendRequests.
  ///
  /// In en, this message translates to:
  /// **'Friend requests'**
  String get drawerFriendRequests;

  /// No description provided for @drawerFriendRequestsSub.
  ///
  /// In en, this message translates to:
  /// **'View incoming and outgoing requests'**
  String get drawerFriendRequestsSub;

  /// No description provided for @drawerMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get drawerMessages;

  /// No description provided for @drawerMessagesSub.
  ///
  /// In en, this message translates to:
  /// **'Open your conversations'**
  String get drawerMessagesSub;

  /// No description provided for @drawerReportedPosts.
  ///
  /// In en, this message translates to:
  /// **'Posts needing edits'**
  String get drawerReportedPosts;

  /// No description provided for @drawerReportedPostsSub.
  ///
  /// In en, this message translates to:
  /// **'Review reported posts and resubmit edits'**
  String get drawerReportedPostsSub;

  /// No description provided for @drawerManualSelection.
  ///
  /// In en, this message translates to:
  /// **'Manual selection'**
  String get drawerManualSelection;

  /// No description provided for @drawerBlockCommunity.
  ///
  /// In en, this message translates to:
  /// **'Block community'**
  String get drawerBlockCommunity;

  /// No description provided for @drawerCompoundCommunity.
  ///
  /// In en, this message translates to:
  /// **'Compound community'**
  String get drawerCompoundCommunity;

  /// No description provided for @drawerBuildingCommunity.
  ///
  /// In en, this message translates to:
  /// **'Building community'**
  String get drawerBuildingCommunity;

  /// No description provided for @drawerEnterBlockCode.
  ///
  /// In en, this message translates to:
  /// **'Enter block code'**
  String get drawerEnterBlockCode;

  /// No description provided for @drawerEnterCompoundCode.
  ///
  /// In en, this message translates to:
  /// **'Enter compound code'**
  String get drawerEnterCompoundCode;

  /// No description provided for @drawerEnterBuildingCode.
  ///
  /// In en, this message translates to:
  /// **'Enter building code'**
  String get drawerEnterBuildingCode;

  /// No description provided for @drawerBlockCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Type a block code like A or B'**
  String get drawerBlockCodeHint;

  /// No description provided for @drawerCompoundCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Type a compound code like A1 or B4'**
  String get drawerCompoundCodeHint;

  /// No description provided for @drawerBuildingCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Type a building code like A711'**
  String get drawerBuildingCodeHint;

  /// No description provided for @carsMarketplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Cars Market'**
  String get carsMarketplaceTitle;

  /// No description provided for @carsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by brand, model, or city'**
  String get carsSearchHint;

  /// No description provided for @carsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load car listings.'**
  String get carsLoadFailed;

  /// No description provided for @carsNoListings.
  ///
  /// In en, this message translates to:
  /// **'No car listings available right now.'**
  String get carsNoListings;

  /// No description provided for @carsFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter cars'**
  String get carsFilterTitle;

  /// No description provided for @carsManageListings.
  ///
  /// In en, this message translates to:
  /// **'Manage my listings'**
  String get carsManageListings;

  /// No description provided for @carsWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Cars workspace'**
  String get carsWorkspaceTitle;

  /// No description provided for @carsWorkspaceLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load cars workspace.'**
  String get carsWorkspaceLoadFailed;

  /// No description provided for @carsActivateSelling.
  ///
  /// In en, this message translates to:
  /// **'Activate car selling'**
  String get carsActivateSelling;

  /// No description provided for @carsOpenUpgrades.
  ///
  /// In en, this message translates to:
  /// **'Open upgrade plans'**
  String get carsOpenUpgrades;

  /// No description provided for @carsListingsSummary.
  ///
  /// In en, this message translates to:
  /// **'Listings summary'**
  String get carsListingsSummary;

  /// No description provided for @carsWorkspaceSyncedHint.
  ///
  /// In en, this message translates to:
  /// **'Some listings were re-synced based on your current subscription state.'**
  String get carsWorkspaceSyncedHint;

  /// No description provided for @carsSellerBannerActive.
  ///
  /// In en, this message translates to:
  /// **'Your seller tools are active. You can add and manage car listings now.'**
  String get carsSellerBannerActive;

  /// No description provided for @carsSellerBannerInactive.
  ///
  /// In en, this message translates to:
  /// **'Activate car seller or premium to publish and manage car listings.'**
  String get carsSellerBannerInactive;

  /// No description provided for @carsAddListing.
  ///
  /// In en, this message translates to:
  /// **'Add listing'**
  String get carsAddListing;

  /// No description provided for @carsEditListing.
  ///
  /// In en, this message translates to:
  /// **'Edit listing'**
  String get carsEditListing;

  /// No description provided for @carsResultsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} listing(s)'**
  String carsResultsCount(int count);

  /// No description provided for @carsQuickNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get carsQuickNewest;

  /// No description provided for @carsQuickSedan.
  ///
  /// In en, this message translates to:
  /// **'Sedan'**
  String get carsQuickSedan;

  /// No description provided for @carsQuickSuv.
  ///
  /// In en, this message translates to:
  /// **'SUV'**
  String get carsQuickSuv;

  /// No description provided for @carsQuickUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get carsQuickUsed;

  /// No description provided for @carsQuickPriceLow.
  ///
  /// In en, this message translates to:
  /// **'Lowest price'**
  String get carsQuickPriceLow;

  /// No description provided for @carsBrand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get carsBrand;

  /// No description provided for @carsModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get carsModel;

  /// No description provided for @carsCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get carsCity;

  /// No description provided for @carsCondition.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get carsCondition;

  /// No description provided for @carsBodyType.
  ///
  /// In en, this message translates to:
  /// **'Body type'**
  String get carsBodyType;

  /// No description provided for @carsMinPrice.
  ///
  /// In en, this message translates to:
  /// **'Min price'**
  String get carsMinPrice;

  /// No description provided for @carsMaxPrice.
  ///
  /// In en, this message translates to:
  /// **'Max price'**
  String get carsMaxPrice;

  /// No description provided for @carsSortRecent.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get carsSortRecent;

  /// No description provided for @carsSortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get carsSortOldest;

  /// No description provided for @carsSortPriceLow.
  ///
  /// In en, this message translates to:
  /// **'Lowest price'**
  String get carsSortPriceLow;

  /// No description provided for @carsSortPriceHigh.
  ///
  /// In en, this message translates to:
  /// **'Highest price'**
  String get carsSortPriceHigh;

  /// No description provided for @carsConditionNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get carsConditionNew;

  /// No description provided for @carsConditionUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get carsConditionUsed;

  /// No description provided for @carsBodyTypeSedan.
  ///
  /// In en, this message translates to:
  /// **'Sedan'**
  String get carsBodyTypeSedan;

  /// No description provided for @carsBodyTypeSuv.
  ///
  /// In en, this message translates to:
  /// **'SUV'**
  String get carsBodyTypeSuv;

  /// No description provided for @carsBodyTypeCrossover.
  ///
  /// In en, this message translates to:
  /// **'Crossover'**
  String get carsBodyTypeCrossover;

  /// No description provided for @carsBodyTypeHatchback.
  ///
  /// In en, this message translates to:
  /// **'Hatchback'**
  String get carsBodyTypeHatchback;

  /// No description provided for @carsBodyTypePickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get carsBodyTypePickup;

  /// No description provided for @carsBodyTypeVan.
  ///
  /// In en, this message translates to:
  /// **'Van'**
  String get carsBodyTypeVan;

  /// No description provided for @carsTransmission.
  ///
  /// In en, this message translates to:
  /// **'Transmission'**
  String get carsTransmission;

  /// No description provided for @carsTransmissionAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get carsTransmissionAutomatic;

  /// No description provided for @carsTransmissionManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get carsTransmissionManual;

  /// No description provided for @carsFuelType.
  ///
  /// In en, this message translates to:
  /// **'Fuel type'**
  String get carsFuelType;

  /// No description provided for @carsFuelTypeFuel.
  ///
  /// In en, this message translates to:
  /// **'Fuel'**
  String get carsFuelTypeFuel;

  /// No description provided for @carsFuelTypeHybrid.
  ///
  /// In en, this message translates to:
  /// **'Hybrid'**
  String get carsFuelTypeHybrid;

  /// No description provided for @carsFuelTypeElectric.
  ///
  /// In en, this message translates to:
  /// **'Electric'**
  String get carsFuelTypeElectric;

  /// No description provided for @carsMileage.
  ///
  /// In en, this message translates to:
  /// **'Mileage'**
  String get carsMileage;

  /// No description provided for @carsModelYear.
  ///
  /// In en, this message translates to:
  /// **'Model year'**
  String get carsModelYear;

  /// No description provided for @carsColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get carsColor;

  /// No description provided for @carsSellerUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown seller'**
  String get carsSellerUnknown;

  /// No description provided for @carsListingTitle.
  ///
  /// In en, this message translates to:
  /// **'Listing title'**
  String get carsListingTitle;

  /// No description provided for @carsDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get carsDescription;

  /// No description provided for @carsPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get carsPhone;

  /// No description provided for @carsBasicSection.
  ///
  /// In en, this message translates to:
  /// **'Listing overview'**
  String get carsBasicSection;

  /// No description provided for @carsPricingSection.
  ///
  /// In en, this message translates to:
  /// **'Price and condition'**
  String get carsPricingSection;

  /// No description provided for @carsSpecsSection.
  ///
  /// In en, this message translates to:
  /// **'Specifications'**
  String get carsSpecsSection;

  /// No description provided for @carsContactSection.
  ///
  /// In en, this message translates to:
  /// **'Contact and location'**
  String get carsContactSection;

  /// No description provided for @carsPhotosSection.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get carsPhotosSection;

  /// No description provided for @carsChoosePhotos.
  ///
  /// In en, this message translates to:
  /// **'Choose photos'**
  String get carsChoosePhotos;

  /// No description provided for @carsImageLimitHint.
  ///
  /// In en, this message translates to:
  /// **'You can add up to 6 photos.'**
  String get carsImageLimitHint;

  /// No description provided for @carsValidationTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a clear listing title.'**
  String get carsValidationTitleRequired;

  /// No description provided for @carsValidationBrandRequired.
  ///
  /// In en, this message translates to:
  /// **'Select the car brand.'**
  String get carsValidationBrandRequired;

  /// No description provided for @carsValidationModelRequired.
  ///
  /// In en, this message translates to:
  /// **'Select the car model.'**
  String get carsValidationModelRequired;

  /// No description provided for @carsValidationModelYearRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid model year.'**
  String get carsValidationModelYearRequired;

  /// No description provided for @carsValidationPriceRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the requested price.'**
  String get carsValidationPriceRequired;

  /// No description provided for @carsValidationPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a phone number for contact.'**
  String get carsValidationPhoneRequired;

  /// No description provided for @carsValidationMileageRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the mileage for a used car.'**
  String get carsValidationMileageRequired;

  /// No description provided for @carsValidationImagesRequired.
  ///
  /// In en, this message translates to:
  /// **'Select at least one photo.'**
  String get carsValidationImagesRequired;

  /// No description provided for @carsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save the car listing.'**
  String get carsSaveFailed;

  /// No description provided for @carsStatusUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update the car listing status.'**
  String get carsStatusUpdateFailed;

  /// No description provided for @carsDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Car Details'**
  String get carsDetailsTitle;

  /// No description provided for @carsCallSeller.
  ///
  /// In en, this message translates to:
  /// **'Call seller'**
  String get carsCallSeller;

  /// No description provided for @carsCallFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the dialer.'**
  String get carsCallFailed;

  /// No description provided for @carsStartChatFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to start a chat with the seller.'**
  String get carsStartChatFailed;

  /// No description provided for @carsShareText.
  ///
  /// In en, this message translates to:
  /// **'Check this car on Maslaki: {title}'**
  String carsShareText(String title);

  /// No description provided for @carsSimilarListings.
  ///
  /// In en, this message translates to:
  /// **'Similar cars'**
  String get carsSimilarListings;

  /// No description provided for @carsStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get carsStatusActive;

  /// No description provided for @carsStatusSold.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get carsStatusSold;

  /// No description provided for @carsStatusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get carsStatusArchived;

  /// No description provided for @carsStatusHiddenByExpiry.
  ///
  /// In en, this message translates to:
  /// **'Hidden by subscription expiry'**
  String get carsStatusHiddenByExpiry;

  /// No description provided for @storePortalWindowTitle.
  ///
  /// In en, this message translates to:
  /// **'Store Portal'**
  String get storePortalWindowTitle;

  /// No description provided for @companyPortalWindowTitle.
  ///
  /// In en, this message translates to:
  /// **'Company Portal'**
  String get companyPortalWindowTitle;

  /// No description provided for @customerHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer Home'**
  String get customerHomeTitle;

  /// No description provided for @adminBackofficeMerchantsTitle.
  ///
  /// In en, this message translates to:
  /// **'Backoffice Merchants'**
  String get adminBackofficeMerchantsTitle;

  /// No description provided for @ownerDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Store Owner Dashboard'**
  String get ownerDashboardTitle;

  /// No description provided for @deliveryDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery Dashboard'**
  String get deliveryDashboardTitle;

  /// No description provided for @deliveryCurrentOrders.
  ///
  /// In en, this message translates to:
  /// **'Current orders'**
  String get deliveryCurrentOrders;

  /// No description provided for @deliveryOrderHistory.
  ///
  /// In en, this message translates to:
  /// **'Order history'**
  String get deliveryOrderHistory;

  /// No description provided for @deliveryCourierCompetitions.
  ///
  /// In en, this message translates to:
  /// **'Courier competitions'**
  String get deliveryCourierCompetitions;

  /// No description provided for @deliveryCourierCompetitionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View competitions and current progress'**
  String get deliveryCourierCompetitionsSubtitle;

  /// No description provided for @deliveryEndDay.
  ///
  /// In en, this message translates to:
  /// **'End day'**
  String get deliveryEndDay;

  /// No description provided for @deliveryFilterByDate.
  ///
  /// In en, this message translates to:
  /// **'Filter by date'**
  String get deliveryFilterByDate;

  /// No description provided for @deliveryOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'On the way'**
  String get deliveryOnTheWay;

  /// No description provided for @deliveryWaitingPickup.
  ///
  /// In en, this message translates to:
  /// **'Waiting pickup'**
  String get deliveryWaitingPickup;

  /// No description provided for @deliveryCompletedToday.
  ///
  /// In en, this message translates to:
  /// **'Completed today'**
  String get deliveryCompletedToday;

  /// No description provided for @deliveryFeesToday.
  ///
  /// In en, this message translates to:
  /// **'Delivery fees today'**
  String get deliveryFeesToday;

  /// No description provided for @deliveryRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get deliveryRating;

  /// No description provided for @deliveryQuickAccess.
  ///
  /// In en, this message translates to:
  /// **'Quick access'**
  String get deliveryQuickAccess;

  /// No description provided for @deliveryOpenCurrentOrders.
  ///
  /// In en, this message translates to:
  /// **'Open current orders'**
  String get deliveryOpenCurrentOrders;

  /// No description provided for @deliveryOpenOrderHistory.
  ///
  /// In en, this message translates to:
  /// **'Open order history'**
  String get deliveryOpenOrderHistory;

  /// No description provided for @deliveryOpenCompetitions.
  ///
  /// In en, this message translates to:
  /// **'Open courier competitions'**
  String get deliveryOpenCompetitions;

  /// No description provided for @deliveryNoCurrentOrders.
  ///
  /// In en, this message translates to:
  /// **'No current orders.'**
  String get deliveryNoCurrentOrders;

  /// No description provided for @deliveryHistoryFilter.
  ///
  /// In en, this message translates to:
  /// **'History filter'**
  String get deliveryHistoryFilter;

  /// No description provided for @deliveryAllDays.
  ///
  /// In en, this message translates to:
  /// **'All days'**
  String get deliveryAllDays;

  /// No description provided for @deliveryChooseDay.
  ///
  /// In en, this message translates to:
  /// **'Choose day'**
  String get deliveryChooseDay;

  /// No description provided for @deliveryArchivedOrders.
  ///
  /// In en, this message translates to:
  /// **'Archived orders'**
  String get deliveryArchivedOrders;

  /// No description provided for @deliveryNoArchivedOrders.
  ///
  /// In en, this message translates to:
  /// **'No archived orders.'**
  String get deliveryNoArchivedOrders;

  /// No description provided for @deliveryProfileAddress.
  ///
  /// In en, this message translates to:
  /// **'Address: Block {block} - Building {building} - Apartment {apartment}'**
  String deliveryProfileAddress(
    String block,
    String building,
    String apartment,
  );

  /// No description provided for @deliveryProfileCompletedToday.
  ///
  /// In en, this message translates to:
  /// **'Completed orders today: {count}'**
  String deliveryProfileCompletedToday(String count);

  /// No description provided for @deliveryProfileFeesToday.
  ///
  /// In en, this message translates to:
  /// **'Today fees: {fees}'**
  String deliveryProfileFeesToday(String fees);

  /// No description provided for @deliveryProfileRatingToday.
  ///
  /// In en, this message translates to:
  /// **'Today rating: {rating}'**
  String deliveryProfileRatingToday(String rating);

  /// No description provided for @deliveryAccountManagement.
  ///
  /// In en, this message translates to:
  /// **'Account management'**
  String get deliveryAccountManagement;

  /// No description provided for @deliveryEditPhoneAndPin.
  ///
  /// In en, this message translates to:
  /// **'Edit phone number and PIN'**
  String get deliveryEditPhoneAndPin;

  /// No description provided for @deliverySupportAndHelp.
  ///
  /// In en, this message translates to:
  /// **'Support and help'**
  String get deliverySupportAndHelp;

  /// No description provided for @deliveryCourierAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Courier analytics'**
  String get deliveryCourierAnalytics;

  /// No description provided for @commonToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get commonToday;

  /// No description provided for @commonMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get commonMonth;

  /// No description provided for @commonYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get commonYear;

  /// No description provided for @deliveryInsightCompletedOrders.
  ///
  /// In en, this message translates to:
  /// **'{label}: {count} completed orders'**
  String deliveryInsightCompletedOrders(String label, String count);

  /// No description provided for @deliveryInsightFeesRating.
  ///
  /// In en, this message translates to:
  /// **'Delivery fees: {fees} | Rating: {rating}'**
  String deliveryInsightFeesRating(String fees, String rating);

  /// No description provided for @drawerWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get drawerWorkspace;

  /// No description provided for @drawerHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get drawerHome;

  /// No description provided for @drawerRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get drawerRefresh;

  /// No description provided for @drawerCart.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get drawerCart;

  /// No description provided for @drawerAddresses.
  ///
  /// In en, this message translates to:
  /// **'Addresses'**
  String get drawerAddresses;

  /// No description provided for @drawerCreateMerchant.
  ///
  /// In en, this message translates to:
  /// **'Create store'**
  String get drawerCreateMerchant;

  /// No description provided for @drawerAddProduct.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get drawerAddProduct;

  /// No description provided for @drawerMerchantsSub.
  ///
  /// In en, this message translates to:
  /// **'Merchant tools'**
  String get drawerMerchantsSub;

  /// No description provided for @drawerOwnerSub.
  ///
  /// In en, this message translates to:
  /// **'Owner tools'**
  String get drawerOwnerSub;

  /// No description provided for @drawerOwnerPendingSub.
  ///
  /// In en, this message translates to:
  /// **'Pending owner request'**
  String get drawerOwnerPendingSub;

  /// No description provided for @drawerOwnerPendingStatus.
  ///
  /// In en, this message translates to:
  /// **'Awaiting approval'**
  String get drawerOwnerPendingStatus;

  /// No description provided for @drawerDeliverySub.
  ///
  /// In en, this message translates to:
  /// **'Delivery tools'**
  String get drawerDeliverySub;

  /// No description provided for @ownerApprovalPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Your owner account is pending approval'**
  String get ownerApprovalPendingTitle;

  /// No description provided for @authLogin.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get authLogin;

  /// No description provided for @authCreateUserAccount.
  ///
  /// In en, this message translates to:
  /// **'Create user account'**
  String get authCreateUserAccount;

  /// No description provided for @authCreateOwnerAccount.
  ///
  /// In en, this message translates to:
  /// **'Create store account'**
  String get authCreateOwnerAccount;

  /// No description provided for @authPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get authPhoneLabel;

  /// No description provided for @authPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get authPinLabel;

  /// No description provided for @authLoginTagline.
  ///
  /// In en, this message translates to:
  /// **'Sign in to access orders, community, and local services.'**
  String get authLoginTagline;

  /// No description provided for @settingsCurrentPin.
  ///
  /// In en, this message translates to:
  /// **'Current PIN'**
  String get settingsCurrentPin;

  /// No description provided for @settingsNewPhone.
  ///
  /// In en, this message translates to:
  /// **'New phone number'**
  String get settingsNewPhone;

  /// No description provided for @settingsNewPin.
  ///
  /// In en, this message translates to:
  /// **'New PIN'**
  String get settingsNewPin;

  /// No description provided for @settingsConfirmNewPin.
  ///
  /// In en, this message translates to:
  /// **'Confirm new PIN'**
  String get settingsConfirmNewPin;

  /// No description provided for @settingsChangePhone.
  ///
  /// In en, this message translates to:
  /// **'Change phone'**
  String get settingsChangePhone;

  /// No description provided for @settingsChangePin.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get settingsChangePin;

  /// No description provided for @settingsSavePhone.
  ///
  /// In en, this message translates to:
  /// **'Save phone'**
  String get settingsSavePhone;

  /// No description provided for @settingsSavePin.
  ///
  /// In en, this message translates to:
  /// **'Save PIN'**
  String get settingsSavePin;

  /// No description provided for @settingsPhoneUpdated.
  ///
  /// In en, this message translates to:
  /// **'Phone number updated successfully.'**
  String get settingsPhoneUpdated;

  /// No description provided for @settingsPinUpdated.
  ///
  /// In en, this message translates to:
  /// **'PIN updated successfully.'**
  String get settingsPinUpdated;

  /// No description provided for @settingsEnterCurrentPin.
  ///
  /// In en, this message translates to:
  /// **'Enter your current PIN.'**
  String get settingsEnterCurrentPin;

  /// No description provided for @settingsEnterPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number.'**
  String get settingsEnterPhone;

  /// No description provided for @settingsPinMinDigits.
  ///
  /// In en, this message translates to:
  /// **'PIN must be at least 4 digits.'**
  String get settingsPinMinDigits;

  /// No description provided for @settingsPinMismatch.
  ///
  /// In en, this message translates to:
  /// **'The new PIN confirmation does not match.'**
  String get settingsPinMismatch;

  /// No description provided for @notificationsGenericTitle.
  ///
  /// In en, this message translates to:
  /// **'New notification'**
  String get notificationsGenericTitle;

  /// No description provided for @notificationsGenericBody.
  ///
  /// In en, this message translates to:
  /// **'You have a new update in Maslaki.'**
  String get notificationsGenericBody;

  /// No description provided for @notificationsOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get notificationsOrders;

  /// No description provided for @notificationsMobility.
  ///
  /// In en, this message translates to:
  /// **'Mobility'**
  String get notificationsMobility;

  /// No description provided for @notificationsJobs.
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get notificationsJobs;

  /// No description provided for @notificationsPosts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get notificationsPosts;

  /// No description provided for @notificationsReels.
  ///
  /// In en, this message translates to:
  /// **'Reels'**
  String get notificationsReels;

  /// No description provided for @notificationsLikes.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get notificationsLikes;

  /// No description provided for @notificationsComments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get notificationsComments;

  /// No description provided for @notificationsStories.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get notificationsStories;

  /// No description provided for @notificationsRelations.
  ///
  /// In en, this message translates to:
  /// **'Relations'**
  String get notificationsRelations;

  /// No description provided for @notificationsMentions.
  ///
  /// In en, this message translates to:
  /// **'Mentions'**
  String get notificationsMentions;

  /// No description provided for @notificationsOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Order update'**
  String get notificationsOrdersTitle;

  /// No description provided for @notificationsOrdersBody.
  ///
  /// In en, this message translates to:
  /// **'There is a new update on your order.'**
  String get notificationsOrdersBody;

  /// No description provided for @notificationsDeliveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery update'**
  String get notificationsDeliveryTitle;

  /// No description provided for @notificationsDeliveryBody.
  ///
  /// In en, this message translates to:
  /// **'A delivery request or courier status has changed.'**
  String get notificationsDeliveryBody;

  /// No description provided for @notificationsTaxiTitle.
  ///
  /// In en, this message translates to:
  /// **'Taxi update'**
  String get notificationsTaxiTitle;

  /// No description provided for @notificationsTaxiBody.
  ///
  /// In en, this message translates to:
  /// **'Your ride status has been updated.'**
  String get notificationsTaxiBody;

  /// No description provided for @notificationsJobsTitle.
  ///
  /// In en, this message translates to:
  /// **'Job update'**
  String get notificationsJobsTitle;

  /// No description provided for @notificationsJobsBody.
  ///
  /// In en, this message translates to:
  /// **'There is a new update related to jobs or applications.'**
  String get notificationsJobsBody;

  /// No description provided for @notificationsRealEstateTitle.
  ///
  /// In en, this message translates to:
  /// **'Real estate update'**
  String get notificationsRealEstateTitle;

  /// No description provided for @notificationsRealEstateBody.
  ///
  /// In en, this message translates to:
  /// **'A real estate listing or seller activity has been updated.'**
  String get notificationsRealEstateBody;

  /// No description provided for @notificationsPaidUpgradesTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan update'**
  String get notificationsPaidUpgradesTitle;

  /// No description provided for @notificationsPaidUpgradesBody.
  ///
  /// In en, this message translates to:
  /// **'There is a new update about your paid plan or upgrade.'**
  String get notificationsPaidUpgradesBody;

  /// No description provided for @notificationsCompanyTitle.
  ///
  /// In en, this message translates to:
  /// **'Company update'**
  String get notificationsCompanyTitle;

  /// No description provided for @notificationsCompanyBody.
  ///
  /// In en, this message translates to:
  /// **'There is a new update related to your company workspace.'**
  String get notificationsCompanyBody;

  /// No description provided for @notificationsAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin update'**
  String get notificationsAdminTitle;

  /// No description provided for @notificationsAdminBody.
  ///
  /// In en, this message translates to:
  /// **'There is a new administrative review or action.'**
  String get notificationsAdminBody;

  /// No description provided for @notificationsHrTitle.
  ///
  /// In en, this message translates to:
  /// **'HR update'**
  String get notificationsHrTitle;

  /// No description provided for @notificationsHrBody.
  ///
  /// In en, this message translates to:
  /// **'There is a new update related to attendance, payroll, or requests.'**
  String get notificationsHrBody;

  /// No description provided for @notificationsProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Account update'**
  String get notificationsProfileTitle;

  /// No description provided for @notificationsProfileBody.
  ///
  /// In en, this message translates to:
  /// **'There is a new update related to your profile data.'**
  String get notificationsProfileBody;

  /// No description provided for @notificationsSocialActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Social update'**
  String get notificationsSocialActivityTitle;

  /// No description provided for @notificationsSocialActivityBody.
  ///
  /// In en, this message translates to:
  /// **'There is new social activity on your account.'**
  String get notificationsSocialActivityBody;

  /// No description provided for @notificationsSocialPostLikeTitle.
  ///
  /// In en, this message translates to:
  /// **'New post like'**
  String get notificationsSocialPostLikeTitle;

  /// No description provided for @notificationsSocialPostLikeBody.
  ///
  /// In en, this message translates to:
  /// **'Someone liked your post.'**
  String get notificationsSocialPostLikeBody;

  /// No description provided for @notificationsSocialReelLikeTitle.
  ///
  /// In en, this message translates to:
  /// **'New reel like'**
  String get notificationsSocialReelLikeTitle;

  /// No description provided for @notificationsSocialReelLikeBody.
  ///
  /// In en, this message translates to:
  /// **'Someone liked your reel.'**
  String get notificationsSocialReelLikeBody;

  /// No description provided for @notificationsSocialCommentTitle.
  ///
  /// In en, this message translates to:
  /// **'New comment'**
  String get notificationsSocialCommentTitle;

  /// No description provided for @notificationsSocialCommentBody.
  ///
  /// In en, this message translates to:
  /// **'Someone commented on your content.'**
  String get notificationsSocialCommentBody;

  /// No description provided for @notificationsSocialMentionTitle.
  ///
  /// In en, this message translates to:
  /// **'You were mentioned'**
  String get notificationsSocialMentionTitle;

  /// No description provided for @notificationsSocialMentionBody.
  ///
  /// In en, this message translates to:
  /// **'Someone mentioned you in a post or comment.'**
  String get notificationsSocialMentionBody;

  /// No description provided for @notificationsSocialRelationTitle.
  ///
  /// In en, this message translates to:
  /// **'New social update'**
  String get notificationsSocialRelationTitle;

  /// No description provided for @notificationsSocialRelationBody.
  ///
  /// In en, this message translates to:
  /// **'There is a new update about your social connections.'**
  String get notificationsSocialRelationBody;

  /// No description provided for @notificationsSocialStoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Story update'**
  String get notificationsSocialStoryTitle;

  /// No description provided for @notificationsSocialStoryBody.
  ///
  /// In en, this message translates to:
  /// **'{senderName} added a new story update.'**
  String notificationsSocialStoryBody(String senderName);

  /// No description provided for @notificationsSocialReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report update'**
  String get notificationsSocialReportTitle;

  /// No description provided for @notificationsSocialReportBody.
  ///
  /// In en, this message translates to:
  /// **'There is a new update related to a report or moderation review.'**
  String get notificationsSocialReportBody;

  /// No description provided for @notificationsSocialCommunityTitle.
  ///
  /// In en, this message translates to:
  /// **'Community update'**
  String get notificationsSocialCommunityTitle;

  /// No description provided for @notificationsSocialCommunityBody.
  ///
  /// In en, this message translates to:
  /// **'There is a new update inside your community.'**
  String get notificationsSocialCommunityBody;

  /// No description provided for @notificationsSocialCallTitle.
  ///
  /// In en, this message translates to:
  /// **'Incoming social call'**
  String get notificationsSocialCallTitle;

  /// No description provided for @notificationsSocialCallBody.
  ///
  /// In en, this message translates to:
  /// **'{senderName} is trying to call you.'**
  String notificationsSocialCallBody(String senderName);

  /// No description provided for @notificationsChatMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get notificationsChatMessageTitle;

  /// No description provided for @notificationsChatMessageBody.
  ///
  /// In en, this message translates to:
  /// **'{senderName} sent you a message.'**
  String notificationsChatMessageBody(String senderName);

  /// No description provided for @apiCategoryRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select a category.'**
  String get apiCategoryRequired;

  /// No description provided for @apiCategoryInvalid.
  ///
  /// In en, this message translates to:
  /// **'The selected category is invalid.'**
  String get apiCategoryInvalid;

  /// No description provided for @apiCategoryNotFound.
  ///
  /// In en, this message translates to:
  /// **'The selected category was not found.'**
  String get apiCategoryNotFound;

  /// No description provided for @apiCategoryHasProducts.
  ///
  /// In en, this message translates to:
  /// **'This category cannot be deleted because it still contains products.'**
  String get apiCategoryHasProducts;

  /// No description provided for @apiOrderItemNotFound.
  ///
  /// In en, this message translates to:
  /// **'The requested order item was not found.'**
  String get apiOrderItemNotFound;

  /// No description provided for @apiProductUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This product is currently unavailable.'**
  String get apiProductUnavailable;

  /// No description provided for @apiForbiddenOwnerOnly.
  ///
  /// In en, this message translates to:
  /// **'This action is available to store owners only.'**
  String get apiForbiddenOwnerOnly;

  /// No description provided for @apiForbiddenDeliveryOnly.
  ///
  /// In en, this message translates to:
  /// **'This action is available to delivery captains only.'**
  String get apiForbiddenDeliveryOnly;

  /// No description provided for @apiOrderNotFound.
  ///
  /// In en, this message translates to:
  /// **'The order was not found.'**
  String get apiOrderNotFound;

  /// No description provided for @apiNoOpenReceivableInvoices.
  ///
  /// In en, this message translates to:
  /// **'There are no open receivable invoices for this request.'**
  String get apiNoOpenReceivableInvoices;

  /// No description provided for @apiInvalidSelectedReceivableInvoices.
  ///
  /// In en, this message translates to:
  /// **'The selected receivable invoices are invalid.'**
  String get apiInvalidSelectedReceivableInvoices;

  /// No description provided for @apiPaymentRequestAmountConfirmationRequired.
  ///
  /// In en, this message translates to:
  /// **'Please confirm the payment request amount before continuing.'**
  String get apiPaymentRequestAmountConfirmationRequired;

  /// No description provided for @apiPaymentRequestSelectionOutdated.
  ///
  /// In en, this message translates to:
  /// **'The selected invoices have changed. Review the request and try again.'**
  String get apiPaymentRequestSelectionOutdated;

  /// No description provided for @apiPaymentRequestSelectionAmountChanged.
  ///
  /// In en, this message translates to:
  /// **'The selected amount has changed. Please review it before continuing.'**
  String get apiPaymentRequestSelectionAmountChanged;

  /// No description provided for @apiOrderPreparingNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This order cannot be moved to preparing right now.'**
  String get apiOrderPreparingNotAllowed;

  /// No description provided for @apiOrderAssignmentNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This order cannot be assigned right now.'**
  String get apiOrderAssignmentNotAllowed;

  /// No description provided for @apiOrderReadyNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This order cannot be marked ready right now.'**
  String get apiOrderReadyNotAllowed;

  /// No description provided for @apiCourierNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'No courier is available for this request right now.'**
  String get apiCourierNotAvailable;

  /// No description provided for @apiCourierNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'The selected courier is not allowed for this request.'**
  String get apiCourierNotAllowed;

  /// No description provided for @apiStoreDriverMerchantRequired.
  ///
  /// In en, this message translates to:
  /// **'A merchant must be selected for store driver requests.'**
  String get apiStoreDriverMerchantRequired;

  /// No description provided for @apiDeliveryDriverTypeChangeBlockedByActiveOrders.
  ///
  /// In en, this message translates to:
  /// **'Driver type cannot be changed while there are active orders.'**
  String get apiDeliveryDriverTypeChangeBlockedByActiveOrders;

  /// No description provided for @apiOrderAlreadyAssigned.
  ///
  /// In en, this message translates to:
  /// **'This order has already been assigned.'**
  String get apiOrderAlreadyAssigned;

  /// No description provided for @apiAssignmentNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This assignment is no longer available.'**
  String get apiAssignmentNotAvailable;

  /// No description provided for @apiAnalyticsConsentRequired.
  ///
  /// In en, this message translates to:
  /// **'Analytics consent is required before enabling this option.'**
  String get apiAnalyticsConsentRequired;

  /// No description provided for @apiDeliveryAccountPendingApproval.
  ///
  /// In en, this message translates to:
  /// **'Your delivery account is pending approval.'**
  String get apiDeliveryAccountPendingApproval;

  /// No description provided for @apiDeliverySubscriptionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your delivery subscription has expired.'**
  String get apiDeliverySubscriptionExpired;

  /// No description provided for @apiDeliverySubscriptionPaymentPending.
  ///
  /// In en, this message translates to:
  /// **'Your delivery subscription payment is still pending.'**
  String get apiDeliverySubscriptionPaymentPending;

  /// No description provided for @apiProfileCoreEditLocked.
  ///
  /// In en, this message translates to:
  /// **'Core profile data cannot be changed right now.'**
  String get apiProfileCoreEditLocked;

  /// No description provided for @apiTaxiActiveRideExists.
  ///
  /// In en, this message translates to:
  /// **'You already have an active ride.'**
  String get apiTaxiActiveRideExists;

  /// No description provided for @apiTaxiRideNotAcceptingBids.
  ///
  /// In en, this message translates to:
  /// **'This ride is no longer accepting bids.'**
  String get apiTaxiRideNotAcceptingBids;

  /// No description provided for @apiTaxiRideOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'This ride is outside the allowed range.'**
  String get apiTaxiRideOutOfRange;

  /// No description provided for @apiTaxiNoActiveBid.
  ///
  /// In en, this message translates to:
  /// **'No active bid was found for this ride.'**
  String get apiTaxiNoActiveBid;

  /// No description provided for @apiTaxiChatEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Please enter a message before sending.'**
  String get apiTaxiChatEmptyMessage;

  /// No description provided for @apiTaxiChatClosed.
  ///
  /// In en, this message translates to:
  /// **'This ride chat is closed.'**
  String get apiTaxiChatClosed;

  /// No description provided for @apiTaxiCallPeerNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'The other participant is not available for calls right now.'**
  String get apiTaxiCallPeerNotAvailable;

  /// No description provided for @apiTaxiCallSessionNotFound.
  ///
  /// In en, this message translates to:
  /// **'The call session was not found.'**
  String get apiTaxiCallSessionNotFound;

  /// No description provided for @apiTaxiRideNotCompleted.
  ///
  /// In en, this message translates to:
  /// **'This ride has not been completed yet.'**
  String get apiTaxiRideNotCompleted;

  /// No description provided for @apiTaxiRideCaptainNotFound.
  ///
  /// In en, this message translates to:
  /// **'The captain for this ride was not found.'**
  String get apiTaxiRideCaptainNotFound;

  /// No description provided for @validationAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount.'**
  String get validationAmountInvalid;

  /// No description provided for @validationPaymentDateInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid payment date.'**
  String get validationPaymentDateInvalid;

  /// No description provided for @validationPaymentAtInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid payment timestamp.'**
  String get validationPaymentAtInvalid;

  /// No description provided for @validationPaymentMethodInvalid.
  ///
  /// In en, this message translates to:
  /// **'Select a valid payment method.'**
  String get validationPaymentMethodInvalid;

  /// No description provided for @validationPaymentMethodOtherRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the custom payment method.'**
  String get validationPaymentMethodOtherRequired;

  /// No description provided for @validationSelectionModeRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a valid selection mode.'**
  String get validationSelectionModeRequired;

  /// No description provided for @validationSelectedInvoiceIdsRequired.
  ///
  /// In en, this message translates to:
  /// **'Select at least one invoice.'**
  String get validationSelectedInvoiceIdsRequired;

  /// No description provided for @validationTargetAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid target amount.'**
  String get validationTargetAmountInvalid;

  /// No description provided for @validationReferenceCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid reference code.'**
  String get validationReferenceCodeInvalid;

  /// No description provided for @validationReceiverNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter the receiver name.'**
  String get validationReceiverNameInvalid;

  /// No description provided for @validationRequestTypeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Select a valid request type.'**
  String get validationRequestTypeInvalid;

  /// No description provided for @validationPaymentScopeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Select a valid payment scope.'**
  String get validationPaymentScopeInvalid;

  /// No description provided for @validationDriverTypeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Select a valid driver type.'**
  String get validationDriverTypeInvalid;

  /// No description provided for @validationMerchantRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a merchant first.'**
  String get validationMerchantRequired;

  /// No description provided for @validationCouponActiveFlagRequired.
  ///
  /// In en, this message translates to:
  /// **'Specify whether the coupon is active.'**
  String get validationCouponActiveFlagRequired;

  /// No description provided for @validationReviewField.
  ///
  /// In en, this message translates to:
  /// **'Please review the field: {field}'**
  String validationReviewField(String field);

  /// No description provided for @authOwnerOnlyAppError.
  ///
  /// In en, this message translates to:
  /// **'Store app accepts owner accounts only.'**
  String get authOwnerOnlyAppError;

  /// No description provided for @authUserOnlyAppError.
  ///
  /// In en, this message translates to:
  /// **'This app is for customer accounts only.'**
  String get authUserOnlyAppError;

  /// No description provided for @authDeliveryOnlyAppError.
  ///
  /// In en, this message translates to:
  /// **'Delivery app accepts delivery accounts only.'**
  String get authDeliveryOnlyAppError;

  /// No description provided for @authTaxiCaptainOnlyAppError.
  ///
  /// In en, this message translates to:
  /// **'Captain app accepts taxi captain accounts only.'**
  String get authTaxiCaptainOnlyAppError;

  /// No description provided for @authTaxiCaptainAccount.
  ///
  /// In en, this message translates to:
  /// **'Create taxi captain account'**
  String get authTaxiCaptainAccount;

  /// No description provided for @authPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number.'**
  String get authPhoneRequired;

  /// No description provided for @authPhoneIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Phone number is incomplete.'**
  String get authPhoneIncomplete;

  /// No description provided for @authPinRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN.'**
  String get authPinRequired;

  /// No description provided for @authPinInvalidFormat.
  ///
  /// In en, this message translates to:
  /// **'PIN must be 4 to 8 digits.'**
  String get authPinInvalidFormat;

  /// No description provided for @authDesktopTitle.
  ///
  /// In en, this message translates to:
  /// **'Maslaki on desktop'**
  String get authDesktopTitle;

  /// No description provided for @authDesktopFeatureNavigationTitle.
  ///
  /// In en, this message translates to:
  /// **'Faster navigation'**
  String get authDesktopFeatureNavigationTitle;

  /// No description provided for @authDesktopFeatureNavigationBody.
  ///
  /// In en, this message translates to:
  /// **'A persistent sidebar and clearer shortcuts for larger screens.'**
  String get authDesktopFeatureNavigationBody;

  /// No description provided for @authDesktopFeatureControlsTitle.
  ///
  /// In en, this message translates to:
  /// **'More controls'**
  String get authDesktopFeatureControlsTitle;

  /// No description provided for @authDesktopFeatureControlsBody.
  ///
  /// In en, this message translates to:
  /// **'Reach important sections directly without returning to hidden menus.'**
  String get authDesktopFeatureControlsBody;

  /// No description provided for @authDesktopFeatureWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Full workspace experience'**
  String get authDesktopFeatureWorkspaceTitle;

  /// No description provided for @authDesktopFeatureWorkspaceBody.
  ///
  /// In en, this message translates to:
  /// **'A wider layout designed for large windows and day-to-day office work.'**
  String get authDesktopFeatureWorkspaceBody;

  /// No description provided for @authDesktopChipCommunity.
  ///
  /// In en, this message translates to:
  /// **'Local community'**
  String get authDesktopChipCommunity;

  /// No description provided for @authDesktopChipOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders and stores'**
  String get authDesktopChipOrders;

  /// No description provided for @authDesktopChipTaxi.
  ///
  /// In en, this message translates to:
  /// **'Taxi and chats'**
  String get authDesktopChipTaxi;

  /// No description provided for @commonNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get commonNotSet;

  /// No description provided for @companyRoleOwner.
  ///
  /// In en, this message translates to:
  /// **'Company owner'**
  String get companyRoleOwner;

  /// No description provided for @companyRoleManager.
  ///
  /// In en, this message translates to:
  /// **'Company manager'**
  String get companyRoleManager;

  /// No description provided for @companyRoleFinanceViewer.
  ///
  /// In en, this message translates to:
  /// **'Finance viewer'**
  String get companyRoleFinanceViewer;

  /// No description provided for @companyRoleOperationsViewer.
  ///
  /// In en, this message translates to:
  /// **'Operations viewer'**
  String get companyRoleOperationsViewer;

  /// No description provided for @companyStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get companyStatusActive;

  /// No description provided for @companyStatusInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get companyStatusInactive;

  /// No description provided for @companyStatusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get companyStatusSuspended;

  /// No description provided for @companyStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get companyStatusPending;

  /// No description provided for @companyStatusPendingAdminReview.
  ///
  /// In en, this message translates to:
  /// **'Pending admin review'**
  String get companyStatusPendingAdminReview;

  /// No description provided for @companyStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get companyStatusApproved;

  /// No description provided for @companyStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get companyStatusRejected;

  /// No description provided for @companyBranchTypeRestaurant.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get companyBranchTypeRestaurant;

  /// No description provided for @companyBranchTypeMarket.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get companyBranchTypeMarket;

  /// No description provided for @companyInventoryModeStrictDaily.
  ///
  /// In en, this message translates to:
  /// **'Strict daily'**
  String get companyInventoryModeStrictDaily;

  /// No description provided for @companyInventoryModeSoftReminder.
  ///
  /// In en, this message translates to:
  /// **'Soft reminder'**
  String get companyInventoryModeSoftReminder;

  /// No description provided for @companyInventoryModeManualOverride.
  ///
  /// In en, this message translates to:
  /// **'Manual override'**
  String get companyInventoryModeManualOverride;

  /// No description provided for @companyStockOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get companyStockOutOfStock;

  /// No description provided for @companyStockLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get companyStockLowStock;

  /// No description provided for @companyStockManualDisabled.
  ///
  /// In en, this message translates to:
  /// **'Manually disabled'**
  String get companyStockManualDisabled;

  /// No description provided for @companyStockAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get companyStockAvailable;

  /// No description provided for @companyPortalTitle.
  ///
  /// In en, this message translates to:
  /// **'Company portal'**
  String get companyPortalTitle;

  /// No description provided for @companyPortalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{companyName} • {role}'**
  String companyPortalSubtitle(String companyName, String role);

  /// No description provided for @companyNavDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get companyNavDashboard;

  /// No description provided for @companyNavBranches.
  ///
  /// In en, this message translates to:
  /// **'Branches'**
  String get companyNavBranches;

  /// No description provided for @companyNavReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get companyNavReports;

  /// No description provided for @companyNavPromotions.
  ///
  /// In en, this message translates to:
  /// **'Promotions'**
  String get companyNavPromotions;

  /// No description provided for @companyNavInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get companyNavInventory;

  /// No description provided for @companyNavUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get companyNavUsers;

  /// No description provided for @companyNavSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get companyNavSettings;

  /// No description provided for @companySwitchCompany.
  ///
  /// In en, this message translates to:
  /// **'Switch company'**
  String get companySwitchCompany;

  /// No description provided for @companyPortalWorkspaceDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage branches, inventory, promotions, reports, and access from one workspace.'**
  String get companyPortalWorkspaceDescription;

  /// No description provided for @companyActiveCompanyLabel.
  ///
  /// In en, this message translates to:
  /// **'Active company'**
  String get companyActiveCompanyLabel;

  /// No description provided for @companyPortalTeamAccess.
  ///
  /// In en, this message translates to:
  /// **'Team access'**
  String get companyPortalTeamAccess;

  /// No description provided for @companyPortalSettings.
  ///
  /// In en, this message translates to:
  /// **'Company settings'**
  String get companyPortalSettings;

  /// No description provided for @companyPortalUserFallback.
  ///
  /// In en, this message translates to:
  /// **'Company user'**
  String get companyPortalUserFallback;

  /// No description provided for @companyLoginIntro.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your company account to manage branches, reports, inventory, and promotions.'**
  String get companyLoginIntro;

  /// No description provided for @companyLoginSubmit.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Company Portal'**
  String get companyLoginSubmit;

  /// No description provided for @companyLoginSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in...'**
  String get companyLoginSigningIn;

  /// No description provided for @companyLoginAccessHint.
  ///
  /// In en, this message translates to:
  /// **'Access is limited to approved company accounts. Contact the admin if you need access.'**
  String get companyLoginAccessHint;

  /// No description provided for @companyDashboardLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load dashboard'**
  String get companyDashboardLoadFailed;

  /// No description provided for @companyDashboardEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No company data yet'**
  String get companyDashboardEmptyTitle;

  /// No description provided for @companyDashboardEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'No company profile is available for this account.'**
  String get companyDashboardEmptyDescription;

  /// No description provided for @companyDashboardWorkspaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A supervisory workspace for branches, performance, settlements, and inventory from one place.'**
  String get companyDashboardWorkspaceSubtitle;

  /// No description provided for @companyDashboardInventoryPolicy.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get companyDashboardInventoryPolicy;

  /// No description provided for @companyDashboardInventoryEnabled.
  ///
  /// In en, this message translates to:
  /// **'Policy Inventory Enabled'**
  String get companyDashboardInventoryEnabled;

  /// No description provided for @companyDashboardInventoryDisabled.
  ///
  /// In en, this message translates to:
  /// **'Policy Inventory Disabled'**
  String get companyDashboardInventoryDisabled;

  /// No description provided for @companyDashboardCompanyName.
  ///
  /// In en, this message translates to:
  /// **'Company name'**
  String get companyDashboardCompanyName;

  /// No description provided for @companyDashboardLegalName.
  ///
  /// In en, this message translates to:
  /// **'Legal name'**
  String get companyDashboardLegalName;

  /// No description provided for @companyDashboardPrimaryContact.
  ///
  /// In en, this message translates to:
  /// **'Primary contact'**
  String get companyDashboardPrimaryContact;

  /// No description provided for @companyDashboardContactPhone.
  ///
  /// In en, this message translates to:
  /// **'Contact phone'**
  String get companyDashboardContactPhone;

  /// No description provided for @companyDashboardSupportPhone.
  ///
  /// In en, this message translates to:
  /// **'Support phone'**
  String get companyDashboardSupportPhone;

  /// No description provided for @companyDashboardEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get companyDashboardEmail;

  /// No description provided for @companyDashboardHeadquarters.
  ///
  /// In en, this message translates to:
  /// **'Headquarters'**
  String get companyDashboardHeadquarters;

  /// No description provided for @companyDashboardRegistrationNumber.
  ///
  /// In en, this message translates to:
  /// **'Registration number'**
  String get companyDashboardRegistrationNumber;

  /// No description provided for @companyDashboardDefaultPolicy.
  ///
  /// In en, this message translates to:
  /// **'Default policy'**
  String get companyDashboardDefaultPolicy;

  /// No description provided for @companyDashboardNoDefaultPolicy.
  ///
  /// In en, this message translates to:
  /// **'No default policy configured yet.'**
  String get companyDashboardNoDefaultPolicy;

  /// No description provided for @companyDashboardPolicySummary.
  ///
  /// In en, this message translates to:
  /// **'Commission {commission} | Settlement {settlement}'**
  String companyDashboardPolicySummary(String commission, String settlement);

  /// No description provided for @companyDashboardSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get companyDashboardSummary;

  /// No description provided for @companyDashboardTotalOrders.
  ///
  /// In en, this message translates to:
  /// **'Total orders'**
  String get companyDashboardTotalOrders;

  /// No description provided for @companyDashboardActiveOrders.
  ///
  /// In en, this message translates to:
  /// **'Active orders'**
  String get companyDashboardActiveOrders;

  /// No description provided for @companyDashboardCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get companyDashboardCompleted;

  /// No description provided for @companyDashboardCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get companyDashboardCancelled;

  /// No description provided for @companyDashboardGrossSales.
  ///
  /// In en, this message translates to:
  /// **'Gross sales'**
  String get companyDashboardGrossSales;

  /// No description provided for @companyDashboardServiceFees.
  ///
  /// In en, this message translates to:
  /// **'Service fees'**
  String get companyDashboardServiceFees;

  /// No description provided for @companyDashboardOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get companyDashboardOutstanding;

  /// No description provided for @companyDashboardQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get companyDashboardQuickActions;

  /// No description provided for @companyDashboardQuickActionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Jump into the most used oversight areas for branches, inventory, promotions, and users.'**
  String get companyDashboardQuickActionsDescription;

  /// No description provided for @companyDashboardOpenBranches.
  ///
  /// In en, this message translates to:
  /// **'Open branches'**
  String get companyDashboardOpenBranches;

  /// No description provided for @companyDashboardInventoryOverview.
  ///
  /// In en, this message translates to:
  /// **'Inventory overview'**
  String get companyDashboardInventoryOverview;

  /// No description provided for @companyDashboardPromotions.
  ///
  /// In en, this message translates to:
  /// **'Promotions'**
  String get companyDashboardPromotions;

  /// No description provided for @companyDashboardUsers.
  ///
  /// In en, this message translates to:
  /// **'Company users'**
  String get companyDashboardUsers;

  /// No description provided for @companyDashboardTopBranch.
  ///
  /// In en, this message translates to:
  /// **'Top branch'**
  String get companyDashboardTopBranch;

  /// No description provided for @companyDashboardTopBranchDescription.
  ///
  /// In en, this message translates to:
  /// **'The branch with the strongest overall performance right now.'**
  String get companyDashboardTopBranchDescription;

  /// No description provided for @companyDashboardNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get companyDashboardNeedsAttention;

  /// No description provided for @companyDashboardNeedsAttentionDescription.
  ///
  /// In en, this message translates to:
  /// **'The branch that currently needs the most attention.'**
  String get companyDashboardNeedsAttentionDescription;

  /// No description provided for @companyDashboardNoBranchInsight.
  ///
  /// In en, this message translates to:
  /// **'No branch insight yet'**
  String get companyDashboardNoBranchInsight;

  /// No description provided for @companyDashboardNoBranchInsightDescription.
  ///
  /// In en, this message translates to:
  /// **'Branch comparisons will appear once branches start receiving activity.'**
  String get companyDashboardNoBranchInsightDescription;

  /// No description provided for @companyDashboardBranchFallback.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get companyDashboardBranchFallback;

  /// No description provided for @companyDashboardBranchOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders {count}'**
  String companyDashboardBranchOrders(String count);

  /// No description provided for @companySettingsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load company settings'**
  String get companySettingsLoadFailed;

  /// No description provided for @companySettingsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No company settings yet'**
  String get companySettingsEmptyTitle;

  /// No description provided for @companySettingsEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'No company settings profile is available for this account yet.'**
  String get companySettingsEmptyDescription;

  /// No description provided for @companySettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Company settings'**
  String get companySettingsTitle;

  /// No description provided for @companySettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage the default company policy and supervisory settings that can flow down to branches.'**
  String get companySettingsSubtitle;

  /// No description provided for @companySettingsEditPolicy.
  ///
  /// In en, this message translates to:
  /// **'Edit policy'**
  String get companySettingsEditPolicy;

  /// No description provided for @companySettingsEditPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit default company policy'**
  String get companySettingsEditPolicyTitle;

  /// No description provided for @companySettingsCommissionRate.
  ///
  /// In en, this message translates to:
  /// **'Commission rate'**
  String get companySettingsCommissionRate;

  /// No description provided for @companySettingsServiceFeeMode.
  ///
  /// In en, this message translates to:
  /// **'Service fee mode'**
  String get companySettingsServiceFeeMode;

  /// No description provided for @companySettingsServiceFeeFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount'**
  String get companySettingsServiceFeeFixed;

  /// No description provided for @companySettingsServiceFeePercent.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get companySettingsServiceFeePercent;

  /// No description provided for @companySettingsServiceFeeValue.
  ///
  /// In en, this message translates to:
  /// **'Service fee value'**
  String get companySettingsServiceFeeValue;

  /// No description provided for @companySettingsDeliveryFeeMode.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee mode'**
  String get companySettingsDeliveryFeeMode;

  /// No description provided for @companySettingsDeliveryFeeValue.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee value'**
  String get companySettingsDeliveryFeeValue;

  /// No description provided for @companySettingsSettlementCycle.
  ///
  /// In en, this message translates to:
  /// **'Settlement cycle'**
  String get companySettingsSettlementCycle;

  /// No description provided for @companySettingsSettlementDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get companySettingsSettlementDaily;

  /// No description provided for @companySettingsSettlementWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get companySettingsSettlementWeekly;

  /// No description provided for @companySettingsSettlementMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get companySettingsSettlementMonthly;

  /// No description provided for @companySettingsInventoryEnabledDefault.
  ///
  /// In en, this message translates to:
  /// **'Enable inventory by default for new branches'**
  String get companySettingsInventoryEnabledDefault;

  /// No description provided for @companySettingsInventoryUpdateMode.
  ///
  /// In en, this message translates to:
  /// **'Daily stock update mode'**
  String get companySettingsInventoryUpdateMode;

  /// No description provided for @companySettingsLowStockThreshold.
  ///
  /// In en, this message translates to:
  /// **'Low stock threshold'**
  String get companySettingsLowStockThreshold;

  /// No description provided for @companySettingsAutoDisableOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Auto disable out-of-stock items'**
  String get companySettingsAutoDisableOutOfStock;

  /// No description provided for @companySettingsShowAllWithoutAutoDisable.
  ///
  /// In en, this message translates to:
  /// **'Show all without auto disable'**
  String get companySettingsShowAllWithoutAutoDisable;

  /// No description provided for @companySettingsCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get companySettingsCode;

  /// No description provided for @companySettingsMyRole.
  ///
  /// In en, this message translates to:
  /// **'My role'**
  String get companySettingsMyRole;

  /// No description provided for @companySettingsCommissionChip.
  ///
  /// In en, this message translates to:
  /// **'Commission {value}'**
  String companySettingsCommissionChip(String value);

  /// No description provided for @companySettingsShowAllChip.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get companySettingsShowAllChip;

  /// No description provided for @companySettingsAutoDisableChip.
  ///
  /// In en, this message translates to:
  /// **'Auto disable'**
  String get companySettingsAutoDisableChip;

  /// No description provided for @companySettingsSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get companySettingsSessionTitle;

  /// No description provided for @companySettingsSessionDescription.
  ///
  /// In en, this message translates to:
  /// **'Use this workspace only for company oversight. Sign out when leaving a shared device.'**
  String get companySettingsSessionDescription;

  /// No description provided for @companySettingsLogoutPortal.
  ///
  /// In en, this message translates to:
  /// **'Log out of Company Portal'**
  String get companySettingsLogoutPortal;

  /// No description provided for @companyBranchesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load branches'**
  String get companyBranchesLoadFailed;

  /// No description provided for @companyBranchesLoadFailedDescription.
  ///
  /// In en, this message translates to:
  /// **'Unable to load company branches right now.'**
  String get companyBranchesLoadFailedDescription;

  /// No description provided for @companyBranchesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No branches yet'**
  String get companyBranchesEmptyTitle;

  /// No description provided for @companyBranchesEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'No branch data is available for this company yet.'**
  String get companyBranchesEmptyDescription;

  /// No description provided for @companyBranchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Branches'**
  String get companyBranchesTitle;

  /// No description provided for @companyBranchesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Each branch remains a regular merchant, while the company tracks them from one supervisory workspace.'**
  String get companyBranchesSubtitle;

  /// No description provided for @companyBranchesCopyProducts.
  ///
  /// In en, this message translates to:
  /// **'Copy products'**
  String get companyBranchesCopyProducts;

  /// No description provided for @companyBranchesRequestNew.
  ///
  /// In en, this message translates to:
  /// **'New branch request'**
  String get companyBranchesRequestNew;

  /// No description provided for @companyBranchesAddFirst.
  ///
  /// In en, this message translates to:
  /// **'Add the first branch'**
  String get companyBranchesAddFirst;

  /// No description provided for @companyBranchesFirstDescription.
  ///
  /// In en, this message translates to:
  /// **'Create the first branch request to start building the company branch network.'**
  String get companyBranchesFirstDescription;

  /// No description provided for @companyBranchesNoDescription.
  ///
  /// In en, this message translates to:
  /// **'No description has been added for this branch yet.'**
  String get companyBranchesNoDescription;

  /// No description provided for @companyBranchesDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get companyBranchesDisabled;

  /// No description provided for @companyBranchesActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get companyBranchesActive;

  /// No description provided for @companyBranchesPendingApproval.
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get companyBranchesPendingApproval;

  /// No description provided for @companyBranchesOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders {count}'**
  String companyBranchesOrders(String count);

  /// No description provided for @companyBranchesOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding {amount}'**
  String companyBranchesOutstanding(String amount);

  /// No description provided for @companyBranchesInventorySummary.
  ///
  /// In en, this message translates to:
  /// **'Inventory {outOfStock}/{tracked}'**
  String companyBranchesInventorySummary(String outOfStock, String tracked);

  /// No description provided for @companyBranchesManualAvailability.
  ///
  /// In en, this message translates to:
  /// **'Manual availability'**
  String get companyBranchesManualAvailability;

  /// No description provided for @companyBranchRequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Branch requests'**
  String get companyBranchRequestsTitle;

  /// No description provided for @companyBranchRequestsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track branch requests until admin approval. Approved requests become merchants linked to the company.'**
  String get companyBranchRequestsSubtitle;

  /// No description provided for @companyBranchRequestsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No branch requests yet'**
  String get companyBranchRequestsEmptyTitle;

  /// No description provided for @companyBranchRequestsEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Branch requests created from the company portal will appear here.'**
  String get companyBranchRequestsEmptyDescription;

  /// No description provided for @companyBranchRequestCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create branch request'**
  String get companyBranchRequestCreateTitle;

  /// No description provided for @companyBranchRequestName.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get companyBranchRequestName;

  /// No description provided for @companyBranchRequestType.
  ///
  /// In en, this message translates to:
  /// **'Branch type'**
  String get companyBranchRequestType;

  /// No description provided for @companyBranchRequestDescription.
  ///
  /// In en, this message translates to:
  /// **'Branch description'**
  String get companyBranchRequestDescription;

  /// No description provided for @companyBranchRequestBusinessPhone.
  ///
  /// In en, this message translates to:
  /// **'Business phone'**
  String get companyBranchRequestBusinessPhone;

  /// No description provided for @companyBranchRequestLocation.
  ///
  /// In en, this message translates to:
  /// **'Location / address'**
  String get companyBranchRequestLocation;

  /// No description provided for @companyBranchRequestOwnerAccount.
  ///
  /// In en, this message translates to:
  /// **'Branch owner account'**
  String get companyBranchRequestOwnerAccount;

  /// No description provided for @companyBranchRequestOwnerName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get companyBranchRequestOwnerName;

  /// No description provided for @companyBranchRequestOwnerPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get companyBranchRequestOwnerPhone;

  /// No description provided for @companyBranchRequestOwnerPin.
  ///
  /// In en, this message translates to:
  /// **'Owner PIN'**
  String get companyBranchRequestOwnerPin;

  /// No description provided for @companyBranchRequestOwnerBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get companyBranchRequestOwnerBlock;

  /// No description provided for @companyBranchRequestOwnerBuilding.
  ///
  /// In en, this message translates to:
  /// **'Building number'**
  String get companyBranchRequestOwnerBuilding;

  /// No description provided for @companyBranchRequestOwnerApartment.
  ///
  /// In en, this message translates to:
  /// **'Apartment'**
  String get companyBranchRequestOwnerApartment;

  /// No description provided for @companyBranchRequestSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit request'**
  String get companyBranchRequestSubmit;

  /// No description provided for @companyBranchRequestNoLocation.
  ///
  /// In en, this message translates to:
  /// **'No saved location'**
  String get companyBranchRequestNoLocation;

  /// No description provided for @companyBranchRequestNoOwner.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get companyBranchRequestNoOwner;

  /// No description provided for @companyBranchRequestNoPhone.
  ///
  /// In en, this message translates to:
  /// **'No phone'**
  String get companyBranchRequestNoPhone;

  /// No description provided for @companyBranchRequestSuggestedOwner.
  ///
  /// In en, this message translates to:
  /// **'Suggested owner: {name} - {phone}'**
  String companyBranchRequestSuggestedOwner(String name, String phone);

  /// No description provided for @companyBranchRequestReviewNote.
  ///
  /// In en, this message translates to:
  /// **'Review note: {note}'**
  String companyBranchRequestReviewNote(String note);

  /// No description provided for @companyBranchRequestApprovedBranch.
  ///
  /// In en, this message translates to:
  /// **'Approved branch: {name}'**
  String companyBranchRequestApprovedBranch(String name);

  /// No description provided for @companyBranchCopyNeedAtLeastTwo.
  ///
  /// In en, this message translates to:
  /// **'At least two branches are required to copy products.'**
  String get companyBranchCopyNeedAtLeastTwo;

  /// No description provided for @companyBranchCopyTitle.
  ///
  /// In en, this message translates to:
  /// **'Copy products between branches'**
  String get companyBranchCopyTitle;

  /// No description provided for @companyBranchCopySource.
  ///
  /// In en, this message translates to:
  /// **'Source branch'**
  String get companyBranchCopySource;

  /// No description provided for @companyBranchCopyTargets.
  ///
  /// In en, this message translates to:
  /// **'Target branches'**
  String get companyBranchCopyTargets;

  /// No description provided for @companyBranchCopyProductIds.
  ///
  /// In en, this message translates to:
  /// **'Specific product IDs - optional'**
  String get companyBranchCopyProductIds;

  /// No description provided for @companyBranchCopyProductIdsHint.
  ///
  /// In en, this message translates to:
  /// **'Example: 12,14,33'**
  String get companyBranchCopyProductIdsHint;

  /// No description provided for @companyBranchCopyConflictStrategy.
  ///
  /// In en, this message translates to:
  /// **'Conflict strategy'**
  String get companyBranchCopyConflictStrategy;

  /// No description provided for @companyBranchCopyConflictSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get companyBranchCopyConflictSkip;

  /// No description provided for @companyBranchCopyConflictUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get companyBranchCopyConflictUpdate;

  /// No description provided for @companyBranchCopyConflictDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Create a new copy'**
  String get companyBranchCopyConflictDuplicate;

  /// No description provided for @companyBranchCopyImages.
  ///
  /// In en, this message translates to:
  /// **'Copy images'**
  String get companyBranchCopyImages;

  /// No description provided for @companyBranchCopyPrices.
  ///
  /// In en, this message translates to:
  /// **'Copy prices'**
  String get companyBranchCopyPrices;

  /// No description provided for @companyBranchCopyExecute.
  ///
  /// In en, this message translates to:
  /// **'Run copy'**
  String get companyBranchCopyExecute;

  /// No description provided for @companyBranchCopyCompleted.
  ///
  /// In en, this message translates to:
  /// **'Copy completed: {summary}'**
  String companyBranchCopyCompleted(String summary);

  /// No description provided for @companyUsersLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load company users'**
  String get companyUsersLoadFailed;

  /// No description provided for @companyUsersTitle.
  ///
  /// In en, this message translates to:
  /// **'Company users & permissions'**
  String get companyUsersTitle;

  /// No description provided for @companyUsersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'These users access Company Portal only; they are not daily store operators.'**
  String get companyUsersSubtitle;

  /// No description provided for @companyUsersCreate.
  ///
  /// In en, this message translates to:
  /// **'Create user'**
  String get companyUsersCreate;

  /// No description provided for @companyUsersCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create company user'**
  String get companyUsersCreateTitle;

  /// No description provided for @companyUsersEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No company users yet'**
  String get companyUsersEmptyTitle;

  /// No description provided for @companyUsersEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Create the first company user to delegate finance, operations, or management access.'**
  String get companyUsersEmptyDescription;

  /// No description provided for @companyUsersAddFirst.
  ///
  /// In en, this message translates to:
  /// **'Add first user'**
  String get companyUsersAddFirst;

  /// No description provided for @companyUsersFullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get companyUsersFullName;

  /// No description provided for @companyUsersRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get companyUsersRole;

  /// No description provided for @companyUsersWorkTitle.
  ///
  /// In en, this message translates to:
  /// **'Work title'**
  String get companyUsersWorkTitle;

  /// No description provided for @companyUsersWorkCompany.
  ///
  /// In en, this message translates to:
  /// **'Work company'**
  String get companyUsersWorkCompany;

  /// No description provided for @companyUsersDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get companyUsersDisabled;

  /// No description provided for @companyInventoryLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load inventory overview'**
  String get companyInventoryLoadFailed;

  /// No description provided for @companyInventoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No company inventory yet'**
  String get companyInventoryEmptyTitle;

  /// No description provided for @companyInventoryEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'No inventory oversight data is available yet.'**
  String get companyInventoryEmptyDescription;

  /// No description provided for @companyInventoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory overview'**
  String get companyInventoryTitle;

  /// No description provided for @companyInventorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track stock health, stale branches, and inventory-enabled operations across the whole company.'**
  String get companyInventorySubtitle;

  /// No description provided for @companyInventoryTotalBranches.
  ///
  /// In en, this message translates to:
  /// **'Total branches'**
  String get companyInventoryTotalBranches;

  /// No description provided for @companyInventoryEnabledBranches.
  ///
  /// In en, this message translates to:
  /// **'Inventory-enabled'**
  String get companyInventoryEnabledBranches;

  /// No description provided for @companyInventoryLowStockItems.
  ///
  /// In en, this message translates to:
  /// **'Low stock items'**
  String get companyInventoryLowStockItems;

  /// No description provided for @companyInventoryStaleBranches.
  ///
  /// In en, this message translates to:
  /// **'Stale branches'**
  String get companyInventoryStaleBranches;

  /// No description provided for @companyInventoryBranchStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Branch inventory status'**
  String get companyInventoryBranchStatusTitle;

  /// No description provided for @companyInventoryBranchStatusSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open any branch to inspect stock settings, daily checks, and tracked items.'**
  String get companyInventoryBranchStatusSubtitle;

  /// No description provided for @companyInventoryNoBranchRecordsTitle.
  ///
  /// In en, this message translates to:
  /// **'No branch inventory records yet'**
  String get companyInventoryNoBranchRecordsTitle;

  /// No description provided for @companyInventoryNoBranchRecordsDescription.
  ///
  /// In en, this message translates to:
  /// **'Inventory metrics will appear here once branches start tracking stock.'**
  String get companyInventoryNoBranchRecordsDescription;

  /// No description provided for @companyInventoryEnabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Inventory enabled'**
  String get companyInventoryEnabledLabel;

  /// No description provided for @companyInventoryManualLabel.
  ///
  /// In en, this message translates to:
  /// **'Manual management'**
  String get companyInventoryManualLabel;

  /// No description provided for @companyInventoryOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock {count}'**
  String companyInventoryOutOfStock(String count);

  /// No description provided for @companyInventoryLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock {count}'**
  String companyInventoryLowStock(String count);

  /// No description provided for @companyInventoryUpdatedToday.
  ///
  /// In en, this message translates to:
  /// **'Updated today'**
  String get companyInventoryUpdatedToday;

  /// No description provided for @companyInventoryStaleToday.
  ///
  /// In en, this message translates to:
  /// **'Not updated today'**
  String get companyInventoryStaleToday;

  /// No description provided for @companyReportsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load reports'**
  String get companyReportsLoadFailed;

  /// No description provided for @companyReportsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No branch data yet'**
  String get companyReportsEmptyTitle;

  /// No description provided for @companyReportsEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Branch reporting needs at least one linked branch with recorded activity.'**
  String get companyReportsEmptyDescription;

  /// No description provided for @companyReportsInsightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Executive insights'**
  String get companyReportsInsightsTitle;

  /// No description provided for @companyReportsInsightsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Quick comparisons across branches for sales, receivables, and stock pressure.'**
  String get companyReportsInsightsSubtitle;

  /// No description provided for @companyReportsBestSalesBranch.
  ///
  /// In en, this message translates to:
  /// **'Best sales branch'**
  String get companyReportsBestSalesBranch;

  /// No description provided for @companyReportsHighestOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Highest outstanding'**
  String get companyReportsHighestOutstanding;

  /// No description provided for @companyReportsComparisonTitle.
  ///
  /// In en, this message translates to:
  /// **'Branch comparison'**
  String get companyReportsComparisonTitle;

  /// No description provided for @companyReportsComparisonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Compare branches across orders, sales, outstanding balances, collections, and low stock.'**
  String get companyReportsComparisonSubtitle;

  /// No description provided for @companyReportsTableBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get companyReportsTableBranch;

  /// No description provided for @companyReportsTableOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get companyReportsTableOrders;

  /// No description provided for @companyReportsTableSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get companyReportsTableSales;

  /// No description provided for @companyReportsTableOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get companyReportsTableOutstanding;

  /// No description provided for @companyReportsTableCollected.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get companyReportsTableCollected;

  /// No description provided for @companyReportsTableInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get companyReportsTableInventory;

  /// No description provided for @companyPromotionsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load promotions'**
  String get companyPromotionsLoadFailed;

  /// No description provided for @companyPromotionsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No promotions data yet'**
  String get companyPromotionsEmptyTitle;

  /// No description provided for @companyPromotionsEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'No company campaigns or coupons data is available yet.'**
  String get companyPromotionsEmptyDescription;

  /// No description provided for @companyPromotionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Promotions & coupons'**
  String get companyPromotionsTitle;

  /// No description provided for @companyPromotionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create an offer once, then target one branch, many branches, or all branches at once.'**
  String get companyPromotionsSubtitle;

  /// No description provided for @companyPromotionsCouponAction.
  ///
  /// In en, this message translates to:
  /// **'Coupon'**
  String get companyPromotionsCouponAction;

  /// No description provided for @companyPromotionsCampaignAction.
  ///
  /// In en, this message translates to:
  /// **'Campaign'**
  String get companyPromotionsCampaignAction;

  /// No description provided for @companyPromotionsCouponsTab.
  ///
  /// In en, this message translates to:
  /// **'Coupons'**
  String get companyPromotionsCouponsTab;

  /// No description provided for @companyPromotionsCampaignsTab.
  ///
  /// In en, this message translates to:
  /// **'Campaigns'**
  String get companyPromotionsCampaignsTab;

  /// No description provided for @companyPromotionsCreateCouponTitle.
  ///
  /// In en, this message translates to:
  /// **'Create company coupon'**
  String get companyPromotionsCreateCouponTitle;

  /// No description provided for @companyPromotionsCouponCode.
  ///
  /// In en, this message translates to:
  /// **'Coupon code'**
  String get companyPromotionsCouponCode;

  /// No description provided for @companyPromotionsDiscountType.
  ///
  /// In en, this message translates to:
  /// **'Discount type'**
  String get companyPromotionsDiscountType;

  /// No description provided for @companyPromotionsDiscountPercent.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get companyPromotionsDiscountPercent;

  /// No description provided for @companyPromotionsDiscountFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount'**
  String get companyPromotionsDiscountFixed;

  /// No description provided for @companyPromotionsDiscountValue.
  ///
  /// In en, this message translates to:
  /// **'Discount value'**
  String get companyPromotionsDiscountValue;

  /// No description provided for @companyPromotionsMaxUses.
  ///
  /// In en, this message translates to:
  /// **'Maximum uses'**
  String get companyPromotionsMaxUses;

  /// No description provided for @companyPromotionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get companyPromotionsDescription;

  /// No description provided for @companyPromotionsApplyAllBranches.
  ///
  /// In en, this message translates to:
  /// **'Apply to all branches'**
  String get companyPromotionsApplyAllBranches;

  /// No description provided for @companyPromotionsCreateCoupon.
  ///
  /// In en, this message translates to:
  /// **'Create coupon'**
  String get companyPromotionsCreateCoupon;

  /// No description provided for @companyPromotionsCreateCouponFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the coupon right now.'**
  String get companyPromotionsCreateCouponFailed;

  /// No description provided for @companyPromotionsCreateCampaignTitle.
  ///
  /// In en, this message translates to:
  /// **'Create company campaign'**
  String get companyPromotionsCreateCampaignTitle;

  /// No description provided for @companyPromotionsCampaignTitle.
  ///
  /// In en, this message translates to:
  /// **'Campaign title'**
  String get companyPromotionsCampaignTitle;

  /// No description provided for @companyPromotionsCampaignType.
  ///
  /// In en, this message translates to:
  /// **'Campaign type'**
  String get companyPromotionsCampaignType;

  /// No description provided for @companyPromotionsCampaignPercentage.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get companyPromotionsCampaignPercentage;

  /// No description provided for @companyPromotionsCampaignFixedAmount.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount'**
  String get companyPromotionsCampaignFixedAmount;

  /// No description provided for @companyPromotionsCampaignBuyXGetY.
  ///
  /// In en, this message translates to:
  /// **'Buy X get Y'**
  String get companyPromotionsCampaignBuyXGetY;

  /// No description provided for @companyPromotionsCampaignBuyQuantity.
  ///
  /// In en, this message translates to:
  /// **'Buy quantity'**
  String get companyPromotionsCampaignBuyQuantity;

  /// No description provided for @companyPromotionsCampaignGetQuantity.
  ///
  /// In en, this message translates to:
  /// **'Free quantity'**
  String get companyPromotionsCampaignGetQuantity;

  /// No description provided for @companyPromotionsCampaignStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get companyPromotionsCampaignStatus;

  /// No description provided for @companyPromotionsStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get companyPromotionsStatusDraft;

  /// No description provided for @companyPromotionsStatusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get companyPromotionsStatusScheduled;

  /// No description provided for @companyPromotionsStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get companyPromotionsStatusActive;

  /// No description provided for @companyPromotionsCreateCampaign.
  ///
  /// In en, this message translates to:
  /// **'Create campaign'**
  String get companyPromotionsCreateCampaign;

  /// No description provided for @companyPromotionsCreateCampaignFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the campaign right now.'**
  String get companyPromotionsCreateCampaignFailed;

  /// No description provided for @companyPromotionsNoCouponsTitle.
  ///
  /// In en, this message translates to:
  /// **'No company coupons yet'**
  String get companyPromotionsNoCouponsTitle;

  /// No description provided for @companyPromotionsNoCouponsDescription.
  ///
  /// In en, this message translates to:
  /// **'Create the first company coupon to target one or more branches.'**
  String get companyPromotionsNoCouponsDescription;

  /// No description provided for @companyPromotionsNoCampaignsTitle.
  ///
  /// In en, this message translates to:
  /// **'No company campaigns yet'**
  String get companyPromotionsNoCampaignsTitle;

  /// No description provided for @companyPromotionsNoCampaignsDescription.
  ///
  /// In en, this message translates to:
  /// **'Create the first campaign to roll out offers across targeted branches.'**
  String get companyPromotionsNoCampaignsDescription;

  /// No description provided for @companyPromotionsAllBranches.
  ///
  /// In en, this message translates to:
  /// **'All branches'**
  String get companyPromotionsAllBranches;

  /// No description provided for @companyPromotionsTargetBranchesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} branches'**
  String companyPromotionsTargetBranchesCount(String count);

  /// No description provided for @companyPromotionsDiscountValueSummary.
  ///
  /// In en, this message translates to:
  /// **'Discount value: {value}'**
  String companyPromotionsDiscountValueSummary(String value);

  /// No description provided for @companyPromotionsTypeStatusSummary.
  ///
  /// In en, this message translates to:
  /// **'Type: {type} | Status: {status}'**
  String companyPromotionsTypeStatusSummary(String type, String status);

  /// No description provided for @adminAdvancedToolsTitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced tools'**
  String get adminAdvancedToolsTitle;

  /// No description provided for @adminAdvancedToolsCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get adminAdvancedToolsCreateAccount;

  /// No description provided for @adminAdvancedToolsCreateAccountDescription.
  ///
  /// In en, this message translates to:
  /// **'Create managed user accounts directly from the admin panel.'**
  String get adminAdvancedToolsCreateAccountDescription;

  /// No description provided for @adminAdvancedToolsCreateMerchant.
  ///
  /// In en, this message translates to:
  /// **'Create store'**
  String get adminAdvancedToolsCreateMerchant;

  /// No description provided for @adminAdvancedToolsCreateMerchantDescription.
  ///
  /// In en, this message translates to:
  /// **'Create a store manually from admin tools.'**
  String get adminAdvancedToolsCreateMerchantDescription;

  /// No description provided for @adminAdvancedToolsCompanyPortal.
  ///
  /// In en, this message translates to:
  /// **'Company portal'**
  String get adminAdvancedToolsCompanyPortal;

  /// No description provided for @adminAdvancedToolsCompanyPortalDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage companies, link branches, and review branch requests from one place.'**
  String get adminAdvancedToolsCompanyPortalDescription;

  /// No description provided for @adminAdvancedToolsCouponManagement.
  ///
  /// In en, this message translates to:
  /// **'Coupon management'**
  String get adminAdvancedToolsCouponManagement;

  /// No description provided for @adminAdvancedToolsCouponManagementDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage global coupons and promotional campaigns.'**
  String get adminAdvancedToolsCouponManagementDescription;

  /// No description provided for @adminAdvancedToolsChatMonitoring.
  ///
  /// In en, this message translates to:
  /// **'Chat monitoring'**
  String get adminAdvancedToolsChatMonitoring;

  /// No description provided for @adminAdvancedToolsChatMonitoringDescription.
  ///
  /// In en, this message translates to:
  /// **'Review sensitive sessions and monitor conversation quality.'**
  String get adminAdvancedToolsChatMonitoringDescription;

  /// No description provided for @adminAdvancedToolsFeed.
  ///
  /// In en, this message translates to:
  /// **'Basmaya feed'**
  String get adminAdvancedToolsFeed;

  /// No description provided for @adminAdvancedToolsFeedDescription.
  ///
  /// In en, this message translates to:
  /// **'Open the public social feed and moderate published content.'**
  String get adminAdvancedToolsFeedDescription;

  /// No description provided for @adminAdvancedToolsAdBoard.
  ///
  /// In en, this message translates to:
  /// **'Ad board'**
  String get adminAdvancedToolsAdBoard;

  /// No description provided for @adminAdvancedToolsAdBoardDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage the ad board inventory from admin tools.'**
  String get adminAdvancedToolsAdBoardDescription;

  /// No description provided for @adminAdvancedToolsJobsHub.
  ///
  /// In en, this message translates to:
  /// **'Jobs hub'**
  String get adminAdvancedToolsJobsHub;

  /// No description provided for @adminAdvancedToolsJobsHubDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage jobs, readers, and candidate pipelines.'**
  String get adminAdvancedToolsJobsHubDescription;

  /// No description provided for @adminAdvancedToolsJobsReader.
  ///
  /// In en, this message translates to:
  /// **'Jobs reader'**
  String get adminAdvancedToolsJobsReader;

  /// No description provided for @adminAdvancedToolsJobsReaderDescription.
  ///
  /// In en, this message translates to:
  /// **'Read jobs and nominate matching candidates.'**
  String get adminAdvancedToolsJobsReaderDescription;

  /// No description provided for @adminAdvancedToolsApplicantsMonitor.
  ///
  /// In en, this message translates to:
  /// **'Applicants monitor'**
  String get adminAdvancedToolsApplicantsMonitor;

  /// No description provided for @adminAdvancedToolsApplicantsMonitorDescription.
  ///
  /// In en, this message translates to:
  /// **'Monitor and filter applicants with super-admin tools.'**
  String get adminAdvancedToolsApplicantsMonitorDescription;

  /// No description provided for @adminCreateUserTitle.
  ///
  /// In en, this message translates to:
  /// **'Create new account'**
  String get adminCreateUserTitle;

  /// No description provided for @adminCreateUserFullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get adminCreateUserFullName;

  /// No description provided for @adminCreateUserNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required.'**
  String get adminCreateUserNameRequired;

  /// No description provided for @adminCreateUserPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone is required.'**
  String get adminCreateUserPhoneRequired;

  /// No description provided for @adminCreateUserPinRequired.
  ///
  /// In en, this message translates to:
  /// **'PIN is required.'**
  String get adminCreateUserPinRequired;

  /// No description provided for @adminCreateUserRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get adminCreateUserRole;

  /// No description provided for @adminCreateUserCustomerRole.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get adminCreateUserCustomerRole;

  /// No description provided for @adminCreateUserOwnerRole.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get adminCreateUserOwnerRole;

  /// No description provided for @adminCreateUserDeliveryRole.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get adminCreateUserDeliveryRole;

  /// No description provided for @adminCreateUserAccountantRole.
  ///
  /// In en, this message translates to:
  /// **'Accountant'**
  String get adminCreateUserAccountantRole;

  /// No description provided for @adminCreateUserHrRole.
  ///
  /// In en, this message translates to:
  /// **'HR'**
  String get adminCreateUserHrRole;

  /// No description provided for @adminCreateUserDeputyAdminRole.
  ///
  /// In en, this message translates to:
  /// **'Deputy admin'**
  String get adminCreateUserDeputyAdminRole;

  /// No description provided for @adminCreateUserCallCenterRole.
  ///
  /// In en, this message translates to:
  /// **'Call center'**
  String get adminCreateUserCallCenterRole;

  /// No description provided for @adminCreateUserAdminRole.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get adminCreateUserAdminRole;

  /// No description provided for @adminCreateUserDriverType.
  ///
  /// In en, this message translates to:
  /// **'Driver type'**
  String get adminCreateUserDriverType;

  /// No description provided for @adminCreateUserStoreDriverHelper.
  ///
  /// In en, this message translates to:
  /// **'Store driver: delivery fees stay on the store side.'**
  String get adminCreateUserStoreDriverHelper;

  /// No description provided for @adminCreateUserAppDriverHelper.
  ///
  /// In en, this message translates to:
  /// **'App driver: delivery fees count for the platform.'**
  String get adminCreateUserAppDriverHelper;

  /// No description provided for @adminCreateUserAppDriver.
  ///
  /// In en, this message translates to:
  /// **'App driver'**
  String get adminCreateUserAppDriver;

  /// No description provided for @adminCreateUserStoreDriver.
  ///
  /// In en, this message translates to:
  /// **'Store driver'**
  String get adminCreateUserStoreDriver;

  /// No description provided for @adminCreateUserDriverTypeRequired.
  ///
  /// In en, this message translates to:
  /// **'Select the driver type.'**
  String get adminCreateUserDriverTypeRequired;

  /// No description provided for @adminCreateUserAssignedMerchant.
  ///
  /// In en, this message translates to:
  /// **'Assigned merchant'**
  String get adminCreateUserAssignedMerchant;

  /// No description provided for @adminCreateUserAssignedMerchantOptional.
  ///
  /// In en, this message translates to:
  /// **'Assigned merchant optional'**
  String get adminCreateUserAssignedMerchantOptional;

  /// No description provided for @adminCreateUserMerchantOptionalHelper.
  ///
  /// In en, this message translates to:
  /// **'You can leave merchant empty for app drivers.'**
  String get adminCreateUserMerchantOptionalHelper;

  /// No description provided for @adminCreateUserMerchantRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a merchant for this account.'**
  String get adminCreateUserMerchantRequired;

  /// No description provided for @adminCreateUserBlockRequired.
  ///
  /// In en, this message translates to:
  /// **'Block is required.'**
  String get adminCreateUserBlockRequired;

  /// No description provided for @adminCreateUserBuildingNumber.
  ///
  /// In en, this message translates to:
  /// **'Building number'**
  String get adminCreateUserBuildingNumber;

  /// No description provided for @adminCreateUserBuildingRequired.
  ///
  /// In en, this message translates to:
  /// **'Building number is required.'**
  String get adminCreateUserBuildingRequired;

  /// No description provided for @adminCreateUserApartmentRequired.
  ///
  /// In en, this message translates to:
  /// **'Apartment is required.'**
  String get adminCreateUserApartmentRequired;

  /// No description provided for @adminCreateUserCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get adminCreateUserCreateButton;

  /// No description provided for @adminDashboardOrdersSummaryFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the orders summary right now.'**
  String get adminDashboardOrdersSummaryFailed;

  /// No description provided for @adminDashboardCurrentPeriodSummaryFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the current period summary.'**
  String get adminDashboardCurrentPeriodSummaryFailed;

  /// No description provided for @adminDashboardToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get adminDashboardToday;

  /// No description provided for @adminDashboardThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get adminDashboardThisWeek;

  /// No description provided for @adminDashboardThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get adminDashboardThisMonth;

  /// No description provided for @adminDashboardThisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get adminDashboardThisYear;

  /// No description provided for @adminDashboardCustomRange.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get adminDashboardCustomRange;

  /// No description provided for @adminDashboardCurrentWindow.
  ///
  /// In en, this message translates to:
  /// **'Current window'**
  String get adminDashboardCurrentWindow;

  /// No description provided for @adminDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin dashboard'**
  String get adminDashboardTitle;

  /// No description provided for @adminDashboardControlPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin Control Panel'**
  String get adminDashboardControlPanelTitle;

  /// No description provided for @adminDashboardHome.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get adminDashboardHome;

  /// No description provided for @adminDashboardHomeDescription.
  ///
  /// In en, this message translates to:
  /// **'Main dashboard home'**
  String get adminDashboardHomeDescription;

  /// No description provided for @adminDashboardRefreshData.
  ///
  /// In en, this message translates to:
  /// **'Refresh data'**
  String get adminDashboardRefreshData;

  /// No description provided for @adminDashboardRefreshDataDescription.
  ///
  /// In en, this message translates to:
  /// **'Reload current counters and reports'**
  String get adminDashboardRefreshDataDescription;

  /// No description provided for @adminDashboardApprovalsHub.
  ///
  /// In en, this message translates to:
  /// **'Approvals hub'**
  String get adminDashboardApprovalsHub;

  /// No description provided for @adminDashboardApprovalsHubDescription.
  ///
  /// In en, this message translates to:
  /// **'All approval workflows in one place'**
  String get adminDashboardApprovalsHubDescription;

  /// No description provided for @adminDashboardMerchantApprovals.
  ///
  /// In en, this message translates to:
  /// **'Merchant approvals'**
  String get adminDashboardMerchantApprovals;

  /// No description provided for @adminDashboardMerchantApprovalsDescription.
  ///
  /// In en, this message translates to:
  /// **'Review new merchants and financial terms'**
  String get adminDashboardMerchantApprovalsDescription;

  /// No description provided for @adminDashboardResidenceChangeRequests.
  ///
  /// In en, this message translates to:
  /// **'Residence change requests'**
  String get adminDashboardResidenceChangeRequests;

  /// No description provided for @adminDashboardResidenceChangeRequestsDescription.
  ///
  /// In en, this message translates to:
  /// **'Review residence change requests before approval'**
  String get adminDashboardResidenceChangeRequestsDescription;

  /// No description provided for @adminDashboardTaxiCaptainRequests.
  ///
  /// In en, this message translates to:
  /// **'Taxi captain requests'**
  String get adminDashboardTaxiCaptainRequests;

  /// No description provided for @adminDashboardTaxiCaptainRequestsDescription.
  ///
  /// In en, this message translates to:
  /// **'Approvals and profile edits'**
  String get adminDashboardTaxiCaptainRequestsDescription;

  /// No description provided for @adminDashboardCaptainSubscriptionPayments.
  ///
  /// In en, this message translates to:
  /// **'Captain subscription payments'**
  String get adminDashboardCaptainSubscriptionPayments;

  /// No description provided for @adminDashboardCaptainSubscriptionPaymentsDescription.
  ///
  /// In en, this message translates to:
  /// **'Cash payments awaiting confirmation'**
  String get adminDashboardCaptainSubscriptionPaymentsDescription;

  /// No description provided for @adminDashboardPaidUpgradeRequests.
  ///
  /// In en, this message translates to:
  /// **'Paid upgrade requests'**
  String get adminDashboardPaidUpgradeRequests;

  /// No description provided for @adminDashboardPaidUpgradeRequestsDescription.
  ///
  /// In en, this message translates to:
  /// **'Review and activate seller and premium requests'**
  String get adminDashboardPaidUpgradeRequestsDescription;

  /// No description provided for @adminDashboardRealEstateModeration.
  ///
  /// In en, this message translates to:
  /// **'Real estate moderation'**
  String get adminDashboardRealEstateModeration;

  /// No description provided for @adminDashboardRealEstateModerationDescription.
  ///
  /// In en, this message translates to:
  /// **'Approve or reject pending real estate listings'**
  String get adminDashboardRealEstateModerationDescription;

  /// No description provided for @adminDashboardMerchantStatusManagement.
  ///
  /// In en, this message translates to:
  /// **'Merchant status management'**
  String get adminDashboardMerchantStatusManagement;

  /// No description provided for @adminDashboardMerchantStatusManagementDescription.
  ///
  /// In en, this message translates to:
  /// **'Open, disable, and manage merchants'**
  String get adminDashboardMerchantStatusManagementDescription;

  /// No description provided for @adminDashboardCustomerProfiles.
  ///
  /// In en, this message translates to:
  /// **'Customer profiles'**
  String get adminDashboardCustomerProfiles;

  /// No description provided for @adminDashboardCustomerProfilesDescription.
  ///
  /// In en, this message translates to:
  /// **'Search and review customer profiles'**
  String get adminDashboardCustomerProfilesDescription;

  /// No description provided for @adminDashboardAuditLog.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get adminDashboardAuditLog;

  /// No description provided for @adminDashboardAuditLogDescription.
  ///
  /// In en, this message translates to:
  /// **'Administrative actions timeline'**
  String get adminDashboardAuditLogDescription;

  /// No description provided for @adminDashboardMerchantReceivables.
  ///
  /// In en, this message translates to:
  /// **'Merchant receivables'**
  String get adminDashboardMerchantReceivables;

  /// No description provided for @adminDashboardMerchantReceivablesDescription.
  ///
  /// In en, this message translates to:
  /// **'Settlements, balances, and financial actions'**
  String get adminDashboardMerchantReceivablesDescription;

  /// No description provided for @adminDashboardFinancialReports.
  ///
  /// In en, this message translates to:
  /// **'Financial reports'**
  String get adminDashboardFinancialReports;

  /// No description provided for @adminDashboardFinancialReportsDescription.
  ///
  /// In en, this message translates to:
  /// **'Commissions, service fees, and collections reports'**
  String get adminDashboardFinancialReportsDescription;

  /// No description provided for @adminDashboardCourierCompetitions.
  ///
  /// In en, this message translates to:
  /// **'Courier competitions'**
  String get adminDashboardCourierCompetitions;

  /// No description provided for @adminDashboardReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get adminDashboardReports;

  /// No description provided for @adminDashboardReportsDescription.
  ///
  /// In en, this message translates to:
  /// **'Review abuse and community reports'**
  String get adminDashboardReportsDescription;

  /// No description provided for @adminDashboardSocialRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Social restrictions'**
  String get adminDashboardSocialRestrictions;

  /// No description provided for @adminDashboardSocialRestrictionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage posting, stories, reels, and comments restrictions'**
  String get adminDashboardSocialRestrictionsDescription;

  /// No description provided for @adminDashboardMaintenanceCenter.
  ///
  /// In en, this message translates to:
  /// **'Maintenance center'**
  String get adminDashboardMaintenanceCenter;

  /// No description provided for @adminDashboardAdvancedHub.
  ///
  /// In en, this message translates to:
  /// **'Advanced Hub'**
  String get adminDashboardAdvancedHub;

  /// No description provided for @adminDashboardAdvancedHubDescription.
  ///
  /// In en, this message translates to:
  /// **'Advanced secondary tools for super admin'**
  String get adminDashboardAdvancedHubDescription;

  /// No description provided for @adminDashboardGroupDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get adminDashboardGroupDashboard;

  /// No description provided for @adminDashboardGroupApprovals.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get adminDashboardGroupApprovals;

  /// No description provided for @adminDashboardGroupOperations.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get adminDashboardGroupOperations;

  /// No description provided for @adminDashboardGroupFinance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get adminDashboardGroupFinance;

  /// No description provided for @adminDashboardGroupCommunityReports.
  ///
  /// In en, this message translates to:
  /// **'Community & reports'**
  String get adminDashboardGroupCommunityReports;

  /// No description provided for @adminDashboardDesktopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unified operations home for orders, approvals, and finance.'**
  String get adminDashboardDesktopSubtitle;

  /// No description provided for @adminDashboardLiveWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Live workspace'**
  String get adminDashboardLiveWorkspace;

  /// No description provided for @adminDashboardDailyOperationsPulse.
  ///
  /// In en, this message translates to:
  /// **'Daily operations pulse'**
  String get adminDashboardDailyOperationsPulse;

  /// No description provided for @adminDashboardDailyOperationsPulseDescription.
  ///
  /// In en, this message translates to:
  /// **'A clean control surface focused on orders, approvals, and finance.'**
  String get adminDashboardDailyOperationsPulseDescription;

  /// No description provided for @adminDashboardLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get adminDashboardLive;

  /// No description provided for @adminDashboardOrdersPulse.
  ///
  /// In en, this message translates to:
  /// **'Orders pulse'**
  String get adminDashboardOrdersPulse;

  /// No description provided for @adminDashboardOrdersPulseDescription.
  ///
  /// In en, this message translates to:
  /// **'Each card opens merchants, then merchant orders with the correct filter.'**
  String get adminDashboardOrdersPulseDescription;

  /// No description provided for @adminDashboardAllOrders.
  ///
  /// In en, this message translates to:
  /// **'All orders'**
  String get adminDashboardAllOrders;

  /// No description provided for @adminDashboardAllOrdersHint.
  ///
  /// In en, this message translates to:
  /// **'Open all merchants then every order per merchant.'**
  String get adminDashboardAllOrdersHint;

  /// No description provided for @adminDashboardCompletedOrdersHint.
  ///
  /// In en, this message translates to:
  /// **'Shows completed orders only for each merchant.'**
  String get adminDashboardCompletedOrdersHint;

  /// No description provided for @adminDashboardCancelledOrdersHint.
  ///
  /// In en, this message translates to:
  /// **'Shows cancelled orders only for each merchant.'**
  String get adminDashboardCancelledOrdersHint;

  /// No description provided for @adminDashboardInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get adminDashboardInProgress;

  /// No description provided for @adminDashboardInProgressHint.
  ///
  /// In en, this message translates to:
  /// **'Shows only active in-progress orders.'**
  String get adminDashboardInProgressHint;

  /// No description provided for @adminDashboardCriticalApprovals.
  ///
  /// In en, this message translates to:
  /// **'Critical approvals'**
  String get adminDashboardCriticalApprovals;

  /// No description provided for @adminDashboardCriticalApprovalsDescription.
  ///
  /// In en, this message translates to:
  /// **'Direct links to focused approval pages with live counters.'**
  String get adminDashboardCriticalApprovalsDescription;

  /// No description provided for @adminDashboardOpenApprovalsHub.
  ///
  /// In en, this message translates to:
  /// **'Open approvals hub'**
  String get adminDashboardOpenApprovalsHub;

  /// No description provided for @adminDashboardPendingMerchants.
  ///
  /// In en, this message translates to:
  /// **'Pending merchants'**
  String get adminDashboardPendingMerchants;

  /// No description provided for @adminDashboardPendingMerchantsDescription.
  ///
  /// In en, this message translates to:
  /// **'New merchant registrations awaiting financial review.'**
  String get adminDashboardPendingMerchantsDescription;

  /// No description provided for @adminDashboardCaptainApprovals.
  ///
  /// In en, this message translates to:
  /// **'Captain approvals'**
  String get adminDashboardCaptainApprovals;

  /// No description provided for @adminDashboardCaptainApprovalsDescription.
  ///
  /// In en, this message translates to:
  /// **'New taxi captain approvals.'**
  String get adminDashboardCaptainApprovalsDescription;

  /// No description provided for @adminDashboardProfileEdits.
  ///
  /// In en, this message translates to:
  /// **'Profile edits'**
  String get adminDashboardProfileEdits;

  /// No description provided for @adminDashboardProfileEditsDescription.
  ///
  /// In en, this message translates to:
  /// **'Taxi captain profile edit requests.'**
  String get adminDashboardProfileEditsDescription;

  /// No description provided for @adminDashboardFinancialActions.
  ///
  /// In en, this message translates to:
  /// **'Financial actions'**
  String get adminDashboardFinancialActions;

  /// No description provided for @adminDashboardFinancialActionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Receivables and cash payments awaiting action.'**
  String get adminDashboardFinancialActionsDescription;

  /// No description provided for @adminDashboardPeriodSummary.
  ///
  /// In en, this message translates to:
  /// **'Period summary'**
  String get adminDashboardPeriodSummary;

  /// No description provided for @adminDashboardPeriodSummaryDescription.
  ///
  /// In en, this message translates to:
  /// **'Built from the same financial and operational sources as the reports.'**
  String get adminDashboardPeriodSummaryDescription;

  /// No description provided for @adminDashboardDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get adminDashboardDay;

  /// No description provided for @adminDashboardWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get adminDashboardWeek;

  /// No description provided for @adminDashboardMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get adminDashboardMonth;

  /// No description provided for @adminDashboardYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get adminDashboardYear;

  /// No description provided for @adminDashboardSelectedWindow.
  ///
  /// In en, this message translates to:
  /// **'Selected window: {window}'**
  String adminDashboardSelectedWindow(String window);

  /// No description provided for @adminDashboardCommissions.
  ///
  /// In en, this message translates to:
  /// **'Commissions'**
  String get adminDashboardCommissions;

  /// No description provided for @adminDashboardCommissionsDescription.
  ///
  /// In en, this message translates to:
  /// **'App commissions within the selected window.'**
  String get adminDashboardCommissionsDescription;

  /// No description provided for @adminDashboardServiceFeesDescription.
  ///
  /// In en, this message translates to:
  /// **'Service fees calculated on orders.'**
  String get adminDashboardServiceFeesDescription;

  /// No description provided for @adminDashboardDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get adminDashboardDelivery;

  /// No description provided for @adminDashboardDeliveryDescription.
  ///
  /// In en, this message translates to:
  /// **'Delivery fees that belong to the app.'**
  String get adminDashboardDeliveryDescription;

  /// No description provided for @adminDashboardCompletedOrdersDescription.
  ///
  /// In en, this message translates to:
  /// **'Completed orders in the selected window.'**
  String get adminDashboardCompletedOrdersDescription;

  /// No description provided for @adminDashboardCancelledOrdersDescription.
  ///
  /// In en, this message translates to:
  /// **'Cancelled orders in the selected window.'**
  String get adminDashboardCancelledOrdersDescription;

  /// No description provided for @adminDashboardInProgressOrders.
  ///
  /// In en, this message translates to:
  /// **'In-progress orders'**
  String get adminDashboardInProgressOrders;

  /// No description provided for @adminDashboardInProgressOrdersDescription.
  ///
  /// In en, this message translates to:
  /// **'Orders still in progress.'**
  String get adminDashboardInProgressOrdersDescription;

  /// No description provided for @adminDashboardFinancialShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Financial shortcuts'**
  String get adminDashboardFinancialShortcuts;

  /// No description provided for @adminDashboardFinancialShortcutsDescription.
  ///
  /// In en, this message translates to:
  /// **'Direct access to the live receivables and reports modules.'**
  String get adminDashboardFinancialShortcutsDescription;

  /// No description provided for @adminDashboardMerchantReceivablesShortcutDescription.
  ///
  /// In en, this message translates to:
  /// **'Settlements, remaining balances, and financial actions.'**
  String get adminDashboardMerchantReceivablesShortcutDescription;

  /// No description provided for @adminDashboardFinancialReportsShortcutDescription.
  ///
  /// In en, this message translates to:
  /// **'Drill-down reports for commissions, service fees, and collections.'**
  String get adminDashboardFinancialReportsShortcutDescription;

  /// No description provided for @adminFinancialFilterToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get adminFinancialFilterToday;

  /// No description provided for @adminFinancialFilterWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get adminFinancialFilterWeek;

  /// No description provided for @adminFinancialFilterMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get adminFinancialFilterMonth;

  /// No description provided for @adminFinancialFilterYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get adminFinancialFilterYear;

  /// No description provided for @adminFinancialFilterCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get adminFinancialFilterCustom;

  /// No description provided for @adminFinancialFilterSearchMerchant.
  ///
  /// In en, this message translates to:
  /// **'Search merchant'**
  String get adminFinancialFilterSearchMerchant;

  /// No description provided for @adminFinancialMerchantPeriodToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get adminFinancialMerchantPeriodToday;

  /// No description provided for @adminFinancialMerchantPeriodThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get adminFinancialMerchantPeriodThisWeek;

  /// No description provided for @adminFinancialMerchantPeriodThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get adminFinancialMerchantPeriodThisMonth;

  /// No description provided for @adminFinancialMerchantPeriodThisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get adminFinancialMerchantPeriodThisYear;

  /// No description provided for @adminFinancialMerchantPeriodCustomRange.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get adminFinancialMerchantPeriodCustomRange;

  /// No description provided for @adminFinancialMerchantSalesDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Merchant sales details'**
  String get adminFinancialMerchantSalesDetailsTitle;

  /// No description provided for @adminFinancialMerchantCollectionsDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Merchant collections details'**
  String get adminFinancialMerchantCollectionsDetailsTitle;

  /// No description provided for @adminFinancialMerchantReceivablesDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Merchant receivables statement'**
  String get adminFinancialMerchantReceivablesDetailsTitle;

  /// No description provided for @adminFinancialMerchantLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load report details.'**
  String get adminFinancialMerchantLoadFailed;

  /// No description provided for @adminFinancialMerchantLabelMerchant.
  ///
  /// In en, this message translates to:
  /// **'Merchant'**
  String get adminFinancialMerchantLabelMerchant;

  /// No description provided for @adminFinancialMerchantLabelPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get adminFinancialMerchantLabelPeriod;

  /// No description provided for @adminFinancialMerchantHeaderOrder.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get adminFinancialMerchantHeaderOrder;

  /// No description provided for @adminFinancialMerchantHeaderDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get adminFinancialMerchantHeaderDate;

  /// No description provided for @adminFinancialMerchantHeaderCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get adminFinancialMerchantHeaderCustomer;

  /// No description provided for @adminFinancialMerchantHeaderAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get adminFinancialMerchantHeaderAmount;

  /// No description provided for @adminFinancialMerchantTotalSales.
  ///
  /// In en, this message translates to:
  /// **'Total sales'**
  String get adminFinancialMerchantTotalSales;

  /// No description provided for @adminFinancialMerchantOrdersCount.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get adminFinancialMerchantOrdersCount;

  /// No description provided for @adminFinancialMerchantHeaderOperation.
  ///
  /// In en, this message translates to:
  /// **'Operation'**
  String get adminFinancialMerchantHeaderOperation;

  /// No description provided for @adminFinancialMerchantHeaderScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get adminFinancialMerchantHeaderScope;

  /// No description provided for @adminFinancialMerchantTotalCollected.
  ///
  /// In en, this message translates to:
  /// **'Total collected'**
  String get adminFinancialMerchantTotalCollected;

  /// No description provided for @adminFinancialMerchantOperationsCount.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get adminFinancialMerchantOperationsCount;

  /// No description provided for @adminFinancialMerchantHeaderDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get adminFinancialMerchantHeaderDescription;

  /// No description provided for @adminFinancialMerchantHeaderDebit.
  ///
  /// In en, this message translates to:
  /// **'Debit'**
  String get adminFinancialMerchantHeaderDebit;

  /// No description provided for @adminFinancialMerchantHeaderCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get adminFinancialMerchantHeaderCredit;

  /// No description provided for @adminFinancialMerchantHeaderBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get adminFinancialMerchantHeaderBalance;

  /// No description provided for @adminFinancialMerchantOpeningBalance.
  ///
  /// In en, this message translates to:
  /// **'Opening balance'**
  String get adminFinancialMerchantOpeningBalance;

  /// No description provided for @adminFinancialMerchantNetReceivables.
  ///
  /// In en, this message translates to:
  /// **'Net receivables'**
  String get adminFinancialMerchantNetReceivables;

  /// No description provided for @adminFinancialMerchantNoDetailData.
  ///
  /// In en, this message translates to:
  /// **'No detail data available.'**
  String get adminFinancialMerchantNoDetailData;

  /// No description provided for @adminFinancialMerchantNoSalesInRange.
  ///
  /// In en, this message translates to:
  /// **'No sales in range.'**
  String get adminFinancialMerchantNoSalesInRange;

  /// No description provided for @adminFinancialMerchantNoCollectionsInRange.
  ///
  /// In en, this message translates to:
  /// **'No collections in range.'**
  String get adminFinancialMerchantNoCollectionsInRange;

  /// No description provided for @adminFinancialMerchantNoStatementEntriesInRange.
  ///
  /// In en, this message translates to:
  /// **'No statement entries in range.'**
  String get adminFinancialMerchantNoStatementEntriesInRange;

  /// No description provided for @deliveryCourierCompetitionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Courier competitions'**
  String get deliveryCourierCompetitionsTitle;

  /// No description provided for @deliveryCourierCompetitionsParticipated.
  ///
  /// In en, this message translates to:
  /// **'Participated'**
  String get deliveryCourierCompetitionsParticipated;

  /// No description provided for @deliveryCourierCompetitionsWins.
  ///
  /// In en, this message translates to:
  /// **'Wins'**
  String get deliveryCourierCompetitionsWins;

  /// No description provided for @deliveryCourierCompetitionsTotalRewards.
  ///
  /// In en, this message translates to:
  /// **'Total rewards'**
  String get deliveryCourierCompetitionsTotalRewards;

  /// No description provided for @deliveryCourierCompetitionsActive.
  ///
  /// In en, this message translates to:
  /// **'Active competitions'**
  String get deliveryCourierCompetitionsActive;

  /// No description provided for @deliveryCourierCompetitionsNoActive.
  ///
  /// In en, this message translates to:
  /// **'No active competitions.'**
  String get deliveryCourierCompetitionsNoActive;

  /// No description provided for @deliveryCourierCompetitionsCompetitionFallback.
  ///
  /// In en, this message translates to:
  /// **'Competition'**
  String get deliveryCourierCompetitionsCompetitionFallback;

  /// No description provided for @deliveryCourierCompetitionsCurrentProgress.
  ///
  /// In en, this message translates to:
  /// **'Current progress: {value}'**
  String deliveryCourierCompetitionsCurrentProgress(String value);

  /// No description provided for @deliveryCourierCompetitionsCurrentRank.
  ///
  /// In en, this message translates to:
  /// **'Current rank: {rank}'**
  String deliveryCourierCompetitionsCurrentRank(String rank);

  /// No description provided for @deliveryCourierCompetitionsOrdersToNextRank.
  ///
  /// In en, this message translates to:
  /// **'{count} orders to next rank'**
  String deliveryCourierCompetitionsOrdersToNextRank(String count);

  /// No description provided for @deliveryCourierCompetitionsPast.
  ///
  /// In en, this message translates to:
  /// **'Past competitions'**
  String get deliveryCourierCompetitionsPast;

  /// No description provided for @deliveryCourierCompetitionsNoPast.
  ///
  /// In en, this message translates to:
  /// **'No past competitions.'**
  String get deliveryCourierCompetitionsNoPast;

  /// No description provided for @deliveryCourierCompetitionsEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get deliveryCourierCompetitionsEnded;

  /// No description provided for @deliveryCourierNewOffersTitle.
  ///
  /// In en, this message translates to:
  /// **'New delivery offers'**
  String get deliveryCourierNewOffersTitle;

  /// No description provided for @deliveryCourierCurrentOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Current orders'**
  String get deliveryCourierCurrentOrdersTitle;

  /// No description provided for @deliveryCourierCompletedOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Completed orders'**
  String get deliveryCourierCompletedOrdersTitle;

  /// No description provided for @deliveryCourierCancelledOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancelled orders'**
  String get deliveryCourierCancelledOrdersTitle;

  /// No description provided for @deliveryCourierNoNewOffers.
  ///
  /// In en, this message translates to:
  /// **'No new offers.'**
  String get deliveryCourierNoNewOffers;

  /// No description provided for @deliveryCourierNoItems.
  ///
  /// In en, this message translates to:
  /// **'No items.'**
  String get deliveryCourierNoItems;

  /// No description provided for @deliveryCourierOrderDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Order details'**
  String get deliveryCourierOrderDetailsTitle;

  /// No description provided for @deliveryCourierOrderNotFound.
  ///
  /// In en, this message translates to:
  /// **'Order not found.'**
  String get deliveryCourierOrderNotFound;

  /// No description provided for @deliveryCourierEarningsTitle.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get deliveryCourierEarningsTitle;

  /// No description provided for @deliveryCourierReportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Courier reports'**
  String get deliveryCourierReportsTitle;

  /// No description provided for @deliveryCourierTodayFees.
  ///
  /// In en, this message translates to:
  /// **'Today fees'**
  String get deliveryCourierTodayFees;

  /// No description provided for @deliveryCourierCompletedToday.
  ///
  /// In en, this message translates to:
  /// **'Completed today'**
  String get deliveryCourierCompletedToday;

  /// No description provided for @deliveryCourierAverageRating.
  ///
  /// In en, this message translates to:
  /// **'Average rating'**
  String get deliveryCourierAverageRating;

  /// No description provided for @deliveryCourierNoReportData.
  ///
  /// In en, this message translates to:
  /// **'No report data available.'**
  String get deliveryCourierNoReportData;

  /// No description provided for @deliveryCourierOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Order offer'**
  String get deliveryCourierOfferTitle;

  /// No description provided for @deliveryCourierLabelMerchant.
  ///
  /// In en, this message translates to:
  /// **'Merchant'**
  String get deliveryCourierLabelMerchant;

  /// No description provided for @deliveryCourierLabelCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get deliveryCourierLabelCustomer;

  /// No description provided for @deliveryCourierAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get deliveryCourierAccept;

  /// No description provided for @deliveryCourierReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get deliveryCourierReject;

  /// No description provided for @deliveryCourierOrderLabel.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get deliveryCourierOrderLabel;

  /// No description provided for @deliveryCourierLabelTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get deliveryCourierLabelTotal;

  /// No description provided for @deliveryCourierActionPickedUp.
  ///
  /// In en, this message translates to:
  /// **'Picked up'**
  String get deliveryCourierActionPickedUp;

  /// No description provided for @deliveryCourierActionArrived.
  ///
  /// In en, this message translates to:
  /// **'Arrived'**
  String get deliveryCourierActionArrived;

  /// No description provided for @deliveryCourierActionDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get deliveryCourierActionDelivered;

  /// No description provided for @ownerFinancialRequestPaymentMethodCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get ownerFinancialRequestPaymentMethodCash;

  /// No description provided for @ownerFinancialRequestPaymentMethodBankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank transfer'**
  String get ownerFinancialRequestPaymentMethodBankTransfer;

  /// No description provided for @ownerFinancialRequestPaymentMethodZainCash.
  ///
  /// In en, this message translates to:
  /// **'Zain Cash'**
  String get ownerFinancialRequestPaymentMethodZainCash;

  /// No description provided for @ownerFinancialRequestPaymentMethodAsiacellCash.
  ///
  /// In en, this message translates to:
  /// **'Asiacell Cash'**
  String get ownerFinancialRequestPaymentMethodAsiacellCash;

  /// No description provided for @ownerFinancialRequestPaymentMethodManualHandover.
  ///
  /// In en, this message translates to:
  /// **'Manual handover'**
  String get ownerFinancialRequestPaymentMethodManualHandover;

  /// No description provided for @ownerFinancialRequestPaymentMethodOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get ownerFinancialRequestPaymentMethodOther;

  /// No description provided for @ownerFinancialRequestPaymentMethodNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get ownerFinancialRequestPaymentMethodNotSet;

  /// No description provided for @ownerFinancialRequestSelectionAllInvoices.
  ///
  /// In en, this message translates to:
  /// **'All invoices'**
  String get ownerFinancialRequestSelectionAllInvoices;

  /// No description provided for @ownerFinancialRequestSelectionPickInvoices.
  ///
  /// In en, this message translates to:
  /// **'Pick invoices'**
  String get ownerFinancialRequestSelectionPickInvoices;

  /// No description provided for @ownerFinancialRequestSelectionMatchAmount.
  ///
  /// In en, this message translates to:
  /// **'Match amount'**
  String get ownerFinancialRequestSelectionMatchAmount;

  /// No description provided for @ownerFinancialRequestChoosePaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Choose a payment method.'**
  String get ownerFinancialRequestChoosePaymentMethod;

  /// No description provided for @ownerFinancialRequestDescribeOtherPaymentMethodError.
  ///
  /// In en, this message translates to:
  /// **'Describe the other payment method.'**
  String get ownerFinancialRequestDescribeOtherPaymentMethodError;

  /// No description provided for @ownerFinancialRequestChoosePaymentDateTime.
  ///
  /// In en, this message translates to:
  /// **'Choose payment date and time.'**
  String get ownerFinancialRequestChoosePaymentDateTime;

  /// No description provided for @ownerFinancialRequestSelectInvoice.
  ///
  /// In en, this message translates to:
  /// **'Select at least one invoice.'**
  String get ownerFinancialRequestSelectInvoice;

  /// No description provided for @ownerFinancialRequestEnterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount.'**
  String get ownerFinancialRequestEnterValidAmount;

  /// No description provided for @ownerFinancialRequestInvoiceSelectionMode.
  ///
  /// In en, this message translates to:
  /// **'Invoice selection mode'**
  String get ownerFinancialRequestInvoiceSelectionMode;

  /// No description provided for @ownerFinancialRequestChooseInvoices.
  ///
  /// In en, this message translates to:
  /// **'Choose invoices'**
  String get ownerFinancialRequestChooseInvoices;

  /// No description provided for @ownerFinancialRequestInvoicesSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} invoices selected.'**
  String ownerFinancialRequestInvoicesSelected(String count);

  /// No description provided for @ownerFinancialRequestTargetAmountToMatch.
  ///
  /// In en, this message translates to:
  /// **'Target amount to match'**
  String get ownerFinancialRequestTargetAmountToMatch;

  /// No description provided for @ownerFinancialRequestLinkAllOpenInvoices.
  ///
  /// In en, this message translates to:
  /// **'The request will be linked to all open receivable invoices.'**
  String get ownerFinancialRequestLinkAllOpenInvoices;

  /// No description provided for @ownerFinancialRequestPreviewMatching.
  ///
  /// In en, this message translates to:
  /// **'Preview matching'**
  String get ownerFinancialRequestPreviewMatching;

  /// No description provided for @ownerFinancialRequestInvoicesCount.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get ownerFinancialRequestInvoicesCount;

  /// No description provided for @ownerFinancialRequestFinalTotal.
  ///
  /// In en, this message translates to:
  /// **'Final total'**
  String get ownerFinancialRequestFinalTotal;

  /// No description provided for @ownerFinancialRequestOldestInvoice.
  ///
  /// In en, this message translates to:
  /// **'Oldest invoice'**
  String get ownerFinancialRequestOldestInvoice;

  /// No description provided for @ownerFinancialRequestLatestInvoice.
  ///
  /// In en, this message translates to:
  /// **'Latest invoice'**
  String get ownerFinancialRequestLatestInvoice;

  /// No description provided for @ownerFinancialRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Financial settlement request'**
  String get ownerFinancialRequestTitle;

  /// No description provided for @ownerFinancialRequestType.
  ///
  /// In en, this message translates to:
  /// **'Request type'**
  String get ownerFinancialRequestType;

  /// No description provided for @ownerFinancialRequestTypeStorePaysApp.
  ///
  /// In en, this message translates to:
  /// **'Store pays app'**
  String get ownerFinancialRequestTypeStorePaysApp;

  /// No description provided for @ownerFinancialRequestTypeAppPaysStore.
  ///
  /// In en, this message translates to:
  /// **'App pays store'**
  String get ownerFinancialRequestTypeAppPaysStore;

  /// No description provided for @ownerFinancialRequestRequestedAmount.
  ///
  /// In en, this message translates to:
  /// **'Requested amount'**
  String get ownerFinancialRequestRequestedAmount;

  /// No description provided for @ownerFinancialRequestPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get ownerFinancialRequestPaymentMethod;

  /// No description provided for @ownerFinancialRequestDescribeOtherMethod.
  ///
  /// In en, this message translates to:
  /// **'Describe the other method'**
  String get ownerFinancialRequestDescribeOtherMethod;

  /// No description provided for @ownerFinancialRequestPickDateTime.
  ///
  /// In en, this message translates to:
  /// **'Pick date & time'**
  String get ownerFinancialRequestPickDateTime;

  /// No description provided for @ownerFinancialRequestReferenceCode.
  ///
  /// In en, this message translates to:
  /// **'Reference code / receipt'**
  String get ownerFinancialRequestReferenceCode;

  /// No description provided for @ownerFinancialRequestReceiverName.
  ///
  /// In en, this message translates to:
  /// **'Receiver name'**
  String get ownerFinancialRequestReceiverName;

  /// No description provided for @ownerFinancialRequestNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get ownerFinancialRequestNotes;

  /// No description provided for @ownerFinancialRequestFinalAmount.
  ///
  /// In en, this message translates to:
  /// **'Final amount'**
  String get ownerFinancialRequestFinalAmount;

  /// No description provided for @ownerFinancialRequestReportIssueTitle.
  ///
  /// In en, this message translates to:
  /// **'Report an issue'**
  String get ownerFinancialRequestReportIssueTitle;

  /// No description provided for @ownerFinancialRequestReportIssueHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the issue here'**
  String get ownerFinancialRequestReportIssueHint;

  /// No description provided for @ownerFinancialRequestSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get ownerFinancialRequestSend;

  /// No description provided for @ownerFinancialRequestPaidAmount.
  ///
  /// In en, this message translates to:
  /// **'Paid amount'**
  String get ownerFinancialRequestPaidAmount;

  /// No description provided for @ownerFinancialRequestPaymentDate.
  ///
  /// In en, this message translates to:
  /// **'Payment date'**
  String get ownerFinancialRequestPaymentDate;

  /// No description provided for @ownerFinancialRequestReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get ownerFinancialRequestReference;

  /// No description provided for @ownerFinancialRequestReviewNote.
  ///
  /// In en, this message translates to:
  /// **'Review note'**
  String get ownerFinancialRequestReviewNote;

  /// No description provided for @ownerFinancialRequestInternalAdminNote.
  ///
  /// In en, this message translates to:
  /// **'Internal admin note'**
  String get ownerFinancialRequestInternalAdminNote;

  /// No description provided for @ownerFinancialRequestLinkedInvoices.
  ///
  /// In en, this message translates to:
  /// **'Linked invoices'**
  String get ownerFinancialRequestLinkedInvoices;

  /// No description provided for @ownerFinancialRequestNoLinkedInvoices.
  ///
  /// In en, this message translates to:
  /// **'No linked invoices are available for this request.'**
  String get ownerFinancialRequestNoLinkedInvoices;

  /// No description provided for @ownerFinancialRequestAllocatedAmount.
  ///
  /// In en, this message translates to:
  /// **'Allocated amount'**
  String get ownerFinancialRequestAllocatedAmount;

  /// No description provided for @ownerFinancialRequestOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get ownerFinancialRequestOutstanding;

  /// No description provided for @ownerFinancialRequestDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get ownerFinancialRequestDate;

  /// No description provided for @ownerFinancialRequestConfirmReceipt.
  ///
  /// In en, this message translates to:
  /// **'Confirm receipt'**
  String get ownerFinancialRequestConfirmReceipt;

  /// No description provided for @ownerFinancialRequestReportIssueAction.
  ///
  /// In en, this message translates to:
  /// **'Report issue'**
  String get ownerFinancialRequestReportIssueAction;

  /// No description provided for @adminCompetitionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Courier competitions'**
  String get adminCompetitionsTitle;

  /// No description provided for @adminCompetitionsTabActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get adminCompetitionsTabActive;

  /// No description provided for @adminCompetitionsTabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get adminCompetitionsTabHistory;

  /// No description provided for @adminCompetitionsTabCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get adminCompetitionsTabCreate;

  /// No description provided for @adminCompetitionsKpiTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get adminCompetitionsKpiTotal;

  /// No description provided for @adminCompetitionsKpiActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get adminCompetitionsKpiActive;

  /// No description provided for @adminCompetitionsKpiEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get adminCompetitionsKpiEnded;

  /// No description provided for @adminCompetitionsKpiRewards.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get adminCompetitionsKpiRewards;

  /// No description provided for @adminCompetitionsCompetitionFallback.
  ///
  /// In en, this message translates to:
  /// **'Competition'**
  String get adminCompetitionsCompetitionFallback;

  /// No description provided for @adminCompetitionsTiers.
  ///
  /// In en, this message translates to:
  /// **'Tiers'**
  String get adminCompetitionsTiers;

  /// No description provided for @adminCompetitionsTierMinimumOrders.
  ///
  /// In en, this message translates to:
  /// **'Min: {count} orders'**
  String adminCompetitionsTierMinimumOrders(String count);

  /// No description provided for @adminCompetitionsLeaderboard.
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get adminCompetitionsLeaderboard;

  /// No description provided for @adminCompetitionsNoParticipants.
  ///
  /// In en, this message translates to:
  /// **'No participants yet.'**
  String get adminCompetitionsNoParticipants;

  /// No description provided for @adminCompetitionsCourierFallback.
  ///
  /// In en, this message translates to:
  /// **'Courier'**
  String get adminCompetitionsCourierFallback;

  /// No description provided for @adminCompetitionsCounted.
  ///
  /// In en, this message translates to:
  /// **'Counted: {count}'**
  String adminCompetitionsCounted(String count);

  /// No description provided for @adminCompetitionsWinners.
  ///
  /// In en, this message translates to:
  /// **'Winners'**
  String get adminCompetitionsWinners;

  /// No description provided for @adminCompetitionsNoWinners.
  ///
  /// In en, this message translates to:
  /// **'No winners yet.'**
  String get adminCompetitionsNoWinners;

  /// No description provided for @adminCompetitionsWinnerSummary.
  ///
  /// In en, this message translates to:
  /// **'Rank: {rank} • Orders: {orders}'**
  String adminCompetitionsWinnerSummary(String rank, String orders);

  /// No description provided for @adminCompetitionsListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No competitions in this section.'**
  String get adminCompetitionsListEmpty;

  /// No description provided for @adminCompetitionsEditTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit competition'**
  String get adminCompetitionsEditTooltip;

  /// No description provided for @adminCompetitionsEndNowTooltip.
  ///
  /// In en, this message translates to:
  /// **'End now'**
  String get adminCompetitionsEndNowTooltip;

  /// No description provided for @adminCompetitionsParticipantsSummary.
  ///
  /// In en, this message translates to:
  /// **'Participants: {participants} - Winners: {winners}'**
  String adminCompetitionsParticipantsSummary(
    String participants,
    String winners,
  );

  /// No description provided for @adminCompetitionsOpenDetails.
  ///
  /// In en, this message translates to:
  /// **'Open details'**
  String get adminCompetitionsOpenDetails;

  /// No description provided for @adminCompetitionsServerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unable to reach the server.'**
  String get adminCompetitionsServerUnavailable;

  /// No description provided for @adminCompetitionsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load competitions.'**
  String get adminCompetitionsLoadFailed;

  /// No description provided for @adminCompetitionsTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title is required.'**
  String get adminCompetitionsTitleRequired;

  /// No description provided for @adminCompetitionsEndAfterStart.
  ///
  /// In en, this message translates to:
  /// **'End time must be after start time.'**
  String get adminCompetitionsEndAfterStart;

  /// No description provided for @adminCompetitionsCheckTiersRewards.
  ///
  /// In en, this message translates to:
  /// **'Check tier requirements and rewards.'**
  String get adminCompetitionsCheckTiersRewards;

  /// No description provided for @adminCompetitionsCreated.
  ///
  /// In en, this message translates to:
  /// **'Competition created.'**
  String get adminCompetitionsCreated;

  /// No description provided for @adminCompetitionsCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Create failed.'**
  String get adminCompetitionsCreateFailed;

  /// No description provided for @adminCompetitionsFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Competition title'**
  String get adminCompetitionsFieldTitle;

  /// No description provided for @adminCompetitionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get adminCompetitionsDescription;

  /// No description provided for @adminCompetitionsStartDateTime.
  ///
  /// In en, this message translates to:
  /// **'Start date & time'**
  String get adminCompetitionsStartDateTime;

  /// No description provided for @adminCompetitionsStartImmediate.
  ///
  /// In en, this message translates to:
  /// **'Not set (starts immediately)'**
  String get adminCompetitionsStartImmediate;

  /// No description provided for @adminCompetitionsEndDateTime.
  ///
  /// In en, this message translates to:
  /// **'End date & time'**
  String get adminCompetitionsEndDateTime;

  /// No description provided for @adminCompetitionsEndServerDefault.
  ///
  /// In en, this message translates to:
  /// **'Not set (server default)'**
  String get adminCompetitionsEndServerDefault;

  /// No description provided for @adminCompetitionsPickDateTime.
  ///
  /// In en, this message translates to:
  /// **'Pick date/time'**
  String get adminCompetitionsPickDateTime;

  /// No description provided for @adminCompetitionsTierTitle.
  ///
  /// In en, this message translates to:
  /// **'Tier title'**
  String get adminCompetitionsTierTitle;

  /// No description provided for @adminCompetitionsRequiredOrders.
  ///
  /// In en, this message translates to:
  /// **'Required orders'**
  String get adminCompetitionsRequiredOrders;

  /// No description provided for @adminCompetitionsRewardIqd.
  ///
  /// In en, this message translates to:
  /// **'Reward (IQD)'**
  String get adminCompetitionsRewardIqd;

  /// No description provided for @adminCompetitionsAddTier.
  ///
  /// In en, this message translates to:
  /// **'Add tier'**
  String get adminCompetitionsAddTier;

  /// No description provided for @adminCompetitionsCreateCompetition.
  ///
  /// In en, this message translates to:
  /// **'Create competition'**
  String get adminCompetitionsCreateCompetition;

  /// No description provided for @adminCompetitionsEditActiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit active competition'**
  String get adminCompetitionsEditActiveTitle;

  /// No description provided for @adminCompetitionsEditActiveHint.
  ///
  /// In en, this message translates to:
  /// **'Editing is allowed for active competitions only.'**
  String get adminCompetitionsEditActiveHint;

  /// No description provided for @adminCompetitionsDateKeepCurrent.
  ///
  /// In en, this message translates to:
  /// **'Not set (keep current)'**
  String get adminCompetitionsDateKeepCurrent;

  /// No description provided for @adminCompetitionsUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update competition.'**
  String get adminCompetitionsUpdateFailed;

  /// No description provided for @adminCompetitionsSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get adminCompetitionsSaveChanges;

  /// No description provided for @adminCompetitionsTierOrderInvalid.
  ///
  /// In en, this message translates to:
  /// **'Each lower tier must require fewer orders.'**
  String get adminCompetitionsTierOrderInvalid;

  /// No description provided for @adminCompetitionsFirstPlace.
  ///
  /// In en, this message translates to:
  /// **'First place'**
  String get adminCompetitionsFirstPlace;

  /// No description provided for @adminCompetitionsSecondPlace.
  ///
  /// In en, this message translates to:
  /// **'Second place'**
  String get adminCompetitionsSecondPlace;

  /// No description provided for @adminCompetitionsThirdPlace.
  ///
  /// In en, this message translates to:
  /// **'Third place'**
  String get adminCompetitionsThirdPlace;

  /// No description provided for @adminCompetitionsGenericTier.
  ///
  /// In en, this message translates to:
  /// **'Tier'**
  String get adminCompetitionsGenericTier;

  /// No description provided for @socialProfileRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get socialProfileRoleAdmin;

  /// No description provided for @socialProfileRoleSuperAdmin.
  ///
  /// In en, this message translates to:
  /// **'Super admin'**
  String get socialProfileRoleSuperAdmin;

  /// No description provided for @socialProfileRoleDeputyAdmin.
  ///
  /// In en, this message translates to:
  /// **'Deputy admin'**
  String get socialProfileRoleDeputyAdmin;

  /// No description provided for @socialProfileRoleMerchantOwner.
  ///
  /// In en, this message translates to:
  /// **'Merchant'**
  String get socialProfileRoleMerchantOwner;

  /// No description provided for @socialProfileRoleDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get socialProfileRoleDelivery;

  /// No description provided for @socialProfileRoleTaxiCaptain.
  ///
  /// In en, this message translates to:
  /// **'Taxi captain'**
  String get socialProfileRoleTaxiCaptain;

  /// No description provided for @socialProfileRoleUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get socialProfileRoleUser;

  /// No description provided for @socialProfileAccountCarsAndRealEstate.
  ///
  /// In en, this message translates to:
  /// **'Cars and real estate'**
  String get socialProfileAccountCarsAndRealEstate;

  /// No description provided for @socialProfileAccountCarSeller.
  ///
  /// In en, this message translates to:
  /// **'Car seller'**
  String get socialProfileAccountCarSeller;

  /// No description provided for @socialProfileAccountPropertyBroker.
  ///
  /// In en, this message translates to:
  /// **'Property broker'**
  String get socialProfileAccountPropertyBroker;

  /// No description provided for @socialProfileAccountPremiumMember.
  ///
  /// In en, this message translates to:
  /// **'Premium member'**
  String get socialProfileAccountPremiumMember;

  /// No description provided for @socialProfileBadgeVerifiedMerchant.
  ///
  /// In en, this message translates to:
  /// **'Verified merchant'**
  String get socialProfileBadgeVerifiedMerchant;

  /// No description provided for @socialProfileBadgeVerifiedSeller.
  ///
  /// In en, this message translates to:
  /// **'Verified seller'**
  String get socialProfileBadgeVerifiedSeller;

  /// No description provided for @socialProfileBadgeVerifiedBroker.
  ///
  /// In en, this message translates to:
  /// **'Verified broker'**
  String get socialProfileBadgeVerifiedBroker;

  /// No description provided for @socialProfileBadgeVerifiedUser.
  ///
  /// In en, this message translates to:
  /// **'Verified user'**
  String get socialProfileBadgeVerifiedUser;

  /// No description provided for @socialProfileShareLine.
  ///
  /// In en, this message translates to:
  /// **'Check out this profile in Maslaki.'**
  String get socialProfileShareLine;

  /// No description provided for @socialProfileTabPosts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get socialProfileTabPosts;

  /// No description provided for @socialProfileTabReels.
  ///
  /// In en, this message translates to:
  /// **'Reels'**
  String get socialProfileTabReels;

  /// No description provided for @socialProfileTabSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get socialProfileTabSaved;

  /// No description provided for @socialProfileTabReviews.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get socialProfileTabReviews;

  /// No description provided for @socialProfileTabTagged.
  ///
  /// In en, this message translates to:
  /// **'Tagged'**
  String get socialProfileTabTagged;

  /// No description provided for @socialProfileMyInsights.
  ///
  /// In en, this message translates to:
  /// **'My insights'**
  String get socialProfileMyInsights;

  /// No description provided for @socialProfileInsights.
  ///
  /// In en, this message translates to:
  /// **'Profile insights'**
  String get socialProfileInsights;

  /// No description provided for @socialProfileTaggedPosts.
  ///
  /// In en, this message translates to:
  /// **'Tagged posts'**
  String get socialProfileTaggedPosts;

  /// No description provided for @socialProfileDeletePostConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this post permanently from your profile?'**
  String get socialProfileDeletePostConfirm;

  /// No description provided for @socialProfileDeletePostSuccess.
  ///
  /// In en, this message translates to:
  /// **'The post was deleted.'**
  String get socialProfileDeletePostSuccess;

  /// No description provided for @socialProfileDeletePostFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete the post right now.'**
  String get socialProfileDeletePostFailed;

  /// No description provided for @socialProfileReportUserTitle.
  ///
  /// In en, this message translates to:
  /// **'Report user'**
  String get socialProfileReportUserTitle;

  /// No description provided for @socialProfileReportReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get socialProfileReportReason;

  /// No description provided for @socialProfileReportReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Example: impersonation or abuse'**
  String get socialProfileReportReasonHint;

  /// No description provided for @socialProfileReportAdditionalDetails.
  ///
  /// In en, this message translates to:
  /// **'Additional details (optional)'**
  String get socialProfileReportAdditionalDetails;

  /// No description provided for @socialProfileSubmitReport.
  ///
  /// In en, this message translates to:
  /// **'Submit report'**
  String get socialProfileSubmitReport;

  /// No description provided for @socialProfileReportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'The report has been submitted.'**
  String get socialProfileReportSubmitted;

  /// No description provided for @socialProfileReportSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit the report.'**
  String get socialProfileReportSubmitFailed;

  /// No description provided for @socialProfileImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get socialProfileImages;

  /// No description provided for @socialProfileFriends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get socialProfileFriends;

  /// No description provided for @socialProfileLikesMade.
  ///
  /// In en, this message translates to:
  /// **'Likes made'**
  String get socialProfileLikesMade;

  /// No description provided for @socialProfileCommentsMade.
  ///
  /// In en, this message translates to:
  /// **'Comments made'**
  String get socialProfileCommentsMade;

  /// No description provided for @socialProfileLikesReceived.
  ///
  /// In en, this message translates to:
  /// **'Likes received'**
  String get socialProfileLikesReceived;

  /// No description provided for @socialProfileCommentsReceived.
  ///
  /// In en, this message translates to:
  /// **'Comments received'**
  String get socialProfileCommentsReceived;

  /// No description provided for @socialProfileContentArchived.
  ///
  /// In en, this message translates to:
  /// **'Content archived.'**
  String get socialProfileContentArchived;

  /// No description provided for @socialProfileContentRestored.
  ///
  /// In en, this message translates to:
  /// **'Content restored.'**
  String get socialProfileContentRestored;

  /// No description provided for @socialProfileContentArchiveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to archive content.'**
  String get socialProfileContentArchiveFailed;

  /// No description provided for @socialProfileContentRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to restore content.'**
  String get socialProfileContentRestoreFailed;

  /// No description provided for @socialProfileEditProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get socialProfileEditProfile;

  /// No description provided for @socialProfileBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get socialProfileBlock;

  /// No description provided for @socialProfileUnblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get socialProfileUnblock;

  /// No description provided for @socialProfileBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get socialProfileBlocked;

  /// No description provided for @socialProfileManageAccount.
  ///
  /// In en, this message translates to:
  /// **'Manage account'**
  String get socialProfileManageAccount;

  /// No description provided for @socialProfileProfileActivity.
  ///
  /// In en, this message translates to:
  /// **'Profile activity'**
  String get socialProfileProfileActivity;

  /// No description provided for @socialProfileArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get socialProfileArchive;

  /// No description provided for @socialProfileInsightsMenu.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get socialProfileInsightsMenu;

  /// No description provided for @socialProfileShareProfile.
  ///
  /// In en, this message translates to:
  /// **'Share profile'**
  String get socialProfileShareProfile;

  /// No description provided for @socialProfileMuteNotifications.
  ///
  /// In en, this message translates to:
  /// **'Mute notifications'**
  String get socialProfileMuteNotifications;

  /// No description provided for @socialProfileEnableNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable notifications'**
  String get socialProfileEnableNotifications;

  /// No description provided for @socialProfileManageUser.
  ///
  /// In en, this message translates to:
  /// **'Manage user'**
  String get socialProfileManageUser;

  /// No description provided for @socialProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get socialProfileTitle;

  /// No description provided for @socialProfileStatsPosts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get socialProfileStatsPosts;

  /// No description provided for @socialProfileStatsFollowers.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get socialProfileStatsFollowers;

  /// No description provided for @socialProfileStatsFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get socialProfileStatsFollowing;

  /// No description provided for @socialProfileUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get socialProfileUpgrade;

  /// No description provided for @socialProfileLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get socialProfileLoadMore;

  /// No description provided for @socialProfileNoPostsForFilter.
  ///
  /// In en, this message translates to:
  /// **'No posts match this filter.'**
  String get socialProfileNoPostsForFilter;

  /// No description provided for @socialProfilePrivatePostsNotice.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s posts are hidden right now.'**
  String socialProfilePrivatePostsNotice(String name);

  /// No description provided for @socialProfileManagePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get socialProfileManagePhone;

  /// No description provided for @socialProfileManageHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get socialProfileManageHidden;

  /// No description provided for @socialProfileManageJoined.
  ///
  /// In en, this message translates to:
  /// **'Joined'**
  String get socialProfileManageJoined;

  /// No description provided for @socialProfileManageAge.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get socialProfileManageAge;

  /// No description provided for @socialProfileManageAgeValue.
  ///
  /// In en, this message translates to:
  /// **'{age} years'**
  String socialProfileManageAgeValue(String age);

  /// No description provided for @socialProfileManageWorkTitle.
  ///
  /// In en, this message translates to:
  /// **'Work title'**
  String get socialProfileManageWorkTitle;

  /// No description provided for @socialProfileManageCompany.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get socialProfileManageCompany;

  /// No description provided for @socialProfileManageLocalContext.
  ///
  /// In en, this message translates to:
  /// **'Local context'**
  String get socialProfileManageLocalContext;

  /// No description provided for @socialProfileManageAccountStatus.
  ///
  /// In en, this message translates to:
  /// **'Account status'**
  String get socialProfileManageAccountStatus;

  /// No description provided for @socialProfileManageDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get socialProfileManageDisabled;

  /// No description provided for @socialProfileManageActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get socialProfileManageActive;

  /// No description provided for @socialProfileManageNextCoreUpdate.
  ///
  /// In en, this message translates to:
  /// **'Next core update'**
  String get socialProfileManageNextCoreUpdate;

  /// No description provided for @socialProfileManageTitle.
  ///
  /// In en, this message translates to:
  /// **'Account management'**
  String get socialProfileManageTitle;

  /// No description provided for @socialProfileManageProfilePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Profile and privacy'**
  String get socialProfileManageProfilePrivacy;

  /// No description provided for @socialProfileManageEditProfilePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Edit profile and privacy'**
  String get socialProfileManageEditProfilePrivacy;

  /// No description provided for @socialProfileManageEditProfilePrivacyHint.
  ///
  /// In en, this message translates to:
  /// **'Name, bio, avatar, and basic visibility settings'**
  String get socialProfileManageEditProfilePrivacyHint;

  /// No description provided for @socialProfileManagePhoneVisible.
  ///
  /// In en, this message translates to:
  /// **'Phone visible'**
  String get socialProfileManagePhoneVisible;

  /// No description provided for @socialProfileManagePhoneHidden.
  ///
  /// In en, this message translates to:
  /// **'Phone hidden'**
  String get socialProfileManagePhoneHidden;

  /// No description provided for @socialProfileManagePostsPublic.
  ///
  /// In en, this message translates to:
  /// **'Posts are public'**
  String get socialProfileManagePostsPublic;

  /// No description provided for @socialProfileManagePostsPrivate.
  ///
  /// In en, this message translates to:
  /// **'Posts are private'**
  String get socialProfileManagePostsPrivate;

  /// No description provided for @socialProfileManageStoriesPublic.
  ///
  /// In en, this message translates to:
  /// **'Stories are public'**
  String get socialProfileManageStoriesPublic;

  /// No description provided for @socialProfileManageStoriesPrivate.
  ///
  /// In en, this message translates to:
  /// **'Stories are private'**
  String get socialProfileManageStoriesPrivate;

  /// No description provided for @socialProfileManageRelationsVisible.
  ///
  /// In en, this message translates to:
  /// **'Relations visible'**
  String get socialProfileManageRelationsVisible;

  /// No description provided for @socialProfileManageRelationsPrivate.
  ///
  /// In en, this message translates to:
  /// **'Relations private'**
  String get socialProfileManageRelationsPrivate;

  /// No description provided for @socialProfileManageOnlineStatus.
  ///
  /// In en, this message translates to:
  /// **'Online status: {visibility}'**
  String socialProfileManageOnlineStatus(String visibility);

  /// No description provided for @socialProfileManageLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen: {visibility}'**
  String socialProfileManageLastSeen(String visibility);

  /// No description provided for @socialProfileManageReadReceiptsOn.
  ///
  /// In en, this message translates to:
  /// **'Read receipts on'**
  String get socialProfileManageReadReceiptsOn;

  /// No description provided for @socialProfileManageReadReceiptsHidden.
  ///
  /// In en, this message translates to:
  /// **'Read receipts hidden'**
  String get socialProfileManageReadReceiptsHidden;

  /// No description provided for @socialProfileManageTypingOn.
  ///
  /// In en, this message translates to:
  /// **'Typing indicator on'**
  String get socialProfileManageTypingOn;

  /// No description provided for @socialProfileManageTypingHidden.
  ///
  /// In en, this message translates to:
  /// **'Typing indicator hidden'**
  String get socialProfileManageTypingHidden;

  /// No description provided for @socialProfileManageAccountActions.
  ///
  /// In en, this message translates to:
  /// **'Account actions'**
  String get socialProfileManageAccountActions;

  /// No description provided for @socialProfileManageConnectionRequests.
  ///
  /// In en, this message translates to:
  /// **'Connection requests'**
  String get socialProfileManageConnectionRequests;

  /// No description provided for @socialProfileManageConnectionRequestsHint.
  ///
  /// In en, this message translates to:
  /// **'Manage incoming and outgoing requests'**
  String get socialProfileManageConnectionRequestsHint;

  /// No description provided for @socialProfileManageResidenceChange.
  ///
  /// In en, this message translates to:
  /// **'Residence change request'**
  String get socialProfileManageResidenceChange;

  /// No description provided for @socialProfileManageResidenceChangeHint.
  ///
  /// In en, this message translates to:
  /// **'Update your residence details when needed'**
  String get socialProfileManageResidenceChangeHint;

  /// No description provided for @socialProfileManageUpgrades.
  ///
  /// In en, this message translates to:
  /// **'Upgrades and subscriptions'**
  String get socialProfileManageUpgrades;

  /// No description provided for @socialProfileManageSocialRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Social restrictions'**
  String get socialProfileManageSocialRestrictions;

  /// No description provided for @socialProfileManageSocialRestrictionsHint.
  ///
  /// In en, this message translates to:
  /// **'View active restrictions or notices tied to your account'**
  String get socialProfileManageSocialRestrictionsHint;

  /// No description provided for @socialProfileManageReportedPosts.
  ///
  /// In en, this message translates to:
  /// **'Reported posts'**
  String get socialProfileManageReportedPosts;

  /// No description provided for @socialProfileManageReportedPostsHint.
  ///
  /// In en, this message translates to:
  /// **'Review posts that need resubmission'**
  String get socialProfileManageReportedPostsHint;

  /// No description provided for @socialProfileManageInsights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get socialProfileManageInsights;

  /// No description provided for @socialProfileManageInsightsHint.
  ///
  /// In en, this message translates to:
  /// **'Open your profile insights'**
  String get socialProfileManageInsightsHint;

  /// No description provided for @socialProfileManageAccountInfo.
  ///
  /// In en, this message translates to:
  /// **'Account info'**
  String get socialProfileManageAccountInfo;

  /// No description provided for @socialProfileManageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get socialProfileManageUnavailable;

  /// No description provided for @socialProfileManageVisibilityEveryone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get socialProfileManageVisibilityEveryone;

  /// No description provided for @socialProfileManageVisibilityNobody.
  ///
  /// In en, this message translates to:
  /// **'Nobody'**
  String get socialProfileManageVisibilityNobody;

  /// No description provided for @socialProfileManageVisibilityConnectionsOnly.
  ///
  /// In en, this message translates to:
  /// **'Connections only'**
  String get socialProfileManageVisibilityConnectionsOnly;

  /// No description provided for @socialProfileManageUpgradeStatusSummary.
  ///
  /// In en, this message translates to:
  /// **'View plans and upgrade status'**
  String get socialProfileManageUpgradeStatusSummary;

  /// No description provided for @socialProfileManageUpgradeStatusActive.
  ///
  /// In en, this message translates to:
  /// **'You have an active upgrade'**
  String get socialProfileManageUpgradeStatusActive;

  /// No description provided for @socialProfileManageUpgradeStatusRequests.
  ///
  /// In en, this message translates to:
  /// **'You have current or past upgrade requests'**
  String get socialProfileManageUpgradeStatusRequests;

  /// No description provided for @socialCallTitle.
  ///
  /// In en, this message translates to:
  /// **'Private call'**
  String get socialCallTitle;

  /// No description provided for @socialCallInitializing.
  ///
  /// In en, this message translates to:
  /// **'Preparing the call...'**
  String get socialCallInitializing;

  /// No description provided for @socialCallIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming call...'**
  String get socialCallIncoming;

  /// No description provided for @socialCallDialingPeer.
  ///
  /// In en, this message translates to:
  /// **'Calling the other participant...'**
  String get socialCallDialingPeer;

  /// No description provided for @socialCallMicrophonePermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required to continue the call.'**
  String get socialCallMicrophonePermissionRequired;

  /// No description provided for @socialCallStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The call could not be started inside the app.'**
  String get socialCallStartFailed;

  /// No description provided for @socialCallConnectionInterrupted.
  ///
  /// In en, this message translates to:
  /// **'The connection was interrupted. Trying to recover...'**
  String get socialCallConnectionInterrupted;

  /// No description provided for @socialCallReconnectRetrying.
  ///
  /// In en, this message translates to:
  /// **'The call failed. Trying again...'**
  String get socialCallReconnectRetrying;

  /// No description provided for @socialCallEnded.
  ///
  /// In en, this message translates to:
  /// **'The call has ended.'**
  String get socialCallEnded;

  /// No description provided for @socialCallRinging.
  ///
  /// In en, this message translates to:
  /// **'Ringing...'**
  String get socialCallRinging;

  /// No description provided for @socialCallMissedTimeout.
  ///
  /// In en, this message translates to:
  /// **'No one answered before the call timed out.'**
  String get socialCallMissedTimeout;

  /// No description provided for @socialCallDeclined.
  ///
  /// In en, this message translates to:
  /// **'The call was declined.'**
  String get socialCallDeclined;

  /// No description provided for @socialCallAnsweredConnectingAudio.
  ///
  /// In en, this message translates to:
  /// **'Answered. Connecting audio...'**
  String get socialCallAnsweredConnectingAudio;

  /// No description provided for @socialCallRecovering.
  ///
  /// In en, this message translates to:
  /// **'Re-establishing the call...'**
  String get socialCallRecovering;

  /// No description provided for @socialCallRecoverFailed.
  ///
  /// In en, this message translates to:
  /// **'The call cannot be recovered right now.'**
  String get socialCallRecoverFailed;

  /// No description provided for @socialCallConnected.
  ///
  /// In en, this message translates to:
  /// **'Call connected'**
  String get socialCallConnected;

  /// No description provided for @socialCallPeerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The other participant is not available right now.'**
  String get socialCallPeerUnavailable;

  /// No description provided for @socialCallSessionNotFound.
  ///
  /// In en, this message translates to:
  /// **'The call session was not found or already ended.'**
  String get socialCallSessionNotFound;

  /// No description provided for @socialCallForbidden.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to call this user.'**
  String get socialCallForbidden;

  /// No description provided for @socialCallGenericError.
  ///
  /// In en, this message translates to:
  /// **'The call could not be started. Check the network and try again.'**
  String get socialCallGenericError;

  /// No description provided for @socialCallParticipantFallback.
  ///
  /// In en, this message translates to:
  /// **'Another user'**
  String get socialCallParticipantFallback;

  /// No description provided for @socialCallOtherParticipant.
  ///
  /// In en, this message translates to:
  /// **'The other participant'**
  String get socialCallOtherParticipant;

  /// No description provided for @socialCallIncomingHeadline.
  ///
  /// In en, this message translates to:
  /// **'{name} is calling you'**
  String socialCallIncomingHeadline(String name);

  /// No description provided for @socialCallDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get socialCallDecline;

  /// No description provided for @socialCallAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get socialCallAnswer;

  /// No description provided for @socialCallMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get socialCallMute;

  /// No description provided for @socialCallUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get socialCallUnmute;

  /// No description provided for @socialCallSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get socialCallSpeaker;

  /// No description provided for @socialCallEarpiece.
  ///
  /// In en, this message translates to:
  /// **'Earpiece'**
  String get socialCallEarpiece;

  /// No description provided for @socialCallHangup.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get socialCallHangup;

  /// No description provided for @socialActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get socialActivityTitle;

  /// No description provided for @socialActivityEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No social activity'**
  String get socialActivityEmptyTitle;

  /// No description provided for @socialActivityEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Likes, comments, mentions, and social requests will appear here.'**
  String get socialActivityEmptyBody;

  /// No description provided for @socialActivityLikes.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get socialActivityLikes;

  /// No description provided for @socialActivityMentions.
  ///
  /// In en, this message translates to:
  /// **'Mentions'**
  String get socialActivityMentions;

  /// No description provided for @socialActivityReels.
  ///
  /// In en, this message translates to:
  /// **'Reels'**
  String get socialActivityReels;

  /// No description provided for @socialActivityPosts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get socialActivityPosts;

  /// No description provided for @socialActivityStories.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get socialActivityStories;

  /// No description provided for @socialActivityRelations.
  ///
  /// In en, this message translates to:
  /// **'Relations'**
  String get socialActivityRelations;

  /// No description provided for @socialActivityUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get socialActivityUnread;

  /// No description provided for @socialActivityEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get socialActivityEarlier;

  /// No description provided for @socialActivityOpenLinkedContentFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the linked content.'**
  String get socialActivityOpenLinkedContentFailed;

  /// No description provided for @socialActivityConnectionRequests.
  ///
  /// In en, this message translates to:
  /// **'Connection requests'**
  String get socialActivityConnectionRequests;

  /// No description provided for @socialActivityMessageRequests.
  ///
  /// In en, this message translates to:
  /// **'Message requests'**
  String get socialActivityMessageRequests;

  /// No description provided for @socialActivityItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String socialActivityItemsCount(int count);

  /// No description provided for @socialActivityLike.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get socialActivityLike;

  /// No description provided for @socialActivityComment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get socialActivityComment;

  /// No description provided for @socialActivityMention.
  ///
  /// In en, this message translates to:
  /// **'Mention'**
  String get socialActivityMention;

  /// No description provided for @socialActivityReel.
  ///
  /// In en, this message translates to:
  /// **'Reel'**
  String get socialActivityReel;

  /// No description provided for @socialActivityStory.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get socialActivityStory;

  /// No description provided for @socialActivityRelation.
  ///
  /// In en, this message translates to:
  /// **'Relation'**
  String get socialActivityRelation;

  /// No description provided for @socialActivityActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get socialActivityActivity;

  /// No description provided for @socialActivityMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String socialActivityMinutesAgo(int count);

  /// No description provided for @socialActivityHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String socialActivityHoursAgo(int count);

  /// No description provided for @socialActivityDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String socialActivityDaysAgo(int count);

  /// No description provided for @socialProfileActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile activity'**
  String get socialProfileActivityTitle;

  /// No description provided for @socialProfileActivityContentTitle.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get socialProfileActivityContentTitle;

  /// No description provided for @socialProfileActivityContentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open images, reels, reviews, and highlights directly.'**
  String get socialProfileActivityContentSubtitle;

  /// No description provided for @socialProfileActivityFrequentMerchants.
  ///
  /// In en, this message translates to:
  /// **'Frequent merchants'**
  String get socialProfileActivityFrequentMerchants;

  /// No description provided for @socialProfileActivityEngagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Engagement'**
  String get socialProfileActivityEngagementTitle;

  /// No description provided for @socialProfileActivityEngagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review outgoing and incoming likes and comments in one place.'**
  String get socialProfileActivityEngagementSubtitle;

  /// No description provided for @socialProfileActivityOpenInsights.
  ///
  /// In en, this message translates to:
  /// **'Open insights'**
  String get socialProfileActivityOpenInsights;

  /// No description provided for @socialProfileActivityImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get socialProfileActivityImages;

  /// No description provided for @socialProfileActivityReels.
  ///
  /// In en, this message translates to:
  /// **'Reels'**
  String get socialProfileActivityReels;

  /// No description provided for @socialProfileActivityReviews.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get socialProfileActivityReviews;

  /// No description provided for @socialProfileActivityHighlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get socialProfileActivityHighlights;

  /// No description provided for @socialProfileActivityFriends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get socialProfileActivityFriends;

  /// No description provided for @socialProfileActivitySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get socialProfileActivitySaved;

  /// No description provided for @socialProfileActivityLikesReceived.
  ///
  /// In en, this message translates to:
  /// **'Likes received'**
  String get socialProfileActivityLikesReceived;

  /// No description provided for @socialProfileActivityCommentsReceived.
  ///
  /// In en, this message translates to:
  /// **'Comments received'**
  String get socialProfileActivityCommentsReceived;

  /// No description provided for @socialProfileActivityLikesMade.
  ///
  /// In en, this message translates to:
  /// **'Likes made'**
  String get socialProfileActivityLikesMade;

  /// No description provided for @socialProfileActivityCommentsMade.
  ///
  /// In en, this message translates to:
  /// **'Comments made'**
  String get socialProfileActivityCommentsMade;

  /// No description provided for @socialProfileActivityTagged.
  ///
  /// In en, this message translates to:
  /// **'Tagged'**
  String get socialProfileActivityTagged;

  /// No description provided for @socialProfileActivityActiveStories.
  ///
  /// In en, this message translates to:
  /// **'Active stories'**
  String get socialProfileActivityActiveStories;

  /// No description provided for @adminCollectionsReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Collections Report'**
  String get adminCollectionsReportTitle;

  /// No description provided for @adminCollectionsReportLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load collections report'**
  String get adminCollectionsReportLoadFailed;

  /// No description provided for @adminCollectionsReportTotalCollected.
  ///
  /// In en, this message translates to:
  /// **'Total collected'**
  String get adminCollectionsReportTotalCollected;

  /// No description provided for @adminCollectionsReportFirstCollection.
  ///
  /// In en, this message translates to:
  /// **'First collection'**
  String get adminCollectionsReportFirstCollection;

  /// No description provided for @adminCollectionsReportLastCollection.
  ///
  /// In en, this message translates to:
  /// **'Last collection'**
  String get adminCollectionsReportLastCollection;

  /// No description provided for @adminCollectionsReportNoData.
  ///
  /// In en, this message translates to:
  /// **'No collections data'**
  String get adminCollectionsReportNoData;

  /// No description provided for @adminSalesReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales Report'**
  String get adminSalesReportTitle;

  /// No description provided for @adminSalesReportLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load sales report'**
  String get adminSalesReportLoadFailed;

  /// No description provided for @adminSalesReportTotalSales.
  ///
  /// In en, this message translates to:
  /// **'Total sales'**
  String get adminSalesReportTotalSales;

  /// No description provided for @adminSalesReportFirstOrder.
  ///
  /// In en, this message translates to:
  /// **'First order'**
  String get adminSalesReportFirstOrder;

  /// No description provided for @adminSalesReportLastOrder.
  ///
  /// In en, this message translates to:
  /// **'Last order'**
  String get adminSalesReportLastOrder;

  /// No description provided for @adminSalesReportNoData.
  ///
  /// In en, this message translates to:
  /// **'No sales data'**
  String get adminSalesReportNoData;

  /// No description provided for @adminMerchantBillingApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'Merchant Financial Approval'**
  String get adminMerchantBillingApprovalTitle;

  /// No description provided for @adminMerchantBillingSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Merchant Billing Settings'**
  String get adminMerchantBillingSettingsTitle;

  /// No description provided for @adminMerchantBillingFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed'**
  String get adminMerchantBillingFixed;

  /// No description provided for @adminMerchantBillingPercentage.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get adminMerchantBillingPercentage;

  /// No description provided for @adminMerchantBillingPerOrder.
  ///
  /// In en, this message translates to:
  /// **'Per order'**
  String get adminMerchantBillingPerOrder;

  /// No description provided for @adminMerchantBillingGlobalRule.
  ///
  /// In en, this message translates to:
  /// **'Global rule'**
  String get adminMerchantBillingGlobalRule;

  /// No description provided for @adminMerchantBillingAppDefined.
  ///
  /// In en, this message translates to:
  /// **'App defined'**
  String get adminMerchantBillingAppDefined;

  /// No description provided for @adminMerchantBillingStoreDefined.
  ///
  /// In en, this message translates to:
  /// **'Store defined'**
  String get adminMerchantBillingStoreDefined;

  /// No description provided for @adminMerchantBillingDynamic.
  ///
  /// In en, this message translates to:
  /// **'Dynamic'**
  String get adminMerchantBillingDynamic;

  /// No description provided for @adminMerchantBillingSentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Financial terms sent to the merchant.'**
  String get adminMerchantBillingSentSuccess;

  /// No description provided for @adminMerchantBillingSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Billing policy saved successfully.'**
  String get adminMerchantBillingSavedSuccess;

  /// No description provided for @adminMerchantBillingSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save the financial policy.'**
  String get adminMerchantBillingSaveFailed;

  /// No description provided for @adminMerchantBillingCommissionType.
  ///
  /// In en, this message translates to:
  /// **'Commission type'**
  String get adminMerchantBillingCommissionType;

  /// No description provided for @adminMerchantBillingCommissionValuePercentage.
  ///
  /// In en, this message translates to:
  /// **'Commission value (%)'**
  String get adminMerchantBillingCommissionValuePercentage;

  /// No description provided for @adminMerchantBillingCommissionValueFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed commission value'**
  String get adminMerchantBillingCommissionValueFixed;

  /// No description provided for @adminMerchantBillingInvalidValue.
  ///
  /// In en, this message translates to:
  /// **'Invalid value'**
  String get adminMerchantBillingInvalidValue;

  /// No description provided for @adminMerchantBillingRateRange.
  ///
  /// In en, this message translates to:
  /// **'Rate must be between 0 and 100'**
  String get adminMerchantBillingRateRange;

  /// No description provided for @adminMerchantBillingServiceFeeType.
  ///
  /// In en, this message translates to:
  /// **'Service fee type'**
  String get adminMerchantBillingServiceFeeType;

  /// No description provided for @adminMerchantBillingServiceFeeValue.
  ///
  /// In en, this message translates to:
  /// **'Service fee value'**
  String get adminMerchantBillingServiceFeeValue;

  /// No description provided for @adminMerchantBillingDeliveryFeeMode.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee mode'**
  String get adminMerchantBillingDeliveryFeeMode;

  /// No description provided for @adminMerchantBillingAppDeliveryFeeValue.
  ///
  /// In en, this message translates to:
  /// **'App delivery fee value'**
  String get adminMerchantBillingAppDeliveryFeeValue;

  /// No description provided for @adminMerchantBillingStoreDeliveryFeeValue.
  ///
  /// In en, this message translates to:
  /// **'Store delivery fee value'**
  String get adminMerchantBillingStoreDeliveryFeeValue;

  /// No description provided for @adminMerchantBillingEnableAppDelivery.
  ///
  /// In en, this message translates to:
  /// **'Enable app delivery'**
  String get adminMerchantBillingEnableAppDelivery;

  /// No description provided for @adminMerchantBillingEnableMerchantDelivery.
  ///
  /// In en, this message translates to:
  /// **'Enable merchant delivery'**
  String get adminMerchantBillingEnableMerchantDelivery;

  /// No description provided for @adminMerchantBillingGracePeriodDays.
  ///
  /// In en, this message translates to:
  /// **'Grace period days'**
  String get adminMerchantBillingGracePeriodDays;

  /// No description provided for @adminMerchantBillingEffectiveFrom.
  ///
  /// In en, this message translates to:
  /// **'Effective from'**
  String get adminMerchantBillingEffectiveFrom;

  /// No description provided for @adminMerchantBillingSendTerms.
  ///
  /// In en, this message translates to:
  /// **'Send Terms To Merchant'**
  String get adminMerchantBillingSendTerms;

  /// No description provided for @adminMerchantBillingSaveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save Financial Settings'**
  String get adminMerchantBillingSaveSettings;

  /// No description provided for @adminTaxiCaptainRequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Taxi captain requests'**
  String get adminTaxiCaptainRequestsTitle;

  /// No description provided for @adminTaxiCaptainApprovalsTab.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get adminTaxiCaptainApprovalsTab;

  /// No description provided for @adminTaxiCaptainProfileEditsTab.
  ///
  /// In en, this message translates to:
  /// **'Profile edits'**
  String get adminTaxiCaptainProfileEditsTab;

  /// No description provided for @adminTaxiCaptainReviewEditRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Review profile edit request'**
  String get adminTaxiCaptainReviewEditRequestTitle;

  /// No description provided for @adminTaxiCaptainCurrentProfile.
  ///
  /// In en, this message translates to:
  /// **'Current profile'**
  String get adminTaxiCaptainCurrentProfile;

  /// No description provided for @adminTaxiCaptainRequestedChanges.
  ///
  /// In en, this message translates to:
  /// **'Requested changes'**
  String get adminTaxiCaptainRequestedChanges;

  /// No description provided for @adminTaxiCaptainAdminNote.
  ///
  /// In en, this message translates to:
  /// **'Admin note'**
  String get adminTaxiCaptainAdminNote;

  /// No description provided for @adminTaxiCaptainNoPendingApprovals.
  ///
  /// In en, this message translates to:
  /// **'No pending captain approvals.'**
  String get adminTaxiCaptainNoPendingApprovals;

  /// No description provided for @adminTaxiCaptainNoPendingProfileEdits.
  ///
  /// In en, this message translates to:
  /// **'No pending profile edits.'**
  String get adminTaxiCaptainNoPendingProfileEdits;

  /// No description provided for @adminTaxiCaptainChangedFields.
  ///
  /// In en, this message translates to:
  /// **'Changed fields: {count}'**
  String adminTaxiCaptainChangedFields(int count);

  /// No description provided for @deliveryOrderChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Order chat #{orderId}'**
  String deliveryOrderChatTitle(int orderId);

  /// No description provided for @deliveryRequestOrderCancelTitle.
  ///
  /// In en, this message translates to:
  /// **'Request order cancel'**
  String get deliveryRequestOrderCancelTitle;

  /// No description provided for @deliveryCancellationReason.
  ///
  /// In en, this message translates to:
  /// **'Cancellation reason'**
  String get deliveryCancellationReason;

  /// No description provided for @deliveryCancellationReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Write the reason so it can be reviewed by merchant or admin'**
  String get deliveryCancellationReasonHint;

  /// No description provided for @deliveryOrderCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Order #{orderId} - {status}'**
  String deliveryOrderCardTitle(int orderId, String status);

  /// No description provided for @deliveryMerchantLine.
  ///
  /// In en, this message translates to:
  /// **'Merchant: {name}'**
  String deliveryMerchantLine(String name);

  /// No description provided for @deliveryCustomerLine.
  ///
  /// In en, this message translates to:
  /// **'Customer: {name} - {phone}'**
  String deliveryCustomerLine(String name, String phone);

  /// No description provided for @deliveryCustomerLocation.
  ///
  /// In en, this message translates to:
  /// **'Customer location: {city} - Block {block} - Building {building} - Apartment {apartment}'**
  String deliveryCustomerLocation(
    String city,
    String block,
    String building,
    String apartment,
  );

  /// No description provided for @deliveryOrderItemsCount.
  ///
  /// In en, this message translates to:
  /// **'Items count: {count}'**
  String deliveryOrderItemsCount(int count);

  /// No description provided for @deliveryOrderPriceLine.
  ///
  /// In en, this message translates to:
  /// **'Order price: {price}'**
  String deliveryOrderPriceLine(String price);

  /// No description provided for @deliveryOrderDiscountLine.
  ///
  /// In en, this message translates to:
  /// **'Total discount: {amount}'**
  String deliveryOrderDiscountLine(String amount);

  /// No description provided for @deliveryPriceAfterDiscountLine.
  ///
  /// In en, this message translates to:
  /// **'Price after discount: {price}'**
  String deliveryPriceAfterDiscountLine(String price);

  /// No description provided for @deliveryDeliveryFeeLine.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee: {fee}'**
  String deliveryDeliveryFeeLine(String fee);

  /// No description provided for @deliveryOrderImageLabel.
  ///
  /// In en, this message translates to:
  /// **'Order image'**
  String get deliveryOrderImageLabel;

  /// No description provided for @deliveryWaitingMerchantPrepare.
  ///
  /// In en, this message translates to:
  /// **'Waiting for merchant to prepare the order'**
  String get deliveryWaitingMerchantPrepare;

  /// No description provided for @deliveryChatCustomer.
  ///
  /// In en, this message translates to:
  /// **'Chat customer'**
  String get deliveryChatCustomer;

  /// No description provided for @deliveryCancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get deliveryCancelRequest;

  /// No description provided for @deliveryHistoryOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'Order #{orderId} - {name}'**
  String deliveryHistoryOrderTitle(int orderId, String name);

  /// No description provided for @deliveryHistoryOrderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Merchant: {merchant} - Total: {total}'**
  String deliveryHistoryOrderSubtitle(String merchant, String total);

  /// No description provided for @jobsMyApplicationsTitle.
  ///
  /// In en, this message translates to:
  /// **'My job applications'**
  String get jobsMyApplicationsTitle;

  /// No description provided for @jobsMyApplicationsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load your job applications.'**
  String get jobsMyApplicationsLoadFailed;

  /// No description provided for @jobsMyApplicationsTabReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get jobsMyApplicationsTabReceived;

  /// No description provided for @jobsMyApplicationsTabShortlisted.
  ///
  /// In en, this message translates to:
  /// **'Shortlisted'**
  String get jobsMyApplicationsTabShortlisted;

  /// No description provided for @jobsMyApplicationsTabHired.
  ///
  /// In en, this message translates to:
  /// **'Hired'**
  String get jobsMyApplicationsTabHired;

  /// No description provided for @jobsMyApplicationsTabRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get jobsMyApplicationsTabRejected;

  /// No description provided for @jobsMyApplicationsTabWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Withdrawn'**
  String get jobsMyApplicationsTabWithdrawn;

  /// No description provided for @jobsMyApplicationsTabDismissed.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get jobsMyApplicationsTabDismissed;

  /// No description provided for @jobsMyApplicationsTabArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get jobsMyApplicationsTabArchived;

  /// No description provided for @jobsMyApplicationsStatusReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get jobsMyApplicationsStatusReceived;

  /// No description provided for @jobsMyApplicationsStatusShortlisted.
  ///
  /// In en, this message translates to:
  /// **'Shortlisted'**
  String get jobsMyApplicationsStatusShortlisted;

  /// No description provided for @jobsMyApplicationsStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get jobsMyApplicationsStatusRejected;

  /// No description provided for @jobsMyApplicationsStatusHired.
  ///
  /// In en, this message translates to:
  /// **'Hired'**
  String get jobsMyApplicationsStatusHired;

  /// No description provided for @jobsMyApplicationsStatusWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Withdrawn'**
  String get jobsMyApplicationsStatusWithdrawn;

  /// No description provided for @jobsMyApplicationsStatusDismissed.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get jobsMyApplicationsStatusDismissed;

  /// No description provided for @jobsMyApplicationsStatusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get jobsMyApplicationsStatusArchived;

  /// No description provided for @jobsMyApplicationsWithdrawReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal reason'**
  String get jobsMyApplicationsWithdrawReasonTitle;

  /// No description provided for @jobsMyApplicationsWithdrawReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Write the reason...'**
  String get jobsMyApplicationsWithdrawReasonHint;

  /// No description provided for @jobsMyApplicationsWithdrawSuccess.
  ///
  /// In en, this message translates to:
  /// **'Application withdrawn successfully.'**
  String get jobsMyApplicationsWithdrawSuccess;

  /// No description provided for @jobsMyApplicationsWithdrawFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to withdraw the application.'**
  String get jobsMyApplicationsWithdrawFailed;

  /// No description provided for @jobsMyApplicationsAcceptOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm job offer acceptance'**
  String get jobsMyApplicationsAcceptOfferTitle;

  /// No description provided for @jobsMyApplicationsOfferDetails.
  ///
  /// In en, this message translates to:
  /// **'Offer details'**
  String get jobsMyApplicationsOfferDetails;

  /// No description provided for @jobsMyApplicationsOfferAttachmentAvailable.
  ///
  /// In en, this message translates to:
  /// **'An offer attachment is available. You can open it from application details.'**
  String get jobsMyApplicationsOfferAttachmentAvailable;

  /// No description provided for @jobsMyApplicationsUploadSignedOffer.
  ///
  /// In en, this message translates to:
  /// **'Upload signed offer'**
  String get jobsMyApplicationsUploadSignedOffer;

  /// No description provided for @jobsMyApplicationsChooseAttachment.
  ///
  /// In en, this message translates to:
  /// **'Choose attachment'**
  String get jobsMyApplicationsChooseAttachment;

  /// No description provided for @jobsMyApplicationsChangeAttachment.
  ///
  /// In en, this message translates to:
  /// **'Change attachment'**
  String get jobsMyApplicationsChangeAttachment;

  /// No description provided for @jobsMyApplicationsSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting...'**
  String get jobsMyApplicationsSubmitting;

  /// No description provided for @jobsMyApplicationsAcceptOfferAction.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get jobsMyApplicationsAcceptOfferAction;

  /// No description provided for @jobsMyApplicationsOfferAcceptedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Offer accepted and your work profile was updated.'**
  String get jobsMyApplicationsOfferAcceptedSuccess;

  /// No description provided for @jobsMyApplicationsOfferAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to accept the offer now. Please try again later.'**
  String get jobsMyApplicationsOfferAcceptFailed;

  /// No description provided for @jobsMyApplicationsNoApplications.
  ///
  /// In en, this message translates to:
  /// **'No applications in this filter currently.'**
  String get jobsMyApplicationsNoApplications;

  /// No description provided for @jobsMyApplicationsJobFallback.
  ///
  /// In en, this message translates to:
  /// **'Job'**
  String get jobsMyApplicationsJobFallback;

  /// No description provided for @jobsMyApplicationsCompanyFallback.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get jobsMyApplicationsCompanyFallback;

  /// No description provided for @jobsMyApplicationsStatusReason.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String jobsMyApplicationsStatusReason(String reason);

  /// No description provided for @jobsMyApplicationsWithdrawAction.
  ///
  /// In en, this message translates to:
  /// **'Withdraw application'**
  String get jobsMyApplicationsWithdrawAction;

  /// No description provided for @jobsMyApplicationsOfferSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Job offer'**
  String get jobsMyApplicationsOfferSectionTitle;

  /// No description provided for @jobsMyApplicationsOfferSalaryLine.
  ///
  /// In en, this message translates to:
  /// **'Salary: {salary}'**
  String jobsMyApplicationsOfferSalaryLine(String salary);

  /// No description provided for @jobsMyApplicationsOfferWorkHoursLine.
  ///
  /// In en, this message translates to:
  /// **'Hours: {hours}'**
  String jobsMyApplicationsOfferWorkHoursLine(String hours);

  /// No description provided for @jobsMyApplicationsOfferWorkDaysLine.
  ///
  /// In en, this message translates to:
  /// **'Days: {days}'**
  String jobsMyApplicationsOfferWorkDaysLine(String days);

  /// No description provided for @jobsMyApplicationsOfferAcceptedAtLine.
  ///
  /// In en, this message translates to:
  /// **'Accepted at: {dateTime}'**
  String jobsMyApplicationsOfferAcceptedAtLine(String dateTime);

  /// No description provided for @jobsMyApplicationsSubmittingAcceptance.
  ///
  /// In en, this message translates to:
  /// **'Confirming acceptance...'**
  String get jobsMyApplicationsSubmittingAcceptance;

  /// No description provided for @jobsMyApplicationsAcceptOfferButton.
  ///
  /// In en, this message translates to:
  /// **'Accept the job offer'**
  String get jobsMyApplicationsAcceptOfferButton;

  /// No description provided for @socialReportedContentTitle.
  ///
  /// In en, this message translates to:
  /// **'Content needing edits'**
  String get socialReportedContentTitle;

  /// No description provided for @socialReportedContentLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load content that needs edits.'**
  String get socialReportedContentLoadFailed;

  /// No description provided for @socialReportedWriteRevisedText.
  ///
  /// In en, this message translates to:
  /// **'Write the revised text'**
  String get socialReportedWriteRevisedText;

  /// No description provided for @socialReportedNewMediaLabel.
  ///
  /// In en, this message translates to:
  /// **'New media: {name}'**
  String socialReportedNewMediaLabel(String name);

  /// No description provided for @socialReportedCurrentMediaExists.
  ///
  /// In en, this message translates to:
  /// **'Current media exists. You can replace or remove it before resubmitting.'**
  String get socialReportedCurrentMediaExists;

  /// No description provided for @socialReportedCurrentMediaWillBeRemoved.
  ///
  /// In en, this message translates to:
  /// **'Current media will be removed on submit.'**
  String get socialReportedCurrentMediaWillBeRemoved;

  /// No description provided for @socialReportedChangeImageOrVideo.
  ///
  /// In en, this message translates to:
  /// **'Change image or video'**
  String get socialReportedChangeImageOrVideo;

  /// No description provided for @socialReportedRemoveMedia.
  ///
  /// In en, this message translates to:
  /// **'Remove media'**
  String get socialReportedRemoveMedia;

  /// No description provided for @socialReportedSubmitEdit.
  ///
  /// In en, this message translates to:
  /// **'Submit edit'**
  String get socialReportedSubmitEdit;

  /// No description provided for @socialReportedEditPostTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit and resubmit post'**
  String get socialReportedEditPostTitle;

  /// No description provided for @socialReportedEditStoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit and resubmit story'**
  String get socialReportedEditStoryTitle;

  /// No description provided for @socialReportedCannotSubmitEmptyPost.
  ///
  /// In en, this message translates to:
  /// **'Cannot submit an empty post. Add text or media.'**
  String get socialReportedCannotSubmitEmptyPost;

  /// No description provided for @socialReportedCannotSubmitEmptyStory.
  ///
  /// In en, this message translates to:
  /// **'Cannot submit an empty story. Add text or media.'**
  String get socialReportedCannotSubmitEmptyStory;

  /// No description provided for @socialReportedPostSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Post edit submitted for review.'**
  String get socialReportedPostSubmitted;

  /// No description provided for @socialReportedPostSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit post edit.'**
  String get socialReportedPostSubmitFailed;

  /// No description provided for @socialReportedStorySubmitted.
  ///
  /// In en, this message translates to:
  /// **'Story edit submitted for review.'**
  String get socialReportedStorySubmitted;

  /// No description provided for @socialReportedStorySubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit story edit.'**
  String get socialReportedStorySubmitFailed;

  /// No description provided for @socialReportedPostsTab.
  ///
  /// In en, this message translates to:
  /// **'Posts ({count})'**
  String socialReportedPostsTab(int count);

  /// No description provided for @socialReportedStoriesTab.
  ///
  /// In en, this message translates to:
  /// **'Stories ({count})'**
  String socialReportedStoriesTab(int count);

  /// No description provided for @socialReportedNoPostsTitle.
  ///
  /// In en, this message translates to:
  /// **'No posts need edits.'**
  String get socialReportedNoPostsTitle;

  /// No description provided for @socialReportedNoPostsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Posts that need edits will appear here.'**
  String get socialReportedNoPostsSubtitle;

  /// No description provided for @socialReportedNoStoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'No stories need edits.'**
  String get socialReportedNoStoriesTitle;

  /// No description provided for @socialReportedNoStoriesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stories that need edits will appear here.'**
  String get socialReportedNoStoriesSubtitle;

  /// No description provided for @socialReportedPostType.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get socialReportedPostType;

  /// No description provided for @socialReportedStoryType.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get socialReportedStoryType;

  /// No description provided for @socialReportedEditAndResubmit.
  ///
  /// In en, this message translates to:
  /// **'Edit & resubmit'**
  String get socialReportedEditAndResubmit;

  /// No description provided for @socialReportedStatusPendingReview.
  ///
  /// In en, this message translates to:
  /// **'Pending review'**
  String get socialReportedStatusPendingReview;

  /// No description provided for @socialReportedStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get socialReportedStatusApproved;

  /// No description provided for @socialReportedStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get socialReportedStatusRejected;

  /// No description provided for @socialReportedVideoAttached.
  ///
  /// In en, this message translates to:
  /// **'Video attached to this content'**
  String get socialReportedVideoAttached;

  /// No description provided for @socialReportedMediaLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load media'**
  String get socialReportedMediaLoadFailed;

  /// No description provided for @adminMerchantStateManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Merchant state management'**
  String get adminMerchantStateManagementTitle;

  /// No description provided for @adminMerchantStateSearch.
  ///
  /// In en, this message translates to:
  /// **'Search merchants'**
  String get adminMerchantStateSearch;

  /// No description provided for @adminMerchantStateActiveFilter.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get adminMerchantStateActiveFilter;

  /// No description provided for @adminMerchantStateDisabledFilter.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get adminMerchantStateDisabledFilter;

  /// No description provided for @adminMerchantStateNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matching merchants.'**
  String get adminMerchantStateNoMatches;

  /// No description provided for @adminMerchantStateTypeLine.
  ///
  /// In en, this message translates to:
  /// **'Type: {type}'**
  String adminMerchantStateTypeLine(String type);

  /// No description provided for @adminMerchantStateOwnerLine.
  ///
  /// In en, this message translates to:
  /// **'Owner: {owner}'**
  String adminMerchantStateOwnerLine(String owner);

  /// No description provided for @adminMerchantStateApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get adminMerchantStateApproved;

  /// No description provided for @adminMerchantStatePendingApproval.
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get adminMerchantStatePendingApproval;

  /// No description provided for @adminMerchantStateDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get adminMerchantStateDisabled;

  /// No description provided for @adminMerchantStateEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get adminMerchantStateEnabled;

  /// No description provided for @adminMerchantStateOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get adminMerchantStateOpen;

  /// No description provided for @adminMerchantStateClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get adminMerchantStateClosed;

  /// No description provided for @adminMerchantStateTodayOrders.
  ///
  /// In en, this message translates to:
  /// **'Today orders: {count}'**
  String adminMerchantStateTodayOrders(int count);

  /// No description provided for @adminMerchantStateBillingProfile.
  ///
  /// In en, this message translates to:
  /// **'Billing profile'**
  String get adminMerchantStateBillingProfile;

  /// No description provided for @socialSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Social search'**
  String get socialSearchTitle;

  /// No description provided for @socialSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search people, reels, hashtags, or merchants'**
  String get socialSearchHint;

  /// No description provided for @socialSearchRecentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get socialSearchRecentSearches;

  /// No description provided for @socialSearchSuggestedPeople.
  ///
  /// In en, this message translates to:
  /// **'Suggested people'**
  String get socialSearchSuggestedPeople;

  /// No description provided for @socialSearchUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get socialSearchUsers;

  /// No description provided for @socialSearchPosts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get socialSearchPosts;

  /// No description provided for @socialSearchReels.
  ///
  /// In en, this message translates to:
  /// **'Reels'**
  String get socialSearchReels;

  /// No description provided for @socialSearchHashtags.
  ///
  /// In en, this message translates to:
  /// **'Hashtags'**
  String get socialSearchHashtags;

  /// No description provided for @socialSearchMerchants.
  ///
  /// In en, this message translates to:
  /// **'Merchants'**
  String get socialSearchMerchants;

  /// No description provided for @socialSearchReviews.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get socialSearchReviews;

  /// No description provided for @deliveryOfferNewRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'New delivery request'**
  String get deliveryOfferNewRequestTitle;

  /// No description provided for @deliveryOfferOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'Order #{orderId}'**
  String deliveryOfferOrderTitle(int orderId);

  /// No description provided for @deliveryOfferExpired.
  ///
  /// In en, this message translates to:
  /// **'This offer is no longer available.'**
  String get deliveryOfferExpired;

  /// No description provided for @deliveryOfferReviewPrompt.
  ///
  /// In en, this message translates to:
  /// **'Review the offer now and respond immediately.'**
  String get deliveryOfferReviewPrompt;

  /// No description provided for @deliveryOfferExpiredHint.
  ///
  /// In en, this message translates to:
  /// **'Another courier may have claimed this offer, or it may have expired.'**
  String get deliveryOfferExpiredHint;

  /// No description provided for @deliveryOfferPickupPoint.
  ///
  /// In en, this message translates to:
  /// **'Pickup point'**
  String get deliveryOfferPickupPoint;

  /// No description provided for @deliveryOfferDropOffPoint.
  ///
  /// In en, this message translates to:
  /// **'Drop-off'**
  String get deliveryOfferDropOffPoint;

  /// No description provided for @deliveryOfferEstimatedDistance.
  ///
  /// In en, this message translates to:
  /// **'Estimated distance'**
  String get deliveryOfferEstimatedDistance;

  /// No description provided for @deliveryOfferAcceptRequest.
  ///
  /// In en, this message translates to:
  /// **'Accept request'**
  String get deliveryOfferAcceptRequest;

  /// No description provided for @deliveryOfferRejectRequest.
  ///
  /// In en, this message translates to:
  /// **'Reject request'**
  String get deliveryOfferRejectRequest;

  /// No description provided for @deliveryOfferLiveHint.
  ///
  /// In en, this message translates to:
  /// **'The offer stays live here. If another courier claims it first, this screen will reflect that.'**
  String get deliveryOfferLiveHint;

  /// No description provided for @ownerCouriersTitle.
  ///
  /// In en, this message translates to:
  /// **'Merchant couriers'**
  String get ownerCouriersTitle;

  /// No description provided for @ownerCouriersAddCourierButton.
  ///
  /// In en, this message translates to:
  /// **'Add courier'**
  String get ownerCouriersAddCourierButton;

  /// No description provided for @ownerCouriersNoAppCouriersFound.
  ///
  /// In en, this message translates to:
  /// **'No app couriers found'**
  String get ownerCouriersNoAppCouriersFound;

  /// No description provided for @ownerCouriersAddMerchantCourier.
  ///
  /// In en, this message translates to:
  /// **'Add merchant courier'**
  String get ownerCouriersAddMerchantCourier;

  /// No description provided for @ownerCouriersSelectCourier.
  ///
  /// In en, this message translates to:
  /// **'Select courier'**
  String get ownerCouriersSelectCourier;

  /// No description provided for @ownerCouriersAddedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Courier added'**
  String get ownerCouriersAddedSuccess;

  /// No description provided for @ownerCouriersAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Add failed'**
  String get ownerCouriersAddFailed;

  /// No description provided for @ownerCouriersEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No merchant couriers yet'**
  String get ownerCouriersEmptyState;

  /// No description provided for @ownerCouriersFallbackName.
  ///
  /// In en, this message translates to:
  /// **'Courier #{userId}'**
  String ownerCouriersFallbackName(int userId);

  /// No description provided for @ownerCouriersActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get ownerCouriersActive;

  /// No description provided for @ownerCouriersDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get ownerCouriersDisabled;

  /// No description provided for @ownerCouriersDisable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get ownerCouriersDisable;

  /// No description provided for @ownerCouriersEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get ownerCouriersEnable;

  /// No description provided for @ownerCouriersAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get ownerCouriersAvailable;

  /// No description provided for @ownerCouriersAvailabilityAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get ownerCouriersAvailabilityAvailable;

  /// No description provided for @ownerCouriersAvailabilityBusy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get ownerCouriersAvailabilityBusy;

  /// No description provided for @ownerCouriersAvailabilityOnDelivery.
  ///
  /// In en, this message translates to:
  /// **'On delivery'**
  String get ownerCouriersAvailabilityOnDelivery;

  /// No description provided for @ownerCouriersAvailabilityOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get ownerCouriersAvailabilityOffline;

  /// No description provided for @socialChatThreadsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get socialChatThreadsTitle;

  /// No description provided for @socialChatThreadsCreateGroupTooltip.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get socialChatThreadsCreateGroupTooltip;

  /// No description provided for @socialChatThreadsCreateGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get socialChatThreadsCreateGroupTitle;

  /// No description provided for @socialChatThreadsCreateGroupNameHint.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get socialChatThreadsCreateGroupNameHint;

  /// No description provided for @socialChatThreadsCreateGroupSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search people'**
  String get socialChatThreadsCreateGroupSearchHint;

  /// No description provided for @socialChatThreadsCreateGroupLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load people.'**
  String get socialChatThreadsCreateGroupLoadFailed;

  /// No description provided for @socialChatThreadsCreateGroupFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create the group.'**
  String get socialChatThreadsCreateGroupFailed;

  /// No description provided for @socialChatThreadsCreateGroupNoUsers.
  ///
  /// In en, this message translates to:
  /// **'No people available right now.'**
  String get socialChatThreadsCreateGroupNoUsers;

  /// No description provided for @socialChatThreadsCreateGroupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a group name.'**
  String get socialChatThreadsCreateGroupNameRequired;

  /// No description provided for @socialChatThreadsCreateGroupMembersRequired.
  ///
  /// In en, this message translates to:
  /// **'Select at least one member.'**
  String get socialChatThreadsCreateGroupMembersRequired;

  /// No description provided for @socialChatThreadsCreateGroupCreate.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get socialChatThreadsCreateGroupCreate;

  /// No description provided for @socialChatThreadsCreateGroupSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String socialChatThreadsCreateGroupSelectedCount(int count);

  /// No description provided for @socialChatThreadsGroupMembersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} members'**
  String socialChatThreadsGroupMembersCount(int count);

  /// No description provided for @socialChatThreadsMessageRequests.
  ///
  /// In en, this message translates to:
  /// **'Message requests'**
  String get socialChatThreadsMessageRequests;

  /// No description provided for @socialChatThreadsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, username, or message'**
  String get socialChatThreadsSearchHint;

  /// No description provided for @socialChatThreadsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No chats available right now.'**
  String get socialChatThreadsEmptyTitle;

  /// No description provided for @socialChatThreadsSearchEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No results match your search.'**
  String get socialChatThreadsSearchEmptyTitle;

  /// No description provided for @socialChatThreadsEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start a chat from a post or from any user profile.'**
  String get socialChatThreadsEmptySubtitle;

  /// No description provided for @socialChatThreadsSearchEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try another name or clear the search.'**
  String get socialChatThreadsSearchEmptySubtitle;

  /// No description provided for @socialChatThreadsStartNow.
  ///
  /// In en, this message translates to:
  /// **'Start the chat now'**
  String get socialChatThreadsStartNow;

  /// No description provided for @socialChatThreadsContextRealEstate.
  ///
  /// In en, this message translates to:
  /// **'Property'**
  String get socialChatThreadsContextRealEstate;

  /// No description provided for @socialChatThreadsContextCar.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get socialChatThreadsContextCar;

  /// No description provided for @socialChatThreadsBucketPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get socialChatThreadsBucketPrivate;

  /// No description provided for @socialChatThreadsBucketWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get socialChatThreadsBucketWork;

  /// No description provided for @socialChatThreadsFilterUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get socialChatThreadsFilterUnread;

  /// No description provided for @socialChatThreadsFilterWithMessages.
  ///
  /// In en, this message translates to:
  /// **'With messages'**
  String get socialChatThreadsFilterWithMessages;

  /// No description provided for @commonAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get commonAccept;

  /// No description provided for @socialMessageRequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Message requests'**
  String get socialMessageRequestsTitle;

  /// No description provided for @socialMessageRequestsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load message requests.'**
  String get socialMessageRequestsLoadFailed;

  /// No description provided for @socialMessageRequestsAccepted.
  ///
  /// In en, this message translates to:
  /// **'Message request accepted.'**
  String get socialMessageRequestsAccepted;

  /// No description provided for @socialMessageRequestsAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to accept the request.'**
  String get socialMessageRequestsAcceptFailed;

  /// No description provided for @socialMessageRequestsRejected.
  ///
  /// In en, this message translates to:
  /// **'Message request rejected.'**
  String get socialMessageRequestsRejected;

  /// No description provided for @socialMessageRequestsRejectFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to reject the request.'**
  String get socialMessageRequestsRejectFailed;

  /// No description provided for @socialMessageRequestsBlocked.
  ///
  /// In en, this message translates to:
  /// **'This request has been blocked.'**
  String get socialMessageRequestsBlocked;

  /// No description provided for @socialMessageRequestsBlockFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to block the request.'**
  String get socialMessageRequestsBlockFailed;

  /// No description provided for @socialMessageRequestsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No message requests right now.'**
  String get socialMessageRequestsEmpty;

  /// No description provided for @socialMessageRequestsPreviewHint.
  ///
  /// In en, this message translates to:
  /// **'Open the request to review the message.'**
  String get socialMessageRequestsPreviewHint;

  /// No description provided for @onboardingRestaurantsTitle.
  ///
  /// In en, this message translates to:
  /// **'Maslaki Restaurants'**
  String get onboardingRestaurantsTitle;

  /// No description provided for @onboardingRestaurantsDescription.
  ///
  /// In en, this message translates to:
  /// **'Order from nearby restaurants and track every step in real time.'**
  String get onboardingRestaurantsDescription;

  /// No description provided for @onboardingShoppingTitle.
  ///
  /// In en, this message translates to:
  /// **'Shop Everything'**
  String get onboardingShoppingTitle;

  /// No description provided for @onboardingShoppingDescription.
  ///
  /// In en, this message translates to:
  /// **'Markets and local shops in one fast and simple experience.'**
  String get onboardingShoppingDescription;

  /// No description provided for @onboardingTaxiTitle.
  ///
  /// In en, this message translates to:
  /// **'Maslaki Taxi'**
  String get onboardingTaxiTitle;

  /// No description provided for @onboardingTaxiDescription.
  ///
  /// In en, this message translates to:
  /// **'Book a taxi instantly in your area and negotiate the fare directly with the captain.'**
  String get onboardingTaxiDescription;

  /// No description provided for @onboardingJobsTitle.
  ///
  /// In en, this message translates to:
  /// **'Basmaya Jobs'**
  String get onboardingJobsTitle;

  /// No description provided for @onboardingJobsDescription.
  ///
  /// In en, this message translates to:
  /// **'Browse jobs, apply directly, and track your application status.'**
  String get onboardingJobsDescription;

  /// No description provided for @onboardingCommunityTitle.
  ///
  /// In en, this message translates to:
  /// **'Basmaya Community'**
  String get onboardingCommunityTitle;

  /// No description provided for @onboardingCommunityDescription.
  ///
  /// In en, this message translates to:
  /// **'Social communication, local announcements, and home bills in one place.'**
  String get onboardingCommunityDescription;

  /// No description provided for @onboardingPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you start'**
  String get onboardingPermissionsTitle;

  /// No description provided for @onboardingPermissionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Turn on the core permissions now so taxi pickup, nearby services, and important updates work properly from the first use.'**
  String get onboardingPermissionsDescription;

  /// No description provided for @onboardingPermissionsLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Precise location'**
  String get onboardingPermissionsLocationTitle;

  /// No description provided for @onboardingPermissionsLocationDescription.
  ///
  /// In en, this message translates to:
  /// **'We use your location to set the pickup point in taxi and to show nearby stores and services more accurately.'**
  String get onboardingPermissionsLocationDescription;

  /// No description provided for @onboardingPermissionsNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get onboardingPermissionsNotificationsTitle;

  /// No description provided for @onboardingPermissionsNotificationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Notifications keep you updated on orders, rides, chat messages, and anything that needs your attention right away.'**
  String get onboardingPermissionsNotificationsDescription;

  /// No description provided for @onboardingPermissionsAllowLocation.
  ///
  /// In en, this message translates to:
  /// **'Enable location'**
  String get onboardingPermissionsAllowLocation;

  /// No description provided for @onboardingPermissionsAllowNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable notifications'**
  String get onboardingPermissionsAllowNotifications;

  /// No description provided for @onboardingBrand.
  ///
  /// In en, this message translates to:
  /// **'Maslaki'**
  String get onboardingBrand;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingStartNow.
  ///
  /// In en, this message translates to:
  /// **'Start Now'**
  String get onboardingStartNow;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @socialShareSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Share content'**
  String get socialShareSheetTitle;

  /// No description provided for @socialShareRecipientsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load share recipients.'**
  String get socialShareRecipientsLoadFailed;

  /// No description provided for @socialShareContentSharedSingle.
  ///
  /// In en, this message translates to:
  /// **'Content shared in chat.'**
  String get socialShareContentSharedSingle;

  /// No description provided for @socialShareContentSharedMultiple.
  ///
  /// In en, this message translates to:
  /// **'Content shared with {count} people.'**
  String socialShareContentSharedMultiple(int count);

  /// No description provided for @socialShareSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to send the share.'**
  String get socialShareSendFailed;

  /// No description provided for @socialShareSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or username'**
  String get socialShareSearchHint;

  /// No description provided for @socialShareExternal.
  ///
  /// In en, this message translates to:
  /// **'External share'**
  String get socialShareExternal;

  /// No description provided for @socialShareRecentChats.
  ///
  /// In en, this message translates to:
  /// **'Recent chats'**
  String get socialShareRecentChats;

  /// No description provided for @socialShareNoRecipients.
  ///
  /// In en, this message translates to:
  /// **'No eligible recipients right now.'**
  String get socialShareNoRecipients;

  /// No description provided for @socialShareSelectAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'Select at least one person'**
  String get socialShareSelectAtLeastOne;

  /// No description provided for @socialShareSendToCount.
  ///
  /// In en, this message translates to:
  /// **'Send to {count}'**
  String socialShareSendToCount(int count);

  /// No description provided for @socialShareWillArriveInRequests.
  ///
  /// In en, this message translates to:
  /// **'Will arrive in message requests first'**
  String get socialShareWillArriveInRequests;

  /// No description provided for @socialShareMessagingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Messaging unavailable'**
  String get socialShareMessagingUnavailable;

  /// No description provided for @adminFinancialActionReviewNote.
  ///
  /// In en, this message translates to:
  /// **'Review note'**
  String get adminFinancialActionReviewNote;

  /// No description provided for @adminFinancialActionInternalNote.
  ///
  /// In en, this message translates to:
  /// **'Internal note'**
  String get adminFinancialActionInternalNote;

  /// No description provided for @adminFinancialActionAssigneeName.
  ///
  /// In en, this message translates to:
  /// **'Assignee/actor name'**
  String get adminFinancialActionAssigneeName;

  /// No description provided for @adminFinancialActionPaidAmount.
  ///
  /// In en, this message translates to:
  /// **'Paid amount'**
  String get adminFinancialActionPaidAmount;

  /// No description provided for @adminFinancialActionPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get adminFinancialActionPaymentMethod;

  /// No description provided for @adminFinancialActionPaymentDate.
  ///
  /// In en, this message translates to:
  /// **'Payment date'**
  String get adminFinancialActionPaymentDate;

  /// No description provided for @adminFinancialActionReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get adminFinancialActionReference;

  /// No description provided for @adminFinancialActionPaymentActor.
  ///
  /// In en, this message translates to:
  /// **'Payment actor'**
  String get adminFinancialActionPaymentActor;

  /// No description provided for @adminFinancialActionAssign.
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get adminFinancialActionAssign;

  /// No description provided for @adminFinancialActionMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark paid'**
  String get adminFinancialActionMarkPaid;

  /// No description provided for @adminFinancialActionReturnForRevision.
  ///
  /// In en, this message translates to:
  /// **'Return for revision'**
  String get adminFinancialActionReturnForRevision;

  /// No description provided for @taxiCaptainPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required.'**
  String get taxiCaptainPhoneRequired;

  /// No description provided for @taxiCaptainPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Phone number is invalid.'**
  String get taxiCaptainPhoneInvalid;

  /// No description provided for @taxiCaptainPinRequired.
  ///
  /// In en, this message translates to:
  /// **'PIN is required.'**
  String get taxiCaptainPinRequired;

  /// No description provided for @taxiCaptainPinInvalid.
  ///
  /// In en, this message translates to:
  /// **'PIN must be 4 to 8 digits.'**
  String get taxiCaptainPinInvalid;

  /// No description provided for @taxiCaptainFullNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Full name is required.'**
  String get taxiCaptainFullNameRequired;

  /// No description provided for @taxiCaptainCarMakeRequired.
  ///
  /// In en, this message translates to:
  /// **'Car make is required.'**
  String get taxiCaptainCarMakeRequired;

  /// No description provided for @taxiCaptainCarModelRequired.
  ///
  /// In en, this message translates to:
  /// **'Car model is required.'**
  String get taxiCaptainCarModelRequired;

  /// No description provided for @taxiCaptainCarColorRequired.
  ///
  /// In en, this message translates to:
  /// **'Car color is required.'**
  String get taxiCaptainCarColorRequired;

  /// No description provided for @taxiCaptainPlateRequired.
  ///
  /// In en, this message translates to:
  /// **'Plate number is required.'**
  String get taxiCaptainPlateRequired;

  /// No description provided for @taxiCaptainCarYearInvalid.
  ///
  /// In en, this message translates to:
  /// **'Car year must be a valid number.'**
  String get taxiCaptainCarYearInvalid;

  /// No description provided for @taxiCaptainCarYearOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'Car year is outside the accepted range.'**
  String get taxiCaptainCarYearOutOfRange;

  /// No description provided for @taxiCaptainConsentRequired.
  ///
  /// In en, this message translates to:
  /// **'You must accept the terms before creating the account.'**
  String get taxiCaptainConsentRequired;

  /// No description provided for @taxiCaptainSectionCaptain.
  ///
  /// In en, this message translates to:
  /// **'Captain details'**
  String get taxiCaptainSectionCaptain;

  /// No description provided for @taxiCaptainFullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get taxiCaptainFullNameLabel;

  /// No description provided for @taxiCaptainFullNameHint.
  ///
  /// In en, this message translates to:
  /// **'Example: Mustafa Ali'**
  String get taxiCaptainFullNameHint;

  /// No description provided for @taxiCaptainPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get taxiCaptainPhoneLabel;

  /// No description provided for @taxiCaptainPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get taxiCaptainPinLabel;

  /// No description provided for @taxiCaptainPinHint.
  ///
  /// In en, this message translates to:
  /// **'4 to 8 digits'**
  String get taxiCaptainPinHint;

  /// No description provided for @taxiCaptainOfferDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Send ride offer'**
  String get taxiCaptainOfferDialogTitle;

  /// No description provided for @taxiCaptainCurrentFareLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer current fare'**
  String get taxiCaptainCurrentFareLabel;

  /// No description provided for @taxiCaptainOfferEtaLabel.
  ///
  /// In en, this message translates to:
  /// **'Estimated arrival time (minutes)'**
  String get taxiCaptainOfferEtaLabel;

  /// No description provided for @taxiCaptainOfferSent.
  ///
  /// In en, this message translates to:
  /// **'Offer sent successfully.'**
  String get taxiCaptainOfferSent;

  /// No description provided for @taxiCaptainProfileEditRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile edit request'**
  String get taxiCaptainProfileEditRequestTitle;

  /// No description provided for @taxiCaptainProfileEditNoChanges.
  ///
  /// In en, this message translates to:
  /// **'There are no changes to submit.'**
  String get taxiCaptainProfileEditNoChanges;

  /// No description provided for @taxiCaptainProfileEditRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Profile edit request sent successfully.'**
  String get taxiCaptainProfileEditRequestSent;

  /// No description provided for @taxiCaptainSectionCar.
  ///
  /// In en, this message translates to:
  /// **'Car details'**
  String get taxiCaptainSectionCar;

  /// No description provided for @taxiCaptainVehicleTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Vehicle type'**
  String get taxiCaptainVehicleTypeLabel;

  /// No description provided for @taxiCaptainVehicleTypeSedan.
  ///
  /// In en, this message translates to:
  /// **'Sedan'**
  String get taxiCaptainVehicleTypeSedan;

  /// No description provided for @taxiCaptainVehicleTypeSuv.
  ///
  /// In en, this message translates to:
  /// **'SUV'**
  String get taxiCaptainVehicleTypeSuv;

  /// No description provided for @taxiCaptainVehicleTypeHatchback.
  ///
  /// In en, this message translates to:
  /// **'Hatchback'**
  String get taxiCaptainVehicleTypeHatchback;

  /// No description provided for @taxiCaptainVehicleTypePickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get taxiCaptainVehicleTypePickup;

  /// No description provided for @taxiCaptainVehicleTypeVan.
  ///
  /// In en, this message translates to:
  /// **'Van'**
  String get taxiCaptainVehicleTypeVan;

  /// No description provided for @taxiCaptainCarMakeLabel.
  ///
  /// In en, this message translates to:
  /// **'Make'**
  String get taxiCaptainCarMakeLabel;

  /// No description provided for @taxiCaptainCarModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get taxiCaptainCarModelLabel;

  /// No description provided for @taxiCaptainCarYearLabel.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get taxiCaptainCarYearLabel;

  /// No description provided for @taxiCaptainCarColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get taxiCaptainCarColorLabel;

  /// No description provided for @taxiCaptainCarColorHint.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get taxiCaptainCarColorHint;

  /// No description provided for @taxiCaptainPlateLabel.
  ///
  /// In en, this message translates to:
  /// **'Plate number'**
  String get taxiCaptainPlateLabel;

  /// No description provided for @taxiCaptainPlateHint.
  ///
  /// In en, this message translates to:
  /// **'Baghdad 12345'**
  String get taxiCaptainPlateHint;

  /// No description provided for @taxiCaptainProfileImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Captain photo (optional)'**
  String get taxiCaptainProfileImageTitle;

  /// No description provided for @taxiCaptainCarImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Car photo (optional)'**
  String get taxiCaptainCarImageTitle;

  /// No description provided for @taxiCaptainCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the captain account right now. Please try again.'**
  String get taxiCaptainCreateFailed;

  /// No description provided for @taxiCaptainRequestSubmittedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your request was sent successfully'**
  String get taxiCaptainRequestSubmittedTitle;

  /// No description provided for @taxiCaptainRequestSubmittedBody.
  ///
  /// In en, this message translates to:
  /// **'Your taxi captain account was submitted for review. The account will be activated after admin approval.'**
  String get taxiCaptainRequestSubmittedBody;

  /// No description provided for @taxiCaptainConsentInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Captain registration policy'**
  String get taxiCaptainConsentInfoTitle;

  /// No description provided for @taxiCaptainConsentInfoBody1.
  ///
  /// In en, this message translates to:
  /// **'Your data is used to activate the captain account, verify identity, and improve service quality inside the app.'**
  String get taxiCaptainConsentInfoBody1;

  /// No description provided for @taxiCaptainConsentInfoBody2.
  ///
  /// In en, this message translates to:
  /// **'This consent also covers chat review when there is a report or when a necessary quality audit is performed by super admin only.'**
  String get taxiCaptainConsentInfoBody2;

  /// No description provided for @taxiCaptainConsentSummary.
  ///
  /// In en, this message translates to:
  /// **'Your consent covers privacy, service operation, and quality review when needed.'**
  String get taxiCaptainConsentSummary;

  /// No description provided for @taxiCaptainConsentDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get taxiCaptainConsentDetails;

  /// No description provided for @taxiCaptainConsentCheckbox.
  ///
  /// In en, this message translates to:
  /// **'I agree to the terms and the captain quality policy'**
  String get taxiCaptainConsentCheckbox;

  /// No description provided for @ownerInvoicePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Select invoices'**
  String get ownerInvoicePickerTitle;

  /// No description provided for @ownerInvoicePickerEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no open receivable invoices right now.'**
  String get ownerInvoicePickerEmpty;

  /// No description provided for @ownerInvoicePickerSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get ownerInvoicePickerSelectAll;

  /// No description provided for @ownerInvoicePickerClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get ownerInvoicePickerClearSelection;

  /// No description provided for @ownerInvoicePickerAllSelected.
  ///
  /// In en, this message translates to:
  /// **'All selected'**
  String get ownerInvoicePickerAllSelected;

  /// No description provided for @ownerInvoicePickerStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get ownerInvoicePickerStatusPaid;

  /// No description provided for @ownerInvoicePickerStatusPartiallyPaid.
  ///
  /// In en, this message translates to:
  /// **'Partially paid'**
  String get ownerInvoicePickerStatusPartiallyPaid;

  /// No description provided for @ownerInvoicePickerStatusUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get ownerInvoicePickerStatusUnpaid;

  /// No description provided for @ownerInvoicePickerSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'Selected invoices: {count}'**
  String ownerInvoicePickerSelectedCount(int count);

  /// No description provided for @adminApprovalsHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Approvals hub'**
  String get adminApprovalsHubTitle;

  /// No description provided for @adminApprovalsHubSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Each approval workflow now lives in its own dedicated page.'**
  String get adminApprovalsHubSubtitle;

  /// No description provided for @adminApprovalsHubMerchantTitle.
  ///
  /// In en, this message translates to:
  /// **'Merchant approvals'**
  String get adminApprovalsHubMerchantTitle;

  /// No description provided for @adminApprovalsHubMerchantSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pending merchant creation and financial-term reviews.'**
  String get adminApprovalsHubMerchantSubtitle;

  /// No description provided for @adminApprovalsHubDeliveryTitle.
  ///
  /// In en, this message translates to:
  /// **'App delivery approvals'**
  String get adminApprovalsHubDeliveryTitle;

  /// No description provided for @adminApprovalsHubDeliverySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pending app delivery captains only, separated from taxi.'**
  String get adminApprovalsHubDeliverySubtitle;

  /// No description provided for @adminApprovalsHubTaxiTitle.
  ///
  /// In en, this message translates to:
  /// **'Taxi captain requests'**
  String get adminApprovalsHubTaxiTitle;

  /// No description provided for @adminApprovalsHubTaxiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Account approvals and profile-edit reviews in one place.'**
  String get adminApprovalsHubTaxiSubtitle;

  /// No description provided for @adminApprovalsHubTaxiPaymentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Captain subscription payments'**
  String get adminApprovalsHubTaxiPaymentsTitle;

  /// No description provided for @adminApprovalsHubTaxiPaymentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pending cash subscription payments waiting for approval.'**
  String get adminApprovalsHubTaxiPaymentsSubtitle;

  /// No description provided for @adminApprovalsHubFinancialTitle.
  ///
  /// In en, this message translates to:
  /// **'Financial actions'**
  String get adminApprovalsHubFinancialTitle;

  /// No description provided for @adminApprovalsHubFinancialSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Receivable requests, settlements, and pending financial actions.'**
  String get adminApprovalsHubFinancialSubtitle;

  /// No description provided for @authOwnerAccount.
  ///
  /// In en, this message translates to:
  /// **'Create store'**
  String get authOwnerAccount;

  /// No description provided for @ownerRegisterAccountOnly.
  ///
  /// In en, this message translates to:
  /// **'Store account only'**
  String get ownerRegisterAccountOnly;

  /// No description provided for @ownerRegisterDescription.
  ///
  /// In en, this message translates to:
  /// **'This account is dedicated to the store and uses its own login phone and PIN. After approval, the app shows only the store workspace, orders, and products.'**
  String get ownerRegisterDescription;

  /// No description provided for @ownerRegisterLoginPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Store login phone is required.'**
  String get ownerRegisterLoginPhoneRequired;

  /// No description provided for @ownerRegisterLoginPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Store login phone is invalid.'**
  String get ownerRegisterLoginPhoneInvalid;

  /// No description provided for @ownerRegisterPinRequired.
  ///
  /// In en, this message translates to:
  /// **'PIN is required.'**
  String get ownerRegisterPinRequired;

  /// No description provided for @ownerRegisterPinInvalid.
  ///
  /// In en, this message translates to:
  /// **'PIN must be 4 to 8 digits.'**
  String get ownerRegisterPinInvalid;

  /// No description provided for @ownerRegisterMerchantNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Store name is required.'**
  String get ownerRegisterMerchantNameRequired;

  /// No description provided for @ownerRegisterMerchantDescriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'Store description is required.'**
  String get ownerRegisterMerchantDescriptionRequired;

  /// No description provided for @ownerRegisterContactPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Contact phone is required.'**
  String get ownerRegisterContactPhoneRequired;

  /// No description provided for @ownerRegisterContactPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Contact phone is invalid.'**
  String get ownerRegisterContactPhoneInvalid;

  /// No description provided for @ownerRegisterServiceAreaRequired.
  ///
  /// In en, this message translates to:
  /// **'Store location note is required.'**
  String get ownerRegisterServiceAreaRequired;

  /// No description provided for @ownerRegisterConsentRequired.
  ///
  /// In en, this message translates to:
  /// **'You must accept the terms before creating the account.'**
  String get ownerRegisterConsentRequired;

  /// No description provided for @ownerRegisterLoginPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Store login phone'**
  String get ownerRegisterLoginPhoneLabel;

  /// No description provided for @ownerRegisterPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'0770xxxxxxx'**
  String get ownerRegisterPhoneHint;

  /// No description provided for @ownerRegisterPinLabel.
  ///
  /// In en, this message translates to:
  /// **'Store PIN'**
  String get ownerRegisterPinLabel;

  /// No description provided for @ownerRegisterPinHint.
  ///
  /// In en, this message translates to:
  /// **'4 to 8 digits'**
  String get ownerRegisterPinHint;

  /// No description provided for @ownerRegisterSectionMerchantData.
  ///
  /// In en, this message translates to:
  /// **'Store details'**
  String get ownerRegisterSectionMerchantData;

  /// No description provided for @ownerRegisterMerchantNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Store name'**
  String get ownerRegisterMerchantNameLabel;

  /// No description provided for @ownerRegisterMerchantNameHint.
  ///
  /// In en, this message translates to:
  /// **'Example: Maslaki Burger'**
  String get ownerRegisterMerchantNameHint;

  /// No description provided for @ownerRegisterMerchantTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Primary store activity'**
  String get ownerRegisterMerchantTypeLabel;

  /// No description provided for @ownerRegisterMerchantTypeRestaurant.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get ownerRegisterMerchantTypeRestaurant;

  /// No description provided for @ownerRegisterMerchantTypeMarket.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get ownerRegisterMerchantTypeMarket;

  /// No description provided for @ownerRegisterMerchantDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Store description'**
  String get ownerRegisterMerchantDescriptionLabel;

  /// No description provided for @ownerRegisterMerchantDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Write a short and clear description for the store.'**
  String get ownerRegisterMerchantDescriptionHint;

  /// No description provided for @ownerRegisterContactPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Store contact phone'**
  String get ownerRegisterContactPhoneLabel;

  /// No description provided for @ownerRegisterContactPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty if it is the same as the store login phone.'**
  String get ownerRegisterContactPhoneHint;

  /// No description provided for @ownerRegisterServiceAreaLabel.
  ///
  /// In en, this message translates to:
  /// **'Location note (required)'**
  String get ownerRegisterServiceAreaLabel;

  /// No description provided for @ownerRegisterServiceAreaHint.
  ///
  /// In en, this message translates to:
  /// **'Write a clear description of the store location such as street, district, and nearest landmark.'**
  String get ownerRegisterServiceAreaHint;

  /// No description provided for @ownerRegisterBasmayaLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Store location inside Basmaya (optional)'**
  String get ownerRegisterBasmayaLocationTitle;

  /// No description provided for @ownerRegisterMerchantImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Store image (optional)'**
  String get ownerRegisterMerchantImageTitle;

  /// No description provided for @ownerRegisterCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the store account right now. Please try again.'**
  String get ownerRegisterCreateFailed;

  /// No description provided for @ownerRegisterConsentInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Store registration policy'**
  String get ownerRegisterConsentInfoTitle;

  /// No description provided for @ownerRegisterConsentInfoBody1.
  ///
  /// In en, this message translates to:
  /// **'Store data is used to activate orders, display products, and improve the service inside the app.'**
  String get ownerRegisterConsentInfoBody1;

  /// No description provided for @ownerRegisterConsentInfoBody2.
  ///
  /// In en, this message translates to:
  /// **'This consent also covers chat review when there is a report or when a necessary quality audit is performed by super admin only.'**
  String get ownerRegisterConsentInfoBody2;

  /// No description provided for @ownerRegisterConsentSummary.
  ///
  /// In en, this message translates to:
  /// **'Your consent covers store operation, privacy, and quality review when needed.'**
  String get ownerRegisterConsentSummary;

  /// No description provided for @ownerRegisterConsentDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get ownerRegisterConsentDetails;

  /// No description provided for @ownerRegisterConsentCheckbox.
  ///
  /// In en, this message translates to:
  /// **'I agree to the terms and store quality policy'**
  String get ownerRegisterConsentCheckbox;

  /// No description provided for @ownerPrinterSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Printer settings'**
  String get ownerPrinterSettingsTitle;

  /// No description provided for @ownerPrinterSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Printer settings saved.'**
  String get ownerPrinterSettingsSaved;

  /// No description provided for @ownerPrinterTestReceiptSent.
  ///
  /// In en, this message translates to:
  /// **'Test receipt sent to printer.'**
  String get ownerPrinterTestReceiptSent;

  /// No description provided for @ownerPrinterTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Print failed: {message}'**
  String ownerPrinterTestFailed(Object message);

  /// No description provided for @ownerPrinterSampleSent.
  ///
  /// In en, this message translates to:
  /// **'Sample invoice sent to printer.'**
  String get ownerPrinterSampleSent;

  /// No description provided for @ownerPrinterSampleFailed.
  ///
  /// In en, this message translates to:
  /// **'Sample print failed: {message}'**
  String ownerPrinterSampleFailed(Object message);

  /// No description provided for @ownerPrinterSamplePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Sample preview'**
  String get ownerPrinterSamplePreviewTitle;

  /// No description provided for @ownerPrinterNoLogs.
  ///
  /// In en, this message translates to:
  /// **'No print logs yet.'**
  String get ownerPrinterNoLogs;

  /// No description provided for @ownerPrinterPermissionsGranted.
  ///
  /// In en, this message translates to:
  /// **'Printer permissions granted.'**
  String get ownerPrinterPermissionsGranted;

  /// No description provided for @ownerPrinterPermissionsDenied.
  ///
  /// In en, this message translates to:
  /// **'Some permissions are denied: {permissions}'**
  String ownerPrinterPermissionsDenied(Object permissions);

  /// No description provided for @ownerPrinterSectionMode.
  ///
  /// In en, this message translates to:
  /// **'Print mode'**
  String get ownerPrinterSectionMode;

  /// No description provided for @ownerPrinterModeSystem.
  ///
  /// In en, this message translates to:
  /// **'System printing (Android Print Service)'**
  String get ownerPrinterModeSystem;

  /// No description provided for @ownerPrinterModeNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network ESC/POS printer (direct IP)'**
  String get ownerPrinterModeNetwork;

  /// No description provided for @ownerPrinterModeIpos.
  ///
  /// In en, this message translates to:
  /// **'Built-in IposPrinter (Bluetooth)'**
  String get ownerPrinterModeIpos;

  /// No description provided for @ownerPrinterModeIposSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recommended for POS devices like V10II'**
  String get ownerPrinterModeIposSubtitle;

  /// No description provided for @ownerPrinterSectionDeviceCapabilities.
  ///
  /// In en, this message translates to:
  /// **'Device capabilities'**
  String get ownerPrinterSectionDeviceCapabilities;

  /// No description provided for @ownerPrinterRequestPermissions.
  ///
  /// In en, this message translates to:
  /// **'Request printer permissions'**
  String get ownerPrinterRequestPermissions;

  /// No description provided for @ownerPrinterBluetoothSettings.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth settings'**
  String get ownerPrinterBluetoothSettings;

  /// No description provided for @ownerPrinterPrintSettings.
  ///
  /// In en, this message translates to:
  /// **'Print settings'**
  String get ownerPrinterPrintSettings;

  /// No description provided for @ownerPrinterSectionSystemSelection.
  ///
  /// In en, this message translates to:
  /// **'System printer selection'**
  String get ownerPrinterSectionSystemSelection;

  /// No description provided for @ownerPrinterSectionNetworkSetup.
  ///
  /// In en, this message translates to:
  /// **'Network printer setup'**
  String get ownerPrinterSectionNetworkSetup;

  /// No description provided for @ownerPrinterNetworkIpLabel.
  ///
  /// In en, this message translates to:
  /// **'Printer IP'**
  String get ownerPrinterNetworkIpLabel;

  /// No description provided for @ownerPrinterPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get ownerPrinterPortLabel;

  /// No description provided for @ownerPrinterCommonPortHint.
  ///
  /// In en, this message translates to:
  /// **'Paper 58mm - common port 9100'**
  String get ownerPrinterCommonPortHint;

  /// No description provided for @ownerPrinterSectionIposStatus.
  ///
  /// In en, this message translates to:
  /// **'IposPrinter status'**
  String get ownerPrinterSectionIposStatus;

  /// No description provided for @ownerPrinterStatusEnabled.
  ///
  /// In en, this message translates to:
  /// **'enabled'**
  String get ownerPrinterStatusEnabled;

  /// No description provided for @ownerPrinterStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'disabled'**
  String get ownerPrinterStatusDisabled;

  /// No description provided for @ownerPrinterStatusFound.
  ///
  /// In en, this message translates to:
  /// **'found'**
  String get ownerPrinterStatusFound;

  /// No description provided for @ownerPrinterStatusNotFound.
  ///
  /// In en, this message translates to:
  /// **'not found'**
  String get ownerPrinterStatusNotFound;

  /// No description provided for @ownerPrinterStatusInstalled.
  ///
  /// In en, this message translates to:
  /// **'installed'**
  String get ownerPrinterStatusInstalled;

  /// No description provided for @ownerPrinterStatusNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'not installed'**
  String get ownerPrinterStatusNotInstalled;

  /// No description provided for @ownerPrinterBluetoothLine.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth: {status}'**
  String ownerPrinterBluetoothLine(Object status);

  /// No description provided for @ownerPrinterBondedLine.
  ///
  /// In en, this message translates to:
  /// **'Bonded printer: {status}'**
  String ownerPrinterBondedLine(Object status);

  /// No description provided for @ownerPrinterServiceLine.
  ///
  /// In en, this message translates to:
  /// **'iPos service: {status}'**
  String ownerPrinterServiceLine(Object status);

  /// No description provided for @ownerPrinterDeviceName.
  ///
  /// In en, this message translates to:
  /// **'Name: {value}'**
  String ownerPrinterDeviceName(Object value);

  /// No description provided for @ownerPrinterDeviceAddress.
  ///
  /// In en, this message translates to:
  /// **'Address: {value}'**
  String ownerPrinterDeviceAddress(Object value);

  /// No description provided for @ownerPrinterIposPairingHint.
  ///
  /// In en, this message translates to:
  /// **'If printer is not found, pair IposPrinter from Bluetooth settings, then refresh.'**
  String get ownerPrinterIposPairingHint;

  /// No description provided for @ownerPrinterTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing...'**
  String get ownerPrinterTesting;

  /// No description provided for @ownerPrinterTestPrint.
  ///
  /// In en, this message translates to:
  /// **'Test print'**
  String get ownerPrinterTestPrint;

  /// No description provided for @ownerPrinterPreviewSample.
  ///
  /// In en, this message translates to:
  /// **'Preview sample'**
  String get ownerPrinterPreviewSample;

  /// No description provided for @ownerPrinterPrintSample.
  ///
  /// In en, this message translates to:
  /// **'Print sample'**
  String get ownerPrinterPrintSample;

  /// No description provided for @ownerPrinterLogs.
  ///
  /// In en, this message translates to:
  /// **'Print logs'**
  String get ownerPrinterLogs;

  /// No description provided for @ownerPrinterClearSystemPrinter.
  ///
  /// In en, this message translates to:
  /// **'Clear system printer'**
  String get ownerPrinterClearSystemPrinter;

  /// No description provided for @ownerPrinterNoSystemPrinters.
  ///
  /// In en, this message translates to:
  /// **'No system printers found. On POS devices, use IposPrinter mode or network mode.'**
  String get ownerPrinterNoSystemPrinters;

  /// No description provided for @ownerPrinterSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get ownerPrinterSaved;

  /// No description provided for @adminAuditLogNoTimestamp.
  ///
  /// In en, this message translates to:
  /// **'No timestamp'**
  String get adminAuditLogNoTimestamp;

  /// No description provided for @adminAuditLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Administrative audit log'**
  String get adminAuditLogTitle;

  /// No description provided for @adminAuditLogSearch.
  ///
  /// In en, this message translates to:
  /// **'Search audit log'**
  String get adminAuditLogSearch;

  /// No description provided for @adminAuditLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matching audit events.'**
  String get adminAuditLogEmpty;

  /// No description provided for @adminAuditLogAction.
  ///
  /// In en, this message translates to:
  /// **'Action: {value}'**
  String adminAuditLogAction(Object value);

  /// No description provided for @adminAuditLogActor.
  ///
  /// In en, this message translates to:
  /// **'Actor: {value}'**
  String adminAuditLogActor(Object value);

  /// No description provided for @adminAuditLogTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get adminAuditLogTarget;

  /// No description provided for @adminAuditLogActorPhone.
  ///
  /// In en, this message translates to:
  /// **'Actor phone'**
  String get adminAuditLogActorPhone;

  /// No description provided for @adminAuditLogMetadata.
  ///
  /// In en, this message translates to:
  /// **'Metadata'**
  String get adminAuditLogMetadata;

  /// No description provided for @adminAuditLogLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get adminAuditLogLoadMore;

  /// No description provided for @adminFinancialReportsHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Financial reports'**
  String get adminFinancialReportsHubTitle;

  /// No description provided for @adminFinancialReportsHubSalesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Merchants sales with drill-down'**
  String get adminFinancialReportsHubSalesSubtitle;

  /// No description provided for @adminFinancialReportsHubCollectionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Confirmed payments collected from stores'**
  String get adminFinancialReportsHubCollectionsSubtitle;

  /// No description provided for @adminFinancialReportsHubReceivablesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Net and outstanding by merchant'**
  String get adminFinancialReportsHubReceivablesSubtitle;

  /// No description provided for @ownerStoreKpisLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load store financial KPIs.'**
  String get ownerStoreKpisLoadFailed;

  /// No description provided for @ownerStoreKpisTitle.
  ///
  /// In en, this message translates to:
  /// **'Store Financial KPIs'**
  String get ownerStoreKpisTitle;

  /// No description provided for @ownerStoreKpisSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'This screen shows all-time totals.'**
  String get ownerStoreKpisSummaryTitle;

  /// No description provided for @ownerStoreKpisSummarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap any card to open the detailed report with time filters.'**
  String get ownerStoreKpisSummarySubtitle;

  /// No description provided for @ownerStoreKpisInvoiceCount.
  ///
  /// In en, this message translates to:
  /// **'Receivable invoices'**
  String get ownerStoreKpisInvoiceCount;

  /// No description provided for @adminCustomerProfilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer profiles'**
  String get adminCustomerProfilesTitle;

  /// No description provided for @adminCustomerProfilesSuperAdminOnly.
  ///
  /// In en, this message translates to:
  /// **'This page is available to super admins only.'**
  String get adminCustomerProfilesSuperAdminOnly;

  /// No description provided for @adminCustomerProfilesSearch.
  ///
  /// In en, this message translates to:
  /// **'Search customers'**
  String get adminCustomerProfilesSearch;

  /// No description provided for @adminCustomerProfilesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No customer profiles available.'**
  String get adminCustomerProfilesEmpty;

  /// No description provided for @adminCustomerProfilesOrdersSpend.
  ///
  /// In en, this message translates to:
  /// **'Orders: {count} - Spend: {spend}'**
  String adminCustomerProfilesOrdersSpend(int count, Object spend);

  /// No description provided for @adminMerchantApprovalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Merchant approval requests'**
  String get adminMerchantApprovalsTitle;

  /// No description provided for @adminMerchantApprovalsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search merchants'**
  String get adminMerchantApprovalsSearch;

  /// No description provided for @adminMerchantApprovalsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No pending merchant requests right now.'**
  String get adminMerchantApprovalsEmpty;

  /// No description provided for @adminMerchantApprovalsType.
  ///
  /// In en, this message translates to:
  /// **'Type: {value}'**
  String adminMerchantApprovalsType(Object value);

  /// No description provided for @adminMerchantApprovalsOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner: {value}'**
  String adminMerchantApprovalsOwner(Object value);

  /// No description provided for @adminMerchantApprovalsReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get adminMerchantApprovalsReview;

  /// No description provided for @adminTaxiCashPaymentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Captain subscription payments'**
  String get adminTaxiCashPaymentsTitle;

  /// No description provided for @adminTaxiCashPaymentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No pending subscription payments.'**
  String get adminTaxiCashPaymentsEmpty;

  /// No description provided for @adminTaxiCashPaymentsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get adminTaxiCashPaymentsConfirm;

  /// No description provided for @adminTaxiCashPaymentsDueAmount.
  ///
  /// In en, this message translates to:
  /// **'Due amount'**
  String get adminTaxiCashPaymentsDueAmount;

  /// No description provided for @adminTaxiCashPaymentsMonthlyFee.
  ///
  /// In en, this message translates to:
  /// **'Monthly fee'**
  String get adminTaxiCashPaymentsMonthlyFee;

  /// No description provided for @adminTaxiCashPaymentsDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get adminTaxiCashPaymentsDiscount;

  /// No description provided for @socialSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get socialSavedTitle;

  /// No description provided for @socialSavedCollections.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get socialSavedCollections;

  /// No description provided for @socialSavedPosts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get socialSavedPosts;

  /// No description provided for @socialSavedReels.
  ///
  /// In en, this message translates to:
  /// **'Reels'**
  String get socialSavedReels;

  /// No description provided for @socialSavedReviews.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get socialSavedReviews;

  /// No description provided for @socialSavedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No saved items yet.'**
  String get socialSavedEmpty;

  /// No description provided for @ownerOrdersCurrentTitle.
  ///
  /// In en, this message translates to:
  /// **'Current store orders'**
  String get ownerOrdersCurrentTitle;

  /// No description provided for @ownerOrdersCompletedTitle.
  ///
  /// In en, this message translates to:
  /// **'Completed orders'**
  String get ownerOrdersCompletedTitle;

  /// No description provided for @ownerOrdersCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancelled orders'**
  String get ownerOrdersCancelledTitle;

  /// No description provided for @ownerOrdersDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Order details'**
  String get ownerOrdersDetailsTitle;

  /// No description provided for @ownerOrdersEmptyCurrent.
  ///
  /// In en, this message translates to:
  /// **'No current orders.'**
  String get ownerOrdersEmptyCurrent;

  /// No description provided for @ownerOrdersEmptyCompleted.
  ///
  /// In en, this message translates to:
  /// **'No completed orders.'**
  String get ownerOrdersEmptyCompleted;

  /// No description provided for @ownerOrdersEmptyCancelled.
  ///
  /// In en, this message translates to:
  /// **'No cancelled orders.'**
  String get ownerOrdersEmptyCancelled;

  /// No description provided for @ownerOrdersEmptyDetails.
  ///
  /// In en, this message translates to:
  /// **'Order not found.'**
  String get ownerOrdersEmptyDetails;

  /// No description provided for @ownerOrdersMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Store menu'**
  String get ownerOrdersMenuTitle;

  /// No description provided for @ownerOrdersPrintSampleInvoice.
  ///
  /// In en, this message translates to:
  /// **'Print sample invoice'**
  String get ownerOrdersPrintSampleInvoice;

  /// No description provided for @ownerOrdersStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get ownerOrdersStatusApproved;

  /// No description provided for @ownerOrdersStatusPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get ownerOrdersStatusPreparing;

  /// No description provided for @ownerOrdersStatusReadyForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Ready for delivery'**
  String get ownerOrdersStatusReadyForDelivery;

  /// No description provided for @ownerOrdersStatusOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'On the way'**
  String get ownerOrdersStatusOnTheWay;

  /// No description provided for @ownerOrdersStatusArrived.
  ///
  /// In en, this message translates to:
  /// **'Arrived'**
  String get ownerOrdersStatusArrived;

  /// No description provided for @ownerOrdersStatusDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get ownerOrdersStatusDelivered;

  /// No description provided for @ownerOrdersStatusReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get ownerOrdersStatusReceived;

  /// No description provided for @ownerOrdersStatusFailedDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery failed'**
  String get ownerOrdersStatusFailedDelivery;

  /// No description provided for @ownerOrdersHintApprovedAssigned.
  ///
  /// In en, this message translates to:
  /// **'A courier is assigned and you can start preparing now.'**
  String get ownerOrdersHintApprovedAssigned;

  /// No description provided for @ownerOrdersHintApprovedPendingCourier.
  ///
  /// In en, this message translates to:
  /// **'The order is approved. Start preparing now; the first available courier will be assigned automatically.'**
  String get ownerOrdersHintApprovedPendingCourier;

  /// No description provided for @ownerOrdersHintPreparing.
  ///
  /// In en, this message translates to:
  /// **'The store is preparing the order now.'**
  String get ownerOrdersHintPreparing;

  /// No description provided for @ownerOrdersHintReadyMerchantDelivery.
  ///
  /// In en, this message translates to:
  /// **'Store delivery is enabled. Update the status to on the way when the order leaves.'**
  String get ownerOrdersHintReadyMerchantDelivery;

  /// No description provided for @ownerOrdersHintReadyPlatformDelivery.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the courier to confirm pickup.'**
  String get ownerOrdersHintReadyPlatformDelivery;

  /// No description provided for @ownerOrdersHintOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'The courier is on the way to the customer.'**
  String get ownerOrdersHintOnTheWay;

  /// No description provided for @ownerOrdersHintArrived.
  ///
  /// In en, this message translates to:
  /// **'The courier has arrived and is waiting for handoff.'**
  String get ownerOrdersHintArrived;

  /// No description provided for @ownerOrdersHintDeliveredAwaitingConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delivered and waiting for customer confirmation.'**
  String get ownerOrdersHintDeliveredAwaitingConfirmation;

  /// No description provided for @ownerOrdersHintFailedDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery failed. Review the order and follow up with support if needed.'**
  String get ownerOrdersHintFailedDelivery;

  /// No description provided for @ownerOrdersStoreDriver.
  ///
  /// In en, this message translates to:
  /// **'Store driver'**
  String get ownerOrdersStoreDriver;

  /// No description provided for @ownerOrdersAppDriver.
  ///
  /// In en, this message translates to:
  /// **'App driver'**
  String get ownerOrdersAppDriver;

  /// No description provided for @ownerOrdersPendingAssignment.
  ///
  /// In en, this message translates to:
  /// **'Pending assignment'**
  String get ownerOrdersPendingAssignment;

  /// No description provided for @ownerOrdersPendingFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending orders'**
  String get ownerOrdersPendingFilterTitle;

  /// No description provided for @ownerOrdersPreparingFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Preparing orders'**
  String get ownerOrdersPreparingFilterTitle;

  /// No description provided for @ownerOrdersReadyFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready for delivery'**
  String get ownerOrdersReadyFilterTitle;

  /// No description provided for @ownerOrdersDeliveringFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivering orders'**
  String get ownerOrdersDeliveringFilterTitle;

  /// No description provided for @ownerOrdersAllCurrentFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'All current orders'**
  String get ownerOrdersAllCurrentFilterTitle;

  /// No description provided for @ownerOrdersAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get ownerOrdersAddressLabel;

  /// No description provided for @ownerOrdersBuildingLabel.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get ownerOrdersBuildingLabel;

  /// No description provided for @ownerOrdersApartmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Apartment'**
  String get ownerOrdersApartmentLabel;

  /// No description provided for @ownerOrdersDriverTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Driver type'**
  String get ownerOrdersDriverTypeLabel;

  /// No description provided for @ownerOrdersNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get ownerOrdersNoteLabel;

  /// No description provided for @ownerOrdersAssignAppCourier.
  ///
  /// In en, this message translates to:
  /// **'Assign app courier'**
  String get ownerOrdersAssignAppCourier;

  /// No description provided for @ownerOrdersPrinting.
  ///
  /// In en, this message translates to:
  /// **'Printing...'**
  String get ownerOrdersPrinting;

  /// No description provided for @ownerOrdersPrintReceipt.
  ///
  /// In en, this message translates to:
  /// **'Print receipt'**
  String get ownerOrdersPrintReceipt;

  /// No description provided for @ownerOrdersCourierAssigned.
  ///
  /// In en, this message translates to:
  /// **'Courier assigned.'**
  String get ownerOrdersCourierAssigned;

  /// No description provided for @ownerOrdersChangeCourier.
  ///
  /// In en, this message translates to:
  /// **'Change courier'**
  String get ownerOrdersChangeCourier;

  /// No description provided for @ownerOrdersAssignCourier.
  ///
  /// In en, this message translates to:
  /// **'Assign courier'**
  String get ownerOrdersAssignCourier;

  /// No description provided for @ownerOrdersPreparationStarted.
  ///
  /// In en, this message translates to:
  /// **'Preparation started. Courier request sent based on settings.'**
  String get ownerOrdersPreparationStarted;

  /// No description provided for @ownerOrdersStartPreparing.
  ///
  /// In en, this message translates to:
  /// **'Start preparing'**
  String get ownerOrdersStartPreparing;

  /// No description provided for @ownerOrdersReadyForPickup.
  ///
  /// In en, this message translates to:
  /// **'Ready for pickup'**
  String get ownerOrdersReadyForPickup;

  /// No description provided for @ownerOrdersSummaryReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get ownerOrdersSummaryReady;

  /// No description provided for @ownerOrdersSummaryDelivering.
  ///
  /// In en, this message translates to:
  /// **'Delivering'**
  String get ownerOrdersSummaryDelivering;

  /// No description provided for @ownerOrdersReceiptPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Receipt preview'**
  String get ownerOrdersReceiptPreviewTitle;

  /// No description provided for @ownerOrdersPrintSuccess.
  ///
  /// In en, this message translates to:
  /// **'Receipt printed successfully via: {adapter}'**
  String ownerOrdersPrintSuccess(String adapter);

  /// No description provided for @ownerOrdersPrintFailed.
  ///
  /// In en, this message translates to:
  /// **'Printing failed: {message}'**
  String ownerOrdersPrintFailed(String message);

  /// No description provided for @ownerOrdersOrderNumber.
  ///
  /// In en, this message translates to:
  /// **'Order #{id}'**
  String ownerOrdersOrderNumber(int id);

  /// No description provided for @ownerOrdersCashierName.
  ///
  /// In en, this message translates to:
  /// **'Store Owner'**
  String get ownerOrdersCashierName;

  /// No description provided for @commonImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get commonImage;

  /// No description provided for @commonVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get commonVideo;

  /// No description provided for @commonFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get commonFile;

  /// No description provided for @socialChatThreadLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load the chat.'**
  String get socialChatThreadLoadFailed;

  /// No description provided for @socialChatThreadSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get socialChatThreadSessionExpired;

  /// No description provided for @socialChatThreadTyping.
  ///
  /// In en, this message translates to:
  /// **'Typing...'**
  String get socialChatThreadTyping;

  /// No description provided for @socialChatThreadTypingBy.
  ///
  /// In en, this message translates to:
  /// **'{name} is typing...'**
  String socialChatThreadTypingBy(String name);

  /// No description provided for @socialChatThreadOnlineNow.
  ///
  /// In en, this message translates to:
  /// **'Online now'**
  String get socialChatThreadOnlineNow;

  /// No description provided for @socialChatThreadLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen {time}'**
  String socialChatThreadLastSeen(String time);

  /// No description provided for @socialChatThreadSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send the message.'**
  String get socialChatThreadSendFailed;

  /// No description provided for @socialChatThreadAttachmentPickFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to pick the attachment.'**
  String get socialChatThreadAttachmentPickFailed;

  /// No description provided for @socialChatThreadEditMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get socialChatThreadEditMessage;

  /// No description provided for @socialChatThreadEditFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to edit message.'**
  String get socialChatThreadEditFailed;

  /// No description provided for @socialChatThreadDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get socialChatThreadDeleteMessage;

  /// No description provided for @socialChatThreadDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'The message will be marked as deleted for both participants.'**
  String get socialChatThreadDeleteConfirm;

  /// No description provided for @socialChatThreadDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete message.'**
  String get socialChatThreadDeleteFailed;

  /// No description provided for @socialChatThreadReactionUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update the message reaction.'**
  String get socialChatThreadReactionUpdateFailed;

  /// No description provided for @socialChatThreadRealtimeConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get socialChatThreadRealtimeConnected;

  /// No description provided for @socialChatThreadRealtimeReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get socialChatThreadRealtimeReconnecting;

  /// No description provided for @socialChatThreadRealtimeConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get socialChatThreadRealtimeConnecting;

  /// No description provided for @socialChatThreadRealtimeOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get socialChatThreadRealtimeOffline;

  /// No description provided for @socialChatThreadReadOnlyMonitor.
  ///
  /// In en, this message translates to:
  /// **'Monitor mode only. You cannot reply from this screen.'**
  String get socialChatThreadReadOnlyMonitor;

  /// No description provided for @socialChatThreadReadOnlyRequests.
  ///
  /// In en, this message translates to:
  /// **'This conversation is in message requests. Open requests to accept or reject it.'**
  String get socialChatThreadReadOnlyRequests;

  /// No description provided for @socialChatThreadReadOnlyDefault.
  ///
  /// In en, this message translates to:
  /// **'This chat is read-only.'**
  String get socialChatThreadReadOnlyDefault;

  /// No description provided for @socialChatThreadShowOlderMessages.
  ///
  /// In en, this message translates to:
  /// **'Show older messages'**
  String get socialChatThreadShowOlderMessages;

  /// No description provided for @socialChatThreadEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet. Start the conversation now.'**
  String get socialChatThreadEmpty;

  /// No description provided for @socialChatThreadLatestMessages.
  ///
  /// In en, this message translates to:
  /// **'Latest messages'**
  String get socialChatThreadLatestMessages;

  /// No description provided for @socialChatThreadReplyingTo.
  ///
  /// In en, this message translates to:
  /// **'Replying to {name}'**
  String socialChatThreadReplyingTo(String name);

  /// No description provided for @socialChatThreadAttachmentReady.
  ///
  /// In en, this message translates to:
  /// **'Attachment ready to send'**
  String get socialChatThreadAttachmentReady;

  /// No description provided for @socialChatThreadAttach.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get socialChatThreadAttach;

  /// No description provided for @socialChatThreadRecordVoice.
  ///
  /// In en, this message translates to:
  /// **'Record voice message'**
  String get socialChatThreadRecordVoice;

  /// No description provided for @socialChatThreadStopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get socialChatThreadStopRecording;

  /// No description provided for @socialChatThreadMicrophonePermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required to record a voice message.'**
  String get socialChatThreadMicrophonePermissionDenied;

  /// No description provided for @socialChatThreadVoiceMessageReady.
  ///
  /// In en, this message translates to:
  /// **'Voice message ready to send'**
  String get socialChatThreadVoiceMessageReady;

  /// No description provided for @socialChatThreadVoiceMessageRecordFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to record the voice message right now.'**
  String get socialChatThreadVoiceMessageRecordFailed;

  /// No description provided for @socialChatThreadHoldToRecord.
  ///
  /// In en, this message translates to:
  /// **'Hold to record a voice message'**
  String get socialChatThreadHoldToRecord;

  /// No description provided for @socialChatThreadSlideUpToLock.
  ///
  /// In en, this message translates to:
  /// **'Slide up to lock'**
  String get socialChatThreadSlideUpToLock;

  /// No description provided for @socialChatThreadRecordingLocked.
  ///
  /// In en, this message translates to:
  /// **'Recording locked. You can continue hands-free.'**
  String get socialChatThreadRecordingLocked;

  /// No description provided for @socialChatThreadPreviewVoiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Voice message preview'**
  String get socialChatThreadPreviewVoiceMessage;

  /// No description provided for @socialChatThreadDeleteVoiceDraft.
  ///
  /// In en, this message translates to:
  /// **'Delete recording'**
  String get socialChatThreadDeleteVoiceDraft;

  /// No description provided for @socialChatThreadSendVoiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Send voice message'**
  String get socialChatThreadSendVoiceMessage;

  /// No description provided for @socialChatThreadVoiceMessageTooShort.
  ///
  /// In en, this message translates to:
  /// **'The voice recording is too short.'**
  String get socialChatThreadVoiceMessageTooShort;

  /// No description provided for @socialChatThreadVoiceMessagePlay.
  ///
  /// In en, this message translates to:
  /// **'Play voice message'**
  String get socialChatThreadVoiceMessagePlay;

  /// No description provided for @socialChatThreadVoiceMessagePause.
  ///
  /// In en, this message translates to:
  /// **'Pause voice message'**
  String get socialChatThreadVoiceMessagePause;

  /// No description provided for @socialChatThreadVoiceMessageSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to send the voice message.'**
  String get socialChatThreadVoiceMessageSendFailed;

  /// No description provided for @socialChatThreadScheduleMessage.
  ///
  /// In en, this message translates to:
  /// **'Schedule message'**
  String get socialChatThreadScheduleMessage;

  /// No description provided for @socialChatThreadScheduledMessages.
  ///
  /// In en, this message translates to:
  /// **'Scheduled messages'**
  String get socialChatThreadScheduledMessages;

  /// No description provided for @socialChatThreadScheduleRequiresContent.
  ///
  /// In en, this message translates to:
  /// **'Add text or an attachment before scheduling the message.'**
  String get socialChatThreadScheduleRequiresContent;

  /// No description provided for @socialChatThreadMessageScheduled.
  ///
  /// In en, this message translates to:
  /// **'The message was scheduled successfully.'**
  String get socialChatThreadMessageScheduled;

  /// No description provided for @socialChatThreadScheduleFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to schedule the message right now.'**
  String get socialChatThreadScheduleFailed;

  /// No description provided for @socialChatThreadScheduledStatus.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get socialChatThreadScheduledStatus;

  /// No description provided for @socialChatThreadScheduledFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get socialChatThreadScheduledFailed;

  /// No description provided for @socialChatThreadScheduledProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get socialChatThreadScheduledProcessing;

  /// No description provided for @socialChatThreadCancelScheduledMessage.
  ///
  /// In en, this message translates to:
  /// **'Cancel scheduled message'**
  String get socialChatThreadCancelScheduledMessage;

  /// No description provided for @socialChatThreadCancelScheduledFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to cancel the scheduled message.'**
  String get socialChatThreadCancelScheduledFailed;

  /// No description provided for @socialChatThreadShareLocation.
  ///
  /// In en, this message translates to:
  /// **'Share location'**
  String get socialChatThreadShareLocation;

  /// No description provided for @socialChatThreadCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'My current location'**
  String get socialChatThreadCurrentLocation;

  /// No description provided for @socialChatThreadLocationPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Location permission is required to share your current location.'**
  String get socialChatThreadLocationPermissionRequired;

  /// No description provided for @socialChatThreadLocationShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to share the location right now.'**
  String get socialChatThreadLocationShareFailed;

  /// No description provided for @socialChatThreadSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search in chat'**
  String get socialChatThreadSearchTooltip;

  /// No description provided for @socialChatThreadSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search messages'**
  String get socialChatThreadSearchHint;

  /// No description provided for @socialChatThreadSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching this chat...'**
  String get socialChatThreadSearching;

  /// No description provided for @socialChatThreadSearchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matches found in this chat.'**
  String get socialChatThreadSearchNoResults;

  /// No description provided for @socialChatThreadSearchResultCounter.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String socialChatThreadSearchResultCounter(int current, int total);

  /// No description provided for @socialChatThreadSearchPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous result'**
  String get socialChatThreadSearchPrevious;

  /// No description provided for @socialChatThreadSearchNext.
  ///
  /// In en, this message translates to:
  /// **'Next result'**
  String get socialChatThreadSearchNext;

  /// No description provided for @socialChatThreadSearchLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load in-chat search results.'**
  String get socialChatThreadSearchLoadFailed;

  /// No description provided for @socialChatThreadTranslateMessage.
  ///
  /// In en, this message translates to:
  /// **'Translate message'**
  String get socialChatThreadTranslateMessage;

  /// No description provided for @socialChatThreadHideTranslation.
  ///
  /// In en, this message translates to:
  /// **'Hide translation'**
  String get socialChatThreadHideTranslation;

  /// No description provided for @socialChatThreadTranslationFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to translate this message right now.'**
  String get socialChatThreadTranslationFailed;

  /// No description provided for @socialChatThreadTranslatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get socialChatThreadTranslatedLabel;

  /// No description provided for @socialChatThreadThemePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat theme'**
  String get socialChatThreadThemePickerTitle;

  /// No description provided for @socialChatThreadThemeDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get socialChatThreadThemeDefault;

  /// No description provided for @socialChatThreadThemeSunset.
  ///
  /// In en, this message translates to:
  /// **'Sunset'**
  String get socialChatThreadThemeSunset;

  /// No description provided for @socialChatThreadThemeOcean.
  ///
  /// In en, this message translates to:
  /// **'Ocean'**
  String get socialChatThreadThemeOcean;

  /// No description provided for @socialChatThreadThemeForest.
  ///
  /// In en, this message translates to:
  /// **'Forest'**
  String get socialChatThreadThemeForest;

  /// No description provided for @socialChatThreadThemeViolet.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get socialChatThreadThemeViolet;

  /// No description provided for @socialChatThreadThemeUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the chat theme right now.'**
  String get socialChatThreadThemeUpdateFailed;

  /// No description provided for @socialChatThreadGroupManage.
  ///
  /// In en, this message translates to:
  /// **'Manage group'**
  String get socialChatThreadGroupManage;

  /// No description provided for @socialChatThreadGroupLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load group details.'**
  String get socialChatThreadGroupLoadFailed;

  /// No description provided for @socialChatThreadGroupRename.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get socialChatThreadGroupRename;

  /// No description provided for @socialChatThreadGroupRenameHint.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get socialChatThreadGroupRenameHint;

  /// No description provided for @socialChatThreadGroupRenameSave.
  ///
  /// In en, this message translates to:
  /// **'Save name'**
  String get socialChatThreadGroupRenameSave;

  /// No description provided for @socialChatThreadGroupAddMembers.
  ///
  /// In en, this message translates to:
  /// **'Add members'**
  String get socialChatThreadGroupAddMembers;

  /// No description provided for @socialChatThreadGroupAddMembersFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to add members.'**
  String get socialChatThreadGroupAddMembersFailed;

  /// No description provided for @socialChatThreadGroupRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'Remove member'**
  String get socialChatThreadGroupRemoveMember;

  /// No description provided for @socialChatThreadGroupRemoveMemberConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from the group?'**
  String socialChatThreadGroupRemoveMemberConfirm(String name);

  /// No description provided for @socialChatThreadGroupRemoveMemberFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to remove the member.'**
  String get socialChatThreadGroupRemoveMemberFailed;

  /// No description provided for @socialChatThreadGroupPromoteAdmin.
  ///
  /// In en, this message translates to:
  /// **'Promote to admin'**
  String get socialChatThreadGroupPromoteAdmin;

  /// No description provided for @socialChatThreadGroupPromoteAdminFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to promote this member to admin.'**
  String get socialChatThreadGroupPromoteAdminFailed;

  /// No description provided for @socialChatThreadGroupDemoteAdmin.
  ///
  /// In en, this message translates to:
  /// **'Remove admin access'**
  String get socialChatThreadGroupDemoteAdmin;

  /// No description provided for @socialChatThreadGroupDemoteAdminFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to remove admin access.'**
  String get socialChatThreadGroupDemoteAdminFailed;

  /// No description provided for @socialChatThreadGroupLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave group'**
  String get socialChatThreadGroupLeave;

  /// No description provided for @socialChatThreadGroupLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Do you want to leave this group?'**
  String get socialChatThreadGroupLeaveConfirm;

  /// No description provided for @socialChatThreadGroupLeaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to leave the group.'**
  String get socialChatThreadGroupLeaveFailed;

  /// No description provided for @socialChatThreadGroupLeaveSuccess.
  ///
  /// In en, this message translates to:
  /// **'You left the group.'**
  String get socialChatThreadGroupLeaveSuccess;

  /// No description provided for @socialChatThreadGroupRemovedFromGroup.
  ///
  /// In en, this message translates to:
  /// **'You were removed from the group.'**
  String get socialChatThreadGroupRemovedFromGroup;

  /// No description provided for @socialChatThreadGroupRoleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get socialChatThreadGroupRoleOwner;

  /// No description provided for @socialChatThreadGroupRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get socialChatThreadGroupRoleAdmin;

  /// No description provided for @socialChatThreadGroupRoleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get socialChatThreadGroupRoleMember;

  /// No description provided for @socialChatThreadWriteMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Write your message...'**
  String get socialChatThreadWriteMessageHint;

  /// No description provided for @socialChatThreadDeletedMessage.
  ///
  /// In en, this message translates to:
  /// **'This message was deleted'**
  String get socialChatThreadDeletedMessage;

  /// No description provided for @socialChatThreadEdited.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get socialChatThreadEdited;

  /// No description provided for @socialChatThreadSeen.
  ///
  /// In en, this message translates to:
  /// **'Seen'**
  String get socialChatThreadSeen;

  /// No description provided for @socialChatThreadDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get socialChatThreadDelivered;

  /// No description provided for @socialChatThreadSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get socialChatThreadSent;

  /// No description provided for @socialChatThreadSavingReaction.
  ///
  /// In en, this message translates to:
  /// **'Saving reaction...'**
  String get socialChatThreadSavingReaction;

  /// No description provided for @socialInsightsImpressions.
  ///
  /// In en, this message translates to:
  /// **'Impressions'**
  String get socialInsightsImpressions;

  /// No description provided for @socialInsightsLikes.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get socialInsightsLikes;

  /// No description provided for @socialInsightsComments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get socialInsightsComments;

  /// No description provided for @socialInsightsSaves.
  ///
  /// In en, this message translates to:
  /// **'Saves'**
  String get socialInsightsSaves;

  /// No description provided for @socialInsightsReelViews.
  ///
  /// In en, this message translates to:
  /// **'Reel views'**
  String get socialInsightsReelViews;

  /// No description provided for @socialInsightsCompletion.
  ///
  /// In en, this message translates to:
  /// **'Completion'**
  String get socialInsightsCompletion;

  /// No description provided for @socialInsightsBestPostingTimes.
  ///
  /// In en, this message translates to:
  /// **'Best posting times'**
  String get socialInsightsBestPostingTimes;

  /// No description provided for @socialInsightsPostingHourSummary.
  ///
  /// In en, this message translates to:
  /// **'Hour {hour} - {posts}'**
  String socialInsightsPostingHourSummary(int hour, int posts);

  /// No description provided for @socialInsightsAudienceLocality.
  ///
  /// In en, this message translates to:
  /// **'Audience locality'**
  String get socialInsightsAudienceLocality;

  /// No description provided for @socialInsightsTopContent.
  ///
  /// In en, this message translates to:
  /// **'Top content'**
  String get socialInsightsTopContent;

  /// No description provided for @socialStoryPublishSharedReel.
  ///
  /// In en, this message translates to:
  /// **'Shared reel'**
  String get socialStoryPublishSharedReel;

  /// No description provided for @socialStoryPublishSharedPost.
  ///
  /// In en, this message translates to:
  /// **'Shared post'**
  String get socialStoryPublishSharedPost;

  /// No description provided for @socialStoryPublishEmptyError.
  ///
  /// In en, this message translates to:
  /// **'Add content before publishing the story.'**
  String get socialStoryPublishEmptyError;

  /// No description provided for @socialStoryPublishFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to publish the story.'**
  String get socialStoryPublishFailed;

  /// No description provided for @socialStoryPublishTitle.
  ///
  /// In en, this message translates to:
  /// **'Publish story'**
  String get socialStoryPublishTitle;

  /// No description provided for @socialStoryPublishSharingTitle.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get socialStoryPublishSharingTitle;

  /// No description provided for @socialStoryPublishSharingBody.
  ///
  /// In en, this message translates to:
  /// **'The story will be published using your current account privacy rules. You can save the draft locally or publish now.'**
  String get socialStoryPublishSharingBody;

  /// No description provided for @socialStoryPublishDraftSaved.
  ///
  /// In en, this message translates to:
  /// **'Draft saved.'**
  String get socialStoryPublishDraftSaved;

  /// No description provided for @socialStoryPublishSaveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save draft'**
  String get socialStoryPublishSaveDraft;

  /// No description provided for @socialStoryPublishPublishing.
  ///
  /// In en, this message translates to:
  /// **'Publishing...'**
  String get socialStoryPublishPublishing;

  /// No description provided for @startupIntroPreparingTitle.
  ///
  /// In en, this message translates to:
  /// **'Preparing Maslaki'**
  String get startupIntroPreparingTitle;

  /// No description provided for @startupIntroCheckingServer.
  ///
  /// In en, this message translates to:
  /// **'Checking server readiness before opening the app.'**
  String get startupIntroCheckingServer;

  /// No description provided for @startupIntroServerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The server is not reachable right now. You can retry in a moment.'**
  String get startupIntroServerUnavailable;

  /// No description provided for @startupIntroErrorDetails.
  ///
  /// In en, this message translates to:
  /// **'Error details: {details}'**
  String startupIntroErrorDetails(String details);

  /// No description provided for @startupIntroAttempts.
  ///
  /// In en, this message translates to:
  /// **'Attempts: {count}'**
  String startupIntroAttempts(int count);

  /// No description provided for @splashBrandName.
  ///
  /// In en, this message translates to:
  /// **'Maslaki'**
  String get splashBrandName;

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'Everything around you.'**
  String get splashTagline;

  /// No description provided for @splashServiceFood.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get splashServiceFood;

  /// No description provided for @splashServiceShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get splashServiceShopping;

  /// No description provided for @splashServiceTaxi.
  ///
  /// In en, this message translates to:
  /// **'Taxi'**
  String get splashServiceTaxi;

  /// No description provided for @splashServiceJobs.
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get splashServiceJobs;

  /// No description provided for @splashServiceCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get splashServiceCommunity;

  /// No description provided for @androidReliabilitySetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Android reliability setup'**
  String get androidReliabilitySetupTitle;

  /// No description provided for @androidReliabilitySetupBody.
  ///
  /// In en, this message translates to:
  /// **'These steps reduce missed rings, call issues, and dropped notifications.'**
  String get androidReliabilitySetupBody;

  /// No description provided for @androidReliabilityYourDevice.
  ///
  /// In en, this message translates to:
  /// **'Your device'**
  String get androidReliabilityYourDevice;

  /// No description provided for @androidReliabilityOemGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'OEM guide ({vendor})'**
  String androidReliabilityOemGuideTitle(String vendor);

  /// No description provided for @androidReliabilityCoveredProfiles.
  ///
  /// In en, this message translates to:
  /// **'Covered OEM profiles:'**
  String get androidReliabilityCoveredProfiles;

  /// No description provided for @androidReliabilityRequestPermissionsAgain.
  ///
  /// In en, this message translates to:
  /// **'Request permissions again'**
  String get androidReliabilityRequestPermissionsAgain;

  /// No description provided for @androidReliabilityOpenOemSettings.
  ///
  /// In en, this message translates to:
  /// **'Open OEM settings'**
  String get androidReliabilityOpenOemSettings;

  /// No description provided for @androidReliabilityConfigureFullScreenCalls.
  ///
  /// In en, this message translates to:
  /// **'Configure full-screen calls'**
  String get androidReliabilityConfigureFullScreenCalls;

  /// No description provided for @androidReliabilityPermissionStatus.
  ///
  /// In en, this message translates to:
  /// **'Permission status'**
  String get androidReliabilityPermissionStatus;

  /// No description provided for @androidReliabilityPermissionNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get androidReliabilityPermissionNotifications;

  /// No description provided for @androidReliabilityPermissionMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get androidReliabilityPermissionMicrophone;

  /// No description provided for @androidReliabilityPermissionLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get androidReliabilityPermissionLocation;

  /// No description provided for @androidReliabilityPermissionIgnoreBattery.
  ///
  /// In en, this message translates to:
  /// **'Ignore battery optimization'**
  String get androidReliabilityPermissionIgnoreBattery;

  /// No description provided for @androidReliabilityPermissionBluetoothCalls.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth (calls)'**
  String get androidReliabilityPermissionBluetoothCalls;

  /// No description provided for @androidReliabilityVendorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Generic Android'**
  String get androidReliabilityVendorGeneric;

  /// No description provided for @androidReliabilityVendorSamsung.
  ///
  /// In en, this message translates to:
  /// **'Samsung'**
  String get androidReliabilityVendorSamsung;

  /// No description provided for @androidReliabilityVendorXiaomi.
  ///
  /// In en, this message translates to:
  /// **'Xiaomi / Redmi / POCO'**
  String get androidReliabilityVendorXiaomi;

  /// No description provided for @androidReliabilityVendorHuawei.
  ///
  /// In en, this message translates to:
  /// **'Huawei / Honor'**
  String get androidReliabilityVendorHuawei;

  /// No description provided for @androidReliabilityVendorOppo.
  ///
  /// In en, this message translates to:
  /// **'OPPO / realme'**
  String get androidReliabilityVendorOppo;

  /// No description provided for @androidReliabilityVendorOnePlus.
  ///
  /// In en, this message translates to:
  /// **'OnePlus'**
  String get androidReliabilityVendorOnePlus;

  /// No description provided for @androidReliabilityVendorVivo.
  ///
  /// In en, this message translates to:
  /// **'vivo / iQOO'**
  String get androidReliabilityVendorVivo;

  /// No description provided for @androidReliabilityVendorAsus.
  ///
  /// In en, this message translates to:
  /// **'ASUS'**
  String get androidReliabilityVendorAsus;

  /// No description provided for @androidReliabilityVendorMotorola.
  ///
  /// In en, this message translates to:
  /// **'Motorola / Lenovo'**
  String get androidReliabilityVendorMotorola;

  /// No description provided for @androidReliabilityVendorNokia.
  ///
  /// In en, this message translates to:
  /// **'Nokia / HMD'**
  String get androidReliabilityVendorNokia;

  /// No description provided for @androidReliabilityVendorSony.
  ///
  /// In en, this message translates to:
  /// **'Sony'**
  String get androidReliabilityVendorSony;

  /// No description provided for @androidReliabilityVendorGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google Pixel'**
  String get androidReliabilityVendorGoogle;

  /// No description provided for @androidReliabilityVendorMeizu.
  ///
  /// In en, this message translates to:
  /// **'Meizu'**
  String get androidReliabilityVendorMeizu;

  /// No description provided for @androidReliabilityVendorTranssion.
  ///
  /// In en, this message translates to:
  /// **'Transsion (Tecno/Infinix/itel)'**
  String get androidReliabilityVendorTranssion;

  /// No description provided for @androidReliabilityVendorNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing'**
  String get androidReliabilityVendorNothing;

  /// No description provided for @androidReliabilityVendorZte.
  ///
  /// In en, this message translates to:
  /// **'ZTE'**
  String get androidReliabilityVendorZte;

  /// No description provided for @androidReliabilityVendorLg.
  ///
  /// In en, this message translates to:
  /// **'LG'**
  String get androidReliabilityVendorLg;

  /// No description provided for @androidReliabilityVendorWiko.
  ///
  /// In en, this message translates to:
  /// **'Wiko'**
  String get androidReliabilityVendorWiko;

  /// No description provided for @androidReliabilityVendorBlackview.
  ///
  /// In en, this message translates to:
  /// **'Blackview'**
  String get androidReliabilityVendorBlackview;

  /// No description provided for @androidReliabilityVendorUnihertz.
  ///
  /// In en, this message translates to:
  /// **'Unihertz'**
  String get androidReliabilityVendorUnihertz;

  /// No description provided for @adminDeliveryApprovalsTitle.
  ///
  /// In en, this message translates to:
  /// **'App delivery approvals'**
  String get adminDeliveryApprovalsTitle;

  /// No description provided for @adminDeliveryApprovalsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No pending app delivery approvals.'**
  String get adminDeliveryApprovalsEmpty;

  /// No description provided for @adminDeliveryApprovalsCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created at: {date}'**
  String adminDeliveryApprovalsCreatedAt(String date);

  /// No description provided for @adminDeliveryApprovalsApproveCourier.
  ///
  /// In en, this message translates to:
  /// **'Approve courier'**
  String get adminDeliveryApprovalsApproveCourier;

  /// No description provided for @socialProfileArchiveStoryRestored.
  ///
  /// In en, this message translates to:
  /// **'Story restored.'**
  String get socialProfileArchiveStoryRestored;

  /// No description provided for @socialProfileArchiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get socialProfileArchiveTitle;

  /// No description provided for @socialProfileArchivePosts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get socialProfileArchivePosts;

  /// No description provided for @socialProfileArchiveReels.
  ///
  /// In en, this message translates to:
  /// **'Reels'**
  String get socialProfileArchiveReels;

  /// No description provided for @socialProfileArchiveStories.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get socialProfileArchiveStories;

  /// No description provided for @socialProfileArchiveReelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reels archive'**
  String get socialProfileArchiveReelsTitle;

  /// No description provided for @socialProfileArchiveEmptyStories.
  ///
  /// In en, this message translates to:
  /// **'No archived stories yet.'**
  String get socialProfileArchiveEmptyStories;

  /// No description provided for @socialProfileArchiveMe.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get socialProfileArchiveMe;

  /// No description provided for @socialProfileArchiveStoryFallback.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get socialProfileArchiveStoryFallback;

  /// No description provided for @socialFeedControlsSearchSocial.
  ///
  /// In en, this message translates to:
  /// **'Search social'**
  String get socialFeedControlsSearchSocial;

  /// No description provided for @socialFeedControlsCreatePostOrStory.
  ///
  /// In en, this message translates to:
  /// **'Post or story'**
  String get socialFeedControlsCreatePostOrStory;

  /// No description provided for @socialFeedControlsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No content yet'**
  String get socialFeedControlsEmptyTitle;

  /// No description provided for @socialFeedControlsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Start with a new post or story to get the feed moving.'**
  String get socialFeedControlsEmptyBody;

  /// No description provided for @socialFeedControlsStartNow.
  ///
  /// In en, this message translates to:
  /// **'Start now'**
  String get socialFeedControlsStartNow;

  /// No description provided for @socialFeedControlsPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get socialFeedControlsPhotos;

  /// No description provided for @socialFeedControlsReels.
  ///
  /// In en, this message translates to:
  /// **'Reels'**
  String get socialFeedControlsReels;

  /// No description provided for @socialFeedControlsReviews.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get socialFeedControlsReviews;

  /// No description provided for @socialFeedControlsTextPosts.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get socialFeedControlsTextPosts;

  /// No description provided for @socialCollectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get socialCollectionsTitle;

  /// No description provided for @socialCollectionsTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get socialCollectionsTitleLabel;

  /// No description provided for @socialCollectionsDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get socialCollectionsDescriptionLabel;

  /// No description provided for @socialCollectionsCreateCollection.
  ///
  /// In en, this message translates to:
  /// **'Create collection'**
  String get socialCollectionsCreateCollection;

  /// No description provided for @socialCollectionsSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get socialCollectionsSaveChanges;

  /// No description provided for @socialCollectionsItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String socialCollectionsItemsCount(int count);

  /// No description provided for @socialSaveSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Save content'**
  String get socialSaveSheetTitle;

  /// No description provided for @socialSaveSheetBody.
  ///
  /// In en, this message translates to:
  /// **'Choose the collections where this content should be saved.'**
  String get socialSaveSheetBody;

  /// No description provided for @socialSaveSheetUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update save'**
  String get socialSaveSheetUpdate;

  /// No description provided for @socialSaveSheetSaveNow.
  ///
  /// In en, this message translates to:
  /// **'Save now'**
  String get socialSaveSheetSaveNow;

  /// No description provided for @socialStoryViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get socialStoryViewerTitle;

  /// No description provided for @socialStoryViewerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This story is unavailable to you or has already expired.'**
  String get socialStoryViewerUnavailable;

  /// No description provided for @socialStoryViewerLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the story.'**
  String get socialStoryViewerLoadFailed;

  /// No description provided for @socialStoryToolDrawTitle.
  ///
  /// In en, this message translates to:
  /// **'Draw directly on the canvas'**
  String get socialStoryToolDrawTitle;

  /// No description provided for @socialStoryToolDrawBody.
  ///
  /// In en, this message translates to:
  /// **'Drag your finger over the story to add strokes, then close the tool when done.'**
  String get socialStoryToolDrawBody;

  /// No description provided for @socialStoryToolReplaceMediaTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace media'**
  String get socialStoryToolReplaceMediaTitle;

  /// No description provided for @socialStoryToolReplaceMediaBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a new photo or video while keeping your current layers.'**
  String get socialStoryToolReplaceMediaBody;

  /// No description provided for @socialStoryToolChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get socialStoryToolChooseFile;

  /// No description provided for @socialStoryToolWriteTextHint.
  ///
  /// In en, this message translates to:
  /// **'Write your text here'**
  String get socialStoryToolWriteTextHint;

  /// No description provided for @socialStoryToolTextColor.
  ///
  /// In en, this message translates to:
  /// **'Text color'**
  String get socialStoryToolTextColor;

  /// No description provided for @socialStoryToolTextBackground.
  ///
  /// In en, this message translates to:
  /// **'Text background'**
  String get socialStoryToolTextBackground;

  /// No description provided for @socialStoryToolSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get socialStoryToolSize;

  /// No description provided for @socialBasmayaAddPost.
  ///
  /// In en, this message translates to:
  /// **'Add post'**
  String get socialBasmayaAddPost;

  /// No description provided for @socialBasmayaAddStory.
  ///
  /// In en, this message translates to:
  /// **'Add story'**
  String get socialBasmayaAddStory;

  /// No description provided for @socialBasmayaMyReports.
  ///
  /// In en, this message translates to:
  /// **'My reports'**
  String get socialBasmayaMyReports;

  /// No description provided for @socialBasmayaSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Social search'**
  String get socialBasmayaSearchTooltip;

  /// No description provided for @socialBasmayaFriendRequests.
  ///
  /// In en, this message translates to:
  /// **'Friend requests'**
  String get socialBasmayaFriendRequests;

  /// No description provided for @socialBasmayaMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get socialBasmayaMenu;

  /// No description provided for @socialBasmayaBrand.
  ///
  /// In en, this message translates to:
  /// **'Shdysir'**
  String get socialBasmayaBrand;

  /// No description provided for @socialBasmayaHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get socialBasmayaHome;

  /// No description provided for @socialBasmayaCompound.
  ///
  /// In en, this message translates to:
  /// **'Compound'**
  String get socialBasmayaCompound;

  /// No description provided for @socialBasmayaBuilding.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get socialBasmayaBuilding;

  /// No description provided for @socialBasmayaMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get socialBasmayaMessages;

  /// No description provided for @socialBasmayaProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get socialBasmayaProfile;

  /// No description provided for @socialBasmayaUnavailableScope.
  ///
  /// In en, this message translates to:
  /// **'This section is currently unavailable based on account address.'**
  String get socialBasmayaUnavailableScope;

  /// No description provided for @socialBasmayaCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get socialBasmayaCommunity;

  /// No description provided for @socialBasmayaMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get socialBasmayaMore;

  /// No description provided for @socialStoryComposerDraftSaved.
  ///
  /// In en, this message translates to:
  /// **'Draft saved locally.'**
  String get socialStoryComposerDraftSaved;

  /// No description provided for @socialStoryComposerTitle.
  ///
  /// In en, this message translates to:
  /// **'Story composer'**
  String get socialStoryComposerTitle;

  /// No description provided for @socialStoryComposerDeleteLayer.
  ///
  /// In en, this message translates to:
  /// **'Delete layer'**
  String get socialStoryComposerDeleteLayer;

  /// No description provided for @socialStoryComposerToolText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get socialStoryComposerToolText;

  /// No description provided for @socialStoryComposerToolMention.
  ///
  /// In en, this message translates to:
  /// **'Mention'**
  String get socialStoryComposerToolMention;

  /// No description provided for @socialStoryComposerToolStickers.
  ///
  /// In en, this message translates to:
  /// **'Stickers'**
  String get socialStoryComposerToolStickers;

  /// No description provided for @socialStoryComposerToolDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get socialStoryComposerToolDraw;

  /// No description provided for @socialStoryComposerToolMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get socialStoryComposerToolMedia;

  /// No description provided for @socialStoryEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Start a story'**
  String get socialStoryEntryTitle;

  /// No description provided for @socialStoryEntrySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a clean starting point, then finish editing in the full story composer.'**
  String get socialStoryEntrySubtitle;

  /// No description provided for @socialStoryEntryMediaTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo or video'**
  String get socialStoryEntryMediaTitle;

  /// No description provided for @socialStoryEntryMediaBody.
  ///
  /// In en, this message translates to:
  /// **'Start from media, then layer text, mentions, or stickers on top.'**
  String get socialStoryEntryMediaBody;

  /// No description provided for @socialStoryEntryTextTitle.
  ///
  /// In en, this message translates to:
  /// **'Text story'**
  String get socialStoryEntryTextTitle;

  /// No description provided for @socialStoryEntryTextBody.
  ///
  /// In en, this message translates to:
  /// **'Start from a clean text-first canvas.'**
  String get socialStoryEntryTextBody;

  /// No description provided for @commonStore.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get commonStore;

  /// No description provided for @socialFeedCreatePostTitle.
  ///
  /// In en, this message translates to:
  /// **'New post'**
  String get socialFeedCreatePostTitle;

  /// No description provided for @socialFeedCreatePostBody.
  ///
  /// In en, this message translates to:
  /// **'Create a post, image, or review.'**
  String get socialFeedCreatePostBody;

  /// No description provided for @socialFeedCreateStoryTitle.
  ///
  /// In en, this message translates to:
  /// **'New story'**
  String get socialFeedCreateStoryTitle;

  /// No description provided for @socialFeedCreateStoryBody.
  ///
  /// In en, this message translates to:
  /// **'Open the story composer on a full screen canvas.'**
  String get socialFeedCreateStoryBody;

  /// No description provided for @socialFeedDrawerTitle.
  ///
  /// In en, this message translates to:
  /// **'Maslaki Social'**
  String get socialFeedDrawerTitle;

  /// No description provided for @socialFeedDrawerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Content, activity, and communities in one place.'**
  String get socialFeedDrawerSubtitle;

  /// No description provided for @socialCommunityInvalidVideoUrl.
  ///
  /// In en, this message translates to:
  /// **'Invalid video URL'**
  String get socialCommunityInvalidVideoUrl;

  /// No description provided for @socialCommunityVideoLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load video'**
  String get socialCommunityVideoLoadFailed;

  /// No description provided for @socialCommunityVideoUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Video playback is not supported on this platform'**
  String get socialCommunityVideoUnsupported;

  /// No description provided for @socialCommunityMuted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get socialCommunityMuted;

  /// No description provided for @socialCommunitySoundOn.
  ///
  /// In en, this message translates to:
  /// **'Sound on'**
  String get socialCommunitySoundOn;

  /// No description provided for @socialCommunityKindReel.
  ///
  /// In en, this message translates to:
  /// **'Reel'**
  String get socialCommunityKindReel;

  /// No description provided for @socialCommunityKindReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get socialCommunityKindReview;

  /// No description provided for @socialCommunityKindPost.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get socialCommunityKindPost;

  /// No description provided for @socialCommunityTapToOpenStore.
  ///
  /// In en, this message translates to:
  /// **'Tap to open store page'**
  String get socialCommunityTapToOpenStore;

  /// No description provided for @socialCommunityLikes.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get socialCommunityLikes;

  /// No description provided for @socialCommunityMessageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get socialCommunityMessageDeleted;

  /// No description provided for @socialCommunityUserFallback.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get socialCommunityUserFallback;

  /// No description provided for @socialCommunityReplyToMessage.
  ///
  /// In en, this message translates to:
  /// **'Reply to a message'**
  String get socialCommunityReplyToMessage;

  /// No description provided for @socialCommunityReactions.
  ///
  /// In en, this message translates to:
  /// **'reactions'**
  String get socialCommunityReactions;

  /// No description provided for @socialCommunityEdited.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get socialCommunityEdited;

  /// No description provided for @socialCommunityVideoPlayFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to play video'**
  String get socialCommunityVideoPlayFailed;

  /// No description provided for @socialCommunityImageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load image'**
  String get socialCommunityImageLoadFailed;

  /// No description provided for @socialConnectionsRoleMerchant.
  ///
  /// In en, this message translates to:
  /// **'Merchant'**
  String get socialConnectionsRoleMerchant;

  /// No description provided for @socialConnectionsRoleDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get socialConnectionsRoleDelivery;

  /// No description provided for @socialConnectionsRoleTaxiCaptain.
  ///
  /// In en, this message translates to:
  /// **'Taxi captain'**
  String get socialConnectionsRoleTaxiCaptain;

  /// No description provided for @socialConnectionsRoleSuperAdmin.
  ///
  /// In en, this message translates to:
  /// **'Super admin'**
  String get socialConnectionsRoleSuperAdmin;

  /// No description provided for @socialConnectionsRoleUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get socialConnectionsRoleUser;

  /// No description provided for @socialConnectionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No users in this section.'**
  String get socialConnectionsEmpty;

  /// No description provided for @socialPostCardOpenLinkedCommerce.
  ///
  /// In en, this message translates to:
  /// **'Open linked commerce'**
  String get socialPostCardOpenLinkedCommerce;

  /// No description provided for @socialOpenStoreCta.
  ///
  /// In en, this message translates to:
  /// **'Open store'**
  String get socialOpenStoreCta;

  /// No description provided for @socialPostCardBadgePremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get socialPostCardBadgePremium;

  /// No description provided for @socialShellHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get socialShellHome;

  /// No description provided for @socialShellExplore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get socialShellExplore;

  /// No description provided for @socialShellReels.
  ///
  /// In en, this message translates to:
  /// **'Reels'**
  String get socialShellReels;

  /// No description provided for @socialShellMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get socialShellMessages;

  /// No description provided for @socialShellActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get socialShellActivity;

  /// No description provided for @adCampaignDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Campaign details'**
  String get adCampaignDetailsTitle;

  /// No description provided for @adCampaignDetailsRelatedMerchant.
  ///
  /// In en, this message translates to:
  /// **'Related merchant'**
  String get adCampaignDetailsRelatedMerchant;

  /// No description provided for @adCampaignDetailsDescriptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Campaign description'**
  String get adCampaignDetailsDescriptionTitle;

  /// No description provided for @socialProfilePostsRestored.
  ///
  /// In en, this message translates to:
  /// **'Content restored.'**
  String get socialProfilePostsRestored;

  /// No description provided for @socialProfilePostsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No content in this section.'**
  String get socialProfilePostsEmpty;

  /// No description provided for @socialProfilePostsRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get socialProfilePostsRestore;

  /// No description provided for @socialProfilePostsLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get socialProfilePostsLoadMore;

  /// No description provided for @appBarQuickActionsQuickAccess.
  ///
  /// In en, this message translates to:
  /// **'Quick access'**
  String get appBarQuickActionsQuickAccess;

  /// No description provided for @merchantAutoMatchSuggestionTitle.
  ///
  /// In en, this message translates to:
  /// **'Amount matching suggestion'**
  String get merchantAutoMatchSuggestionTitle;

  /// No description provided for @merchantAutoMatchSuggestionUseHigher.
  ///
  /// In en, this message translates to:
  /// **'Use the nearest higher amount'**
  String get merchantAutoMatchSuggestionUseHigher;

  /// No description provided for @merchantAutoMatchSuggestionUseLower.
  ///
  /// In en, this message translates to:
  /// **'Use the nearest lower amount'**
  String get merchantAutoMatchSuggestionUseLower;

  /// No description provided for @adminFinancialKpiTotalSales.
  ///
  /// In en, this message translates to:
  /// **'Total sales'**
  String get adminFinancialKpiTotalSales;

  /// No description provided for @adminFinancialKpiTotalSalesHint.
  ///
  /// In en, this message translates to:
  /// **'All-time merchant sales'**
  String get adminFinancialKpiTotalSalesHint;

  /// No description provided for @adminFinancialKpiTotalCollected.
  ///
  /// In en, this message translates to:
  /// **'Total collected'**
  String get adminFinancialKpiTotalCollected;

  /// No description provided for @adminFinancialKpiTotalCollectedHint.
  ///
  /// In en, this message translates to:
  /// **'Confirmed collections only'**
  String get adminFinancialKpiTotalCollectedHint;

  /// No description provided for @adminFinancialKpiTotalReceivables.
  ///
  /// In en, this message translates to:
  /// **'Total receivables'**
  String get adminFinancialKpiTotalReceivables;

  /// No description provided for @adminFinancialKpiOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding: {amount}'**
  String adminFinancialKpiOutstanding(String amount);

  /// No description provided for @adminFinancialKpiTotalReceivablesHint.
  ///
  /// In en, this message translates to:
  /// **'Financial net after collections'**
  String get adminFinancialKpiTotalReceivablesHint;

  /// No description provided for @customerStyleHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Fashion hub'**
  String get customerStyleHubTitle;

  /// No description provided for @customerStyleHubHeaderTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose by what you need'**
  String get customerStyleHubHeaderTitle;

  /// No description provided for @customerStyleHubHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clothing, shoes, bags, care, and fragrance with a clearer split for women and men.'**
  String get customerStyleHubHeaderSubtitle;

  /// No description provided for @customerStyleHubWomenSection.
  ///
  /// In en, this message translates to:
  /// **'Women'**
  String get customerStyleHubWomenSection;

  /// No description provided for @customerStyleHubMenSection.
  ///
  /// In en, this message translates to:
  /// **'Men'**
  String get customerStyleHubMenSection;

  /// No description provided for @customerStyleHubWomenClothingTitle.
  ///
  /// In en, this message translates to:
  /// **'Women clothing'**
  String get customerStyleHubWomenClothingTitle;

  /// No description provided for @customerStyleHubWomenClothingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Dresses and abayas'**
  String get customerStyleHubWomenClothingSubtitle;

  /// No description provided for @customerStyleHubWomenShoesTitle.
  ///
  /// In en, this message translates to:
  /// **'Women shoes'**
  String get customerStyleHubWomenShoesTitle;

  /// No description provided for @customerStyleHubWomenShoesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Heels and sneakers'**
  String get customerStyleHubWomenShoesSubtitle;

  /// No description provided for @customerStyleHubBagsTitle.
  ///
  /// In en, this message translates to:
  /// **'Bags & accessories'**
  String get customerStyleHubBagsTitle;

  /// No description provided for @customerStyleHubBagsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bags and watches'**
  String get customerStyleHubBagsSubtitle;

  /// No description provided for @customerStyleHubBeautyTitle.
  ///
  /// In en, this message translates to:
  /// **'Beauty & care'**
  String get customerStyleHubBeautyTitle;

  /// No description provided for @customerStyleHubBeautySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Perfume and makeup'**
  String get customerStyleHubBeautySubtitle;

  /// No description provided for @customerStyleHubMenClothingTitle.
  ///
  /// In en, this message translates to:
  /// **'Men clothing'**
  String get customerStyleHubMenClothingTitle;

  /// No description provided for @customerStyleHubMenClothingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Casual and formal'**
  String get customerStyleHubMenClothingSubtitle;

  /// No description provided for @customerStyleHubMenShoesTitle.
  ///
  /// In en, this message translates to:
  /// **'Men shoes'**
  String get customerStyleHubMenShoesTitle;

  /// No description provided for @customerStyleHubMenShoesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Formal and sport'**
  String get customerStyleHubMenShoesSubtitle;

  /// No description provided for @customerStyleHubMenFragranceTitle.
  ///
  /// In en, this message translates to:
  /// **'Men fragrance'**
  String get customerStyleHubMenFragranceTitle;

  /// No description provided for @customerStyleHubMenFragranceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily fragrance'**
  String get customerStyleHubMenFragranceSubtitle;

  /// No description provided for @customerStyleHubSportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sports gear'**
  String get customerStyleHubSportsTitle;

  /// No description provided for @customerStyleHubSportsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clothing and gear'**
  String get customerStyleHubSportsSubtitle;

  /// No description provided for @customerElectronicsHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Electronics hub'**
  String get customerElectronicsHubTitle;

  /// No description provided for @customerElectronicsHubHeaderTitle.
  ///
  /// In en, this message translates to:
  /// **'Electronics and tech in one place'**
  String get customerElectronicsHubHeaderTitle;

  /// No description provided for @customerElectronicsHubHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Home appliances, electrical accessories, phones, and daily tech.'**
  String get customerElectronicsHubHeaderSubtitle;

  /// No description provided for @customerElectronicsHubHomeAppliancesTitle.
  ///
  /// In en, this message translates to:
  /// **'Home appliances'**
  String get customerElectronicsHubHomeAppliancesTitle;

  /// No description provided for @customerElectronicsHubHomeAppliancesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily home essentials'**
  String get customerElectronicsHubHomeAppliancesSubtitle;

  /// No description provided for @customerElectronicsHubSmallAppliancesTitle.
  ///
  /// In en, this message translates to:
  /// **'Small appliances'**
  String get customerElectronicsHubSmallAppliancesTitle;

  /// No description provided for @customerElectronicsHubSmallAppliancesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Kitchen and daily use'**
  String get customerElectronicsHubSmallAppliancesSubtitle;

  /// No description provided for @customerElectronicsHubAccessoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Electrical accessories'**
  String get customerElectronicsHubAccessoriesTitle;

  /// No description provided for @customerElectronicsHubAccessoriesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Switches, cables, and plugs'**
  String get customerElectronicsHubAccessoriesSubtitle;

  /// No description provided for @customerElectronicsHubPhonesTitle.
  ///
  /// In en, this message translates to:
  /// **'Phones & tech'**
  String get customerElectronicsHubPhonesTitle;

  /// No description provided for @customerElectronicsHubPhonesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Phones, accessories, and tech'**
  String get customerElectronicsHubPhonesSubtitle;

  /// No description provided for @customerFoodHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Food & drinks'**
  String get customerFoodHubTitle;

  /// No description provided for @customerFoodHubHeaderTitle.
  ///
  /// In en, this message translates to:
  /// **'All food choices in one place'**
  String get customerFoodHubHeaderTitle;

  /// No description provided for @customerFoodHubHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restaurants, desserts, bakery, coffee, and drinks in one clear flow.'**
  String get customerFoodHubHeaderSubtitle;

  /// No description provided for @customerFoodHubRestaurantsTitle.
  ///
  /// In en, this message translates to:
  /// **'Restaurants'**
  String get customerFoodHubRestaurantsTitle;

  /// No description provided for @customerFoodHubRestaurantsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily meals and quick bites'**
  String get customerFoodHubRestaurantsSubtitle;

  /// No description provided for @customerFoodHubDessertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Desserts'**
  String get customerFoodHubDessertsTitle;

  /// No description provided for @customerFoodHubDessertsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cake, baklava, and kunafa'**
  String get customerFoodHubDessertsSubtitle;

  /// No description provided for @customerFoodHubBakeryTitle.
  ///
  /// In en, this message translates to:
  /// **'Bakery'**
  String get customerFoodHubBakeryTitle;

  /// No description provided for @customerFoodHubBakerySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fresh bakery every day'**
  String get customerFoodHubBakerySubtitle;

  /// No description provided for @customerFoodHubCoffeeTitle.
  ///
  /// In en, this message translates to:
  /// **'Coffee & drinks'**
  String get customerFoodHubCoffeeTitle;

  /// No description provided for @customerFoodHubCoffeeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hot and cold drinks all day'**
  String get customerFoodHubCoffeeSubtitle;

  /// No description provided for @customerHomeShoppingHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Home shopping'**
  String get customerHomeShoppingHubTitle;

  /// No description provided for @customerHomeShoppingHubHeaderTitle.
  ///
  /// In en, this message translates to:
  /// **'Everything for home, in one place'**
  String get customerHomeShoppingHubHeaderTitle;

  /// No description provided for @customerHomeShoppingHubHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Groceries, produce, meats, houseware, gifts, and personal care.'**
  String get customerHomeShoppingHubHeaderSubtitle;

  /// No description provided for @customerHomeShoppingHubGroceriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Groceries & cleaning'**
  String get customerHomeShoppingHubGroceriesTitle;

  /// No description provided for @customerHomeShoppingHubGroceriesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily home shopping'**
  String get customerHomeShoppingHubGroceriesSubtitle;

  /// No description provided for @customerHomeShoppingHubProduceTitle.
  ///
  /// In en, this message translates to:
  /// **'Fruits & vegetables'**
  String get customerHomeShoppingHubProduceTitle;

  /// No description provided for @customerHomeShoppingHubProduceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fresh produce every day'**
  String get customerHomeShoppingHubProduceSubtitle;

  /// No description provided for @customerHomeShoppingHubMeatTitle.
  ///
  /// In en, this message translates to:
  /// **'Meat & poultry'**
  String get customerHomeShoppingHubMeatTitle;

  /// No description provided for @customerHomeShoppingHubMeatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Butchery and frozen items'**
  String get customerHomeShoppingHubMeatSubtitle;

  /// No description provided for @customerHomeShoppingHubGiftsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stationery, gifts & flowers'**
  String get customerHomeShoppingHubGiftsTitle;

  /// No description provided for @customerHomeShoppingHubGiftsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Occasions and wrapping'**
  String get customerHomeShoppingHubGiftsSubtitle;

  /// No description provided for @customerHomeShoppingHubHousewareTitle.
  ///
  /// In en, this message translates to:
  /// **'Houseware'**
  String get customerHomeShoppingHubHousewareTitle;

  /// No description provided for @customerHomeShoppingHubHousewareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Kitchen and organization'**
  String get customerHomeShoppingHubHousewareSubtitle;

  /// No description provided for @customerHomeShoppingHubPersonalCareTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal care'**
  String get customerHomeShoppingHubPersonalCareTitle;

  /// No description provided for @customerHomeShoppingHubPersonalCareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Perfumes and essentials'**
  String get customerHomeShoppingHubPersonalCareSubtitle;

  /// No description provided for @socialStoryArchiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Story archive'**
  String get socialStoryArchiveTitle;

  /// No description provided for @socialStoryArchiveEmpty.
  ///
  /// In en, this message translates to:
  /// **'No archived stories yet.'**
  String get socialStoryArchiveEmpty;

  /// No description provided for @socialStoryArchiveMe.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get socialStoryArchiveMe;

  /// No description provided for @socialStoryArchiveFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get socialStoryArchiveFallbackTitle;

  /// No description provided for @socialStoriesStripEmpty.
  ///
  /// In en, this message translates to:
  /// **'No stories yet'**
  String get socialStoriesStripEmpty;

  /// No description provided for @socialStoriesStripAdd.
  ///
  /// In en, this message translates to:
  /// **'Add story'**
  String get socialStoriesStripAdd;

  /// No description provided for @settingsUsageGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'App usage guide'**
  String get settingsUsageGuideTitle;

  /// No description provided for @settingsUsageGuideIntro.
  ///
  /// In en, this message translates to:
  /// **'This guide explains every app interface: what you see, what you can do, and how to navigate quickly.'**
  String get settingsUsageGuideIntro;

  /// No description provided for @settingsUsageGuideMainHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Main home'**
  String get settingsUsageGuideMainHomeTitle;

  /// No description provided for @settingsUsageGuideMainHomeDescription.
  ///
  /// In en, this message translates to:
  /// **'Fast navigation between the four app modules.'**
  String get settingsUsageGuideMainHomeDescription;

  /// No description provided for @settingsUsageGuideMainHomeStepMaslaki.
  ///
  /// In en, this message translates to:
  /// **'Maslaki: shopping, orders, and merchants.'**
  String get settingsUsageGuideMainHomeStepMaslaki;

  /// No description provided for @settingsUsageGuideMainHomeStepTaxi.
  ///
  /// In en, this message translates to:
  /// **'Maslaki Taxi: taxi requests and live bids.'**
  String get settingsUsageGuideMainHomeStepTaxi;

  /// No description provided for @settingsUsageGuideMainHomeStepCommunity.
  ///
  /// In en, this message translates to:
  /// **'Basmaya Community: social feed and bills.'**
  String get settingsUsageGuideMainHomeStepCommunity;

  /// No description provided for @settingsUsageGuideMainHomeStepJobs.
  ///
  /// In en, this message translates to:
  /// **'Basmaya Jobs: discover and apply for jobs.'**
  String get settingsUsageGuideMainHomeStepJobs;

  /// No description provided for @settingsUsageGuideCustomerTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer interface'**
  String get settingsUsageGuideCustomerTitle;

  /// No description provided for @settingsUsageGuideCustomerDescription.
  ///
  /// In en, this message translates to:
  /// **'Order, track delivery, and review services.'**
  String get settingsUsageGuideCustomerDescription;

  /// No description provided for @settingsUsageGuideCustomerStepBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse categories, then enter the store or restaurant.'**
  String get settingsUsageGuideCustomerStepBrowse;

  /// No description provided for @settingsUsageGuideCustomerStepCart.
  ///
  /// In en, this message translates to:
  /// **'Add products to the cart, then complete the order.'**
  String get settingsUsageGuideCustomerStepCart;

  /// No description provided for @settingsUsageGuideCustomerStepTrack.
  ///
  /// In en, this message translates to:
  /// **'Track the order status in real time from the orders screen.'**
  String get settingsUsageGuideCustomerStepTrack;

  /// No description provided for @settingsUsageGuideCustomerStepReview.
  ///
  /// In en, this message translates to:
  /// **'After delivery, you can rate the order or publish a review.'**
  String get settingsUsageGuideCustomerStepReview;

  /// No description provided for @settingsUsageGuideStoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Store owner interface'**
  String get settingsUsageGuideStoreTitle;

  /// No description provided for @settingsUsageGuideStoreDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage products, orders, and store staff.'**
  String get settingsUsageGuideStoreDescription;

  /// No description provided for @settingsUsageGuideStoreStepCategories.
  ///
  /// In en, this message translates to:
  /// **'Create categories first, then assign each product to one category.'**
  String get settingsUsageGuideStoreStepCategories;

  /// No description provided for @settingsUsageGuideStoreStepStatusFlow.
  ///
  /// In en, this message translates to:
  /// **'Update the order status using the required status flow.'**
  String get settingsUsageGuideStoreStepStatusFlow;

  /// No description provided for @settingsUsageGuideStoreStepAssignCourier.
  ///
  /// In en, this message translates to:
  /// **'Assign the courier before marking the order ready for delivery.'**
  String get settingsUsageGuideStoreStepAssignCourier;

  /// No description provided for @settingsUsageGuideStoreStepStaff.
  ///
  /// In en, this message translates to:
  /// **'Use staff management to add delivery, accountant, or HR staff.'**
  String get settingsUsageGuideStoreStepStaff;

  /// No description provided for @settingsUsageGuideDeliveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery interface'**
  String get settingsUsageGuideDeliveryTitle;

  /// No description provided for @settingsUsageGuideDeliveryDescription.
  ///
  /// In en, this message translates to:
  /// **'Receive orders, deliver them, and confirm settlements.'**
  String get settingsUsageGuideDeliveryDescription;

  /// No description provided for @settingsUsageGuideDeliveryStepAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept ready orders, then start the delivery route.'**
  String get settingsUsageGuideDeliveryStepAccept;

  /// No description provided for @settingsUsageGuideDeliveryStepStatusFlow.
  ///
  /// In en, this message translates to:
  /// **'Update the status flow: picked up -> arrived -> delivered.'**
  String get settingsUsageGuideDeliveryStepStatusFlow;

  /// No description provided for @settingsUsageGuideDeliveryStepCloseDay.
  ///
  /// In en, this message translates to:
  /// **'Close the day to submit the pending settlement to accounting.'**
  String get settingsUsageGuideDeliveryStepCloseDay;

  /// No description provided for @settingsUsageGuideDeliveryStepNotifications.
  ///
  /// In en, this message translates to:
  /// **'Follow your notifications instantly for new assignments.'**
  String get settingsUsageGuideDeliveryStepNotifications;

  /// No description provided for @settingsUsageGuideTaxiTitle.
  ///
  /// In en, this message translates to:
  /// **'Taxi captain interface'**
  String get settingsUsageGuideTaxiTitle;

  /// No description provided for @settingsUsageGuideTaxiDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage trips, bids, and calls.'**
  String get settingsUsageGuideTaxiDescription;

  /// No description provided for @settingsUsageGuideTaxiStepPresence.
  ///
  /// In en, this message translates to:
  /// **'Enable presence so nearby ride requests can reach you.'**
  String get settingsUsageGuideTaxiStepPresence;

  /// No description provided for @settingsUsageGuideTaxiStepBid.
  ///
  /// In en, this message translates to:
  /// **'Submit a clear fare bid and wait for the rider to accept it.'**
  String get settingsUsageGuideTaxiStepBid;

  /// No description provided for @settingsUsageGuideTaxiStepChat.
  ///
  /// In en, this message translates to:
  /// **'Use in-trip chat and call tools while the ride is active.'**
  String get settingsUsageGuideTaxiStepChat;

  /// No description provided for @settingsUsageGuideTaxiStepStatusFlow.
  ///
  /// In en, this message translates to:
  /// **'Keep updating the trip state until it reaches final completion.'**
  String get settingsUsageGuideTaxiStepStatusFlow;

  /// No description provided for @settingsUsageGuideCommunityTitle.
  ///
  /// In en, this message translates to:
  /// **'Basmaya community'**
  String get settingsUsageGuideCommunityTitle;

  /// No description provided for @settingsUsageGuideCommunityDescription.
  ///
  /// In en, this message translates to:
  /// **'Hierarchical posts, chats, and announcements.'**
  String get settingsUsageGuideCommunityDescription;

  /// No description provided for @settingsUsageGuideCommunityStepScopes.
  ///
  /// In en, this message translates to:
  /// **'The general feed is for everyone, while the block feed is limited to block members.'**
  String get settingsUsageGuideCommunityStepScopes;

  /// No description provided for @settingsUsageGuideCommunityStepBuildings.
  ///
  /// In en, this message translates to:
  /// **'The compound includes its buildings, and the building feed is private to its residents.'**
  String get settingsUsageGuideCommunityStepBuildings;

  /// No description provided for @settingsUsageGuideCommunityStepSearch.
  ///
  /// In en, this message translates to:
  /// **'You can search users globally by name or phone.'**
  String get settingsUsageGuideCommunityStepSearch;

  /// No description provided for @settingsUsageGuideCommunityStepPermissions.
  ///
  /// In en, this message translates to:
  /// **'Notifications and chats follow the permissions of each community scope.'**
  String get settingsUsageGuideCommunityStepPermissions;

  /// No description provided for @settingsUsageGuideHrTitle.
  ///
  /// In en, this message translates to:
  /// **'HR interface'**
  String get settingsUsageGuideHrTitle;

  /// No description provided for @settingsUsageGuideHrDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage employees, attendance, payroll, and leave.'**
  String get settingsUsageGuideHrDescription;

  /// No description provided for @settingsUsageGuideHrStepPayroll.
  ///
  /// In en, this message translates to:
  /// **'Create payroll batches by month and year.'**
  String get settingsUsageGuideHrStepPayroll;

  /// No description provided for @settingsUsageGuideHrStepRequests.
  ///
  /// In en, this message translates to:
  /// **'Review leave and advance requests, then approve or reject them.'**
  String get settingsUsageGuideHrStepRequests;

  /// No description provided for @settingsUsageGuideHrStepShifts.
  ///
  /// In en, this message translates to:
  /// **'Configure work shifts and role tags.'**
  String get settingsUsageGuideHrStepShifts;

  /// No description provided for @settingsUsageGuideHrStepArchive.
  ///
  /// In en, this message translates to:
  /// **'Review period-based attendance and payroll archives.'**
  String get settingsUsageGuideHrStepArchive;

  /// No description provided for @settingsUsageGuideAccountantTitle.
  ///
  /// In en, this message translates to:
  /// **'Accountant interface'**
  String get settingsUsageGuideAccountantTitle;

  /// No description provided for @settingsUsageGuideAccountantDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage ledger, settlements, and expenses.'**
  String get settingsUsageGuideAccountantDescription;

  /// No description provided for @settingsUsageGuideAccountantStepOpeningBalance.
  ///
  /// In en, this message translates to:
  /// **'Start with an opening balance at the beginning of the day when needed.'**
  String get settingsUsageGuideAccountantStepOpeningBalance;

  /// No description provided for @settingsUsageGuideAccountantStepSettlements.
  ///
  /// In en, this message translates to:
  /// **'Confirm the delivery settlements queued by the system.'**
  String get settingsUsageGuideAccountantStepSettlements;

  /// No description provided for @settingsUsageGuideAccountantStepExpenses.
  ///
  /// In en, this message translates to:
  /// **'Register expenses with clear notes.'**
  String get settingsUsageGuideAccountantStepExpenses;

  /// No description provided for @settingsUsageGuideAccountantStepNegativeBalance.
  ///
  /// In en, this message translates to:
  /// **'The system blocks spending that would create a negative balance.'**
  String get settingsUsageGuideAccountantStepNegativeBalance;

  /// No description provided for @settingsUsageGuideAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin and super admin'**
  String get settingsUsageGuideAdminTitle;

  /// No description provided for @settingsUsageGuideAdminDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage approvals, audit logs, and permissions.'**
  String get settingsUsageGuideAdminDescription;

  /// No description provided for @settingsUsageGuideAdminStepApprovals.
  ///
  /// In en, this message translates to:
  /// **'Review pending merchant requests and account approvals.'**
  String get settingsUsageGuideAdminStepApprovals;

  /// No description provided for @settingsUsageGuideAdminStepAudit.
  ///
  /// In en, this message translates to:
  /// **'Use the audit log to inspect all important actions.'**
  String get settingsUsageGuideAdminStepAudit;

  /// No description provided for @settingsUsageGuideAdminStepPermissions.
  ///
  /// In en, this message translates to:
  /// **'Assign or revoke manager permissions inside communities.'**
  String get settingsUsageGuideAdminStepPermissions;

  /// No description provided for @settingsUsageGuideAdminStepSuperAdmin.
  ///
  /// In en, this message translates to:
  /// **'Super admin has full cross-module oversight.'**
  String get settingsUsageGuideAdminStepSuperAdmin;

  /// No description provided for @settingsUsageGuideNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications and calls'**
  String get settingsUsageGuideNotificationsTitle;

  /// No description provided for @settingsUsageGuideNotificationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Reliable alerts with deep links to their related screens.'**
  String get settingsUsageGuideNotificationsDescription;

  /// No description provided for @settingsUsageGuideNotificationsStepPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant notification permission from the operating system settings.'**
  String get settingsUsageGuideNotificationsStepPermission;

  /// No description provided for @settingsUsageGuideNotificationsStepDeepLinks.
  ///
  /// In en, this message translates to:
  /// **'Each notification should open the linked screen directly.'**
  String get settingsUsageGuideNotificationsStepDeepLinks;

  /// No description provided for @settingsUsageGuideNotificationsStepRefresh.
  ///
  /// In en, this message translates to:
  /// **'When the network is unstable, use the refresh action inside the page.'**
  String get settingsUsageGuideNotificationsStepRefresh;

  /// No description provided for @settingsUsageGuideNotificationsStepCalls.
  ///
  /// In en, this message translates to:
  /// **'For calls, ensure microphone permission and background allowances are enabled.'**
  String get settingsUsageGuideNotificationsStepCalls;

  /// No description provided for @socialDiscoveryPeopleSuggestedTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggested people'**
  String get socialDiscoveryPeopleSuggestedTitle;

  /// No description provided for @socialDiscoveryPeopleEmpty.
  ///
  /// In en, this message translates to:
  /// **'No suggestions are available right now.'**
  String get socialDiscoveryPeopleEmpty;

  /// No description provided for @socialDiscoveryPeopleBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get socialDiscoveryPeopleBlocked;

  /// No description provided for @socialDiscoveryPeopleFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get socialDiscoveryPeopleFollowing;

  /// No description provided for @socialDiscoveryPeopleCancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get socialDiscoveryPeopleCancelRequest;

  /// No description provided for @socialDiscoveryPeopleAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get socialDiscoveryPeopleAccept;

  /// No description provided for @socialDiscoveryPeopleFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get socialDiscoveryPeopleFollow;

  /// No description provided for @socialDiscoveryPeopleAlreadyConnected.
  ///
  /// In en, this message translates to:
  /// **'Already connected'**
  String get socialDiscoveryPeopleAlreadyConnected;

  /// No description provided for @socialDiscoveryPeopleWaitingForResponse.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a response'**
  String get socialDiscoveryPeopleWaitingForResponse;

  /// No description provided for @socialDiscoveryPeopleSentYouRequest.
  ///
  /// In en, this message translates to:
  /// **'Sent you a follow request'**
  String get socialDiscoveryPeopleSentYouRequest;

  /// No description provided for @socialDiscoveryPeopleYouBlocked.
  ///
  /// In en, this message translates to:
  /// **'You blocked this account'**
  String get socialDiscoveryPeopleYouBlocked;

  /// No description provided for @socialDiscoveryPeopleBlockedYou.
  ///
  /// In en, this message translates to:
  /// **'This account blocked you'**
  String get socialDiscoveryPeopleBlockedYou;

  /// No description provided for @socialDiscoveryPeopleBlockedActionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This action is unavailable because this account blocked you.'**
  String get socialDiscoveryPeopleBlockedActionUnavailable;

  /// No description provided for @socialDiscoveryPeopleUnblockFirst.
  ///
  /// In en, this message translates to:
  /// **'Unblock this profile first before sending a request.'**
  String get socialDiscoveryPeopleUnblockFirst;

  /// No description provided for @socialDiscoveryPeopleAccepted.
  ///
  /// In en, this message translates to:
  /// **'Follow request accepted.'**
  String get socialDiscoveryPeopleAccepted;

  /// No description provided for @socialDiscoveryPeopleCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled.'**
  String get socialDiscoveryPeopleCancelled;

  /// No description provided for @socialDiscoveryPeopleRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Follow request sent.'**
  String get socialDiscoveryPeopleRequestSent;

  /// No description provided for @socialDiscoveryPeopleActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to complete the action right now.'**
  String get socialDiscoveryPeopleActionFailed;

  /// No description provided for @socialReelViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'Basmaya reels'**
  String get socialReelViewerTitle;

  /// No description provided for @socialReelViewerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No reels right now.'**
  String get socialReelViewerEmpty;

  /// No description provided for @socialReelViewerSharedToStory.
  ///
  /// In en, this message translates to:
  /// **'Reel shared to story.'**
  String get socialReelViewerSharedToStory;

  /// No description provided for @socialReelMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get socialReelMute;

  /// No description provided for @socialReelUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get socialReelUnmute;

  /// No description provided for @socialReelCardStory.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get socialReelCardStory;

  /// No description provided for @socialReelCardLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get socialReelCardLink;

  /// No description provided for @socialStoryMentionLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load suggestions.'**
  String get socialStoryMentionLoadFailed;

  /// No description provided for @socialStoryMentionHint.
  ///
  /// In en, this message translates to:
  /// **'Type @ and a user name'**
  String get socialStoryMentionHint;

  /// No description provided for @socialStoryMentionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Start typing @ to search users.'**
  String get socialStoryMentionEmpty;

  /// No description provided for @adminFinancialPrintReport.
  ///
  /// In en, this message translates to:
  /// **'Print report'**
  String get adminFinancialPrintReport;

  /// No description provided for @commonIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get commonIncoming;

  /// No description provided for @commonOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get commonOutgoing;

  /// No description provided for @commonSince.
  ///
  /// In en, this message translates to:
  /// **'Since'**
  String get commonSince;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get commonApproved;

  /// No description provided for @commonUnknownUser.
  ///
  /// In en, this message translates to:
  /// **'Unknown user'**
  String get commonUnknownUser;

  /// No description provided for @commonBuilding.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get commonBuilding;

  /// No description provided for @commonApartment.
  ///
  /// In en, this message translates to:
  /// **'Apartment'**
  String get commonApartment;

  /// No description provided for @commonLoad.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get commonLoad;

  /// No description provided for @commonUserId.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get commonUserId;

  /// No description provided for @commonCapability.
  ///
  /// In en, this message translates to:
  /// **'Capability'**
  String get commonCapability;

  /// No description provided for @commonActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get commonActive;

  /// No description provided for @commonInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get commonInactive;

  /// No description provided for @commonUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get commonUser;

  /// No description provided for @commonPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get commonPhone;

  /// No description provided for @commonReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get commonReason;

  /// No description provided for @commonStarts.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get commonStarts;

  /// No description provided for @commonEnds.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get commonEnds;

  /// No description provided for @commonOpenEnded.
  ///
  /// In en, this message translates to:
  /// **'Open-ended'**
  String get commonOpenEnded;

  /// No description provided for @commonDurationOneDay.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get commonDurationOneDay;

  /// No description provided for @commonDurationSevenDays.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get commonDurationSevenDays;

  /// No description provided for @commonDurationThirtyDays.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get commonDurationThirtyDays;

  /// No description provided for @commonSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get commonSystem;

  /// No description provided for @commonSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get commonSubmitted;

  /// No description provided for @commonAccountId.
  ///
  /// In en, this message translates to:
  /// **'Account ID'**
  String get commonAccountId;

  /// No description provided for @commonTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get commonTitle;

  /// No description provided for @commonActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get commonActivity;

  /// No description provided for @commonDepartment.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get commonDepartment;

  /// No description provided for @commonCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get commonCategory;

  /// No description provided for @commonEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get commonEmail;

  /// No description provided for @commonAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get commonAddress;

  /// No description provided for @commonArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get commonArchive;

  /// No description provided for @commonBy.
  ///
  /// In en, this message translates to:
  /// **'By'**
  String get commonBy;

  /// No description provided for @commonTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get commonTime;

  /// No description provided for @commonDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get commonDetails;

  /// No description provided for @socialRelationRequestsLoadIncomingFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load incoming requests.'**
  String get socialRelationRequestsLoadIncomingFailed;

  /// No description provided for @socialRelationRequestsLoadOutgoingFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load outgoing requests.'**
  String get socialRelationRequestsLoadOutgoingFailed;

  /// No description provided for @socialRelationRequestsAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to accept the request.'**
  String get socialRelationRequestsAcceptFailed;

  /// No description provided for @socialRelationRequestsRejected.
  ///
  /// In en, this message translates to:
  /// **'Request rejected.'**
  String get socialRelationRequestsRejected;

  /// No description provided for @socialRelationRequestsRejectFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to reject the request.'**
  String get socialRelationRequestsRejectFailed;

  /// No description provided for @socialRelationRequestsCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled.'**
  String get socialRelationRequestsCancelled;

  /// No description provided for @socialRelationRequestsCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to cancel the request.'**
  String get socialRelationRequestsCancelFailed;

  /// No description provided for @socialRelationRequestsNoTimestamp.
  ///
  /// In en, this message translates to:
  /// **'No timestamp'**
  String get socialRelationRequestsNoTimestamp;

  /// No description provided for @socialRelationRequestsEmptyIncoming.
  ///
  /// In en, this message translates to:
  /// **'No incoming requests right now.'**
  String get socialRelationRequestsEmptyIncoming;

  /// No description provided for @socialRelationRequestsEmptyOutgoing.
  ///
  /// In en, this message translates to:
  /// **'No outgoing requests right now.'**
  String get socialRelationRequestsEmptyOutgoing;

  /// No description provided for @socialRelationRequestsCancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get socialRelationRequestsCancelAction;

  /// No description provided for @adminResidenceChangeLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load residence change requests.'**
  String get adminResidenceChangeLoadFailed;

  /// No description provided for @adminResidenceChangeApproveDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve residence change'**
  String get adminResidenceChangeApproveDialogTitle;

  /// No description provided for @adminResidenceChangeRejectDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Reject residence change'**
  String get adminResidenceChangeRejectDialogTitle;

  /// No description provided for @adminResidenceChangeOptionalReviewNote.
  ///
  /// In en, this message translates to:
  /// **'Optional review note'**
  String get adminResidenceChangeOptionalReviewNote;

  /// No description provided for @adminResidenceChangeApproved.
  ///
  /// In en, this message translates to:
  /// **'Request approved.'**
  String get adminResidenceChangeApproved;

  /// No description provided for @adminResidenceChangeRejected.
  ///
  /// In en, this message translates to:
  /// **'Request rejected.'**
  String get adminResidenceChangeRejected;

  /// No description provided for @adminResidenceChangeReviewActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply the review decision.'**
  String get adminResidenceChangeReviewActionFailed;

  /// No description provided for @adminResidenceChangeCurrentResidence.
  ///
  /// In en, this message translates to:
  /// **'Current residence'**
  String get adminResidenceChangeCurrentResidence;

  /// No description provided for @adminResidenceChangeRequestedResidence.
  ///
  /// In en, this message translates to:
  /// **'Requested residence'**
  String get adminResidenceChangeRequestedResidence;

  /// No description provided for @adminResidenceChangeUserNote.
  ///
  /// In en, this message translates to:
  /// **'User note'**
  String get adminResidenceChangeUserNote;

  /// No description provided for @adminResidenceChangeReviewNote.
  ///
  /// In en, this message translates to:
  /// **'Review note'**
  String get adminResidenceChangeReviewNote;

  /// No description provided for @adminResidenceChangeEmpty.
  ///
  /// In en, this message translates to:
  /// **'No residence requests for this filter.'**
  String get adminResidenceChangeEmpty;

  /// No description provided for @adminSocialRestrictionsStoryPublishing.
  ///
  /// In en, this message translates to:
  /// **'Story publishing'**
  String get adminSocialRestrictionsStoryPublishing;

  /// No description provided for @adminSocialRestrictionsReelsPublishing.
  ///
  /// In en, this message translates to:
  /// **'Reels / video publishing'**
  String get adminSocialRestrictionsReelsPublishing;

  /// No description provided for @adminSocialRestrictionsCommunityPosting.
  ///
  /// In en, this message translates to:
  /// **'Community posting'**
  String get adminSocialRestrictionsCommunityPosting;

  /// No description provided for @adminSocialRestrictionsRegularPosting.
  ///
  /// In en, this message translates to:
  /// **'Regular posting'**
  String get adminSocialRestrictionsRegularPosting;

  /// No description provided for @adminSocialRestrictionsInvalidUserId.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid user ID.'**
  String get adminSocialRestrictionsInvalidUserId;

  /// No description provided for @adminSocialRestrictionsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load social restrictions for this user.'**
  String get adminSocialRestrictionsLoadFailed;

  /// No description provided for @adminSocialRestrictionsCreated.
  ///
  /// In en, this message translates to:
  /// **'Restriction created.'**
  String get adminSocialRestrictionsCreated;

  /// No description provided for @adminSocialRestrictionsCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create restriction.'**
  String get adminSocialRestrictionsCreateFailed;

  /// No description provided for @adminSocialRestrictionsRevoked.
  ///
  /// In en, this message translates to:
  /// **'Restriction revoked.'**
  String get adminSocialRestrictionsRevoked;

  /// No description provided for @adminSocialRestrictionsRevokeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to revoke restriction.'**
  String get adminSocialRestrictionsRevokeFailed;

  /// No description provided for @adminSocialRestrictionsManageByUser.
  ///
  /// In en, this message translates to:
  /// **'Manage restrictions by user'**
  String get adminSocialRestrictionsManageByUser;

  /// No description provided for @adminSocialRestrictionsReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Restriction reason'**
  String get adminSocialRestrictionsReasonLabel;

  /// No description provided for @adminSocialRestrictionsCreate.
  ///
  /// In en, this message translates to:
  /// **'Create restriction'**
  String get adminSocialRestrictionsCreate;

  /// No description provided for @adminSocialRestrictionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No restrictions found for this user.'**
  String get adminSocialRestrictionsEmpty;

  /// No description provided for @adminSocialRestrictionsRevokeAction.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get adminSocialRestrictionsRevokeAction;

  /// No description provided for @jobsStatusReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get jobsStatusReceived;

  /// No description provided for @jobsStatusShortlisted.
  ///
  /// In en, this message translates to:
  /// **'Shortlisted'**
  String get jobsStatusShortlisted;

  /// No description provided for @jobsStatusHired.
  ///
  /// In en, this message translates to:
  /// **'Hired'**
  String get jobsStatusHired;

  /// No description provided for @jobsStatusWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Withdrawn'**
  String get jobsStatusWithdrawn;

  /// No description provided for @jobsStatusDismissed.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get jobsStatusDismissed;

  /// No description provided for @jobsStatusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get jobsStatusArchived;

  /// No description provided for @jobsStatusReceivedGroup.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get jobsStatusReceivedGroup;

  /// No description provided for @jobsStatusShortlistedGroup.
  ///
  /// In en, this message translates to:
  /// **'Shortlisted'**
  String get jobsStatusShortlistedGroup;

  /// No description provided for @jobsStatusRejectedGroup.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get jobsStatusRejectedGroup;

  /// No description provided for @jobsStatusHiredGroup.
  ///
  /// In en, this message translates to:
  /// **'Hired'**
  String get jobsStatusHiredGroup;

  /// No description provided for @jobsStatusWithdrawnGroup.
  ///
  /// In en, this message translates to:
  /// **'Withdrawn'**
  String get jobsStatusWithdrawnGroup;

  /// No description provided for @jobsStatusDismissedGroup.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get jobsStatusDismissedGroup;

  /// No description provided for @jobsStatusArchivedGroup.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get jobsStatusArchivedGroup;

  /// No description provided for @jobApplicationDetailsStatusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Applicant status updated.'**
  String get jobApplicationDetailsStatusUpdated;

  /// No description provided for @jobApplicationDetailsWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Application withdrawn successfully.'**
  String get jobApplicationDetailsWithdrawn;

  /// No description provided for @jobApplicationDetailsWithdrawReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Reason for withdrawing the application'**
  String get jobApplicationDetailsWithdrawReasonTitle;

  /// No description provided for @jobApplicationDetailsReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Write the reason...'**
  String get jobApplicationDetailsReasonHint;

  /// No description provided for @jobApplicationDetailsInvalidLink.
  ///
  /// In en, this message translates to:
  /// **'Invalid link.'**
  String get jobApplicationDetailsInvalidLink;

  /// No description provided for @jobApplicationDetailsNoLinkedAccount.
  ///
  /// In en, this message translates to:
  /// **'No linked system account exists for this applicant.'**
  String get jobApplicationDetailsNoLinkedAccount;

  /// No description provided for @jobApplicationDetailsApplicantFallback.
  ///
  /// In en, this message translates to:
  /// **'Applicant'**
  String get jobApplicationDetailsApplicantFallback;

  /// No description provided for @jobApplicationDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Applicant details'**
  String get jobApplicationDetailsTitle;

  /// No description provided for @jobApplicationDetailsWithdrawAction.
  ///
  /// In en, this message translates to:
  /// **'Withdraw application'**
  String get jobApplicationDetailsWithdrawAction;

  /// No description provided for @jobApplicationDetailsOpenLinkedAccount.
  ///
  /// In en, this message translates to:
  /// **'Open linked account'**
  String get jobApplicationDetailsOpenLinkedAccount;

  /// No description provided for @jobApplicationDetailsOfferSection.
  ///
  /// In en, this message translates to:
  /// **'Job offer'**
  String get jobApplicationDetailsOfferSection;

  /// No description provided for @jobApplicationDetailsOfferSentAt.
  ///
  /// In en, this message translates to:
  /// **'Offer sent at'**
  String get jobApplicationDetailsOfferSentAt;

  /// No description provided for @jobApplicationDetailsOfferDetails.
  ///
  /// In en, this message translates to:
  /// **'Offer details'**
  String get jobApplicationDetailsOfferDetails;

  /// No description provided for @jobApplicationDetailsOfferAcceptedAt.
  ///
  /// In en, this message translates to:
  /// **'Applicant accepted at'**
  String get jobApplicationDetailsOfferAcceptedAt;

  /// No description provided for @jobApplicationDetailsOpenOfferAttachment.
  ///
  /// In en, this message translates to:
  /// **'Open offer attachment'**
  String get jobApplicationDetailsOpenOfferAttachment;

  /// No description provided for @jobApplicationDetailsOpenAcceptanceAttachment.
  ///
  /// In en, this message translates to:
  /// **'Open applicant acceptance attachment'**
  String get jobApplicationDetailsOpenAcceptanceAttachment;

  /// No description provided for @jobApplicationDetailsJobInfo.
  ///
  /// In en, this message translates to:
  /// **'Job information'**
  String get jobApplicationDetailsJobInfo;

  /// No description provided for @jobApplicationDetailsApplicantInfo.
  ///
  /// In en, this message translates to:
  /// **'Applicant information'**
  String get jobApplicationDetailsApplicantInfo;

  /// No description provided for @jobApplicationDetailsProfileName.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get jobApplicationDetailsProfileName;

  /// No description provided for @jobApplicationDetailsProfilePhone.
  ///
  /// In en, this message translates to:
  /// **'Profile phone'**
  String get jobApplicationDetailsProfilePhone;

  /// No description provided for @jobApplicationDetailsSubmittedPhone.
  ///
  /// In en, this message translates to:
  /// **'Submitted phone'**
  String get jobApplicationDetailsSubmittedPhone;

  /// No description provided for @jobApplicationDetailsExpectedSalary.
  ///
  /// In en, this message translates to:
  /// **'Expected salary'**
  String get jobApplicationDetailsExpectedSalary;

  /// No description provided for @jobApplicationDetailsIntroductionMessage.
  ///
  /// In en, this message translates to:
  /// **'Introduction message'**
  String get jobApplicationDetailsIntroductionMessage;

  /// No description provided for @jobApplicationDetailsResumeSection.
  ///
  /// In en, this message translates to:
  /// **'Resume and attachments'**
  String get jobApplicationDetailsResumeSection;

  /// No description provided for @jobApplicationDetailsDownloadAttachment.
  ///
  /// In en, this message translates to:
  /// **'Download attachment'**
  String get jobApplicationDetailsDownloadAttachment;

  /// No description provided for @jobApplicationDetailsOpenResumeLink.
  ///
  /// In en, this message translates to:
  /// **'Open resume link'**
  String get jobApplicationDetailsOpenResumeLink;

  /// No description provided for @jobApplicationDetailsDecisionSection.
  ///
  /// In en, this message translates to:
  /// **'Administrative decision'**
  String get jobApplicationDetailsDecisionSection;

  /// No description provided for @jobApplicationDetailsCurrentStatus.
  ///
  /// In en, this message translates to:
  /// **'Current status'**
  String get jobApplicationDetailsCurrentStatus;

  /// No description provided for @jobApplicationDetailsLastStatusUpdate.
  ///
  /// In en, this message translates to:
  /// **'Last status update'**
  String get jobApplicationDetailsLastStatusUpdate;

  /// No description provided for @jobApplicationDetailsStatusLocked.
  ///
  /// In en, this message translates to:
  /// **'Application status cannot be changed from this page.'**
  String get jobApplicationDetailsStatusLocked;

  /// No description provided for @jobApplicationDetailsHistorySection.
  ///
  /// In en, this message translates to:
  /// **'Status history'**
  String get jobApplicationDetailsHistorySection;

  /// No description provided for @jobApplicationDetailsHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No status history yet.'**
  String get jobApplicationDetailsHistoryEmpty;

  /// No description provided for @jobSuperAdminMonitorLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load applicants monitor.'**
  String get jobSuperAdminMonitorLoadFailed;

  /// No description provided for @jobSuperAdminMonitorFiltersTitle.
  ///
  /// In en, this message translates to:
  /// **'Applicants monitor filters'**
  String get jobSuperAdminMonitorFiltersTitle;

  /// No description provided for @jobSuperAdminMonitorJobIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Job ID'**
  String get jobSuperAdminMonitorJobIdLabel;

  /// No description provided for @jobSuperAdminMonitorJobIdHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for all jobs'**
  String get jobSuperAdminMonitorJobIdHint;

  /// No description provided for @jobSuperAdminMonitorSuperAdminOnly.
  ///
  /// In en, this message translates to:
  /// **'This page is for super admin only.'**
  String get jobSuperAdminMonitorSuperAdminOnly;

  /// No description provided for @jobSuperAdminMonitorTitle.
  ///
  /// In en, this message translates to:
  /// **'Applicants aggregation center'**
  String get jobSuperAdminMonitorTitle;

  /// No description provided for @jobSuperAdminMonitorHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Central recruitment monitoring'**
  String get jobSuperAdminMonitorHeroTitle;

  /// No description provided for @jobSuperAdminMonitorHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Central applicants view by activity, department, and category, with full status lifecycle visibility.'**
  String get jobSuperAdminMonitorHeroSubtitle;

  /// No description provided for @jobSuperAdminMonitorTotalApplications.
  ///
  /// In en, this message translates to:
  /// **'Total applications'**
  String get jobSuperAdminMonitorTotalApplications;

  /// No description provided for @jobSuperAdminMonitorDistributionTitle.
  ///
  /// In en, this message translates to:
  /// **'Distribution by activity and department'**
  String get jobSuperAdminMonitorDistributionTitle;

  /// No description provided for @jobSuperAdminMonitorSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, phone, job, company...'**
  String get jobSuperAdminMonitorSearchHint;

  /// No description provided for @jobSuperAdminMonitorEmpty.
  ///
  /// In en, this message translates to:
  /// **'No applications match the current filters.'**
  String get jobSuperAdminMonitorEmpty;

  /// No description provided for @socialRelationRequestsAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted request from {name}'**
  String socialRelationRequestsAccepted(String name);

  /// No description provided for @jobApplicationDetailsChangeStatusReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Reason for changing status to {statusLabel}'**
  String jobApplicationDetailsChangeStatusReasonTitle(String statusLabel);

  /// No description provided for @jobApplicationDetailsOfferAttachmentNamed.
  ///
  /// In en, this message translates to:
  /// **'Offer attachment ({name})'**
  String jobApplicationDetailsOfferAttachmentNamed(String name);

  /// No description provided for @jobApplicationDetailsAcceptanceAttachmentNamed.
  ///
  /// In en, this message translates to:
  /// **'Acceptance attachment ({name})'**
  String jobApplicationDetailsAcceptanceAttachmentNamed(String name);

  /// No description provided for @jobApplicationDetailsDownloadAttachmentNamed.
  ///
  /// In en, this message translates to:
  /// **'Download attachment ({name})'**
  String jobApplicationDetailsDownloadAttachmentNamed(String name);

  /// No description provided for @jobTalentPoolLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load talent pool.'**
  String get jobTalentPoolLoadFailed;

  /// No description provided for @jobTalentPoolManagementOnly.
  ///
  /// In en, this message translates to:
  /// **'This page is for management only.'**
  String get jobTalentPoolManagementOnly;

  /// No description provided for @jobTalentPoolTitle.
  ///
  /// In en, this message translates to:
  /// **'Talent pool'**
  String get jobTalentPoolTitle;

  /// No description provided for @jobTalentPoolSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by activity, department, or applicant name...'**
  String get jobTalentPoolSearchHint;

  /// No description provided for @jobTalentPoolEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matching applicants found.'**
  String get jobTalentPoolEmpty;

  /// No description provided for @jobTalentPoolApplications.
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get jobTalentPoolApplications;

  /// No description provided for @jobTalentPoolApplicants.
  ///
  /// In en, this message translates to:
  /// **'Applicants'**
  String get jobTalentPoolApplicants;

  /// No description provided for @jobTalentPoolLastApplication.
  ///
  /// In en, this message translates to:
  /// **'Last application'**
  String get jobTalentPoolLastApplication;

  /// No description provided for @adminAdBoardFailedToLoadTheAdBoard.
  ///
  /// In en, this message translates to:
  /// **'Failed to load the ad board.'**
  String get adminAdBoardFailedToLoadTheAdBoard;

  /// No description provided for @adminAdBoardAdItemCreated.
  ///
  /// In en, this message translates to:
  /// **'Ad item created.'**
  String get adminAdBoardAdItemCreated;

  /// No description provided for @adminAdBoardFailedToCreateTheAdItem.
  ///
  /// In en, this message translates to:
  /// **'Failed to create the ad item.'**
  String get adminAdBoardFailedToCreateTheAdItem;

  /// No description provided for @adminAdBoardAdItemUpdated.
  ///
  /// In en, this message translates to:
  /// **'Ad item updated.'**
  String get adminAdBoardAdItemUpdated;

  /// No description provided for @adminAdBoardFailedToUpdateTheAdItem.
  ///
  /// In en, this message translates to:
  /// **'Failed to update the ad item.'**
  String get adminAdBoardFailedToUpdateTheAdItem;

  /// No description provided for @adminAdBoardAdItemDeleted.
  ///
  /// In en, this message translates to:
  /// **'Ad item deleted.'**
  String get adminAdBoardAdItemDeleted;

  /// No description provided for @adminAdBoardFailedToDeleteTheAdItem.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete the ad item.'**
  String get adminAdBoardFailedToDeleteTheAdItem;

  /// No description provided for @adminAdBoardFailedToConnectToTheServer.
  ///
  /// In en, this message translates to:
  /// **'Failed to connect to the server.'**
  String get adminAdBoardFailedToConnectToTheServer;

  /// No description provided for @adminAdBoardTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get adminAdBoardTitle;

  /// No description provided for @adminAdBoardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle'**
  String get adminAdBoardSubtitle;

  /// No description provided for @adminAdBoardBadgeLabel.
  ///
  /// In en, this message translates to:
  /// **'Badge label'**
  String get adminAdBoardBadgeLabel;

  /// No description provided for @adminAdBoardImageUrl.
  ///
  /// In en, this message translates to:
  /// **'Image URL'**
  String get adminAdBoardImageUrl;

  /// No description provided for @adminAdBoardCtaLabel.
  ///
  /// In en, this message translates to:
  /// **'CTA label'**
  String get adminAdBoardCtaLabel;

  /// No description provided for @adminAdBoardCtaType.
  ///
  /// In en, this message translates to:
  /// **'CTA type'**
  String get adminAdBoardCtaType;

  /// No description provided for @adminAdBoardCtaValue.
  ///
  /// In en, this message translates to:
  /// **'CTA value'**
  String get adminAdBoardCtaValue;

  /// No description provided for @adminAdBoardLinkedMerchant.
  ///
  /// In en, this message translates to:
  /// **'Linked merchant'**
  String get adminAdBoardLinkedMerchant;

  /// No description provided for @adminAdBoardPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get adminAdBoardPriority;

  /// No description provided for @adminAdBoardStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get adminAdBoardStartDate;

  /// No description provided for @adminAdBoardEndDate.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get adminAdBoardEndDate;

  /// No description provided for @adminAdBoardNewAd.
  ///
  /// In en, this message translates to:
  /// **'New ad'**
  String get adminAdBoardNewAd;

  /// No description provided for @adminAdBoardNoAdItemsYet.
  ///
  /// In en, this message translates to:
  /// **'No ad items yet.'**
  String get adminAdBoardNoAdItemsYet;

  /// No description provided for @adminAdBoardCta.
  ///
  /// In en, this message translates to:
  /// **'CTA'**
  String get adminAdBoardCta;

  /// No description provided for @adminAdBoardDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get adminAdBoardDisabled;

  /// No description provided for @adminAdBoardScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get adminAdBoardScheduled;

  /// No description provided for @adminAdBoardExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get adminAdBoardExpired;

  /// No description provided for @adminAdBoardOpenMerchant.
  ///
  /// In en, this message translates to:
  /// **'Open merchant'**
  String get adminAdBoardOpenMerchant;

  /// No description provided for @adminAdBoardOpenCategory.
  ///
  /// In en, this message translates to:
  /// **'Open category'**
  String get adminAdBoardOpenCategory;

  /// No description provided for @adminAdBoardOpenProduct.
  ///
  /// In en, this message translates to:
  /// **'Open product'**
  String get adminAdBoardOpenProduct;

  /// No description provided for @adminAdBoardOpenTaxi.
  ///
  /// In en, this message translates to:
  /// **'Open taxi'**
  String get adminAdBoardOpenTaxi;

  /// No description provided for @adminAdBoardExternalUrl.
  ///
  /// In en, this message translates to:
  /// **'External URL'**
  String get adminAdBoardExternalUrl;

  /// No description provided for @adminAdBoardInternalCampaignPage.
  ///
  /// In en, this message translates to:
  /// **'Internal campaign page'**
  String get adminAdBoardInternalCampaignPage;

  /// No description provided for @adminAdBoardNoAction.
  ///
  /// In en, this message translates to:
  /// **'No action'**
  String get adminAdBoardNoAction;

  /// No description provided for @adminAdBoardStarts.
  ///
  /// In en, this message translates to:
  /// **'Starts: {start}'**
  String adminAdBoardStarts(Object start);

  /// No description provided for @adminAdBoardEnds.
  ///
  /// In en, this message translates to:
  /// **'Ends: {end}'**
  String adminAdBoardEnds(Object end);

  /// No description provided for @adminAdBoardGeneralAdWithoutMerchant.
  ///
  /// In en, this message translates to:
  /// **'General ad without merchant'**
  String get adminAdBoardGeneralAdWithoutMerchant;

  /// No description provided for @adminAdBoardCreateAd.
  ///
  /// In en, this message translates to:
  /// **'Create ad'**
  String get adminAdBoardCreateAd;

  /// No description provided for @adminAdBoardEditAd.
  ///
  /// In en, this message translates to:
  /// **'Edit ad'**
  String get adminAdBoardEditAd;

  /// No description provided for @adminAdBoardRequiredField.
  ///
  /// In en, this message translates to:
  /// **'Required field'**
  String get adminAdBoardRequiredField;

  /// No description provided for @adminAdBoardLinkedProduct.
  ///
  /// In en, this message translates to:
  /// **'Linked product'**
  String get adminAdBoardLinkedProduct;

  /// No description provided for @adminAdBoardAdImage.
  ///
  /// In en, this message translates to:
  /// **'Ad image'**
  String get adminAdBoardAdImage;

  /// No description provided for @adminAdBoardOrImageUrl.
  ///
  /// In en, this message translates to:
  /// **'Or image URL'**
  String get adminAdBoardOrImageUrl;

  /// No description provided for @adminAdBoardCtaDestination.
  ///
  /// In en, this message translates to:
  /// **'CTA destination'**
  String get adminAdBoardCtaDestination;

  /// No description provided for @adminAdBoardActiveAndVisible.
  ///
  /// In en, this message translates to:
  /// **'Active and visible'**
  String get adminAdBoardActiveAndVisible;

  /// No description provided for @adminAdBoardSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get adminAdBoardSaving;

  /// No description provided for @adminAdBoardSaveAd.
  ///
  /// In en, this message translates to:
  /// **'Save ad'**
  String get adminAdBoardSaveAd;

  /// No description provided for @adminAdBoardNoImageSelected.
  ///
  /// In en, this message translates to:
  /// **'No image selected'**
  String get adminAdBoardNoImageSelected;

  /// No description provided for @adminAdBoardRemoveImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get adminAdBoardRemoveImage;

  /// No description provided for @adminAdBoardPickFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Pick from device'**
  String get adminAdBoardPickFromDevice;

  /// No description provided for @adminAdBoardReviewTheseFields.
  ///
  /// In en, this message translates to:
  /// **'Please review these fields: {fields}'**
  String adminAdBoardReviewTheseFields(Object fields);

  /// No description provided for @adminAdBoardIntroBanner.
  ///
  /// In en, this message translates to:
  /// **'Create a banner that opens a merchant, category, product, or a richer internal campaign page.'**
  String get adminAdBoardIntroBanner;

  /// No description provided for @adminAdBoardChooseMerchantAndProductFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose a merchant and a product first.'**
  String get adminAdBoardChooseMerchantAndProductFirst;

  /// No description provided for @adminAdBoardEndDateAfterStart.
  ///
  /// In en, this message translates to:
  /// **'End date must be after start date.'**
  String get adminAdBoardEndDateAfterStart;

  /// No description provided for @adminAdBoardCampaignPageHelper.
  ///
  /// In en, this message translates to:
  /// **'Optional: URL, category key, or taxi keyword inside the campaign page.'**
  String get adminAdBoardCampaignPageHelper;

  /// No description provided for @hrDashboardHrDashboard.
  ///
  /// In en, this message translates to:
  /// **'HR Dashboard'**
  String get hrDashboardHrDashboard;

  /// No description provided for @hrDashboardEmployeeDirectory.
  ///
  /// In en, this message translates to:
  /// **'Employee Directory'**
  String get hrDashboardEmployeeDirectory;

  /// No description provided for @hrDashboardAttendance.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get hrDashboardAttendance;

  /// No description provided for @hrDashboardLeaveRequests.
  ///
  /// In en, this message translates to:
  /// **'Leave Requests'**
  String get hrDashboardLeaveRequests;

  /// No description provided for @hrDashboardAdvanceRequests.
  ///
  /// In en, this message translates to:
  /// **'Advance Requests'**
  String get hrDashboardAdvanceRequests;

  /// No description provided for @hrDashboardCompensationActions.
  ///
  /// In en, this message translates to:
  /// **'Compensation Actions'**
  String get hrDashboardCompensationActions;

  /// No description provided for @hrDashboardPayroll.
  ///
  /// In en, this message translates to:
  /// **'Payroll'**
  String get hrDashboardPayroll;

  /// No description provided for @hrDashboardJobsManagement.
  ///
  /// In en, this message translates to:
  /// **'Jobs Management'**
  String get hrDashboardJobsManagement;

  /// No description provided for @hrDashboardEmployee.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get hrDashboardEmployee;

  /// No description provided for @hrDashboardBuildPayrollBatch.
  ///
  /// In en, this message translates to:
  /// **'Build Payroll Batch'**
  String get hrDashboardBuildPayrollBatch;

  /// No description provided for @hrDashboardSummaryNoteOptional.
  ///
  /// In en, this message translates to:
  /// **'Summary note (optional)'**
  String get hrDashboardSummaryNoteOptional;

  /// No description provided for @hrDashboardBuild.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get hrDashboardBuild;

  /// No description provided for @hrDashboardUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get hrDashboardUpdate;

  /// No description provided for @hrDashboardRoleTag.
  ///
  /// In en, this message translates to:
  /// **'Role Tag'**
  String get hrDashboardRoleTag;

  /// No description provided for @hrDashboardBaseSalary.
  ///
  /// In en, this message translates to:
  /// **'Base Salary'**
  String get hrDashboardBaseSalary;

  /// No description provided for @hrDashboardWorkDaysWeek.
  ///
  /// In en, this message translates to:
  /// **'Work days/week'**
  String get hrDashboardWorkDaysWeek;

  /// No description provided for @hrDashboardShiftEndHhMm.
  ///
  /// In en, this message translates to:
  /// **'Shift end (HH:MM)'**
  String get hrDashboardShiftEndHhMm;

  /// No description provided for @hrDashboardDateYyyyMmDd.
  ///
  /// In en, this message translates to:
  /// **'Date (YYYY-MM-DD)'**
  String get hrDashboardDateYyyyMmDd;

  /// No description provided for @hrDashboardLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get hrDashboardLeave;

  /// No description provided for @hrDashboardLeaveType.
  ///
  /// In en, this message translates to:
  /// **'Leave type'**
  String get hrDashboardLeaveType;

  /// No description provided for @hrDashboardAnnual.
  ///
  /// In en, this message translates to:
  /// **'Annual'**
  String get hrDashboardAnnual;

  /// No description provided for @hrDashboardSick.
  ///
  /// In en, this message translates to:
  /// **'Sick'**
  String get hrDashboardSick;

  /// No description provided for @hrDashboardEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get hrDashboardEmergency;

  /// No description provided for @hrDashboardMaternity.
  ///
  /// In en, this message translates to:
  /// **'Maternity'**
  String get hrDashboardMaternity;

  /// No description provided for @hrDashboardPayPolicy.
  ///
  /// In en, this message translates to:
  /// **'Pay policy'**
  String get hrDashboardPayPolicy;

  /// No description provided for @hrDashboardPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get hrDashboardPaid;

  /// No description provided for @hrDashboardHalfPaid.
  ///
  /// In en, this message translates to:
  /// **'Half paid'**
  String get hrDashboardHalfPaid;

  /// No description provided for @hrDashboardUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get hrDashboardUnpaid;

  /// No description provided for @hrDashboardSickPaid.
  ///
  /// In en, this message translates to:
  /// **'Sick paid'**
  String get hrDashboardSickPaid;

  /// No description provided for @hrDashboardFromYyyyMmDd.
  ///
  /// In en, this message translates to:
  /// **'From (YYYY-MM-DD)'**
  String get hrDashboardFromYyyyMmDd;

  /// No description provided for @hrDashboardToYyyyMmDd.
  ///
  /// In en, this message translates to:
  /// **'To (YYYY-MM-DD)'**
  String get hrDashboardToYyyyMmDd;

  /// No description provided for @hrDashboardDaysCount.
  ///
  /// In en, this message translates to:
  /// **'Days count'**
  String get hrDashboardDaysCount;

  /// No description provided for @hrDashboardReasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get hrDashboardReasonOptional;

  /// No description provided for @hrDashboardCompensation.
  ///
  /// In en, this message translates to:
  /// **'Compensation'**
  String get hrDashboardCompensation;

  /// No description provided for @hrDashboardActionType.
  ///
  /// In en, this message translates to:
  /// **'Action type'**
  String get hrDashboardActionType;

  /// No description provided for @hrDashboardBonus.
  ///
  /// In en, this message translates to:
  /// **'Bonus'**
  String get hrDashboardBonus;

  /// No description provided for @hrDashboardAllowance.
  ///
  /// In en, this message translates to:
  /// **'Allowance'**
  String get hrDashboardAllowance;

  /// No description provided for @hrDashboardDeduction.
  ///
  /// In en, this message translates to:
  /// **'Deduction'**
  String get hrDashboardDeduction;

  /// No description provided for @hrDashboardAdvance.
  ///
  /// In en, this message translates to:
  /// **'Advance'**
  String get hrDashboardAdvance;

  /// No description provided for @hrDashboardSalaryAction.
  ///
  /// In en, this message translates to:
  /// **'Salary action'**
  String get hrDashboardSalaryAction;

  /// No description provided for @hrDashboardLoadArchivePeriod.
  ///
  /// In en, this message translates to:
  /// **'Load archive period'**
  String get hrDashboardLoadArchivePeriod;

  /// No description provided for @hrDashboardLoad.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get hrDashboardLoad;

  /// No description provided for @hrDashboardHrCommandCenter.
  ///
  /// In en, this message translates to:
  /// **'HR Command Center'**
  String get hrDashboardHrCommandCenter;

  /// No description provided for @hrDashboardEmployees.
  ///
  /// In en, this message translates to:
  /// **'Employees'**
  String get hrDashboardEmployees;

  /// No description provided for @hrDashboardPresentToday.
  ///
  /// In en, this message translates to:
  /// **'Present Today'**
  String get hrDashboardPresentToday;

  /// No description provided for @hrDashboardPendingLeave.
  ///
  /// In en, this message translates to:
  /// **'Pending Leave'**
  String get hrDashboardPendingLeave;

  /// No description provided for @hrDashboardOpenPayroll.
  ///
  /// In en, this message translates to:
  /// **'Open Payroll'**
  String get hrDashboardOpenPayroll;

  /// No description provided for @hrDashboardBuildPayroll.
  ///
  /// In en, this message translates to:
  /// **'Build Payroll'**
  String get hrDashboardBuildPayroll;

  /// No description provided for @hrDashboardJobs.
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get hrDashboardJobs;

  /// No description provided for @hrDashboardEmployeePortal.
  ///
  /// In en, this message translates to:
  /// **'Employee Portal'**
  String get hrDashboardEmployeePortal;

  /// No description provided for @hrDashboardTotalEmployees.
  ///
  /// In en, this message translates to:
  /// **'Total Employees'**
  String get hrDashboardTotalEmployees;

  /// No description provided for @hrDashboardOpenJobsManagement.
  ///
  /// In en, this message translates to:
  /// **'Open Jobs Management'**
  String get hrDashboardOpenJobsManagement;

  /// No description provided for @hrDashboardNoEmployeesFound.
  ///
  /// In en, this message translates to:
  /// **'No employees found.'**
  String get hrDashboardNoEmployeesFound;

  /// No description provided for @hrDashboardRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get hrDashboardRole;

  /// No description provided for @hrDashboardIn.
  ///
  /// In en, this message translates to:
  /// **'In'**
  String get hrDashboardIn;

  /// No description provided for @hrDashboardOut.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get hrDashboardOut;

  /// No description provided for @hrDashboardEditAttendance.
  ///
  /// In en, this message translates to:
  /// **'Edit attendance'**
  String get hrDashboardEditAttendance;

  /// No description provided for @hrDashboardDays.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get hrDashboardDays;

  /// No description provided for @hrDashboardApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get hrDashboardApprove;

  /// No description provided for @hrDashboardRequested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get hrDashboardRequested;

  /// No description provided for @hrDashboardBatch.
  ///
  /// In en, this message translates to:
  /// **'Batch'**
  String get hrDashboardBatch;

  /// No description provided for @hrDashboardSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get hrDashboardSubmit;

  /// No description provided for @hrDashboardOpenedBatchItems.
  ///
  /// In en, this message translates to:
  /// **'Opened Batch Items'**
  String get hrDashboardOpenedBatchItems;

  /// No description provided for @hrDashboardSelectPeriod.
  ///
  /// In en, this message translates to:
  /// **'Select Period'**
  String get hrDashboardSelectPeriod;

  /// No description provided for @hrDashboardPresent.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get hrDashboardPresent;

  /// No description provided for @hrDashboardAbsent.
  ///
  /// In en, this message translates to:
  /// **'Absent'**
  String get hrDashboardAbsent;

  /// No description provided for @hrDashboardAccountSettings.
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get hrDashboardAccountSettings;

  /// No description provided for @hrDashboardOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get hrDashboardOverview;

  /// No description provided for @jobApplicationsAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get jobApplicationsAll;

  /// No description provided for @jobApplicationsHired.
  ///
  /// In en, this message translates to:
  /// **'Hired'**
  String get jobApplicationsHired;

  /// No description provided for @jobApplicationsReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get jobApplicationsReceived;

  /// No description provided for @jobApplicationsShortlisted.
  ///
  /// In en, this message translates to:
  /// **'Shortlisted'**
  String get jobApplicationsShortlisted;

  /// No description provided for @jobApplicationsRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get jobApplicationsRejected;

  /// No description provided for @jobApplicationsWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Withdrawn'**
  String get jobApplicationsWithdrawn;

  /// No description provided for @jobApplicationsArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get jobApplicationsArchived;

  /// No description provided for @jobApplicationsInvalidLink.
  ///
  /// In en, this message translates to:
  /// **'Invalid link.'**
  String get jobApplicationsInvalidLink;

  /// No description provided for @jobApplicationsFailedToOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Failed to open link.'**
  String get jobApplicationsFailedToOpenLink;

  /// No description provided for @jobApplicationsApplicationsManagement.
  ///
  /// In en, this message translates to:
  /// **'Applications Management'**
  String get jobApplicationsApplicationsManagement;

  /// No description provided for @jobApplicationsJob.
  ///
  /// In en, this message translates to:
  /// **'Job: {selectedjobtitle}'**
  String jobApplicationsJob(Object selectedjobtitle);

  /// No description provided for @jobApplicationsHiringBoard.
  ///
  /// In en, this message translates to:
  /// **'Hiring Board'**
  String get jobApplicationsHiringBoard;

  /// No description provided for @jobApplicationsAllJobs.
  ///
  /// In en, this message translates to:
  /// **'All jobs'**
  String get jobApplicationsAllJobs;

  /// No description provided for @jobApplicationsJob2.
  ///
  /// In en, this message translates to:
  /// **'Job'**
  String get jobApplicationsJob2;

  /// No description provided for @jobApplicationsCompany.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get jobApplicationsCompany;

  /// No description provided for @jobApplicationsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get jobApplicationsConfirm;

  /// No description provided for @hrDashboardShiftStartHhMm.
  ///
  /// In en, this message translates to:
  /// **'Shift start (HH:MM)'**
  String get hrDashboardShiftStartHhMm;

  /// No description provided for @hrDashboardAttendanceStatusHint.
  ///
  /// In en, this message translates to:
  /// **'Status (present/absent/leave/half_day/late)'**
  String get hrDashboardAttendanceStatusHint;

  /// No description provided for @hrDashboardManageDayFromOneWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Manage your day from one workspace: staff, attendance, payroll, and requests.'**
  String get hrDashboardManageDayFromOneWorkspace;

  /// No description provided for @hrDashboardOpenPayrollBatches.
  ///
  /// In en, this message translates to:
  /// **'Open Payroll Batches'**
  String get hrDashboardOpenPayrollBatches;

  /// No description provided for @hrDashboardPendingLeaveRequests.
  ///
  /// In en, this message translates to:
  /// **'Pending Leave Requests'**
  String get hrDashboardPendingLeaveRequests;

  /// No description provided for @hrDashboardActiveSalaryActions.
  ///
  /// In en, this message translates to:
  /// **'Active Salary Actions'**
  String get hrDashboardActiveSalaryActions;

  /// No description provided for @hrDashboardPendingAdvanceRequests.
  ///
  /// In en, this message translates to:
  /// **'Pending Advance Requests'**
  String get hrDashboardPendingAdvanceRequests;

  /// No description provided for @hrDashboardNoAttendanceLogsYet.
  ///
  /// In en, this message translates to:
  /// **'No attendance logs yet.'**
  String get hrDashboardNoAttendanceLogsYet;

  /// No description provided for @hrDashboardNoLeaveRequestsYet.
  ///
  /// In en, this message translates to:
  /// **'No leave requests yet.'**
  String get hrDashboardNoLeaveRequestsYet;

  /// No description provided for @hrDashboardEmployeeActions.
  ///
  /// In en, this message translates to:
  /// **'Employee actions'**
  String get hrDashboardEmployeeActions;

  /// No description provided for @hrDashboardNoAdvanceRequestsYet.
  ///
  /// In en, this message translates to:
  /// **'No advance requests yet.'**
  String get hrDashboardNoAdvanceRequestsYet;

  /// No description provided for @hrDashboardReactivate.
  ///
  /// In en, this message translates to:
  /// **'Re-activate'**
  String get hrDashboardReactivate;

  /// No description provided for @hrDashboardNoCompensationActionsYet.
  ///
  /// In en, this message translates to:
  /// **'No compensation actions yet.'**
  String get hrDashboardNoCompensationActionsYet;

  /// No description provided for @hrDashboardNoPayrollBatchesYet.
  ///
  /// In en, this message translates to:
  /// **'No payroll batches yet.'**
  String get hrDashboardNoPayrollBatchesYet;

  /// No description provided for @hrDashboardNoArchiveDataLoadedYet.
  ///
  /// In en, this message translates to:
  /// **'No archive data loaded yet.'**
  String get hrDashboardNoArchiveDataLoadedYet;

  /// No description provided for @hrDashboardDesktopWorkspaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Desktop workspace for high-efficiency HR operations.'**
  String get hrDashboardDesktopWorkspaceSubtitle;

  /// No description provided for @hrDashboardProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get hrDashboardProfile;

  /// No description provided for @jobApplicationsLoadJobsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load jobs.'**
  String get jobApplicationsLoadJobsFailed;

  /// No description provided for @jobApplicationsLoadApplicationsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load job applications.'**
  String get jobApplicationsLoadApplicationsFailed;

  /// No description provided for @jobApplicationsUpdateStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update application status.'**
  String get jobApplicationsUpdateStatusFailed;

  /// No description provided for @jobApplicationsOfferDetailsBeforeHiring.
  ///
  /// In en, this message translates to:
  /// **'Offer details before hiring'**
  String get jobApplicationsOfferDetailsBeforeHiring;

  /// No description provided for @jobApplicationsOfferedSalaryIqd.
  ///
  /// In en, this message translates to:
  /// **'Offered salary (IQD)'**
  String get jobApplicationsOfferedSalaryIqd;

  /// No description provided for @jobApplicationsOfferedSalaryHint.
  ///
  /// In en, this message translates to:
  /// **'Example: 900000'**
  String get jobApplicationsOfferedSalaryHint;

  /// No description provided for @jobApplicationsWorkHoursHint.
  ///
  /// In en, this message translates to:
  /// **'Example: 9:00 AM - 5:00 PM'**
  String get jobApplicationsWorkHoursHint;

  /// No description provided for @jobApplicationsWorkDaysHint.
  ///
  /// In en, this message translates to:
  /// **'Example: Sunday - Thursday'**
  String get jobApplicationsWorkDaysHint;

  /// No description provided for @jobApplicationsOfferMessageDetails.
  ///
  /// In en, this message translates to:
  /// **'Offer message/details'**
  String get jobApplicationsOfferMessageDetails;

  /// No description provided for @jobApplicationsOfferMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Salary details, allowances, hiring terms...'**
  String get jobApplicationsOfferMessageHint;

  /// No description provided for @jobApplicationsOfferAttachmentOptional.
  ///
  /// In en, this message translates to:
  /// **'Offer attachment (optional)'**
  String get jobApplicationsOfferAttachmentOptional;

  /// No description provided for @jobApplicationsChangeAttachment.
  ///
  /// In en, this message translates to:
  /// **'Change attachment'**
  String get jobApplicationsChangeAttachment;

  /// No description provided for @jobApplicationsInvalidSalaryValue.
  ///
  /// In en, this message translates to:
  /// **'Invalid salary value.'**
  String get jobApplicationsInvalidSalaryValue;

  /// No description provided for @jobApplicationsSaveAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Save and continue'**
  String get jobApplicationsSaveAndContinue;

  /// No description provided for @jobApplicationsRecommendationAccepted.
  ///
  /// In en, this message translates to:
  /// **'Recommendation accepted and moved to shortlisted candidates.'**
  String get jobApplicationsRecommendationAccepted;

  /// No description provided for @jobApplicationsRecommendationAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to accept recommendation.'**
  String get jobApplicationsRecommendationAcceptFailed;

  /// No description provided for @jobApplicationsRecommendationAcceptanceReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Recommendation acceptance reason'**
  String get jobApplicationsRecommendationAcceptanceReasonTitle;

  /// No description provided for @jobApplicationsRecommendationAcceptanceReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Reason for acceptance (optional)'**
  String get jobApplicationsRecommendationAcceptanceReasonHint;

  /// No description provided for @jobApplicationsManagementOnly.
  ///
  /// In en, this message translates to:
  /// **'This page is for management only.'**
  String get jobApplicationsManagementOnly;

  /// No description provided for @jobApplicationsNoApplicationsForCurrentFilters.
  ///
  /// In en, this message translates to:
  /// **'No applications for current filters.'**
  String get jobApplicationsNoApplicationsForCurrentFilters;

  /// No description provided for @jobApplicationsApplicant.
  ///
  /// In en, this message translates to:
  /// **'Applicant'**
  String get jobApplicationsApplicant;

  /// No description provided for @jobApplicationsScopeActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity: {value}'**
  String jobApplicationsScopeActivity(Object value);

  /// No description provided for @jobApplicationsScopeDepartment.
  ///
  /// In en, this message translates to:
  /// **'Department: {value}'**
  String jobApplicationsScopeDepartment(Object value);

  /// No description provided for @jobApplicationsViewingAllCurrentApplications.
  ///
  /// In en, this message translates to:
  /// **'Viewing all current applications.'**
  String get jobApplicationsViewingAllCurrentApplications;

  /// No description provided for @jobApplicationsVisibleNow.
  ///
  /// In en, this message translates to:
  /// **'Visible now: {count}'**
  String jobApplicationsVisibleNow(Object count);

  /// No description provided for @jobApplicationsSearchByApplicantPhoneJob.
  ///
  /// In en, this message translates to:
  /// **'Search by applicant name, phone, or job...'**
  String get jobApplicationsSearchByApplicantPhoneJob;

  /// No description provided for @commonName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get commonName;

  /// No description provided for @jobApplicationsRecommendationCandidateDetails.
  ///
  /// In en, this message translates to:
  /// **'Recommended candidate details'**
  String get jobApplicationsRecommendationCandidateDetails;

  /// No description provided for @jobApplicationsCurrentExperience.
  ///
  /// In en, this message translates to:
  /// **'Current experience'**
  String get jobApplicationsCurrentExperience;

  /// No description provided for @jobApplicationsRecommendedBy.
  ///
  /// In en, this message translates to:
  /// **'Recommended by'**
  String get jobApplicationsRecommendedBy;

  /// No description provided for @jobApplicationsAdminSource.
  ///
  /// In en, this message translates to:
  /// **'Administration'**
  String get jobApplicationsAdminSource;

  /// No description provided for @jobApplicationsRecommendationTime.
  ///
  /// In en, this message translates to:
  /// **'Recommendation time'**
  String get jobApplicationsRecommendationTime;

  /// No description provided for @jobApplicationsRecommendationNote.
  ///
  /// In en, this message translates to:
  /// **'Recommendation note'**
  String get jobApplicationsRecommendationNote;

  /// No description provided for @jobApplicationsRecommendationStatus.
  ///
  /// In en, this message translates to:
  /// **'Recommendation status'**
  String get jobApplicationsRecommendationStatus;

  /// No description provided for @jobApplicationsExperienceSource.
  ///
  /// In en, this message translates to:
  /// **'Experience source'**
  String get jobApplicationsExperienceSource;

  /// No description provided for @jobApplicationsOriginalApplicationData.
  ///
  /// In en, this message translates to:
  /// **'Original application data'**
  String get jobApplicationsOriginalApplicationData;

  /// No description provided for @jobApplicationsApplicationName.
  ///
  /// In en, this message translates to:
  /// **'Application name'**
  String get jobApplicationsApplicationName;

  /// No description provided for @jobApplicationsApplicationPhone.
  ///
  /// In en, this message translates to:
  /// **'Application phone'**
  String get jobApplicationsApplicationPhone;

  /// No description provided for @jobApplicationsApplicationEmail.
  ///
  /// In en, this message translates to:
  /// **'Application email'**
  String get jobApplicationsApplicationEmail;

  /// No description provided for @jobApplicationsExpectedSalary.
  ///
  /// In en, this message translates to:
  /// **'Expected salary'**
  String get jobApplicationsExpectedSalary;

  /// No description provided for @jobApplicationsCoverMessage.
  ///
  /// In en, this message translates to:
  /// **'Cover message'**
  String get jobApplicationsCoverMessage;

  /// No description provided for @jobApplicationsRecommendationAttachmentWithName.
  ///
  /// In en, this message translates to:
  /// **'Recommendation attachment ({name})'**
  String jobApplicationsRecommendationAttachmentWithName(Object name);

  /// No description provided for @jobApplicationsOpenRecommendationAttachment.
  ///
  /// In en, this message translates to:
  /// **'Open recommendation attachment'**
  String get jobApplicationsOpenRecommendationAttachment;

  /// No description provided for @jobApplicationsApplicantAttachmentWithName.
  ///
  /// In en, this message translates to:
  /// **'Applicant attachment ({name})'**
  String jobApplicationsApplicantAttachmentWithName(Object name);

  /// No description provided for @jobApplicationsOpenApplicantAttachment.
  ///
  /// In en, this message translates to:
  /// **'Open applicant attachment'**
  String get jobApplicationsOpenApplicantAttachment;

  /// No description provided for @jobApplicationsOpenResumeLink.
  ///
  /// In en, this message translates to:
  /// **'Open resume link'**
  String get jobApplicationsOpenResumeLink;

  /// No description provided for @jobApplicationsAdminRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Administration recommendations'**
  String get jobApplicationsAdminRecommendations;

  /// No description provided for @jobApplicationsAdministrativeRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Administrative recommendation'**
  String get jobApplicationsAdministrativeRecommendation;

  /// No description provided for @jobApplicationsByName.
  ///
  /// In en, this message translates to:
  /// **'By: {name}'**
  String jobApplicationsByName(Object name);

  /// No description provided for @jobApplicationsRecommendationTimeLine.
  ///
  /// In en, this message translates to:
  /// **'Recommendation time: {value}'**
  String jobApplicationsRecommendationTimeLine(Object value);

  /// No description provided for @jobApplicationsRecommendationSourceLine.
  ///
  /// In en, this message translates to:
  /// **'Recommendation source: application #{id}'**
  String jobApplicationsRecommendationSourceLine(Object id);

  /// No description provided for @jobApplicationsCurrentStatusLine.
  ///
  /// In en, this message translates to:
  /// **'Current status: {status}'**
  String jobApplicationsCurrentStatusLine(Object status);

  /// No description provided for @jobApplicationsAccepting.
  ///
  /// In en, this message translates to:
  /// **'Accepting...'**
  String get jobApplicationsAccepting;

  /// No description provided for @jobApplicationsAcceptRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Accept recommendation'**
  String get jobApplicationsAcceptRecommendation;

  /// No description provided for @jobApplicationsManualRecommendationNoUser.
  ///
  /// In en, this message translates to:
  /// **'Manual recommendation without a user account. It cannot be converted automatically to a candidate.'**
  String get jobApplicationsManualRecommendationNoUser;

  /// No description provided for @jobsHubJobStatusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Job status updated.'**
  String get jobsHubJobStatusUpdated;

  /// No description provided for @jobsHubDeleteJob.
  ///
  /// In en, this message translates to:
  /// **'Delete job'**
  String get jobsHubDeleteJob;

  /// No description provided for @jobsHubJobDeleted.
  ///
  /// In en, this message translates to:
  /// **'Job deleted.'**
  String get jobsHubJobDeleted;

  /// No description provided for @jobsHubFullTime.
  ///
  /// In en, this message translates to:
  /// **'Full-time'**
  String get jobsHubFullTime;

  /// No description provided for @jobsHubPartTime.
  ///
  /// In en, this message translates to:
  /// **'Part-time'**
  String get jobsHubPartTime;

  /// No description provided for @jobsHubContract.
  ///
  /// In en, this message translates to:
  /// **'Contract'**
  String get jobsHubContract;

  /// No description provided for @jobsHubInternship.
  ///
  /// In en, this message translates to:
  /// **'Internship'**
  String get jobsHubInternship;

  /// No description provided for @jobsHubFreelance.
  ///
  /// In en, this message translates to:
  /// **'Freelance'**
  String get jobsHubFreelance;

  /// No description provided for @jobsHubOnSite.
  ///
  /// In en, this message translates to:
  /// **'On-site'**
  String get jobsHubOnSite;

  /// No description provided for @jobsHubHybrid.
  ///
  /// In en, this message translates to:
  /// **'Hybrid'**
  String get jobsHubHybrid;

  /// No description provided for @jobsHubRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get jobsHubRemote;

  /// No description provided for @jobsHubEntry.
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get jobsHubEntry;

  /// No description provided for @jobsHubJunior.
  ///
  /// In en, this message translates to:
  /// **'Junior'**
  String get jobsHubJunior;

  /// No description provided for @jobsHubMid.
  ///
  /// In en, this message translates to:
  /// **'Mid'**
  String get jobsHubMid;

  /// No description provided for @jobsHubSenior.
  ///
  /// In en, this message translates to:
  /// **'Senior'**
  String get jobsHubSenior;

  /// No description provided for @jobsHubLead.
  ///
  /// In en, this message translates to:
  /// **'Lead'**
  String get jobsHubLead;

  /// No description provided for @jobsHubManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get jobsHubManager;

  /// No description provided for @jobsHubPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get jobsHubPaused;

  /// No description provided for @jobsHubClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get jobsHubClosed;

  /// No description provided for @jobsHubSalaryIsNegotiable.
  ///
  /// In en, this message translates to:
  /// **'Salary is negotiable'**
  String get jobsHubSalaryIsNegotiable;

  /// No description provided for @jobsHubSalaryNotSpecified.
  ///
  /// In en, this message translates to:
  /// **'Salary not specified'**
  String get jobsHubSalaryNotSpecified;

  /// No description provided for @jobsHubPerHour.
  ///
  /// In en, this message translates to:
  /// **'per hour'**
  String get jobsHubPerHour;

  /// No description provided for @jobsHubMonthly.
  ///
  /// In en, this message translates to:
  /// **'monthly'**
  String get jobsHubMonthly;

  /// No description provided for @jobsHubYearly.
  ///
  /// In en, this message translates to:
  /// **'yearly'**
  String get jobsHubYearly;

  /// No description provided for @jobsHubPerProject.
  ///
  /// In en, this message translates to:
  /// **'per project'**
  String get jobsHubPerProject;

  /// No description provided for @jobsHubRecommendCandidates.
  ///
  /// In en, this message translates to:
  /// **'Recommend Candidates'**
  String get jobsHubRecommendCandidates;

  /// No description provided for @jobsHubApplications.
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get jobsHubApplications;

  /// No description provided for @jobsHubTalentPool.
  ///
  /// In en, this message translates to:
  /// **'Talent Pool'**
  String get jobsHubTalentPool;

  /// No description provided for @jobsHubFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get jobsHubFilter;

  /// No description provided for @jobsHubPostJob.
  ///
  /// In en, this message translates to:
  /// **'Post Job'**
  String get jobsHubPostJob;

  /// No description provided for @jobsHubShowing.
  ///
  /// In en, this message translates to:
  /// **'Showing'**
  String get jobsHubShowing;

  /// No description provided for @jobsHubOf.
  ///
  /// In en, this message translates to:
  /// **'of'**
  String get jobsHubOf;

  /// No description provided for @jobsHubJobsSection.
  ///
  /// In en, this message translates to:
  /// **'Jobs Section'**
  String get jobsHubJobsSection;

  /// No description provided for @jobsHubManageMode.
  ///
  /// In en, this message translates to:
  /// **'Manage Mode'**
  String get jobsHubManageMode;

  /// No description provided for @jobsHubBrowseMode.
  ///
  /// In en, this message translates to:
  /// **'Browse Mode'**
  String get jobsHubBrowseMode;

  /// No description provided for @jobsHubSmartFilters.
  ///
  /// In en, this message translates to:
  /// **'Smart Filters'**
  String get jobsHubSmartFilters;

  /// No description provided for @jobsHubDirectApply.
  ///
  /// In en, this message translates to:
  /// **'Direct Apply'**
  String get jobsHubDirectApply;

  /// No description provided for @jobsHubAllJobs.
  ///
  /// In en, this message translates to:
  /// **'All Jobs'**
  String get jobsHubAllJobs;

  /// No description provided for @jobsHubManageMyListings.
  ///
  /// In en, this message translates to:
  /// **'Manage My Listings'**
  String get jobsHubManageMyListings;

  /// No description provided for @jobsHubCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get jobsHubCategory;

  /// No description provided for @jobsHubDepartment.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get jobsHubDepartment;

  /// No description provided for @jobsHubCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get jobsHubCity;

  /// No description provided for @jobsHubArea.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get jobsHubArea;

  /// No description provided for @jobsHubEmployment.
  ///
  /// In en, this message translates to:
  /// **'Employment'**
  String get jobsHubEmployment;

  /// No description provided for @jobsHubWorkplace.
  ///
  /// In en, this message translates to:
  /// **'Workplace'**
  String get jobsHubWorkplace;

  /// No description provided for @jobsHubExperience.
  ///
  /// In en, this message translates to:
  /// **'Experience'**
  String get jobsHubExperience;

  /// No description provided for @jobsHubSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get jobsHubSort;

  /// No description provided for @jobsHubOpenOnly.
  ///
  /// In en, this message translates to:
  /// **'Open only'**
  String get jobsHubOpenOnly;

  /// No description provided for @jobsHubClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear Filters'**
  String get jobsHubClearFilters;

  /// No description provided for @jobsHubAdvancedFiltering.
  ///
  /// In en, this message translates to:
  /// **'Advanced filtering'**
  String get jobsHubAdvancedFiltering;

  /// No description provided for @jobsHubReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get jobsHubReload;

  /// No description provided for @jobsHubMyApplications.
  ///
  /// In en, this message translates to:
  /// **'My Applications'**
  String get jobsHubMyApplications;

  /// No description provided for @jobsHubApplicationStatuses.
  ///
  /// In en, this message translates to:
  /// **'Application statuses'**
  String get jobsHubApplicationStatuses;

  /// No description provided for @jobsHubManageApplicants.
  ///
  /// In en, this message translates to:
  /// **'Manage applicants'**
  String get jobsHubManageApplicants;

  /// No description provided for @jobsHubTalentPool2.
  ///
  /// In en, this message translates to:
  /// **'Talent pool'**
  String get jobsHubTalentPool2;

  /// No description provided for @jobsHubApplicantsCenter.
  ///
  /// In en, this message translates to:
  /// **'Applicants center'**
  String get jobsHubApplicantsCenter;

  /// No description provided for @jobsHubPostJob2.
  ///
  /// In en, this message translates to:
  /// **'Post job'**
  String get jobsHubPostJob2;

  /// No description provided for @jobsHubNewListing.
  ///
  /// In en, this message translates to:
  /// **'New listing'**
  String get jobsHubNewListing;

  /// No description provided for @jobsHubVisibleNow.
  ///
  /// In en, this message translates to:
  /// **'Visible now'**
  String get jobsHubVisibleNow;

  /// No description provided for @jobsHubOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get jobsHubOpen;

  /// No description provided for @jobsHubAllStatuses.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get jobsHubAllStatuses;

  /// No description provided for @jobsHubResetFilters.
  ///
  /// In en, this message translates to:
  /// **'Reset Filters'**
  String get jobsHubResetFilters;

  /// No description provided for @jobsHubHighestSalary.
  ///
  /// In en, this message translates to:
  /// **'Highest salary'**
  String get jobsHubHighestSalary;

  /// No description provided for @jobsHubLowestSalary.
  ///
  /// In en, this message translates to:
  /// **'Lowest salary'**
  String get jobsHubLowestSalary;

  /// No description provided for @jobsHubExpiresSoon.
  ///
  /// In en, this message translates to:
  /// **'Expires soon'**
  String get jobsHubExpiresSoon;

  /// No description provided for @jobsHubMostRecent.
  ///
  /// In en, this message translates to:
  /// **'Most recent'**
  String get jobsHubMostRecent;

  /// No description provided for @jobsHubJobsFilters.
  ///
  /// In en, this message translates to:
  /// **'Jobs Filters'**
  String get jobsHubJobsFilters;

  /// No description provided for @jobsHubActivityType.
  ///
  /// In en, this message translates to:
  /// **'Activity Type'**
  String get jobsHubActivityType;

  /// No description provided for @jobsHubEmploymentType.
  ///
  /// In en, this message translates to:
  /// **'Employment Type'**
  String get jobsHubEmploymentType;

  /// No description provided for @jobsHubWorkplaceType.
  ///
  /// In en, this message translates to:
  /// **'Workplace Type'**
  String get jobsHubWorkplaceType;

  /// No description provided for @jobsHubExperienceLevel.
  ///
  /// In en, this message translates to:
  /// **'Experience Level'**
  String get jobsHubExperienceLevel;

  /// No description provided for @jobsHubListingStatus.
  ///
  /// In en, this message translates to:
  /// **'Listing Status'**
  String get jobsHubListingStatus;

  /// No description provided for @jobsHubMinimumSalary.
  ///
  /// In en, this message translates to:
  /// **'Minimum salary'**
  String get jobsHubMinimumSalary;

  /// No description provided for @jobsHubMaximumSalary.
  ///
  /// In en, this message translates to:
  /// **'Maximum salary'**
  String get jobsHubMaximumSalary;

  /// No description provided for @jobsHubApplyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply Filters'**
  String get jobsHubApplyFilters;

  /// No description provided for @jobsHubPostNewJob.
  ///
  /// In en, this message translates to:
  /// **'Post New Job'**
  String get jobsHubPostNewJob;

  /// No description provided for @jobsHubCategory2.
  ///
  /// In en, this message translates to:
  /// **'Category *'**
  String get jobsHubCategory2;

  /// No description provided for @jobsHubActivityType2.
  ///
  /// In en, this message translates to:
  /// **'Activity Type *'**
  String get jobsHubActivityType2;

  /// No description provided for @jobsHubDepartment2.
  ///
  /// In en, this message translates to:
  /// **'Department *'**
  String get jobsHubDepartment2;

  /// No description provided for @jobsHubCity2.
  ///
  /// In en, this message translates to:
  /// **'City *'**
  String get jobsHubCity2;

  /// No description provided for @jobsHubSalaryPeriod.
  ///
  /// In en, this message translates to:
  /// **'Salary Period'**
  String get jobsHubSalaryPeriod;

  /// No description provided for @jobsHubHourly.
  ///
  /// In en, this message translates to:
  /// **'Hourly'**
  String get jobsHubHourly;

  /// No description provided for @jobsHubMonthly2.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get jobsHubMonthly2;

  /// No description provided for @jobsHubYearly2.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get jobsHubYearly2;

  /// No description provided for @jobsHubPerProject2.
  ///
  /// In en, this message translates to:
  /// **'Per Project'**
  String get jobsHubPerProject2;

  /// No description provided for @jobsHubRequirements.
  ///
  /// In en, this message translates to:
  /// **'Requirements'**
  String get jobsHubRequirements;

  /// No description provided for @jobsHubResponsibilities.
  ///
  /// In en, this message translates to:
  /// **'Responsibilities'**
  String get jobsHubResponsibilities;

  /// No description provided for @jobsHubBenefits.
  ///
  /// In en, this message translates to:
  /// **'Benefits'**
  String get jobsHubBenefits;

  /// No description provided for @jobsHubVacancies.
  ///
  /// In en, this message translates to:
  /// **'Vacancies'**
  String get jobsHubVacancies;

  /// No description provided for @jobsHubExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get jobsHubExpires;

  /// No description provided for @jobsHubContactPhone.
  ///
  /// In en, this message translates to:
  /// **'Contact phone'**
  String get jobsHubContactPhone;

  /// No description provided for @jobsHubContactEmail.
  ///
  /// In en, this message translates to:
  /// **'Contact email'**
  String get jobsHubContactEmail;

  /// No description provided for @jobsHubPublishJob.
  ///
  /// In en, this message translates to:
  /// **'Publish Job'**
  String get jobsHubPublishJob;

  /// No description provided for @jobsHubApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get jobsHubApplied;

  /// No description provided for @jobsHubJobDescription.
  ///
  /// In en, this message translates to:
  /// **'Job Description'**
  String get jobsHubJobDescription;

  /// No description provided for @jobsHubSkills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get jobsHubSkills;

  /// No description provided for @jobsHubPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get jobsHubPhone;

  /// No description provided for @jobsHubEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get jobsHubEmail;

  /// No description provided for @jobsHubPauseListing.
  ///
  /// In en, this message translates to:
  /// **'Pause Listing'**
  String get jobsHubPauseListing;

  /// No description provided for @jobsHubActivateListing.
  ///
  /// In en, this message translates to:
  /// **'Activate Listing'**
  String get jobsHubActivateListing;

  /// No description provided for @jobsHubCloseListing.
  ///
  /// In en, this message translates to:
  /// **'Close Listing'**
  String get jobsHubCloseListing;

  /// No description provided for @jobsHubDeleteListing.
  ///
  /// In en, this message translates to:
  /// **'Delete Listing'**
  String get jobsHubDeleteListing;

  /// No description provided for @jobsHubApplyNow.
  ///
  /// In en, this message translates to:
  /// **'Apply Now'**
  String get jobsHubApplyNow;

  /// No description provided for @jobApplyPleaseEnterPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Please enter phone number.'**
  String get jobApplyPleaseEnterPhoneNumber;

  /// No description provided for @jobApplyApplyForJob.
  ///
  /// In en, this message translates to:
  /// **'Apply for Job'**
  String get jobApplyApplyForJob;

  /// No description provided for @jobApplySubmitApplication.
  ///
  /// In en, this message translates to:
  /// **'Submit Application'**
  String get jobApplySubmitApplication;

  /// No description provided for @jobApplySendApplication.
  ///
  /// In en, this message translates to:
  /// **'Send Application'**
  String get jobApplySendApplication;

  /// No description provided for @jobApplyApplicationDetails.
  ///
  /// In en, this message translates to:
  /// **'Application Details'**
  String get jobApplyApplicationDetails;

  /// No description provided for @jobApplyApplicantPhone.
  ///
  /// In en, this message translates to:
  /// **'Applicant phone'**
  String get jobApplyApplicantPhone;

  /// No description provided for @jobApplyCoverMessage.
  ///
  /// In en, this message translates to:
  /// **'Cover message'**
  String get jobApplyCoverMessage;

  /// No description provided for @jobApplyUploadPdfImage.
  ///
  /// In en, this message translates to:
  /// **'Upload PDF/Image'**
  String get jobApplyUploadPdfImage;

  /// No description provided for @jobApplyRemoveAttachment.
  ///
  /// In en, this message translates to:
  /// **'Remove attachment'**
  String get jobApplyRemoveAttachment;

  /// No description provided for @jobApplyAttachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get jobApplyAttachment;

  /// No description provided for @jobAdminJobsReaderRecommendationSubmittedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Recommendation submitted successfully.'**
  String get jobAdminJobsReaderRecommendationSubmittedSuccessfully;

  /// No description provided for @jobAdminJobsReaderThisPageIsForAdminsOnly.
  ///
  /// In en, this message translates to:
  /// **'This page is for admins only.'**
  String get jobAdminJobsReaderThisPageIsForAdminsOnly;

  /// No description provided for @jobAdminJobsReaderRecommendCandidate.
  ///
  /// In en, this message translates to:
  /// **'Recommend Candidate'**
  String get jobAdminJobsReaderRecommendCandidate;

  /// No description provided for @jobAdminJobsReaderPleaseEnterCandidateName.
  ///
  /// In en, this message translates to:
  /// **'Please enter candidate name.'**
  String get jobAdminJobsReaderPleaseEnterCandidateName;

  /// No description provided for @jobAdminJobsReaderRecommendationFor.
  ///
  /// In en, this message translates to:
  /// **'Recommendation for'**
  String get jobAdminJobsReaderRecommendationFor;

  /// No description provided for @jobAdminJobsReaderFromTalentPool.
  ///
  /// In en, this message translates to:
  /// **'From Talent Pool'**
  String get jobAdminJobsReaderFromTalentPool;

  /// No description provided for @jobAdminJobsReaderManualRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Manual Recommendation'**
  String get jobAdminJobsReaderManualRecommendation;

  /// No description provided for @jobAdminJobsReaderCandidateName.
  ///
  /// In en, this message translates to:
  /// **'Candidate name *'**
  String get jobAdminJobsReaderCandidateName;

  /// No description provided for @jobAdminJobsReaderPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get jobAdminJobsReaderPhone;

  /// No description provided for @jobAdminJobsReaderCurrentJobTitle.
  ///
  /// In en, this message translates to:
  /// **'Current job title'**
  String get jobAdminJobsReaderCurrentJobTitle;

  /// No description provided for @jobAdminJobsReaderCurrentCompany.
  ///
  /// In en, this message translates to:
  /// **'Current company'**
  String get jobAdminJobsReaderCurrentCompany;

  /// No description provided for @jobAdminJobsReaderAttachFileImage.
  ///
  /// In en, this message translates to:
  /// **'Attach file/image'**
  String get jobAdminJobsReaderAttachFileImage;

  /// No description provided for @jobAdminJobsReaderNoAttachmentSelected.
  ///
  /// In en, this message translates to:
  /// **'No attachment selected'**
  String get jobAdminJobsReaderNoAttachmentSelected;

  /// No description provided for @jobAdminJobsReaderLatestAppliedJob.
  ///
  /// In en, this message translates to:
  /// **'Latest applied job'**
  String get jobAdminJobsReaderLatestAppliedJob;

  /// No description provided for @jobAdminJobsReaderPreviousApplications.
  ///
  /// In en, this message translates to:
  /// **'Previous applications'**
  String get jobAdminJobsReaderPreviousApplications;

  /// No description provided for @jobsHubAlreadyAppliedToThisJob.
  ///
  /// In en, this message translates to:
  /// **'Already applied to this job'**
  String get jobsHubAlreadyAppliedToThisJob;

  /// No description provided for @jobsHubUnavailableForApplication.
  ///
  /// In en, this message translates to:
  /// **'This job is currently unavailable for application.'**
  String get jobsHubUnavailableForApplication;

  /// No description provided for @customerMainMarketTitle.
  ///
  /// In en, this message translates to:
  /// **'Main market'**
  String get customerMainMarketTitle;

  /// No description provided for @customerMainMarketMainHubs.
  ///
  /// In en, this message translates to:
  /// **'Main hubs'**
  String get customerMainMarketMainHubs;

  /// No description provided for @customerMainMarketQuickCategoryAccess.
  ///
  /// In en, this message translates to:
  /// **'Quick category access'**
  String get customerMainMarketQuickCategoryAccess;

  /// No description provided for @customerMainMarketHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Everything in one market'**
  String get customerMainMarketHeroTitle;

  /// No description provided for @customerMainMarketHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Explore stores clearly with smart suggestions based on your activity.'**
  String get customerMainMarketHeroSubtitle;

  /// No description provided for @jobApplyValidEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address.'**
  String get jobApplyValidEmailAddress;

  /// No description provided for @jobApplyEmailOptional.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get jobApplyEmailOptional;

  /// No description provided for @jobApplyExpectedSalaryOptional.
  ///
  /// In en, this message translates to:
  /// **'Expected salary (optional)'**
  String get jobApplyExpectedSalaryOptional;

  /// No description provided for @jobAdminJobsReaderTitle.
  ///
  /// In en, this message translates to:
  /// **'Jobs Reader & Candidate Recommendation'**
  String get jobAdminJobsReaderTitle;

  /// No description provided for @jobAdminJobsReaderSearchByJobTitleOrCompany.
  ///
  /// In en, this message translates to:
  /// **'Search by job title or company...'**
  String get jobAdminJobsReaderSearchByJobTitleOrCompany;

  /// No description provided for @jobAdminJobsReaderNoJobsMatchCurrentSearch.
  ///
  /// In en, this message translates to:
  /// **'No jobs match the current search.'**
  String get jobAdminJobsReaderNoJobsMatchCurrentSearch;

  /// No description provided for @jobAdminJobsReaderLoadPublishedJobsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load published jobs.'**
  String get jobAdminJobsReaderLoadPublishedJobsFailed;

  /// No description provided for @jobAdminJobsReaderLoadRecommendationCandidatesFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load recommendation candidates.'**
  String get jobAdminJobsReaderLoadRecommendationCandidatesFailed;

  /// No description provided for @jobAdminJobsReaderSubmitRecommendationFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit recommendation.'**
  String get jobAdminJobsReaderSubmitRecommendationFailed;

  /// No description provided for @jobAdminJobsReaderSubmitManualRecommendationFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit manual recommendation.'**
  String get jobAdminJobsReaderSubmitManualRecommendationFailed;

  /// No description provided for @jobAdminJobsReaderRecommendationNoteOptional.
  ///
  /// In en, this message translates to:
  /// **'Recommendation note (optional)'**
  String get jobAdminJobsReaderRecommendationNoteOptional;

  /// No description provided for @jobAdminJobsReaderSubmitManualRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Submit manual recommendation'**
  String get jobAdminJobsReaderSubmitManualRecommendation;

  /// No description provided for @jobAdminJobsReaderSearchByNameOrPhone.
  ///
  /// In en, this message translates to:
  /// **'Search by name or phone...'**
  String get jobAdminJobsReaderSearchByNameOrPhone;

  /// No description provided for @jobAdminJobsReaderNoMatchingCandidatesRightNow.
  ///
  /// In en, this message translates to:
  /// **'No matching candidates right now. You can switch to manual recommendation.'**
  String get jobAdminJobsReaderNoMatchingCandidatesRightNow;

  /// No description provided for @jobAdminJobsReaderRecommendThisCandidate.
  ///
  /// In en, this message translates to:
  /// **'Recommend this candidate'**
  String get jobAdminJobsReaderRecommendThisCandidate;

  /// No description provided for @socialReelCommentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reel comments'**
  String get socialReelCommentsTitle;

  /// No description provided for @socialProfileAdminActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'User management'**
  String get socialProfileAdminActionsTitle;

  /// No description provided for @commonUnexpectedError.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred.'**
  String get commonUnexpectedError;

  /// No description provided for @commonServerConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to connect to the server.'**
  String get commonServerConnectionFailed;

  /// No description provided for @ownerAssignExistingAccountantFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to link the existing accountant to the store.'**
  String get ownerAssignExistingAccountantFailed;

  /// No description provided for @ownerAssignExistingHrStaffFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to link the existing HR staff member to the store.'**
  String get ownerAssignExistingHrStaffFailed;

  /// No description provided for @ownerMarkOrderItemUnavailableFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update item availability.'**
  String get ownerMarkOrderItemUnavailableFailed;

  /// No description provided for @deliveryDashboardLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the delivery dashboard.'**
  String get deliveryDashboardLoadFailed;

  /// No description provided for @deliveryAcceptRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to accept the request.'**
  String get deliveryAcceptRequestFailed;

  /// No description provided for @deliveryRejectRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to reject the request.'**
  String get deliveryRejectRequestFailed;

  /// No description provided for @deliveryPickedUpOrderFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the pickup status.'**
  String get deliveryPickedUpOrderFailed;

  /// No description provided for @deliveryArrivedOrderFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the arrival status.'**
  String get deliveryArrivedOrderFailed;

  /// No description provided for @deliveryDeliveredOrderFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to complete the delivery.'**
  String get deliveryDeliveredOrderFailed;

  /// No description provided for @deliveryCancelOrderRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to send the cancellation request. Please try again.'**
  String get deliveryCancelOrderRequestFailed;

  /// No description provided for @deliveryEndDaySummary.
  ///
  /// In en, this message translates to:
  /// **'Day {date} closed: {count} orders, total {amount}'**
  String deliveryEndDaySummary(Object date, Object count, Object amount);

  /// No description provided for @deliveryEndDayFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to close the day.'**
  String get deliveryEndDayFailed;

  /// No description provided for @taxiShareRideFriendsTitle.
  ///
  /// In en, this message translates to:
  /// **'Share the ride with friends'**
  String get taxiShareRideFriendsTitle;

  /// No description provided for @taxiShareRideFriendsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the friends who can follow this ride live. Deselect everyone to stop sharing.'**
  String get taxiShareRideFriendsSubtitle;

  /// No description provided for @taxiShareRideFriendsSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save sharing'**
  String get taxiShareRideFriendsSaveAction;

  /// No description provided for @taxiShareRideFriendsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the friends list.'**
  String get taxiShareRideFriendsLoadFailed;

  /// No description provided for @taxiShareRideFriendsSaved.
  ///
  /// In en, this message translates to:
  /// **'Ride sharing with friends was updated.'**
  String get taxiShareRideFriendsSaved;

  /// No description provided for @taxiShareRideFriendsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save ride sharing settings.'**
  String get taxiShareRideFriendsSaveFailed;

  /// No description provided for @taxiShareRideFriendsEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no accepted friends available to share this ride with right now.'**
  String get taxiShareRideFriendsEmpty;

  /// No description provided for @taxiShareRideFriendsId.
  ///
  /// In en, this message translates to:
  /// **'ID: {friendId}'**
  String taxiShareRideFriendsId(Object friendId);

  /// No description provided for @taxiSharedRideTrackingTitle.
  ///
  /// In en, this message translates to:
  /// **'Shared ride tracking'**
  String get taxiSharedRideTrackingTitle;

  /// No description provided for @taxiSharedRideTrackingEmpty.
  ///
  /// In en, this message translates to:
  /// **'No ride data is currently available.'**
  String get taxiSharedRideTrackingEmpty;

  /// No description provided for @taxiSharedRideTrackingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The shared ride link has expired or is no longer available.'**
  String get taxiSharedRideTrackingUnavailable;

  /// No description provided for @taxiSharedRideTrackingRideStatus.
  ///
  /// In en, this message translates to:
  /// **'Ride status'**
  String get taxiSharedRideTrackingRideStatus;

  /// No description provided for @taxiSharedRideTrackingFare.
  ///
  /// In en, this message translates to:
  /// **'Fare'**
  String get taxiSharedRideTrackingFare;

  /// No description provided for @taxiSharedRideTrackingCaptain.
  ///
  /// In en, this message translates to:
  /// **'Captain'**
  String get taxiSharedRideTrackingCaptain;

  /// No description provided for @taxiSharedRideTrackingPendingAssignment.
  ///
  /// In en, this message translates to:
  /// **'Pending assignment'**
  String get taxiSharedRideTrackingPendingAssignment;

  /// No description provided for @taxiSharedRideTrackingPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get taxiSharedRideTrackingPickup;

  /// No description provided for @taxiSharedRideTrackingDropoff.
  ///
  /// In en, this message translates to:
  /// **'Dropoff'**
  String get taxiSharedRideTrackingDropoff;

  /// No description provided for @taxiSharedRideTrackingLastUpdate.
  ///
  /// In en, this message translates to:
  /// **'Last update'**
  String get taxiSharedRideTrackingLastUpdate;

  /// No description provided for @taxiSharedRideTrackingStatusSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching'**
  String get taxiSharedRideTrackingStatusSearching;

  /// No description provided for @taxiSharedRideTrackingStatusCaptainAssigned.
  ///
  /// In en, this message translates to:
  /// **'Captain assigned'**
  String get taxiSharedRideTrackingStatusCaptainAssigned;

  /// No description provided for @taxiSharedRideTrackingStatusCaptainArriving.
  ///
  /// In en, this message translates to:
  /// **'Captain arriving'**
  String get taxiSharedRideTrackingStatusCaptainArriving;

  /// No description provided for @taxiSharedRideTrackingStatusRideStarted.
  ///
  /// In en, this message translates to:
  /// **'Ride started'**
  String get taxiSharedRideTrackingStatusRideStarted;

  /// No description provided for @mapPageCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'My current location'**
  String get mapPageCurrentLocation;

  /// No description provided for @mapPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Smart taxi map'**
  String get mapPageTitle;

  /// No description provided for @mapPageLoginRequired.
  ///
  /// In en, this message translates to:
  /// **'Please sign in first to use the taxi service.'**
  String get mapPageLoginRequired;

  /// No description provided for @mapPageCustomerOnly.
  ///
  /// In en, this message translates to:
  /// **'The taxi service is available for customer accounts only.'**
  String get mapPageCustomerOnly;

  /// No description provided for @mapPageCurrentRideLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the current ride.'**
  String get mapPageCurrentRideLoadFailed;

  /// No description provided for @mapPageSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get mapPageSessionExpired;

  /// No description provided for @mapPageEnableLocationService.
  ///
  /// In en, this message translates to:
  /// **'Please enable location services on your device.'**
  String get mapPageEnableLocationService;

  /// No description provided for @mapPageLocationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission was denied.'**
  String get mapPageLocationPermissionDenied;

  /// No description provided for @mapPageLocateCurrentPositionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to determine your current location.'**
  String get mapPageLocateCurrentPositionFailed;

  /// No description provided for @mapPageSelectPickupFirst.
  ///
  /// In en, this message translates to:
  /// **'Select the pickup point first.'**
  String get mapPageSelectPickupFirst;

  /// No description provided for @mapPageSelectDropoffFirst.
  ///
  /// In en, this message translates to:
  /// **'Select the dropoff point first.'**
  String get mapPageSelectDropoffFirst;

  /// No description provided for @mapPagePickupConfirmedNextDropoff.
  ///
  /// In en, this message translates to:
  /// **'Pickup confirmed. Now select the dropoff point.'**
  String get mapPagePickupConfirmedNextDropoff;

  /// No description provided for @mapPageConfirmDropoffLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm the dropoff point'**
  String get mapPageConfirmDropoffLabel;

  /// No description provided for @mapPageFareMayReduceAcceptance.
  ///
  /// In en, this message translates to:
  /// **'A lower fare may reduce captain acceptance chance.'**
  String get mapPageFareMayReduceAcceptance;

  /// No description provided for @mapPageSelectPickupAndDropoff.
  ///
  /// In en, this message translates to:
  /// **'Select both the pickup and dropoff points.'**
  String get mapPageSelectPickupAndDropoff;

  /// No description provided for @mapPageConfirmPickupBeforeSubmit.
  ///
  /// In en, this message translates to:
  /// **'You must confirm the pickup point before sending the request.'**
  String get mapPageConfirmPickupBeforeSubmit;

  /// No description provided for @mapPageEnterValidFare.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid fare amount using numbers only.'**
  String get mapPageEnterValidFare;

  /// No description provided for @mapPagePickupAndDropoffLabelsRequired.
  ///
  /// In en, this message translates to:
  /// **'Please provide a clear label for both the pickup and dropoff points.'**
  String get mapPagePickupAndDropoffLabelsRequired;

  /// No description provided for @mapPageRideRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Your taxi request was sent successfully.'**
  String get mapPageRideRequestSent;

  /// No description provided for @mapPageRideRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to send the request right now.'**
  String get mapPageRideRequestFailed;

  /// No description provided for @mapPageRideCancelled.
  ///
  /// In en, this message translates to:
  /// **'The ride was cancelled.'**
  String get mapPageRideCancelled;

  /// No description provided for @mapPageRideCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to cancel the ride right now.'**
  String get mapPageRideCancelFailed;

  /// No description provided for @mapPageRateRideTitle.
  ///
  /// In en, this message translates to:
  /// **'Rate the ride'**
  String get mapPageRateRideTitle;

  /// No description provided for @mapPageRateRideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Rate the captain\'s performance after this ride.'**
  String get mapPageRateRideSubtitle;

  /// No description provided for @mapPageOptionalNote.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get mapPageOptionalNote;

  /// No description provided for @mapPageRateRideLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get mapPageRateRideLater;

  /// No description provided for @mapPageSubmitRating.
  ///
  /// In en, this message translates to:
  /// **'Submit rating'**
  String get mapPageSubmitRating;

  /// No description provided for @mapPageRideRated.
  ///
  /// In en, this message translates to:
  /// **'The ride rating was submitted.'**
  String get mapPageRideRated;

  /// No description provided for @mapPageRideRatingFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to submit the ride rating.'**
  String get mapPageRideRatingFailed;

  /// No description provided for @mapPageCaptainOfferAccepted.
  ///
  /// In en, this message translates to:
  /// **'The captain\'s offer was accepted.'**
  String get mapPageCaptainOfferAccepted;

  /// No description provided for @mapPageCaptainOfferAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to accept the offer right now.'**
  String get mapPageCaptainOfferAcceptFailed;

  /// No description provided for @mapPageCurrentOfferRejected.
  ///
  /// In en, this message translates to:
  /// **'The current offer was rejected and the next one is now active.'**
  String get mapPageCurrentOfferRejected;

  /// No description provided for @mapPageCurrentOfferRejectFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to reject the current offer.'**
  String get mapPageCurrentOfferRejectFailed;

  /// No description provided for @mapPageCounterOfferSent.
  ///
  /// In en, this message translates to:
  /// **'The counter offer was sent.'**
  String get mapPageCounterOfferSent;

  /// No description provided for @mapPageCounterOfferFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to send the counter offer.'**
  String get mapPageCounterOfferFailed;

  /// No description provided for @mapPageCounterOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Send a counter offer'**
  String get mapPageCounterOfferTitle;

  /// No description provided for @mapPageSuggestedFareLabel.
  ///
  /// In en, this message translates to:
  /// **'Suggested fare (IQD)'**
  String get mapPageSuggestedFareLabel;

  /// No description provided for @mapPageFareInvalid.
  ///
  /// In en, this message translates to:
  /// **'The fare amount is invalid.'**
  String get mapPageFareInvalid;

  /// No description provided for @mapPageRideChatLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the ride chat.'**
  String get mapPageRideChatLoadFailed;

  /// No description provided for @mapPageRideChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Ride chat'**
  String get mapPageRideChatTitle;

  /// No description provided for @mapPageRideChatEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get mapPageRideChatEmpty;

  /// No description provided for @mapPageCaptainLabel.
  ///
  /// In en, this message translates to:
  /// **'Captain'**
  String get mapPageCaptainLabel;

  /// No description provided for @mapPageWriteMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Write your message...'**
  String get mapPageWriteMessageHint;

  /// No description provided for @mapPageRideChatSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to send the message.'**
  String get mapPageRideChatSendFailed;

  /// No description provided for @mapPageRideActivePointsLocked.
  ///
  /// In en, this message translates to:
  /// **'You already have an active ride, so the points cannot be changed now.'**
  String get mapPageRideActivePointsLocked;

  /// No description provided for @mapPagePickupPoint.
  ///
  /// In en, this message translates to:
  /// **'Pickup point'**
  String get mapPagePickupPoint;

  /// No description provided for @mapPageDropoffPoint.
  ///
  /// In en, this message translates to:
  /// **'Dropoff point'**
  String get mapPageDropoffPoint;

  /// No description provided for @mapPageSwitchToDropoff.
  ///
  /// In en, this message translates to:
  /// **'Switch to the dropoff point'**
  String get mapPageSwitchToDropoff;

  /// No description provided for @mapPageSwitchToPickup.
  ///
  /// In en, this message translates to:
  /// **'Switch to the pickup point'**
  String get mapPageSwitchToPickup;

  /// No description provided for @mapPageReadyForRequest.
  ///
  /// In en, this message translates to:
  /// **'Ready for a new taxi request'**
  String get mapPageReadyForRequest;

  /// No description provided for @mapPageRealtimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Live status'**
  String get mapPageRealtimeLabel;

  /// No description provided for @mapPageRealtimeConnected.
  ///
  /// In en, this message translates to:
  /// **'Real-time updates are active'**
  String get mapPageRealtimeConnected;

  /// No description provided for @mapPageRealtimeReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting to live updates...'**
  String get mapPageRealtimeReconnecting;

  /// No description provided for @mapPageRouteDistanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get mapPageRouteDistanceLabel;

  /// No description provided for @mapPageRouteDurationLabel.
  ///
  /// In en, this message translates to:
  /// **'ETA'**
  String get mapPageRouteDurationLabel;

  /// No description provided for @mapPageStatusSearching.
  ///
  /// In en, this message translates to:
  /// **'Waiting for captain offers'**
  String get mapPageStatusSearching;

  /// No description provided for @mapPageStatusCaptainAssigned.
  ///
  /// In en, this message translates to:
  /// **'Captain selected'**
  String get mapPageStatusCaptainAssigned;

  /// No description provided for @mapPageStatusCaptainArriving.
  ///
  /// In en, this message translates to:
  /// **'Captain is on the way'**
  String get mapPageStatusCaptainArriving;

  /// No description provided for @mapPageStatusRideStarted.
  ///
  /// In en, this message translates to:
  /// **'Ride in progress'**
  String get mapPageStatusRideStarted;

  /// No description provided for @mapPageStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Ride completed'**
  String get mapPageStatusCompleted;

  /// No description provided for @mapPageStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Ride cancelled'**
  String get mapPageStatusCancelled;

  /// No description provided for @mapPageStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Request expired'**
  String get mapPageStatusExpired;

  /// No description provided for @mapPageStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Status unavailable'**
  String get mapPageStatusUnknown;

  /// No description provided for @mapPageRouteDistanceUnknown.
  ///
  /// In en, this message translates to:
  /// **'Distance will appear after planning the route'**
  String get mapPageRouteDistanceUnknown;

  /// No description provided for @mapPageRouteDistanceMeters.
  ///
  /// In en, this message translates to:
  /// **'{meters} m'**
  String mapPageRouteDistanceMeters(Object meters);

  /// No description provided for @mapPageRouteDistanceKilometers.
  ///
  /// In en, this message translates to:
  /// **'{kilometers} km'**
  String mapPageRouteDistanceKilometers(Object kilometers);

  /// No description provided for @mapPageRouteDurationUnknown.
  ///
  /// In en, this message translates to:
  /// **'Duration will appear after planning the route'**
  String get mapPageRouteDurationUnknown;

  /// No description provided for @mapPageRouteDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String mapPageRouteDurationMinutes(Object minutes);

  /// No description provided for @mapPageRouteDurationHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} hr'**
  String mapPageRouteDurationHours(Object hours);

  /// No description provided for @mapPageRouteDurationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} hr {minutes} min'**
  String mapPageRouteDurationHoursMinutes(Object hours, Object minutes);

  /// No description provided for @mapPageRideSearchingTitle.
  ///
  /// In en, this message translates to:
  /// **'Looking for the right captain'**
  String get mapPageRideSearchingTitle;

  /// No description provided for @mapPageRideCaptainAssignedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your ride is confirmed'**
  String get mapPageRideCaptainAssignedTitle;

  /// No description provided for @mapPageRideStartedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your ride is underway'**
  String get mapPageRideStartedTitle;

  /// No description provided for @mapPageRideCompletedTitle.
  ///
  /// In en, this message translates to:
  /// **'Ride completed successfully'**
  String get mapPageRideCompletedTitle;

  /// No description provided for @mapPageRideCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'This ride was cancelled'**
  String get mapPageRideCancelledTitle;

  /// No description provided for @mapPageRideExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'The request expired'**
  String get mapPageRideExpiredTitle;

  /// No description provided for @mapPageRideRequestCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a taxi request'**
  String get mapPageRideRequestCreateTitle;

  /// No description provided for @mapPageSearchingRaiseFareHint.
  ///
  /// In en, this message translates to:
  /// **'No captain has accepted yet. Try raising the fare to speed up matching.'**
  String get mapPageSearchingRaiseFareHint;

  /// No description provided for @mapPageSearchingCountdownHint.
  ///
  /// In en, this message translates to:
  /// **'Final confirmation window: {time}'**
  String mapPageSearchingCountdownHint(Object time);

  /// No description provided for @mapPageSearchingCaptainSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stay on this screen while we compare nearby offers in real time.'**
  String get mapPageSearchingCaptainSubtitle;

  /// No description provided for @mapPageCaptainAssignedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The captain has your trip details and is heading to the pickup point.'**
  String get mapPageCaptainAssignedSubtitle;

  /// No description provided for @mapPageRideStartedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Follow the live route and stay in touch with your captain if needed.'**
  String get mapPageRideStartedSubtitle;

  /// No description provided for @mapPageRideCompletedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You can now rate the ride and review the trip details.'**
  String get mapPageRideCompletedSubtitle;

  /// No description provided for @mapPageRideCancelledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You can review the pickup and destination, then submit a new request.'**
  String get mapPageRideCancelledSubtitle;

  /// No description provided for @mapPageRideExpiredSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You can adjust the fare or route details and submit the request again.'**
  String get mapPageRideExpiredSubtitle;

  /// No description provided for @mapPageRideRequestHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the pickup and dropoff points, then review the route before sending the request.'**
  String get mapPageRideRequestHeroSubtitle;

  /// No description provided for @mapPageActiveRideTitle.
  ///
  /// In en, this message translates to:
  /// **'Active ride #{rideId}'**
  String mapPageActiveRideTitle(Object rideId);

  /// No description provided for @mapPageRideFareLabel.
  ///
  /// In en, this message translates to:
  /// **'Fare: {amount}'**
  String mapPageRideFareLabel(Object amount);

  /// No description provided for @mapPageRidePickupSummary.
  ///
  /// In en, this message translates to:
  /// **'Pickup: {label}'**
  String mapPageRidePickupSummary(Object label);

  /// No description provided for @mapPageRideDropoffSummary.
  ///
  /// In en, this message translates to:
  /// **'Dropoff: {label}'**
  String mapPageRideDropoffSummary(Object label);

  /// No description provided for @mapPageSearchingFinalAcceptanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Time left for final confirmation'**
  String get mapPageSearchingFinalAcceptanceTitle;

  /// No description provided for @mapPageSearchingRaiseFareNow.
  ///
  /// In en, this message translates to:
  /// **'No captain has accepted yet. Raise the fare to improve your chances.'**
  String get mapPageSearchingRaiseFareNow;

  /// No description provided for @mapPageSearchingWaitBeforeRaise.
  ///
  /// In en, this message translates to:
  /// **'If matching takes five minutes, we will recommend increasing the fare.'**
  String get mapPageSearchingWaitBeforeRaise;

  /// No description provided for @mapPageCaptainFallbackName.
  ///
  /// In en, this message translates to:
  /// **'Captain'**
  String get mapPageCaptainFallbackName;

  /// No description provided for @mapPageCaptainPlateLabel.
  ///
  /// In en, this message translates to:
  /// **'Plate: {plate}'**
  String mapPageCaptainPlateLabel(Object plate);

  /// No description provided for @mapPageRateTaxiRide.
  ///
  /// In en, this message translates to:
  /// **'Rate this taxi ride'**
  String get mapPageRateTaxiRide;

  /// No description provided for @mapPageNegotiationTitle.
  ///
  /// In en, this message translates to:
  /// **'Fare negotiation with the captain'**
  String get mapPageNegotiationTitle;

  /// No description provided for @mapPageNegotiationQueueLabel.
  ///
  /// In en, this message translates to:
  /// **'Queue: {count}'**
  String mapPageNegotiationQueueLabel(Object count);

  /// No description provided for @mapPageNegotiationCurrentOfferLabel.
  ///
  /// In en, this message translates to:
  /// **'Current offer: {amount}'**
  String mapPageNegotiationCurrentOfferLabel(Object amount);

  /// No description provided for @mapPageNegotiationEtaLabel.
  ///
  /// In en, this message translates to:
  /// **'Estimated arrival: {minutes} min'**
  String mapPageNegotiationEtaLabel(Object minutes);

  /// No description provided for @mapPageNegotiationRemainingTitle.
  ///
  /// In en, this message translates to:
  /// **'Time left for negotiation'**
  String get mapPageNegotiationRemainingTitle;

  /// No description provided for @mapPageNegotiationRoundsLeft.
  ///
  /// In en, this message translates to:
  /// **'Counter-offer rounds left: {count} of 6'**
  String mapPageNegotiationRoundsLeft(Object count);

  /// No description provided for @mapPageNegotiationRejectAndSearch.
  ///
  /// In en, this message translates to:
  /// **'Reject and find another captain'**
  String get mapPageNegotiationRejectAndSearch;

  /// No description provided for @mapPageNegotiationCounterOffer.
  ///
  /// In en, this message translates to:
  /// **'Counter offer'**
  String get mapPageNegotiationCounterOffer;

  /// No description provided for @mapPageNegotiationFirstOfferSummary.
  ///
  /// In en, this message translates to:
  /// **'First available offer: {captainName} - {amount}'**
  String mapPageNegotiationFirstOfferSummary(Object captainName, Object amount);

  /// No description provided for @mapPageNegotiationWaitingCaptains.
  ///
  /// In en, this message translates to:
  /// **'{count} captains are waiting in the negotiation queue.'**
  String mapPageNegotiationWaitingCaptains(Object count);

  /// No description provided for @mapPageCaptainTrackingActive.
  ///
  /// In en, this message translates to:
  /// **'The captain is being tracked live on the map.'**
  String get mapPageCaptainTrackingActive;

  /// No description provided for @mapPageChatWithCaptain.
  ///
  /// In en, this message translates to:
  /// **'Chat with the captain'**
  String get mapPageChatWithCaptain;

  /// No description provided for @mapPageRideCancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel the ride'**
  String get mapPageRideCancelAction;

  /// No description provided for @mapPageRideCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling...'**
  String get mapPageRideCancelling;

  /// No description provided for @mapPagePickupSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search for the pickup point'**
  String get mapPagePickupSearchLabel;

  /// No description provided for @mapPagePickupSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Type an area or street name'**
  String get mapPagePickupSearchHint;

  /// No description provided for @mapPageConfirmPickupLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm the pickup point'**
  String get mapPageConfirmPickupLabel;

  /// No description provided for @mapPagePickupConfirmedLabel.
  ///
  /// In en, this message translates to:
  /// **'Pickup point confirmed'**
  String get mapPagePickupConfirmedLabel;

  /// No description provided for @mapPageDropoffSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search for the dropoff point'**
  String get mapPageDropoffSearchLabel;

  /// No description provided for @mapPageDropoffSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Restaurant, hospital, street, or any place'**
  String get mapPageDropoffSearchHint;

  /// No description provided for @mapPagePickupDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Pickup point label'**
  String get mapPagePickupDescriptionLabel;

  /// No description provided for @mapPageDropoffDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Dropoff point label'**
  String get mapPageDropoffDescriptionLabel;

  /// No description provided for @mapPageCaptainNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note for the captain (optional)'**
  String get mapPageCaptainNoteLabel;

  /// No description provided for @mapPageTapMapForPickup.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to choose the pickup point'**
  String get mapPageTapMapForPickup;

  /// No description provided for @mapPageTapMapForDropoff.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to choose the dropoff point'**
  String get mapPageTapMapForDropoff;

  /// No description provided for @mapPageSwapPoints.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get mapPageSwapPoints;

  /// No description provided for @mapPageRouteSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Route summary'**
  String get mapPageRouteSummaryTitle;

  /// No description provided for @mapPageRouteReadyHint.
  ///
  /// In en, this message translates to:
  /// **'Pickup and destination are ready. Review the fare and send the request.'**
  String get mapPageRouteReadyHint;

  /// No description provided for @mapPageRouteFarePreviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Fare preview'**
  String get mapPageRouteFarePreviewLabel;

  /// No description provided for @mapPageRideRequestSubmit.
  ///
  /// In en, this message translates to:
  /// **'Send taxi request'**
  String get mapPageRideRequestSubmit;

  /// No description provided for @mapPageRideRequestSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Sending request...'**
  String get mapPageRideRequestSubmitting;

  /// No description provided for @merchantListSearchHintFor.
  ///
  /// In en, this message translates to:
  /// **'Search for {title}'**
  String merchantListSearchHintFor(Object title);

  /// No description provided for @merchantListSearchHintMarket.
  ///
  /// In en, this message translates to:
  /// **'Search for markets'**
  String get merchantListSearchHintMarket;

  /// No description provided for @merchantListSearchHintRestaurant.
  ///
  /// In en, this message translates to:
  /// **'Search for restaurants'**
  String get merchantListSearchHintRestaurant;

  /// No description provided for @merchantListSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Bismayah stores'**
  String get merchantListSectionTitle;

  /// No description provided for @merchantListSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{availableCount} stores available ? {openCount} open now'**
  String merchantListSectionSubtitle(Object availableCount, Object openCount);

  /// No description provided for @merchantListNoStores.
  ///
  /// In en, this message translates to:
  /// **'No stores are available right now'**
  String get merchantListNoStores;

  /// No description provided for @merchantListNoStoresSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The main list is still empty. Try again in a moment or refresh the page.'**
  String get merchantListNoStoresSubtitle;

  /// No description provided for @merchantListNoMatching.
  ///
  /// In en, this message translates to:
  /// **'No matching results were found'**
  String get merchantListNoMatching;

  /// No description provided for @merchantListTryChangingFilters.
  ///
  /// In en, this message translates to:
  /// **'Try changing the search query or clearing the active filters.'**
  String get merchantListTryChangingFilters;

  /// No description provided for @adminCompaniesPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to manage companies.'**
  String get adminCompaniesPermissionDenied;

  /// No description provided for @adminCompaniesCompanyNotFound.
  ///
  /// In en, this message translates to:
  /// **'The requested company was not found.'**
  String get adminCompaniesCompanyNotFound;

  /// No description provided for @adminCompaniesBranchRequestNotFound.
  ///
  /// In en, this message translates to:
  /// **'The requested branch request was not found.'**
  String get adminCompaniesBranchRequestNotFound;

  /// No description provided for @adminCompaniesBranchRequestAlreadyReviewed.
  ///
  /// In en, this message translates to:
  /// **'This request was already reviewed. Refresh the page to see its latest status.'**
  String get adminCompaniesBranchRequestAlreadyReviewed;

  /// No description provided for @adminCompaniesBranchOwnerPhoneRoleConflict.
  ///
  /// In en, this message translates to:
  /// **'The branch owner\'s phone belongs to an account with a different role and cannot be used for this request.'**
  String get adminCompaniesBranchOwnerPhoneRoleConflict;

  /// No description provided for @adminCompaniesOwnerAlreadyHasBranch.
  ///
  /// In en, this message translates to:
  /// **'This owner is already linked to another branch.'**
  String get adminCompaniesOwnerAlreadyHasBranch;

  /// No description provided for @adminCompaniesBranchNotFound.
  ///
  /// In en, this message translates to:
  /// **'The requested branch was not found.'**
  String get adminCompaniesBranchNotFound;

  /// No description provided for @adminCompaniesEditCompanyTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit company details'**
  String get adminCompaniesEditCompanyTitle;

  /// No description provided for @adminCompaniesCreateCompanyTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a new company'**
  String get adminCompaniesCreateCompanyTitle;

  /// No description provided for @adminCompaniesCompanyNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Company name'**
  String get adminCompaniesCompanyNameLabel;

  /// No description provided for @adminCompaniesCompanyCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Company code'**
  String get adminCompaniesCompanyCodeLabel;

  /// No description provided for @adminCompaniesCompanyCodeHelper.
  ///
  /// In en, this message translates to:
  /// **'Example: maslaki-hq'**
  String get adminCompaniesCompanyCodeHelper;

  /// No description provided for @adminCompaniesLegalNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Legal name'**
  String get adminCompaniesLegalNameLabel;

  /// No description provided for @adminCompaniesBrandNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Brand name'**
  String get adminCompaniesBrandNameLabel;

  /// No description provided for @adminCompaniesBusinessTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Business type'**
  String get adminCompaniesBusinessTypeLabel;

  /// No description provided for @adminCompaniesSummaryLabel.
  ///
  /// In en, this message translates to:
  /// **'Short summary'**
  String get adminCompaniesSummaryLabel;

  /// No description provided for @adminCompaniesPrimaryContactLabel.
  ///
  /// In en, this message translates to:
  /// **'Primary contact'**
  String get adminCompaniesPrimaryContactLabel;

  /// No description provided for @adminCompaniesSupportPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Support phone'**
  String get adminCompaniesSupportPhoneLabel;

  /// No description provided for @adminCompaniesWebsiteLabel.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get adminCompaniesWebsiteLabel;

  /// No description provided for @adminCompaniesHeadquartersAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Headquarters address'**
  String get adminCompaniesHeadquartersAddressLabel;

  /// No description provided for @adminCompaniesRegistrationNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Registration number'**
  String get adminCompaniesRegistrationNumberLabel;

  /// No description provided for @adminCompaniesTaxNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Tax number'**
  String get adminCompaniesTaxNumberLabel;

  /// No description provided for @adminCompaniesAdminNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Admin notes'**
  String get adminCompaniesAdminNotesLabel;

  /// No description provided for @adminCompaniesPrimaryOwnerSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Primary company owner'**
  String get adminCompaniesPrimaryOwnerSectionTitle;

  /// No description provided for @adminCompaniesOwnerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Owner name'**
  String get adminCompaniesOwnerNameLabel;

  /// No description provided for @adminCompaniesOwnerPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Owner phone number'**
  String get adminCompaniesOwnerPhoneLabel;

  /// No description provided for @adminCompaniesOwnerPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get adminCompaniesOwnerPinLabel;

  /// No description provided for @adminCompaniesValidPinRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid PIN.'**
  String get adminCompaniesValidPinRequired;

  /// No description provided for @adminCompaniesOwnerWorkTitle.
  ///
  /// In en, this message translates to:
  /// **'Company owner'**
  String get adminCompaniesOwnerWorkTitle;

  /// No description provided for @adminCompaniesUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the company right now.'**
  String get adminCompaniesUpdateFailed;

  /// No description provided for @adminCompaniesCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the company right now.'**
  String get adminCompaniesCreateFailed;

  /// No description provided for @adminCompaniesCodeExists.
  ///
  /// In en, this message translates to:
  /// **'This company code is already in use. Choose another one.'**
  String get adminCompaniesCodeExists;

  /// No description provided for @adminCompaniesOwnerPhoneRoleConflict.
  ///
  /// In en, this message translates to:
  /// **'The company owner\'s phone is linked to an account that is not intended for the company portal.'**
  String get adminCompaniesOwnerPhoneRoleConflict;

  /// No description provided for @adminCompaniesOwnerAccountRequired.
  ///
  /// In en, this message translates to:
  /// **'The owner account must be a valid company account.'**
  String get adminCompaniesOwnerAccountRequired;

  /// No description provided for @adminCompaniesSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get adminCompaniesSaveChanges;

  /// No description provided for @adminCompaniesCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create company'**
  String get adminCompaniesCreateAction;

  /// No description provided for @adminCompaniesDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete company'**
  String get adminCompaniesDeleteTitle;

  /// No description provided for @adminCompaniesDeleteDescription.
  ///
  /// In en, this message translates to:
  /// **'The company \"{companyName}\" will be deleted permanently and all linked branches will be detached. This action cannot be undone.'**
  String adminCompaniesDeleteDescription(Object companyName);

  /// No description provided for @adminCompaniesDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get adminCompaniesDeleteConfirm;

  /// No description provided for @adminCompaniesDeleted.
  ///
  /// In en, this message translates to:
  /// **'The company {companyName} was deleted.'**
  String adminCompaniesDeleted(Object companyName);

  /// No description provided for @adminCompaniesDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete the company right now.'**
  String get adminCompaniesDeleteFailed;

  /// No description provided for @adminCompaniesLinkBranchTitle.
  ///
  /// In en, this message translates to:
  /// **'Link a branch to {companyName}'**
  String adminCompaniesLinkBranchTitle(Object companyName);

  /// No description provided for @adminCompaniesBranchSelectorLabel.
  ///
  /// In en, this message translates to:
  /// **'Store / branch'**
  String get adminCompaniesBranchSelectorLabel;

  /// No description provided for @adminCompaniesDefaultMerchantName.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get adminCompaniesDefaultMerchantName;

  /// No description provided for @adminCompaniesLinkBranchFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to link this branch to the company right now.'**
  String get adminCompaniesLinkBranchFailed;

  /// No description provided for @adminCompaniesLinkBranchAction.
  ///
  /// In en, this message translates to:
  /// **'Link branch'**
  String get adminCompaniesLinkBranchAction;

  /// No description provided for @adminCompaniesApproveBranchRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve branch request'**
  String get adminCompaniesApproveBranchRequestTitle;

  /// No description provided for @adminCompaniesRejectBranchRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Reject branch request'**
  String get adminCompaniesRejectBranchRequestTitle;

  /// No description provided for @adminCompaniesReviewNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Review note'**
  String get adminCompaniesReviewNoteLabel;

  /// No description provided for @adminCompaniesApproveBranchRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to approve the branch request right now.'**
  String get adminCompaniesApproveBranchRequestFailed;

  /// No description provided for @adminCompaniesRejectBranchRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to reject the branch request right now.'**
  String get adminCompaniesRejectBranchRequestFailed;

  /// No description provided for @adminCompaniesScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Companies management'**
  String get adminCompaniesScreenTitle;

  /// No description provided for @adminCompaniesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load company management right now.'**
  String get adminCompaniesLoadFailed;

  /// No description provided for @adminCompaniesNoData.
  ///
  /// In en, this message translates to:
  /// **'No data is available right now.'**
  String get adminCompaniesNoData;

  /// No description provided for @adminCompaniesPortalTitle.
  ///
  /// In en, this message translates to:
  /// **'Company portal management'**
  String get adminCompaniesPortalTitle;

  /// No description provided for @adminCompaniesPortalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create companies, edit their data, delete them when needed, link existing branches, or review new branch requests.'**
  String get adminCompaniesPortalSubtitle;

  /// No description provided for @adminCompaniesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No companies have been registered yet.'**
  String get adminCompaniesEmpty;

  /// No description provided for @adminCompaniesBranchesMetric.
  ///
  /// In en, this message translates to:
  /// **'Branches'**
  String get adminCompaniesBranchesMetric;

  /// No description provided for @adminCompaniesUsersMetric.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get adminCompaniesUsersMetric;

  /// No description provided for @adminCompaniesActiveUsersMetric.
  ///
  /// In en, this message translates to:
  /// **'Active users'**
  String get adminCompaniesActiveUsersMetric;

  /// No description provided for @adminCompaniesPrimaryContactShort.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get adminCompaniesPrimaryContactShort;

  /// No description provided for @adminCompaniesWebsiteShort.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get adminCompaniesWebsiteShort;

  /// No description provided for @adminCompaniesHeadquartersShort.
  ///
  /// In en, this message translates to:
  /// **'Headquarters'**
  String get adminCompaniesHeadquartersShort;

  /// No description provided for @adminCompaniesAdminNotesShort.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get adminCompaniesAdminNotesShort;

  /// No description provided for @adminCompaniesEditInfoAction.
  ///
  /// In en, this message translates to:
  /// **'Edit details'**
  String get adminCompaniesEditInfoAction;

  /// No description provided for @adminCompaniesDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete company'**
  String get adminCompaniesDeleteAction;

  /// No description provided for @adminCompaniesPendingBranchRequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending branch requests'**
  String get adminCompaniesPendingBranchRequestsTitle;

  /// No description provided for @adminCompaniesPendingBranchRequestsEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no pending branch requests right now.'**
  String get adminCompaniesPendingBranchRequestsEmpty;

  /// No description provided for @adminCompaniesBranchRequestLocationLine.
  ///
  /// In en, this message translates to:
  /// **'{branchType} | {location}'**
  String adminCompaniesBranchRequestLocationLine(
    Object branchType,
    Object location,
  );

  /// No description provided for @adminCompaniesNoLocation.
  ///
  /// In en, this message translates to:
  /// **'No location'**
  String get adminCompaniesNoLocation;

  /// No description provided for @adminCompaniesSuggestedOwnerLine.
  ///
  /// In en, this message translates to:
  /// **'Suggested owner: {ownerName} - {ownerPhone}'**
  String adminCompaniesSuggestedOwnerLine(Object ownerName, Object ownerPhone);

  /// No description provided for @adminCompaniesNoPhone.
  ///
  /// In en, this message translates to:
  /// **'No phone'**
  String get adminCompaniesNoPhone;

  /// No description provided for @companyBranchDetailInventorySettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory settings'**
  String get companyBranchDetailInventorySettingsTitle;

  /// No description provided for @companyBranchDetailEnableInventoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable inventory for this branch'**
  String get companyBranchDetailEnableInventoryTitle;

  /// No description provided for @companyBranchDetailEnableInventorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'When enabled, availability becomes tied to tracked stock quantities.'**
  String get companyBranchDetailEnableInventorySubtitle;

  /// No description provided for @companyBranchDetailDailyModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Daily inventory update mode'**
  String get companyBranchDetailDailyModeLabel;

  /// No description provided for @companyBranchDetailLowStockThresholdLabel.
  ///
  /// In en, this message translates to:
  /// **'Low stock threshold'**
  String get companyBranchDetailLowStockThresholdLabel;

  /// No description provided for @companyBranchDetailAutoDisableOutOfStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-disable out-of-stock items'**
  String get companyBranchDetailAutoDisableOutOfStockTitle;

  /// No description provided for @companyBranchDetailShowAllWithoutDisableTitle.
  ///
  /// In en, this message translates to:
  /// **'Show all items without auto-disable'**
  String get companyBranchDetailShowAllWithoutDisableTitle;

  /// No description provided for @companyBranchDetailQuantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get companyBranchDetailQuantityLabel;

  /// No description provided for @companyBranchDetailReorderThresholdLabel.
  ///
  /// In en, this message translates to:
  /// **'Reorder threshold'**
  String get companyBranchDetailReorderThresholdLabel;

  /// No description provided for @companyBranchDetailManualDisableTitle.
  ///
  /// In en, this message translates to:
  /// **'Manual disable'**
  String get companyBranchDetailManualDisableTitle;

  /// No description provided for @companyBranchDetailConfirmDailyCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm today\'s stock check'**
  String get companyBranchDetailConfirmDailyCheckTitle;

  /// No description provided for @companyBranchDetailCheckNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Check note'**
  String get companyBranchDetailCheckNoteLabel;

  /// No description provided for @companyBranchDetailNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get companyBranchDetailNotAvailable;

  /// No description provided for @companyBranchDetailLoadFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unable to load branch details'**
  String get companyBranchDetailLoadFailedTitle;

  /// No description provided for @companyBranchDetailLoadFailedDescription.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the supervisory branch details right now.'**
  String get companyBranchDetailLoadFailedDescription;

  /// No description provided for @companyBranchDetailEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Branch not found'**
  String get companyBranchDetailEmptyTitle;

  /// No description provided for @companyBranchDetailEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'No supervisory data was found for this branch.'**
  String get companyBranchDetailEmptyDescription;

  /// No description provided for @companyBranchDetailHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This is the supervisory view for the branch. Day-to-day order operations still happen in the store app.'**
  String get companyBranchDetailHeaderSubtitle;

  /// No description provided for @companyBranchDetailInventoryEnabledChip.
  ///
  /// In en, this message translates to:
  /// **'Inventory enabled'**
  String get companyBranchDetailInventoryEnabledChip;

  /// No description provided for @companyBranchDetailManualAvailabilityChip.
  ///
  /// In en, this message translates to:
  /// **'Manual availability'**
  String get companyBranchDetailManualAvailabilityChip;

  /// No description provided for @companyBranchDetailOwnerLabel.
  ///
  /// In en, this message translates to:
  /// **'Branch owner'**
  String get companyBranchDetailOwnerLabel;

  /// No description provided for @companyBranchDetailLastInventoryUpdateLabel.
  ///
  /// In en, this message translates to:
  /// **'Last inventory update'**
  String get companyBranchDetailLastInventoryUpdateLabel;

  /// No description provided for @companyBranchDetailLastDailyCheckLabel.
  ///
  /// In en, this message translates to:
  /// **'Last daily check'**
  String get companyBranchDetailLastDailyCheckLabel;

  /// No description provided for @companyBranchDetailOutOfStockItemsLabel.
  ///
  /// In en, this message translates to:
  /// **'Out-of-stock items'**
  String get companyBranchDetailOutOfStockItemsLabel;

  /// No description provided for @companyBranchDetailInventoryPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory policy'**
  String get companyBranchDetailInventoryPolicyTitle;

  /// No description provided for @companyBranchDetailInventoryPolicySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review the live rules currently controlling stock behavior for this branch.'**
  String get companyBranchDetailInventoryPolicySubtitle;

  /// No description provided for @companyBranchDetailEditSettingsAction.
  ///
  /// In en, this message translates to:
  /// **'Edit settings'**
  String get companyBranchDetailEditSettingsAction;

  /// No description provided for @companyBranchDetailConfirmTodayAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm today\'s check'**
  String get companyBranchDetailConfirmTodayAction;

  /// No description provided for @companyBranchDetailInventoryDisabledChip.
  ///
  /// In en, this message translates to:
  /// **'Inventory disabled'**
  String get companyBranchDetailInventoryDisabledChip;

  /// No description provided for @companyBranchDetailModeChip.
  ///
  /// In en, this message translates to:
  /// **'Mode: {mode}'**
  String companyBranchDetailModeChip(Object mode);

  /// No description provided for @companyBranchDetailThresholdChip.
  ///
  /// In en, this message translates to:
  /// **'Threshold: {count}'**
  String companyBranchDetailThresholdChip(Object count);

  /// No description provided for @companyBranchDetailShowAllChip.
  ///
  /// In en, this message translates to:
  /// **'Show all enabled'**
  String get companyBranchDetailShowAllChip;

  /// No description provided for @companyBranchDetailAutoDisableChip.
  ///
  /// In en, this message translates to:
  /// **'Auto-disable enabled'**
  String get companyBranchDetailAutoDisableChip;

  /// No description provided for @companyBranchDetailInventoryItemsTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory items'**
  String get companyBranchDetailInventoryItemsTitle;

  /// No description provided for @companyBranchDetailInventoryItemsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{inventoryCount} inventory items • {productCount} products • {categoryCount} categories.'**
  String companyBranchDetailInventoryItemsSubtitle(
    Object inventoryCount,
    Object productCount,
    Object categoryCount,
  );

  /// No description provided for @companyBranchDetailInventoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No inventory items yet'**
  String get companyBranchDetailInventoryEmptyTitle;

  /// No description provided for @companyBranchDetailInventoryEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Enable inventory and start syncing branch quantities to track items here.'**
  String get companyBranchDetailInventoryEmptyDescription;

  /// No description provided for @companyBranchDetailQuantityChip.
  ///
  /// In en, this message translates to:
  /// **'Quantity {quantity}'**
  String companyBranchDetailQuantityChip(Object quantity);

  /// No description provided for @companyBranchDetailAvailableForOrder.
  ///
  /// In en, this message translates to:
  /// **'Available for ordering'**
  String get companyBranchDetailAvailableForOrder;

  /// No description provided for @companyBranchDetailUnavailableForOrder.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get companyBranchDetailUnavailableForOrder;

  /// No description provided for @socialRestrictionsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load your active social restrictions.'**
  String get socialRestrictionsLoadFailed;

  /// No description provided for @socialRestrictionsCapabilityStory.
  ///
  /// In en, this message translates to:
  /// **'Story publishing'**
  String get socialRestrictionsCapabilityStory;

  /// No description provided for @socialRestrictionsCapabilityReel.
  ///
  /// In en, this message translates to:
  /// **'Reels and video publishing'**
  String get socialRestrictionsCapabilityReel;

  /// No description provided for @socialRestrictionsCapabilityComments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get socialRestrictionsCapabilityComments;

  /// No description provided for @socialRestrictionsCapabilityCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community posting'**
  String get socialRestrictionsCapabilityCommunity;

  /// No description provided for @socialRestrictionsCapabilityRegular.
  ///
  /// In en, this message translates to:
  /// **'Regular posting'**
  String get socialRestrictionsCapabilityRegular;

  /// No description provided for @socialRestrictionsLatestNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Latest restriction notice'**
  String get socialRestrictionsLatestNoticeTitle;

  /// No description provided for @socialRestrictionsCapabilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Capability'**
  String get socialRestrictionsCapabilityLabel;

  /// No description provided for @socialRestrictionsReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get socialRestrictionsReasonLabel;

  /// No description provided for @socialRestrictionsStartLabel.
  ///
  /// In en, this message translates to:
  /// **'Restriction start'**
  String get socialRestrictionsStartLabel;

  /// No description provided for @socialRestrictionsEndsAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Ends at'**
  String get socialRestrictionsEndsAtLabel;

  /// No description provided for @socialRestrictionsUntilFurtherNotice.
  ///
  /// In en, this message translates to:
  /// **'Until further notice'**
  String get socialRestrictionsUntilFurtherNotice;

  /// No description provided for @socialRestrictionsActiveChip.
  ///
  /// In en, this message translates to:
  /// **'Active restriction'**
  String get socialRestrictionsActiveChip;

  /// No description provided for @socialRestrictionsNoAdditionalNote.
  ///
  /// In en, this message translates to:
  /// **'No additional note provided.'**
  String get socialRestrictionsNoAdditionalNote;

  /// No description provided for @socialRestrictionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Social restrictions'**
  String get socialRestrictionsTitle;

  /// No description provided for @socialRestrictionsIntro.
  ///
  /// In en, this message translates to:
  /// **'This screen shows the active social restrictions currently applied to your account. Each restriction explains which activity is temporarily limited, such as posting, stories, or comments.'**
  String get socialRestrictionsIntro;

  /// No description provided for @socialRestrictionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no active social restrictions on your account right now.'**
  String get socialRestrictionsEmpty;

  /// No description provided for @socialResidenceChangeLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load residence change request.'**
  String get socialResidenceChangeLoadFailed;

  /// No description provided for @socialResidenceChangeImageOnly.
  ///
  /// In en, this message translates to:
  /// **'Choose an image document only.'**
  String get socialResidenceChangeImageOnly;

  /// No description provided for @socialResidenceChangeSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Residence change request submitted.'**
  String get socialResidenceChangeSubmitted;

  /// No description provided for @socialResidenceChangeSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit the request.'**
  String get socialResidenceChangeSubmitFailed;

  /// No description provided for @socialResidenceChangeCancelled.
  ///
  /// In en, this message translates to:
  /// **'Pending request cancelled.'**
  String get socialResidenceChangeCancelled;

  /// No description provided for @socialResidenceChangeCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to cancel the request.'**
  String get socialResidenceChangeCancelFailed;

  /// No description provided for @socialResidenceChangeBlockLabel.
  ///
  /// In en, this message translates to:
  /// **'Sector'**
  String get socialResidenceChangeBlockLabel;

  /// No description provided for @socialResidenceChangeBuildingLabel.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get socialResidenceChangeBuildingLabel;

  /// No description provided for @socialResidenceChangeApartmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Apartment'**
  String get socialResidenceChangeApartmentLabel;

  /// No description provided for @socialResidenceChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Residence change request'**
  String get socialResidenceChangeTitle;

  /// No description provided for @socialResidenceChangeCurrentResidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Current residence'**
  String get socialResidenceChangeCurrentResidenceTitle;

  /// No description provided for @socialResidenceChangePendingRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending request'**
  String get socialResidenceChangePendingRequestTitle;

  /// No description provided for @socialResidenceChangeLastReviewedTitle.
  ///
  /// In en, this message translates to:
  /// **'Last reviewed request'**
  String get socialResidenceChangeLastReviewedTitle;

  /// No description provided for @socialResidenceChangeStatusLine.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String socialResidenceChangeStatusLine(Object status);

  /// No description provided for @socialResidenceChangeReviewNoteLine.
  ///
  /// In en, this message translates to:
  /// **'Review note: {note}'**
  String socialResidenceChangeReviewNoteLine(Object note);

  /// No description provided for @socialResidenceChangeCancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get socialResidenceChangeCancelRequest;

  /// No description provided for @socialResidenceChangeNewRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Submit a new request'**
  String get socialResidenceChangeNewRequestTitle;

  /// No description provided for @socialResidenceChangeAdditionalNote.
  ///
  /// In en, this message translates to:
  /// **'Additional note'**
  String get socialResidenceChangeAdditionalNote;

  /// No description provided for @socialResidenceChangeAttachDocument.
  ///
  /// In en, this message translates to:
  /// **'Attach residence document (optional)'**
  String get socialResidenceChangeAttachDocument;

  /// No description provided for @socialResidenceChangeSubmitAction.
  ///
  /// In en, this message translates to:
  /// **'Submit request'**
  String get socialResidenceChangeSubmitAction;

  /// No description provided for @socialResidenceChangePendingLockMessage.
  ///
  /// In en, this message translates to:
  /// **'You cannot submit a new request while one is pending.'**
  String get socialResidenceChangePendingLockMessage;

  /// No description provided for @socialUserSearchLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to search users.'**
  String get socialUserSearchLoadFailed;

  /// No description provided for @socialUserSearchRelationBlockedByMe.
  ///
  /// In en, this message translates to:
  /// **'You blocked this account'**
  String get socialUserSearchRelationBlockedByMe;

  /// No description provided for @socialUserSearchRelationBlockedByOther.
  ///
  /// In en, this message translates to:
  /// **'This account blocked you'**
  String get socialUserSearchRelationBlockedByOther;

  /// No description provided for @socialUserSearchRelationAccepted.
  ///
  /// In en, this message translates to:
  /// **'Friend and followed'**
  String get socialUserSearchRelationAccepted;

  /// No description provided for @socialUserSearchRelationPendingOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Your request is pending'**
  String get socialUserSearchRelationPendingOutgoing;

  /// No description provided for @socialUserSearchRelationPendingIncoming.
  ///
  /// In en, this message translates to:
  /// **'Sent you a friend or follow request'**
  String get socialUserSearchRelationPendingIncoming;

  /// No description provided for @socialUserSearchRelationOpenProfile.
  ///
  /// In en, this message translates to:
  /// **'Open profile'**
  String get socialUserSearchRelationOpenProfile;

  /// No description provided for @socialUserSearchActionBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get socialUserSearchActionBlocked;

  /// No description provided for @socialUserSearchActionFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get socialUserSearchActionFollowing;

  /// No description provided for @socialUserSearchActionCancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get socialUserSearchActionCancelRequest;

  /// No description provided for @socialUserSearchActionAcceptFollow.
  ///
  /// In en, this message translates to:
  /// **'Accept follow'**
  String get socialUserSearchActionAcceptFollow;

  /// No description provided for @socialUserSearchActionFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get socialUserSearchActionFollow;

  /// No description provided for @socialUserSearchActionFriend.
  ///
  /// In en, this message translates to:
  /// **'Friend'**
  String get socialUserSearchActionFriend;

  /// No description provided for @socialUserSearchActionAcceptFriend.
  ///
  /// In en, this message translates to:
  /// **'Accept friend'**
  String get socialUserSearchActionAcceptFriend;

  /// No description provided for @socialUserSearchActionAddFriend.
  ///
  /// In en, this message translates to:
  /// **'Add friend'**
  String get socialUserSearchActionAddFriend;

  /// No description provided for @socialUserSearchBlockedByOtherActionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This action is not available because this account blocked you.'**
  String get socialUserSearchBlockedByOtherActionUnavailable;

  /// No description provided for @socialUserSearchUnblockFirst.
  ///
  /// In en, this message translates to:
  /// **'Unblock this profile first before sending a request.'**
  String get socialUserSearchUnblockFirst;

  /// No description provided for @socialUserSearchFriendRequestAccepted.
  ///
  /// In en, this message translates to:
  /// **'Friend request accepted.'**
  String get socialUserSearchFriendRequestAccepted;

  /// No description provided for @socialUserSearchFollowRequestAccepted.
  ///
  /// In en, this message translates to:
  /// **'Follow request accepted.'**
  String get socialUserSearchFollowRequestAccepted;

  /// No description provided for @socialUserSearchRequestCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled.'**
  String get socialUserSearchRequestCancelled;

  /// No description provided for @socialUserSearchFriendRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent.'**
  String get socialUserSearchFriendRequestSent;

  /// No description provided for @socialUserSearchFollowRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Follow request sent.'**
  String get socialUserSearchFollowRequestSent;

  /// No description provided for @socialUserSearchActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to complete the action right now.'**
  String get socialUserSearchActionFailed;

  /// No description provided for @socialUserSearchOpenChatFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the chat now.'**
  String get socialUserSearchOpenChatFailed;

  /// No description provided for @socialUserSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Find users'**
  String get socialUserSearchTitle;

  /// No description provided for @socialUserSearchFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Search by name or phone'**
  String get socialUserSearchFieldLabel;

  /// No description provided for @socialUserSearchIncomingRequests.
  ///
  /// In en, this message translates to:
  /// **'Incoming requests ({count})'**
  String socialUserSearchIncomingRequests(Object count);

  /// No description provided for @socialUserSearchNoIncomingRequests.
  ///
  /// In en, this message translates to:
  /// **'No incoming requests right now.'**
  String get socialUserSearchNoIncomingRequests;

  /// No description provided for @socialUserSearchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Type a name or phone number to search.'**
  String get socialUserSearchPrompt;

  /// No description provided for @socialUserSearchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching results found.'**
  String get socialUserSearchNoResults;

  /// No description provided for @socialUserSearchMessageAction.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get socialUserSearchMessageAction;

  /// No description provided for @adminMaintenanceStatusHealthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get adminMaintenanceStatusHealthy;

  /// No description provided for @adminMaintenanceStatusWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get adminMaintenanceStatusWarning;

  /// No description provided for @adminMaintenanceStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get adminMaintenanceStatusFailed;

  /// No description provided for @adminMaintenanceProbeFailed.
  ///
  /// In en, this message translates to:
  /// **'Probe failed: {message}'**
  String adminMaintenanceProbeFailed(Object message);

  /// No description provided for @adminMaintenanceRetryHint.
  ///
  /// In en, this message translates to:
  /// **'Retry the diagnostics after verifying connectivity and session state.'**
  String get adminMaintenanceRetryHint;

  /// No description provided for @adminMaintenanceServerConnectivity.
  ///
  /// In en, this message translates to:
  /// **'Server connectivity'**
  String get adminMaintenanceServerConnectivity;

  /// No description provided for @adminMaintenanceServerReachable.
  ///
  /// In en, this message translates to:
  /// **'Server reachable. HTTP {code} - DB: {db}'**
  String adminMaintenanceServerReachable(Object code, Object db);

  /// No description provided for @adminMaintenanceServerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Server unreachable. HTTP {code}'**
  String adminMaintenanceServerUnreachable(Object code);

  /// No description provided for @adminMaintenanceServerFixHint.
  ///
  /// In en, this message translates to:
  /// **'Check environment variables and Railway connectivity.'**
  String get adminMaintenanceServerFixHint;

  /// No description provided for @adminMaintenanceAdminSession.
  ///
  /// In en, this message translates to:
  /// **'Admin session'**
  String get adminMaintenanceAdminSession;

  /// No description provided for @adminMaintenanceSessionValid.
  ///
  /// In en, this message translates to:
  /// **'Session is valid and admin privileges are active.'**
  String get adminMaintenanceSessionValid;

  /// No description provided for @adminMaintenanceSessionInvalid.
  ///
  /// In en, this message translates to:
  /// **'Session is incomplete or role privileges mismatch.'**
  String get adminMaintenanceSessionInvalid;

  /// No description provided for @adminMaintenanceSessionFixHint.
  ///
  /// In en, this message translates to:
  /// **'Logout and login again.'**
  String get adminMaintenanceSessionFixHint;

  /// No description provided for @adminMaintenanceAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Admin analytics'**
  String get adminMaintenanceAnalytics;

  /// No description provided for @adminMaintenanceAnalyticsLoaded.
  ///
  /// In en, this message translates to:
  /// **'Analytics loaded successfully.'**
  String get adminMaintenanceAnalyticsLoaded;

  /// No description provided for @adminMaintenanceAnalyticsPartial.
  ///
  /// In en, this message translates to:
  /// **'API responded but analytics payload is partial.'**
  String get adminMaintenanceAnalyticsPartial;

  /// No description provided for @adminMaintenanceAnalyticsFixHint.
  ///
  /// In en, this message translates to:
  /// **'Refresh admin data.'**
  String get adminMaintenanceAnalyticsFixHint;

  /// No description provided for @adminMaintenanceApprovalInbox.
  ///
  /// In en, this message translates to:
  /// **'Approval inbox'**
  String get adminMaintenanceApprovalInbox;

  /// No description provided for @adminMaintenanceApprovalInboxLoaded.
  ///
  /// In en, this message translates to:
  /// **'Approval inbox loaded. Current items: {count}'**
  String adminMaintenanceApprovalInboxLoaded(Object count);

  /// No description provided for @adminMaintenanceAuditFeed.
  ///
  /// In en, this message translates to:
  /// **'Audit feed'**
  String get adminMaintenanceAuditFeed;

  /// No description provided for @adminMaintenanceAuditFeedLoaded.
  ///
  /// In en, this message translates to:
  /// **'Audit feed loaded. Events: {count}'**
  String adminMaintenanceAuditFeedLoaded(Object count);

  /// No description provided for @adminMaintenanceLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to run diagnostics. Try again.'**
  String get adminMaintenanceLoadFailed;

  /// No description provided for @adminMaintenanceQuickFixDone.
  ///
  /// In en, this message translates to:
  /// **'Fix completed and diagnostics rerun.'**
  String get adminMaintenanceQuickFixDone;

  /// No description provided for @adminMaintenanceQuickFixFailed.
  ///
  /// In en, this message translates to:
  /// **'Fix action failed.'**
  String get adminMaintenanceQuickFixFailed;

  /// No description provided for @adminMaintenanceScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'System maintenance'**
  String get adminMaintenanceScreenTitle;

  /// No description provided for @adminMaintenanceRunDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Run diagnostics'**
  String get adminMaintenanceRunDiagnostics;

  /// No description provided for @adminMaintenanceHealthSummary.
  ///
  /// In en, this message translates to:
  /// **'Health summary'**
  String get adminMaintenanceHealthSummary;

  /// No description provided for @adminMaintenanceHealthyCount.
  ///
  /// In en, this message translates to:
  /// **'Healthy: {count}'**
  String adminMaintenanceHealthyCount(Object count);

  /// No description provided for @adminMaintenanceWarningCount.
  ///
  /// In en, this message translates to:
  /// **'Warning: {count}'**
  String adminMaintenanceWarningCount(Object count);

  /// No description provided for @adminMaintenanceFailedCount.
  ///
  /// In en, this message translates to:
  /// **'Failed: {count}'**
  String adminMaintenanceFailedCount(Object count);

  /// No description provided for @adminMaintenanceProbeTime.
  ///
  /// In en, this message translates to:
  /// **'Probe time: {elapsedMs}ms'**
  String adminMaintenanceProbeTime(Object elapsedMs);

  /// No description provided for @adminMaintenanceQuickFixAction.
  ///
  /// In en, this message translates to:
  /// **'Quick fix'**
  String get adminMaintenanceQuickFixAction;

  /// No description provided for @adminSocialReportsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load social reports right now.'**
  String get adminSocialReportsLoadFailed;

  /// No description provided for @adminSocialReportsPostActionApplied.
  ///
  /// In en, this message translates to:
  /// **'Post action applied.'**
  String get adminSocialReportsPostActionApplied;

  /// No description provided for @adminSocialReportsPostActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply post action.'**
  String get adminSocialReportsPostActionFailed;

  /// No description provided for @adminSocialReportsEditedPostApproved.
  ///
  /// In en, this message translates to:
  /// **'Edited post approved and republished.'**
  String get adminSocialReportsEditedPostApproved;

  /// No description provided for @adminSocialReportsEditedPostApproveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to approve the edited post.'**
  String get adminSocialReportsEditedPostApproveFailed;

  /// No description provided for @adminSocialReportsStoryActionApplied.
  ///
  /// In en, this message translates to:
  /// **'Story action applied.'**
  String get adminSocialReportsStoryActionApplied;

  /// No description provided for @adminSocialReportsStoryActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply story action.'**
  String get adminSocialReportsStoryActionFailed;

  /// No description provided for @adminSocialReportsEditedStoryApproved.
  ///
  /// In en, this message translates to:
  /// **'Edited story approved and republished.'**
  String get adminSocialReportsEditedStoryApproved;

  /// No description provided for @adminSocialReportsEditedStoryApproveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to approve the edited story.'**
  String get adminSocialReportsEditedStoryApproveFailed;

  /// No description provided for @adminSocialReportsFilterLabel.
  ///
  /// In en, this message translates to:
  /// **'Moderation filter:'**
  String get adminSocialReportsFilterLabel;

  /// No description provided for @adminSocialReportsPendingEdit.
  ///
  /// In en, this message translates to:
  /// **'Pending edit'**
  String get adminSocialReportsPendingEdit;

  /// No description provided for @adminSocialReportsReportsCount.
  ///
  /// In en, this message translates to:
  /// **'Reports: {count}'**
  String adminSocialReportsReportsCount(Object count);

  /// No description provided for @adminSocialReportsRecentReports.
  ///
  /// In en, this message translates to:
  /// **'Recent reports'**
  String get adminSocialReportsRecentReports;

  /// No description provided for @adminSocialReportsSourceSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get adminSocialReportsSourceSystem;

  /// No description provided for @adminSocialReportsSourceUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get adminSocialReportsSourceUser;

  /// No description provided for @adminSocialReportsReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Read only: moderation actions are available to super admin.'**
  String get adminSocialReportsReadOnly;

  /// No description provided for @adminSocialReportsApproveEdit.
  ///
  /// In en, this message translates to:
  /// **'Approve edit'**
  String get adminSocialReportsApproveEdit;

  /// No description provided for @adminSocialReportsKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get adminSocialReportsKeep;

  /// No description provided for @adminSocialReportsRequestEdit.
  ///
  /// In en, this message translates to:
  /// **'Request edit'**
  String get adminSocialReportsRequestEdit;

  /// No description provided for @adminSocialReportsDeleteWithPenalty.
  ///
  /// In en, this message translates to:
  /// **'Delete + penalty'**
  String get adminSocialReportsDeleteWithPenalty;

  /// No description provided for @adminSocialReportsNoText.
  ///
  /// In en, this message translates to:
  /// **'(No text)'**
  String get adminSocialReportsNoText;

  /// No description provided for @adminSocialReportsRequestPostEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Request post edit'**
  String get adminSocialReportsRequestPostEditTitle;

  /// No description provided for @adminSocialReportsRequestPostEditHint.
  ///
  /// In en, this message translates to:
  /// **'Write the required post edits...'**
  String get adminSocialReportsRequestPostEditHint;

  /// No description provided for @adminSocialReportsRequestEditDefaultNote.
  ///
  /// In en, this message translates to:
  /// **'Please update the content so it complies with community guidelines.'**
  String get adminSocialReportsRequestEditDefaultNote;

  /// No description provided for @adminSocialReportsDeletePostTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete post and apply penalty'**
  String get adminSocialReportsDeletePostTitle;

  /// No description provided for @adminSocialReportsDeletePostHint.
  ///
  /// In en, this message translates to:
  /// **'Write the delete reason or penalty note...'**
  String get adminSocialReportsDeletePostHint;

  /// No description provided for @adminSocialReportsStoryVideoAttachment.
  ///
  /// In en, this message translates to:
  /// **'Story contains a video attachment'**
  String get adminSocialReportsStoryVideoAttachment;

  /// No description provided for @adminSocialReportsStoryImageAttachment.
  ///
  /// In en, this message translates to:
  /// **'Story contains an image attachment'**
  String get adminSocialReportsStoryImageAttachment;

  /// No description provided for @adminSocialReportsRequestStoryEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Request story edit'**
  String get adminSocialReportsRequestStoryEditTitle;

  /// No description provided for @adminSocialReportsRequestStoryEditHint.
  ///
  /// In en, this message translates to:
  /// **'Write the required story edits...'**
  String get adminSocialReportsRequestStoryEditHint;

  /// No description provided for @adminSocialReportsDeleteStoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete story and apply penalty'**
  String get adminSocialReportsDeleteStoryTitle;

  /// No description provided for @adminSocialReportsDeleteStoryHint.
  ///
  /// In en, this message translates to:
  /// **'Write the delete reason or penalty note...'**
  String get adminSocialReportsDeleteStoryHint;

  /// No description provided for @adminSocialReportsReporterLabel.
  ///
  /// In en, this message translates to:
  /// **'Reporter:'**
  String get adminSocialReportsReporterLabel;

  /// No description provided for @adminSocialReportsManageRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Manage restrictions'**
  String get adminSocialReportsManageRestrictions;

  /// No description provided for @adminSocialReportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Social moderation'**
  String get adminSocialReportsTitle;

  /// No description provided for @adminSocialReportsPostsTab.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get adminSocialReportsPostsTab;

  /// No description provided for @adminSocialReportsStoriesTab.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get adminSocialReportsStoriesTab;

  /// No description provided for @adminSocialReportsUsersTab.
  ///
  /// In en, this message translates to:
  /// **'User reports'**
  String get adminSocialReportsUsersTab;

  /// No description provided for @adminSocialReportsNoPostReports.
  ///
  /// In en, this message translates to:
  /// **'No post reports right now.'**
  String get adminSocialReportsNoPostReports;

  /// No description provided for @adminSocialReportsNoStoryReports.
  ///
  /// In en, this message translates to:
  /// **'No story reports right now.'**
  String get adminSocialReportsNoStoryReports;

  /// No description provided for @adminSocialReportsNoUserReports.
  ///
  /// In en, this message translates to:
  /// **'No user reports right now.'**
  String get adminSocialReportsNoUserReports;

  /// No description provided for @socialCommunityChatMonitorLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load the community chat.'**
  String get socialCommunityChatMonitorLoadFailed;

  /// No description provided for @socialCommunityChatMonitorSystemMessage.
  ///
  /// In en, this message translates to:
  /// **'System message'**
  String get socialCommunityChatMonitorSystemMessage;

  /// No description provided for @socialCommunityChatMonitorDeletedMessage.
  ///
  /// In en, this message translates to:
  /// **'This message was deleted'**
  String get socialCommunityChatMonitorDeletedMessage;

  /// No description provided for @socialCommunityChatMonitorEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Message without text'**
  String get socialCommunityChatMonitorEmptyBody;

  /// No description provided for @socialCommunityChatMonitorSystemChip.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get socialCommunityChatMonitorSystemChip;

  /// No description provided for @socialCommunityChatMonitorTitle.
  ///
  /// In en, this message translates to:
  /// **'Community chat'**
  String get socialCommunityChatMonitorTitle;

  /// No description provided for @socialCommunityChatMonitorHeaderTitle.
  ///
  /// In en, this message translates to:
  /// **'Administrative community chat view'**
  String get socialCommunityChatMonitorHeaderTitle;

  /// No description provided for @socialCommunityChatMonitorHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This view is read-only and shows community messages inside the admin monitoring flow.'**
  String get socialCommunityChatMonitorHeaderSubtitle;

  /// No description provided for @socialCommunityChatMonitorEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages in this chat yet.'**
  String get socialCommunityChatMonitorEmpty;

  /// No description provided for @socialCommunityChatMonitorLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get socialCommunityChatMonitorLoadMore;

  /// No description provided for @socialChatQualityMonitorLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load monitored chats.'**
  String get socialChatQualityMonitorLoadFailed;

  /// No description provided for @socialChatQualityMonitorTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat monitoring'**
  String get socialChatQualityMonitorTitle;

  /// No description provided for @socialChatQualityMonitorSuperAdminOnly.
  ///
  /// In en, this message translates to:
  /// **'This page is available to super admins only.'**
  String get socialChatQualityMonitorSuperAdminOnly;

  /// No description provided for @socialChatQualityMonitorSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, phone, or message content'**
  String get socialChatQualityMonitorSearchHint;

  /// No description provided for @socialChatQualityMonitorDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get socialChatQualityMonitorDirect;

  /// No description provided for @socialChatQualityMonitorSummary.
  ///
  /// In en, this message translates to:
  /// **'This view shows direct and community chats in one admin monitor for review when needed.'**
  String get socialChatQualityMonitorSummary;

  /// No description provided for @socialChatQualityMonitorEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matching chats were found.'**
  String get socialChatQualityMonitorEmpty;

  /// No description provided for @socialChatQualityMonitorNoMessageYet.
  ///
  /// In en, this message translates to:
  /// **'No message yet'**
  String get socialChatQualityMonitorNoMessageYet;

  /// No description provided for @socialChatQualityMonitorCommunityDetails.
  ///
  /// In en, this message translates to:
  /// **'Monitored community chat'**
  String get socialChatQualityMonitorCommunityDetails;

  /// No description provided for @socialChatQualityMonitorNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No activity'**
  String get socialChatQualityMonitorNoActivity;

  /// No description provided for @adminPaidUpgradeRequestsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load paid upgrade requests.'**
  String get adminPaidUpgradeRequestsLoadFailed;

  /// No description provided for @adminPaidUpgradeRequestsOptionalNote.
  ///
  /// In en, this message translates to:
  /// **'Optional note'**
  String get adminPaidUpgradeRequestsOptionalNote;

  /// No description provided for @adminPaidUpgradeRequestsApproveTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve request'**
  String get adminPaidUpgradeRequestsApproveTitle;

  /// No description provided for @adminPaidUpgradeRequestsRejectTitle.
  ///
  /// In en, this message translates to:
  /// **'Reject request'**
  String get adminPaidUpgradeRequestsRejectTitle;

  /// No description provided for @adminPaidUpgradeRequestsApproveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to approve request.'**
  String get adminPaidUpgradeRequestsApproveFailed;

  /// No description provided for @adminPaidUpgradeRequestsRejectFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to reject request.'**
  String get adminPaidUpgradeRequestsRejectFailed;

  /// No description provided for @adminPaidUpgradeRequestsActivateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to activate subscription.'**
  String get adminPaidUpgradeRequestsActivateFailed;

  /// No description provided for @adminPaidUpgradeRequestsStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get adminPaidUpgradeRequestsStatusApproved;

  /// No description provided for @adminPaidUpgradeRequestsStatusActivated.
  ///
  /// In en, this message translates to:
  /// **'Activated'**
  String get adminPaidUpgradeRequestsStatusActivated;

  /// No description provided for @adminPaidUpgradeRequestsStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get adminPaidUpgradeRequestsStatusRejected;

  /// No description provided for @adminPaidUpgradeRequestsStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get adminPaidUpgradeRequestsStatusCancelled;

  /// No description provided for @adminPaidUpgradeRequestsStatusPendingReview.
  ///
  /// In en, this message translates to:
  /// **'Pending review'**
  String get adminPaidUpgradeRequestsStatusPendingReview;

  /// No description provided for @adminPaidUpgradeRequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Paid upgrade requests'**
  String get adminPaidUpgradeRequestsTitle;

  /// No description provided for @adminPaidUpgradeRequestsFilterPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get adminPaidUpgradeRequestsFilterPending;

  /// No description provided for @adminPaidUpgradeRequestsFilterApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get adminPaidUpgradeRequestsFilterApproved;

  /// No description provided for @adminPaidUpgradeRequestsFilterActivated.
  ///
  /// In en, this message translates to:
  /// **'Activated'**
  String get adminPaidUpgradeRequestsFilterActivated;

  /// No description provided for @adminPaidUpgradeRequestsFilterRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get adminPaidUpgradeRequestsFilterRejected;

  /// No description provided for @adminPaidUpgradeRequestsFilterCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get adminPaidUpgradeRequestsFilterCancelled;

  /// No description provided for @adminPaidUpgradeRequestsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No requests for this filter.'**
  String get adminPaidUpgradeRequestsEmpty;

  /// No description provided for @adminPaidUpgradeRequestsUserLine.
  ///
  /// In en, this message translates to:
  /// **'User: {name} (#{userId})'**
  String adminPaidUpgradeRequestsUserLine(Object name, Object userId);

  /// No description provided for @adminPaidUpgradeRequestsPhoneLine.
  ///
  /// In en, this message translates to:
  /// **'Phone: {phone}'**
  String adminPaidUpgradeRequestsPhoneLine(Object phone);

  /// No description provided for @adminPaidUpgradeRequestsActivityLine.
  ///
  /// In en, this message translates to:
  /// **'Activity: {activity}'**
  String adminPaidUpgradeRequestsActivityLine(Object activity);

  /// No description provided for @adminPaidUpgradeRequestsDescriptionLine.
  ///
  /// In en, this message translates to:
  /// **'Description: {description}'**
  String adminPaidUpgradeRequestsDescriptionLine(Object description);

  /// No description provided for @adminPaidUpgradeRequestsFeeLine.
  ///
  /// In en, this message translates to:
  /// **'Fee: {fee}'**
  String adminPaidUpgradeRequestsFeeLine(Object fee);

  /// No description provided for @adminPaidUpgradeRequestsNotesLine.
  ///
  /// In en, this message translates to:
  /// **'Notes: {notes}'**
  String adminPaidUpgradeRequestsNotesLine(Object notes);

  /// No description provided for @adminPaidUpgradeRequestsReviewNoteLine.
  ///
  /// In en, this message translates to:
  /// **'Review note: {note}'**
  String adminPaidUpgradeRequestsReviewNoteLine(Object note);

  /// No description provided for @adminPaidUpgradeRequestsRejectAction.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get adminPaidUpgradeRequestsRejectAction;

  /// No description provided for @adminPaidUpgradeRequestsApproveAction.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get adminPaidUpgradeRequestsApproveAction;

  /// No description provided for @adminPaidUpgradeRequestsActivateThirtyDays.
  ///
  /// In en, this message translates to:
  /// **'Activate 30 days'**
  String get adminPaidUpgradeRequestsActivateThirtyDays;

  /// No description provided for @socialCreatePostMerchantTypeRestaurant.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get socialCreatePostMerchantTypeRestaurant;

  /// No description provided for @socialCreatePostMerchantTypeDesserts.
  ///
  /// In en, this message translates to:
  /// **'Desserts'**
  String get socialCreatePostMerchantTypeDesserts;

  /// No description provided for @socialCreatePostMerchantTypeCoffee.
  ///
  /// In en, this message translates to:
  /// **'Coffee and drinks'**
  String get socialCreatePostMerchantTypeCoffee;

  /// No description provided for @socialCreatePostMerchantTypeElectronics.
  ///
  /// In en, this message translates to:
  /// **'Electronics'**
  String get socialCreatePostMerchantTypeElectronics;

  /// No description provided for @socialCreatePostMerchantTypePharmacy.
  ///
  /// In en, this message translates to:
  /// **'Pharmacy'**
  String get socialCreatePostMerchantTypePharmacy;

  /// No description provided for @socialCreatePostMerchantTypeMarket.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get socialCreatePostMerchantTypeMarket;

  /// No description provided for @socialCreatePostMerchantTypeStore.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get socialCreatePostMerchantTypeStore;

  /// No description provided for @socialCreatePostErrorTextRequired.
  ///
  /// In en, this message translates to:
  /// **'Write the post text first.'**
  String get socialCreatePostErrorTextRequired;

  /// No description provided for @socialCreatePostErrorMediaRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose an image or video first.'**
  String get socialCreatePostErrorMediaRequired;

  /// No description provided for @socialCreatePostErrorMerchantRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose the store you want to review.'**
  String get socialCreatePostErrorMerchantRequired;

  /// No description provided for @socialCreatePostReviewEligibilityFallback.
  ///
  /// In en, this message translates to:
  /// **'You can review this store after a completed order.'**
  String get socialCreatePostReviewEligibilityFallback;

  /// No description provided for @socialCreatePostTitle.
  ///
  /// In en, this message translates to:
  /// **'New post'**
  String get socialCreatePostTitle;

  /// No description provided for @socialCreatePostModeStoreReview.
  ///
  /// In en, this message translates to:
  /// **'Store review'**
  String get socialCreatePostModeStoreReview;

  /// No description provided for @socialCreatePostModeReel.
  ///
  /// In en, this message translates to:
  /// **'Reel'**
  String get socialCreatePostModeReel;

  /// No description provided for @socialCreatePostModePhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get socialCreatePostModePhoto;

  /// No description provided for @socialCreatePostModeText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get socialCreatePostModeText;

  /// No description provided for @socialCreatePostReviewHint.
  ///
  /// In en, this message translates to:
  /// **'Write your review...'**
  String get socialCreatePostReviewHint;

  /// No description provided for @socialCreatePostShareHint.
  ///
  /// In en, this message translates to:
  /// **'What would you like to share today?'**
  String get socialCreatePostShareHint;

  /// No description provided for @socialCreatePostChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get socialCreatePostChooseFile;

  /// No description provided for @socialCreatePostReplaceFile.
  ///
  /// In en, this message translates to:
  /// **'Replace file'**
  String get socialCreatePostReplaceFile;

  /// No description provided for @socialCreatePostMerchantSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search for a restaurant or store'**
  String get socialCreatePostMerchantSearchLabel;

  /// No description provided for @socialCreatePostLoadingMerchants.
  ///
  /// In en, this message translates to:
  /// **'Loading stores...'**
  String get socialCreatePostLoadingMerchants;

  /// No description provided for @socialCreatePostNoMatchingMerchants.
  ///
  /// In en, this message translates to:
  /// **'No matching stores found right now. Try another search.'**
  String get socialCreatePostNoMatchingMerchants;

  /// No description provided for @socialCreatePostSubmitNow.
  ///
  /// In en, this message translates to:
  /// **'Post now'**
  String get socialCreatePostSubmitNow;

  /// No description provided for @adminRealEstatePendingLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load pending real estate listings.'**
  String get adminRealEstatePendingLoadFailed;

  /// No description provided for @adminRealEstatePendingOptionalReviewNote.
  ///
  /// In en, this message translates to:
  /// **'Optional review note'**
  String get adminRealEstatePendingOptionalReviewNote;

  /// No description provided for @adminRealEstatePendingApproveTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve listing'**
  String get adminRealEstatePendingApproveTitle;

  /// No description provided for @adminRealEstatePendingRejectTitle.
  ///
  /// In en, this message translates to:
  /// **'Reject listing'**
  String get adminRealEstatePendingRejectTitle;

  /// No description provided for @adminRealEstatePendingReviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply review decision.'**
  String get adminRealEstatePendingReviewFailed;

  /// No description provided for @adminRealEstatePendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending real estate listings'**
  String get adminRealEstatePendingTitle;

  /// No description provided for @adminRealEstatePendingEmpty.
  ///
  /// In en, this message translates to:
  /// **'No pending listings right now.'**
  String get adminRealEstatePendingEmpty;

  /// No description provided for @adminRealEstatePendingOwnerLine.
  ///
  /// In en, this message translates to:
  /// **'Owner: {name} (#{ownerId})'**
  String adminRealEstatePendingOwnerLine(Object name, Object ownerId);

  /// No description provided for @adminRealEstatePendingOwnerPhoneLine.
  ///
  /// In en, this message translates to:
  /// **'Owner phone: {phone}'**
  String adminRealEstatePendingOwnerPhoneLine(Object phone);

  /// No description provided for @adminRealEstatePendingPurposeSale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get adminRealEstatePendingPurposeSale;

  /// No description provided for @adminRealEstatePendingPurposeRent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get adminRealEstatePendingPurposeRent;

  /// No description provided for @adminRealEstatePendingPhoneLine.
  ///
  /// In en, this message translates to:
  /// **'Phone: {phone}'**
  String adminRealEstatePendingPhoneLine(Object phone);

  /// No description provided for @adminRealEstatePendingRejectAction.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get adminRealEstatePendingRejectAction;

  /// No description provided for @adminRealEstatePendingApproveAction.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get adminRealEstatePendingApproveAction;

  /// No description provided for @socialExploreBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get socialExploreBlocked;

  /// No description provided for @socialExploreFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get socialExploreFollowing;

  /// No description provided for @socialExploreCancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get socialExploreCancelRequest;

  /// No description provided for @socialExploreAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get socialExploreAccept;

  /// No description provided for @socialExploreFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get socialExploreFollow;

  /// No description provided for @socialExploreBlockedByOther.
  ///
  /// In en, this message translates to:
  /// **'This action is unavailable because this account blocked you.'**
  String get socialExploreBlockedByOther;

  /// No description provided for @socialExploreUnblockFirst.
  ///
  /// In en, this message translates to:
  /// **'Unblock this profile first before sending a request.'**
  String get socialExploreUnblockFirst;

  /// No description provided for @socialExploreFollowRequestAccepted.
  ///
  /// In en, this message translates to:
  /// **'Follow request accepted.'**
  String get socialExploreFollowRequestAccepted;

  /// No description provided for @socialExploreRequestCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled.'**
  String get socialExploreRequestCancelled;

  /// No description provided for @socialExploreFollowRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Follow request sent.'**
  String get socialExploreFollowRequestSent;

  /// No description provided for @socialExploreActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to complete the action right now.'**
  String get socialExploreActionFailed;

  /// No description provided for @socialExploreTitle.
  ///
  /// In en, this message translates to:
  /// **'Explore Basmaya'**
  String get socialExploreTitle;

  /// No description provided for @socialExploreSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Social search'**
  String get socialExploreSearchTooltip;

  /// No description provided for @socialExploreLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load explore right now.'**
  String get socialExploreLoadFailed;

  /// No description provided for @socialExploreRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get socialExploreRetry;

  /// No description provided for @socialExploreHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Search the community fast'**
  String get socialExploreHeroTitle;

  /// No description provided for @socialExploreHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'People, reels, hashtags, and local reviews in one place.'**
  String get socialExploreHeroSubtitle;

  /// No description provided for @socialExploreSuggestedPeople.
  ///
  /// In en, this message translates to:
  /// **'Suggested people'**
  String get socialExploreSuggestedPeople;

  /// No description provided for @socialExploreSuggestedPeopleEmpty.
  ///
  /// In en, this message translates to:
  /// **'No suggested accounts are available right now.'**
  String get socialExploreSuggestedPeopleEmpty;

  /// No description provided for @socialExploreSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get socialExploreSeeAll;

  /// No description provided for @socialExploreTrendingTopics.
  ///
  /// In en, this message translates to:
  /// **'Trending topics'**
  String get socialExploreTrendingTopics;

  /// No description provided for @socialExploreTrendingTopicsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local hashtags and topics moving right now.'**
  String get socialExploreTrendingTopicsSubtitle;

  /// No description provided for @socialExploreBasmayaReels.
  ///
  /// In en, this message translates to:
  /// **'Basmaya reels'**
  String get socialExploreBasmayaReels;

  /// No description provided for @socialExploreOpenReels.
  ///
  /// In en, this message translates to:
  /// **'Open reels'**
  String get socialExploreOpenReels;

  /// No description provided for @socialExploreNearYou.
  ///
  /// In en, this message translates to:
  /// **'Near you'**
  String get socialExploreNearYou;

  /// No description provided for @socialExploreNearYouSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Posts and activity from people closer to your local area.'**
  String get socialExploreNearYouSubtitle;

  /// No description provided for @socialExplorePopularNow.
  ///
  /// In en, this message translates to:
  /// **'Popular now'**
  String get socialExplorePopularNow;

  /// No description provided for @socialExplorePopularNowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The social content getting the most attention in Basmaya.'**
  String get socialExplorePopularNowSubtitle;

  /// No description provided for @socialExploreLocalReviews.
  ///
  /// In en, this message translates to:
  /// **'Local reviews'**
  String get socialExploreLocalReviews;

  /// No description provided for @socialExploreLocalReviewsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restaurant and store reviews the community is discussing now.'**
  String get socialExploreLocalReviewsSubtitle;

  /// No description provided for @socialExploreForYou.
  ///
  /// In en, this message translates to:
  /// **'For you'**
  String get socialExploreForYou;

  /// No description provided for @socialTaggedPostsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tagged posts'**
  String get socialTaggedPostsTitle;

  /// No description provided for @socialTaggedPostsLoadFailedFriendly.
  ///
  /// In en, this message translates to:
  /// **'Unable to load tagged posts right now.'**
  String get socialTaggedPostsLoadFailedFriendly;

  /// No description provided for @socialTaggedPostsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tagged posts yet.'**
  String get socialTaggedPostsEmpty;

  /// No description provided for @jobsHubLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load jobs.'**
  String get jobsHubLoadFailed;

  /// No description provided for @jobsHubPostedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Job posted successfully.'**
  String get jobsHubPostedSuccess;

  /// No description provided for @jobsHubPublishFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to publish job.'**
  String get jobsHubPublishFailed;

  /// No description provided for @jobsHubLoadDetailsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load job details.'**
  String get jobsHubLoadDetailsFailed;

  /// No description provided for @jobsHubUpdateStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update job status.'**
  String get jobsHubUpdateStatusFailed;

  /// No description provided for @jobsHubDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Do you want to delete the job \"{title}\"?'**
  String jobsHubDeleteConfirm(Object title);

  /// No description provided for @jobsHubDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete job.'**
  String get jobsHubDeleteFailed;

  /// No description provided for @jobsHubApplicationSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Application request sent.'**
  String get jobsHubApplicationSubmitted;

  /// No description provided for @jobsHubApplicationFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send application request.'**
  String get jobsHubApplicationFailed;

  /// No description provided for @jobsHubDrawerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Jobs and your submitted applications'**
  String get jobsHubDrawerSubtitle;

  /// No description provided for @jobsHubDrawerStatusesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shortlisted - Rejected - Accepted'**
  String get jobsHubDrawerStatusesSubtitle;

  /// No description provided for @jobsHubManageHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track postings and candidates quickly, and update application statuses from one place.'**
  String get jobsHubManageHeaderSubtitle;

  /// No description provided for @jobsHubBrowseHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Verified job opportunities inside Basmaya with precise filtering by specialty and area.'**
  String get jobsHubBrowseHeaderSubtitle;

  /// No description provided for @jobsHubPlatformTitle.
  ///
  /// In en, this message translates to:
  /// **'Basmaya Jobs Platform'**
  String get jobsHubPlatformTitle;

  /// No description provided for @jobsHubSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by job title, company, city...'**
  String get jobsHubSearchHint;

  /// No description provided for @jobsHubNoActiveFilters.
  ///
  /// In en, this message translates to:
  /// **'No active filters at the moment.'**
  String get jobsHubNoActiveFilters;

  /// No description provided for @jobsHubEmptyManage.
  ///
  /// In en, this message translates to:
  /// **'No job listings yet. Start by posting your first job.'**
  String get jobsHubEmptyManage;

  /// No description provided for @jobsHubEmptyBrowse.
  ///
  /// In en, this message translates to:
  /// **'No jobs match the current filters.'**
  String get jobsHubEmptyBrowse;

  /// No description provided for @jobsHubJobTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Job Title *'**
  String get jobsHubJobTitleLabel;

  /// No description provided for @jobsHubCompanyNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Company Name (Optional for Admin)'**
  String get jobsHubCompanyNameOptional;

  /// No description provided for @jobsHubSkillsCommaSeparated.
  ///
  /// In en, this message translates to:
  /// **'Skills (comma separated)'**
  String get jobsHubSkillsCommaSeparated;

  /// No description provided for @jobsHubExpirationDate.
  ///
  /// In en, this message translates to:
  /// **'Expiration Date'**
  String get jobsHubExpirationDate;

  /// No description provided for @jobsHubExternalApplyUrl.
  ///
  /// In en, this message translates to:
  /// **'External apply URL'**
  String get jobsHubExternalApplyUrl;

  /// No description provided for @jobsHubFillRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill all required fields.'**
  String get jobsHubFillRequiredFields;

  /// No description provided for @jobsHubChooseActivityAndDepartment.
  ///
  /// In en, this message translates to:
  /// **'Please choose activity type and department.'**
  String get jobsHubChooseActivityAndDepartment;

  /// No description provided for @jobsHubSalaryRangeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Maximum salary must be greater than minimum salary.'**
  String get jobsHubSalaryRangeInvalid;

  /// No description provided for @socialCommunityScopeForbidden.
  ///
  /// In en, this message translates to:
  /// **'You cannot access this community.'**
  String get socialCommunityScopeForbidden;

  /// No description provided for @socialCommunityManagerRequired.
  ///
  /// In en, this message translates to:
  /// **'This action is restricted to community managers only.'**
  String get socialCommunityManagerRequired;

  /// No description provided for @socialCommunityChatLocked.
  ///
  /// In en, this message translates to:
  /// **'Group chat is currently locked.'**
  String get socialCommunityChatLocked;

  /// No description provided for @socialCommunityChatBanned.
  ///
  /// In en, this message translates to:
  /// **'You are banned from group chat.'**
  String get socialCommunityChatBanned;

  /// No description provided for @socialCommunityMemberMuted.
  ///
  /// In en, this message translates to:
  /// **'You are muted in this community. You cannot post or send messages here.'**
  String get socialCommunityMemberMuted;

  /// No description provided for @socialCommunityMemberRemoved.
  ///
  /// In en, this message translates to:
  /// **'You have been removed from this community.'**
  String get socialCommunityMemberRemoved;

  /// No description provided for @socialCommunityMemberRemoveForbidden.
  ///
  /// In en, this message translates to:
  /// **'You are not allowed to remove this member.'**
  String get socialCommunityMemberRemoveForbidden;

  /// No description provided for @socialCommunityMemberRemoveSelfNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'You cannot remove your own account.'**
  String get socialCommunityMemberRemoveSelfNotAllowed;

  /// No description provided for @socialCommunityManagerAssignForbidden.
  ///
  /// In en, this message translates to:
  /// **'Only admin can assign managers.'**
  String get socialCommunityManagerAssignForbidden;

  /// No description provided for @socialCommunityManagerRevokeForbidden.
  ///
  /// In en, this message translates to:
  /// **'Only admin can revoke manager role.'**
  String get socialCommunityManagerRevokeForbidden;

  /// No description provided for @authRegisterCardExtractFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to extract card data.'**
  String get authRegisterCardExtractFailed;

  /// No description provided for @authRegisterConsentRequired.
  ///
  /// In en, this message translates to:
  /// **'Please accept the terms before creating your account.'**
  String get authRegisterConsentRequired;

  /// No description provided for @authRegisterCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the account right now. Please try again.'**
  String get authRegisterCreateFailed;

  /// No description provided for @authRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Create User Account'**
  String get authRegisterTitle;

  /// No description provided for @authRegisterResidenceCardSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Extract Residence Card Data (Optional)'**
  String get authRegisterResidenceCardSectionTitle;

  /// No description provided for @authRegisterUploadCardImage.
  ///
  /// In en, this message translates to:
  /// **'Upload Card Image'**
  String get authRegisterUploadCardImage;

  /// No description provided for @authRegisterCaptureFromCamera.
  ///
  /// In en, this message translates to:
  /// **'Capture from Camera'**
  String get authRegisterCaptureFromCamera;

  /// No description provided for @authRegisterAnalyzingCard.
  ///
  /// In en, this message translates to:
  /// **'Analyzing card...'**
  String get authRegisterAnalyzingCard;

  /// No description provided for @authRegisterExtractDataAutomatically.
  ///
  /// In en, this message translates to:
  /// **'Extract Data Automatically'**
  String get authRegisterExtractDataAutomatically;

  /// No description provided for @authRegisterExtractionConfidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Extraction Confidence'**
  String get authRegisterExtractionConfidenceLabel;

  /// No description provided for @authRegisterNameFromCard.
  ///
  /// In en, this message translates to:
  /// **'Name from card'**
  String get authRegisterNameFromCard;

  /// No description provided for @authRegisterExtractedName.
  ///
  /// In en, this message translates to:
  /// **'Extracted name'**
  String get authRegisterExtractedName;

  /// No description provided for @authRegisterBlockOrTown.
  ///
  /// In en, this message translates to:
  /// **'Block / Town'**
  String get authRegisterBlockOrTown;

  /// No description provided for @authRegisterBuildingNumber.
  ///
  /// In en, this message translates to:
  /// **'Building number'**
  String get authRegisterBuildingNumber;

  /// No description provided for @authRegisterFloorNumber.
  ///
  /// In en, this message translates to:
  /// **'Floor number'**
  String get authRegisterFloorNumber;

  /// No description provided for @authRegisterApartmentNumber.
  ///
  /// In en, this message translates to:
  /// **'Apartment number'**
  String get authRegisterApartmentNumber;

  /// No description provided for @authRegisterContractNumber.
  ///
  /// In en, this message translates to:
  /// **'Contract number'**
  String get authRegisterContractNumber;

  /// No description provided for @authRegisterVisibleIdNumber.
  ///
  /// In en, this message translates to:
  /// **'Visible ID number'**
  String get authRegisterVisibleIdNumber;

  /// No description provided for @authRegisterIssueDate.
  ///
  /// In en, this message translates to:
  /// **'Issue date'**
  String get authRegisterIssueDate;

  /// No description provided for @authRegisterFullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get authRegisterFullName;

  /// No description provided for @authRegisterPinHint.
  ///
  /// In en, this message translates to:
  /// **'4 to 8 digits'**
  String get authRegisterPinHint;

  /// No description provided for @authRegisterFullNameHint.
  ///
  /// In en, this message translates to:
  /// **'Example: Mustafa Salam'**
  String get authRegisterFullNameHint;

  /// No description provided for @authRegisterCurrentJobTitle.
  ///
  /// In en, this message translates to:
  /// **'Current job title (optional)'**
  String get authRegisterCurrentJobTitle;

  /// No description provided for @authRegisterWorkTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Example: Accountant'**
  String get authRegisterWorkTitleHint;

  /// No description provided for @authRegisterCurrentCompany.
  ///
  /// In en, this message translates to:
  /// **'Current company (optional)'**
  String get authRegisterCurrentCompany;

  /// No description provided for @authRegisterWorkCompanyHint.
  ///
  /// In en, this message translates to:
  /// **'Example: Al-Rafidain Co.'**
  String get authRegisterWorkCompanyHint;

  /// No description provided for @authRegisterProfileImageOptional.
  ///
  /// In en, this message translates to:
  /// **'Profile image (optional)'**
  String get authRegisterProfileImageOptional;

  /// No description provided for @authRegisterConsentCheckbox.
  ///
  /// In en, this message translates to:
  /// **'I agree once to: Terms of Use and usage analytics for service improvement.'**
  String get authRegisterConsentCheckbox;

  /// No description provided for @authRegisterCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get authRegisterCreateAccount;

  /// No description provided for @authRegisterConfirmAndCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Confirm Data & Create Account'**
  String get authRegisterConfirmAndCreateAccount;

  /// No description provided for @paidUpgradesPlanCarsDescription.
  ///
  /// In en, this message translates to:
  /// **'Publish and manage car listings for 30 days.'**
  String get paidUpgradesPlanCarsDescription;

  /// No description provided for @paidUpgradesPlanPropertyDescription.
  ///
  /// In en, this message translates to:
  /// **'Publish and manage apartment and property listings for 30 days.'**
  String get paidUpgradesPlanPropertyDescription;

  /// No description provided for @paidUpgradesPlanPremiumDescription.
  ///
  /// In en, this message translates to:
  /// **'Includes a public verified badge plus both cars and property entitlements for 30 days.'**
  String get paidUpgradesPlanPremiumDescription;

  /// No description provided for @paidUpgradesRequestValidation.
  ///
  /// In en, this message translates to:
  /// **'Select at least one plan and enter the activity name.'**
  String get paidUpgradesRequestValidation;

  /// No description provided for @paidUpgradesRequestSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit upgrade request.'**
  String get paidUpgradesRequestSubmitFailed;

  /// No description provided for @paidUpgradesRequestSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Request a new upgrade'**
  String get paidUpgradesRequestSheetTitle;

  /// No description provided for @paidUpgradesActivityName.
  ///
  /// In en, this message translates to:
  /// **'Activity name'**
  String get paidUpgradesActivityName;

  /// No description provided for @paidUpgradesActivityDescription.
  ///
  /// In en, this message translates to:
  /// **'Activity description'**
  String get paidUpgradesActivityDescription;

  /// No description provided for @paidUpgradesContactPhone.
  ///
  /// In en, this message translates to:
  /// **'Contact phone'**
  String get paidUpgradesContactPhone;

  /// No description provided for @paidUpgradesNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get paidUpgradesNotes;

  /// No description provided for @paidUpgradesSubmitRequest.
  ///
  /// In en, this message translates to:
  /// **'Submit request'**
  String get paidUpgradesSubmitRequest;

  /// No description provided for @paidUpgradesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load paid upgrades.'**
  String get paidUpgradesLoadFailed;

  /// No description provided for @paidUpgradesRequestCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled.'**
  String get paidUpgradesRequestCancelled;

  /// No description provided for @paidUpgradesCancelRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to cancel the request.'**
  String get paidUpgradesCancelRequestFailed;

  /// No description provided for @paidUpgradesStatusPendingAdminReview.
  ///
  /// In en, this message translates to:
  /// **'Pending admin review'**
  String get paidUpgradesStatusPendingAdminReview;

  /// No description provided for @paidUpgradesExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get paidUpgradesExpired;

  /// No description provided for @paidUpgradesNoExpirySet.
  ///
  /// In en, this message translates to:
  /// **'No expiry set'**
  String get paidUpgradesNoExpirySet;

  /// No description provided for @paidUpgradesDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} day(s) left'**
  String paidUpgradesDaysLeft(int count);

  /// No description provided for @paidUpgradesHoursLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} hour(s) left'**
  String paidUpgradesHoursLeft(int count);

  /// No description provided for @paidUpgradesPlanCarsExtendedDescription.
  ///
  /// In en, this message translates to:
  /// **'Publish and manage car listings for 30 days, with a seller workspace in your account.'**
  String get paidUpgradesPlanCarsExtendedDescription;

  /// No description provided for @paidUpgradesPlanPropertyExtendedDescription.
  ///
  /// In en, this message translates to:
  /// **'Publish and manage apartment and property listings for 30 days, with a real-estate workspace in your account.'**
  String get paidUpgradesPlanPropertyExtendedDescription;

  /// No description provided for @paidUpgradesPlanPremiumExtendedDescription.
  ///
  /// In en, this message translates to:
  /// **'A 30-day premium subscription with a public verified badge in social, plus both car-seller and property-seller entitlements.'**
  String get paidUpgradesPlanPremiumExtendedDescription;

  /// No description provided for @paidUpgradesCurrentSubscription.
  ///
  /// In en, this message translates to:
  /// **'Your current subscription'**
  String get paidUpgradesCurrentSubscription;

  /// No description provided for @paidUpgradesNoActiveSubscription.
  ///
  /// In en, this message translates to:
  /// **'No active subscription yet. If your request was approved just now, refresh the page in a moment.'**
  String get paidUpgradesNoActiveSubscription;

  /// No description provided for @paidUpgradesActiveNow.
  ///
  /// In en, this message translates to:
  /// **'Active now'**
  String get paidUpgradesActiveNow;

  /// No description provided for @paidUpgradesActiveDescription.
  ///
  /// In en, this message translates to:
  /// **'You are currently subscribed to this service.'**
  String get paidUpgradesActiveDescription;

  /// No description provided for @paidUpgradesSubscriptionEndsOn.
  ///
  /// In en, this message translates to:
  /// **'Subscription ends on {date}'**
  String paidUpgradesSubscriptionEndsOn(Object date);

  /// No description provided for @paidUpgradesPremiumIncludesEntitlements.
  ///
  /// In en, this message translates to:
  /// **'This subscription also includes both car-seller and property-seller access for the premium period.'**
  String get paidUpgradesPremiumIncludesEntitlements;

  /// No description provided for @paidUpgradesIncludedWithPremium.
  ///
  /// In en, this message translates to:
  /// **'Included with premium'**
  String get paidUpgradesIncludedWithPremium;

  /// No description provided for @paidUpgradesCurrentlyActive.
  ///
  /// In en, this message translates to:
  /// **'Currently active'**
  String get paidUpgradesCurrentlyActive;

  /// No description provided for @paidUpgradesAvailableStatus.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get paidUpgradesAvailableStatus;

  /// No description provided for @paidUpgradesCurrentAccessEnds.
  ///
  /// In en, this message translates to:
  /// **'Current access ends on {date} ? {remaining}'**
  String paidUpgradesCurrentAccessEnds(Object date, Object remaining);

  /// No description provided for @paidUpgradesPlanEnabledByPremium.
  ///
  /// In en, this message translates to:
  /// **'This plan is currently enabled for you because premium includes it automatically.'**
  String get paidUpgradesPlanEnabledByPremium;

  /// No description provided for @paidUpgradesHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Paid upgrades'**
  String get paidUpgradesHomeTitle;

  /// No description provided for @paidUpgradesRequestUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Request upgrade'**
  String get paidUpgradesRequestUpgrade;

  /// No description provided for @paidUpgradesPremiumBadgeActive.
  ///
  /// In en, this message translates to:
  /// **'Your premium badge is active'**
  String get paidUpgradesPremiumBadgeActive;

  /// No description provided for @paidUpgradesPremiumBadgeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Visible to everyone until {date} ? {remaining}'**
  String paidUpgradesPremiumBadgeSubtitle(Object date, Object remaining);

  /// No description provided for @paidUpgradesAvailablePlans.
  ///
  /// In en, this message translates to:
  /// **'Available plans'**
  String get paidUpgradesAvailablePlans;

  /// No description provided for @paidUpgradesYourRequests.
  ///
  /// In en, this message translates to:
  /// **'Your requests'**
  String get paidUpgradesYourRequests;

  /// No description provided for @paidUpgradesNoRequests.
  ///
  /// In en, this message translates to:
  /// **'No upgrade requests yet.'**
  String get paidUpgradesNoRequests;

  /// No description provided for @paidUpgradesActivityLine.
  ///
  /// In en, this message translates to:
  /// **'Activity: {value}'**
  String paidUpgradesActivityLine(Object value);

  /// No description provided for @paidUpgradesPhoneLine.
  ///
  /// In en, this message translates to:
  /// **'Phone: {value}'**
  String paidUpgradesPhoneLine(Object value);

  /// No description provided for @paidUpgradesMonthlyFeeLine.
  ///
  /// In en, this message translates to:
  /// **'Monthly fee: {value}'**
  String paidUpgradesMonthlyFeeLine(Object value);

  /// No description provided for @paidUpgradesReviewNoteLine.
  ///
  /// In en, this message translates to:
  /// **'Review note: {value}'**
  String paidUpgradesReviewNoteLine(Object value);

  /// No description provided for @paidUpgradesActivatedOn.
  ///
  /// In en, this message translates to:
  /// **'Activated on: {date}'**
  String paidUpgradesActivatedOn(Object date);

  /// No description provided for @paidUpgradesCancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get paidUpgradesCancelRequest;

  /// No description provided for @hrEmployeePortalTitle.
  ///
  /// In en, this message translates to:
  /// **'Employee Portal'**
  String get hrEmployeePortalTitle;

  /// No description provided for @hrEmployeePortalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Attendance, leave requests and salary advances.'**
  String get hrEmployeePortalSubtitle;

  /// No description provided for @hrEmployeePortalProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get hrEmployeePortalProfile;

  /// No description provided for @hrEmployeePortalBaseInfo.
  ///
  /// In en, this message translates to:
  /// **'Base info'**
  String get hrEmployeePortalBaseInfo;

  /// No description provided for @hrEmployeePortalAttendance.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get hrEmployeePortalAttendance;

  /// No description provided for @hrEmployeePortalCheckInOut.
  ///
  /// In en, this message translates to:
  /// **'Check in/out'**
  String get hrEmployeePortalCheckInOut;

  /// No description provided for @hrEmployeePortalLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get hrEmployeePortalLeave;

  /// No description provided for @hrEmployeePortalRequestLeave.
  ///
  /// In en, this message translates to:
  /// **'Request leave'**
  String get hrEmployeePortalRequestLeave;

  /// No description provided for @hrEmployeePortalAdvance.
  ///
  /// In en, this message translates to:
  /// **'Advance'**
  String get hrEmployeePortalAdvance;

  /// No description provided for @hrEmployeePortalAdvanceRequest.
  ///
  /// In en, this message translates to:
  /// **'Advance request'**
  String get hrEmployeePortalAdvanceRequest;

  /// No description provided for @hrEmployeePortalLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get hrEmployeePortalLogs;

  /// No description provided for @hrEmployeePortalTrackHistory.
  ///
  /// In en, this message translates to:
  /// **'Track history'**
  String get hrEmployeePortalTrackHistory;

  /// No description provided for @hrEmployeePortalRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get hrEmployeePortalRole;

  /// No description provided for @hrEmployeePortalShift.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get hrEmployeePortalShift;

  /// No description provided for @hrEmployeePortalWorkDaysPerWeek.
  ///
  /// In en, this message translates to:
  /// **'Work days/week'**
  String get hrEmployeePortalWorkDaysPerWeek;

  /// No description provided for @hrEmployeePortalBaseSalary.
  ///
  /// In en, this message translates to:
  /// **'Base salary'**
  String get hrEmployeePortalBaseSalary;

  /// No description provided for @hrEmployeePortalOptionalPhoto.
  ///
  /// In en, this message translates to:
  /// **'Optional photo'**
  String get hrEmployeePortalOptionalPhoto;

  /// No description provided for @hrEmployeePortalRemovePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get hrEmployeePortalRemovePhoto;

  /// No description provided for @hrEmployeePortalCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Check in'**
  String get hrEmployeePortalCheckIn;

  /// No description provided for @hrEmployeePortalCheckOut.
  ///
  /// In en, this message translates to:
  /// **'Check out'**
  String get hrEmployeePortalCheckOut;

  /// No description provided for @hrEmployeePortalLeaveRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave Request'**
  String get hrEmployeePortalLeaveRequestTitle;

  /// No description provided for @hrEmployeePortalLeaveType.
  ///
  /// In en, this message translates to:
  /// **'Leave type'**
  String get hrEmployeePortalLeaveType;

  /// No description provided for @hrEmployeePortalLeaveTypeAnnual.
  ///
  /// In en, this message translates to:
  /// **'Annual'**
  String get hrEmployeePortalLeaveTypeAnnual;

  /// No description provided for @hrEmployeePortalLeaveTypeSick.
  ///
  /// In en, this message translates to:
  /// **'Sick'**
  String get hrEmployeePortalLeaveTypeSick;

  /// No description provided for @hrEmployeePortalLeaveTypeEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get hrEmployeePortalLeaveTypeEmergency;

  /// No description provided for @hrEmployeePortalLeaveTypeMaternity.
  ///
  /// In en, this message translates to:
  /// **'Maternity'**
  String get hrEmployeePortalLeaveTypeMaternity;

  /// No description provided for @hrEmployeePortalLeaveTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get hrEmployeePortalLeaveTypeOther;

  /// No description provided for @hrEmployeePortalPayPolicy.
  ///
  /// In en, this message translates to:
  /// **'Pay policy'**
  String get hrEmployeePortalPayPolicy;

  /// No description provided for @hrEmployeePortalPayPolicyPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get hrEmployeePortalPayPolicyPaid;

  /// No description provided for @hrEmployeePortalPayPolicyHalfPaid.
  ///
  /// In en, this message translates to:
  /// **'Half paid'**
  String get hrEmployeePortalPayPolicyHalfPaid;

  /// No description provided for @hrEmployeePortalPayPolicyUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get hrEmployeePortalPayPolicyUnpaid;

  /// No description provided for @hrEmployeePortalPayPolicySickPaid.
  ///
  /// In en, this message translates to:
  /// **'Sick paid'**
  String get hrEmployeePortalPayPolicySickPaid;

  /// No description provided for @hrEmployeePortalDaysCount.
  ///
  /// In en, this message translates to:
  /// **'Days count'**
  String get hrEmployeePortalDaysCount;

  /// No description provided for @hrEmployeePortalReasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get hrEmployeePortalReasonOptional;

  /// No description provided for @hrEmployeePortalSendLeaveRequest.
  ///
  /// In en, this message translates to:
  /// **'Send leave request'**
  String get hrEmployeePortalSendLeaveRequest;

  /// No description provided for @hrEmployeePortalSalaryAdvanceRequest.
  ///
  /// In en, this message translates to:
  /// **'Salary Advance Request'**
  String get hrEmployeePortalSalaryAdvanceRequest;

  /// No description provided for @hrEmployeePortalRequestedAmount.
  ///
  /// In en, this message translates to:
  /// **'Requested amount'**
  String get hrEmployeePortalRequestedAmount;

  /// No description provided for @hrEmployeePortalSendAdvanceRequest.
  ///
  /// In en, this message translates to:
  /// **'Send advance request'**
  String get hrEmployeePortalSendAdvanceRequest;

  /// No description provided for @hrEmployeePortalMyAttendanceLogs.
  ///
  /// In en, this message translates to:
  /// **'My attendance logs'**
  String get hrEmployeePortalMyAttendanceLogs;

  /// No description provided for @hrEmployeePortalStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get hrEmployeePortalStatus;

  /// No description provided for @hrEmployeePortalIn.
  ///
  /// In en, this message translates to:
  /// **'In'**
  String get hrEmployeePortalIn;

  /// No description provided for @hrEmployeePortalOut.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get hrEmployeePortalOut;

  /// No description provided for @hrEmployeePortalMyLeaveRequests.
  ///
  /// In en, this message translates to:
  /// **'My leave requests'**
  String get hrEmployeePortalMyLeaveRequests;

  /// No description provided for @hrEmployeePortalMyAdvanceRequests.
  ///
  /// In en, this message translates to:
  /// **'My advance requests'**
  String get hrEmployeePortalMyAdvanceRequests;

  /// No description provided for @hrEmployeePortalCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get hrEmployeePortalCreated;

  /// No description provided for @hrEmployeePortalAttendanceCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Attendance Check-in'**
  String get hrEmployeePortalAttendanceCheckIn;

  /// No description provided for @hrEmployeePortalNoteOptional.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get hrEmployeePortalNoteOptional;

  /// No description provided for @hrEmployeePortalPhotoSelected.
  ///
  /// In en, this message translates to:
  /// **'Photo selected'**
  String get hrEmployeePortalPhotoSelected;

  /// No description provided for @hrEmployeePortalFromDate.
  ///
  /// In en, this message translates to:
  /// **'From (YYYY-MM-DD)'**
  String get hrEmployeePortalFromDate;

  /// No description provided for @hrEmployeePortalToDate.
  ///
  /// In en, this message translates to:
  /// **'To (YYYY-MM-DD)'**
  String get hrEmployeePortalToDate;

  /// No description provided for @commonChooseFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Choose from device'**
  String get commonChooseFromDevice;

  /// No description provided for @commonRemoveImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get commonRemoveImage;

  /// No description provided for @validationRequiredField.
  ///
  /// In en, this message translates to:
  /// **'{fieldName} is required.'**
  String validationRequiredField(Object fieldName);

  /// No description provided for @validationInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get validationInvalidEmail;

  /// No description provided for @validationInvalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number.'**
  String get validationInvalidPhone;

  /// No description provided for @validationInvalidPin.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid PIN.'**
  String get validationInvalidPin;

  /// No description provided for @validationPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'The password is too short.'**
  String get validationPasswordTooShort;

  /// No description provided for @validationPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'The passwords do not match.'**
  String get validationPasswordMismatch;

  /// No description provided for @validationInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number.'**
  String get validationInvalidNumber;

  /// No description provided for @validationValueAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'This value is already in use.'**
  String get validationValueAlreadyUsed;

  /// No description provided for @validationInvalidCouponCode.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid short coupon code (AA123).'**
  String get validationInvalidCouponCode;

  /// No description provided for @validationMinValue.
  ///
  /// In en, this message translates to:
  /// **'Enter a value greater than or equal to {value}.'**
  String validationMinValue(Object value);

  /// No description provided for @validationMaxValue.
  ///
  /// In en, this message translates to:
  /// **'Enter a value less than or equal to {value}.'**
  String validationMaxValue(Object value);

  /// No description provided for @validationSelectOption.
  ///
  /// In en, this message translates to:
  /// **'Choose an option first.'**
  String get validationSelectOption;

  /// No description provided for @validationSelectImage.
  ///
  /// In en, this message translates to:
  /// **'Choose an image first.'**
  String get validationSelectImage;

  /// No description provided for @validationSelectLocation.
  ///
  /// In en, this message translates to:
  /// **'Choose a location first.'**
  String get validationSelectLocation;

  /// No description provided for @validationInvalidDate.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid date.'**
  String get validationInvalidDate;

  /// No description provided for @validationInvalidTime.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid time.'**
  String get validationInvalidTime;

  /// No description provided for @validationTextTooLong.
  ///
  /// In en, this message translates to:
  /// **'The text is too long.'**
  String get validationTextTooLong;

  /// No description provided for @validationReviewRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Review the highlighted fields and try again.'**
  String get validationReviewRequiredFields;

  /// No description provided for @validationTooManyFiles.
  ///
  /// In en, this message translates to:
  /// **'Too many files were selected.'**
  String get validationTooManyFiles;

  /// No description provided for @validationMessageRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a message before sending.'**
  String get validationMessageRequired;

  /// No description provided for @errorsBusinessRule.
  ///
  /// In en, this message translates to:
  /// **'The request could not be completed right now.'**
  String get errorsBusinessRule;

  /// No description provided for @errorsPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to perform this action.'**
  String get errorsPermissionDenied;

  /// No description provided for @errorsServerFailure.
  ///
  /// In en, this message translates to:
  /// **'The server could not process the request right now.'**
  String get errorsServerFailure;

  /// No description provided for @errorsUnknown.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred. Please try again.'**
  String get errorsUnknown;

  /// No description provided for @basmayaGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'District'**
  String get basmayaGroupLabel;

  /// No description provided for @basmayaGroupHint.
  ///
  /// In en, this message translates to:
  /// **'A or B'**
  String get basmayaGroupHint;

  /// No description provided for @basmayaSectorLabel.
  ///
  /// In en, this message translates to:
  /// **'Sector'**
  String get basmayaSectorLabel;

  /// No description provided for @basmayaSectorHint.
  ///
  /// In en, this message translates to:
  /// **'A1..A9 or B1..B8'**
  String get basmayaSectorHint;

  /// No description provided for @basmayaBuildingLabel.
  ///
  /// In en, this message translates to:
  /// **'Building number'**
  String get basmayaBuildingLabel;

  /// No description provided for @basmayaBuildingHint.
  ///
  /// In en, this message translates to:
  /// **'A101 or B122'**
  String get basmayaBuildingHint;

  /// No description provided for @basmayaApartmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Apartment number'**
  String get basmayaApartmentLabel;

  /// No description provided for @basmayaApartmentHint.
  ///
  /// In en, this message translates to:
  /// **'G01 or 101'**
  String get basmayaApartmentHint;

  /// No description provided for @basmayaValidationSectorInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid Basmaya sector.'**
  String get basmayaValidationSectorInvalid;

  /// No description provided for @basmayaValidationBuildingInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid building inside {block}.'**
  String basmayaValidationBuildingInvalid(Object block);

  /// No description provided for @basmayaValidationApartmentInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid apartment number.'**
  String get basmayaValidationApartmentInvalid;

  /// No description provided for @deliveryAddressesTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery addresses'**
  String get deliveryAddressesTitle;

  /// No description provided for @deliveryAddressesAdd.
  ///
  /// In en, this message translates to:
  /// **'Add address'**
  String get deliveryAddressesAdd;

  /// No description provided for @deliveryAddressesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No delivery addresses yet.'**
  String get deliveryAddressesEmpty;

  /// No description provided for @deliveryAddressesDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete address'**
  String get deliveryAddressesDeleteTitle;

  /// No description provided for @deliveryAddressesDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Do you want to delete this delivery address?'**
  String get deliveryAddressesDeleteBody;

  /// No description provided for @deliveryAddressesMarkDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get deliveryAddressesMarkDefault;

  /// No description provided for @deliveryAddressesSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as default address'**
  String get deliveryAddressesSetDefault;

  /// No description provided for @deliveryAddressesEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit delivery address'**
  String get deliveryAddressesEditTitle;

  /// No description provided for @deliveryAddressesAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add delivery address'**
  String get deliveryAddressesAddTitle;

  /// No description provided for @deliveryAddressesLabel.
  ///
  /// In en, this message translates to:
  /// **'Address label'**
  String get deliveryAddressesLabel;

  /// No description provided for @deliveryAddressesCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get deliveryAddressesCity;

  /// No description provided for @deliveryAddressesSaveEdit.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get deliveryAddressesSaveEdit;

  /// No description provided for @deliveryAddressesSaveNew.
  ///
  /// In en, this message translates to:
  /// **'Add address'**
  String get deliveryAddressesSaveNew;

  /// No description provided for @deliveryAddressesCompleteData.
  ///
  /// In en, this message translates to:
  /// **'Complete the required address fields.'**
  String get deliveryAddressesCompleteData;

  /// No description provided for @deliveryAddressesDefaultSwitch.
  ///
  /// In en, this message translates to:
  /// **'Set as default address'**
  String get deliveryAddressesDefaultSwitch;

  /// No description provided for @deliveryAddressesDefaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Primary address'**
  String get deliveryAddressesDefaultLabel;

  /// No description provided for @deliveryAddressesDefaultCity.
  ///
  /// In en, this message translates to:
  /// **'Basmaya City'**
  String get deliveryAddressesDefaultCity;

  /// No description provided for @deliveryAddressesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the delivery addresses.'**
  String get deliveryAddressesLoadFailed;

  /// No description provided for @deliveryAddressesCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to add the delivery address.'**
  String get deliveryAddressesCreateFailed;

  /// No description provided for @deliveryAddressesUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the delivery address.'**
  String get deliveryAddressesUpdateFailed;

  /// No description provided for @deliveryAddressesDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete the delivery address.'**
  String get deliveryAddressesDeleteFailed;

  /// No description provided for @deliveryAddressesDefaultFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to set the default address.'**
  String get deliveryAddressesDefaultFailed;

  /// No description provided for @authLoginFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Unable to sign in. Check your phone number and PIN.'**
  String get authLoginFailedGeneric;

  /// No description provided for @authLogoutOtherDevicesFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to sign out from the other devices.'**
  String get authLogoutOtherDevicesFailed;

  /// No description provided for @authLoadSessionsFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the active sessions.'**
  String get authLoadSessionsFailed;

  /// No description provided for @authUpdateAccountFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the account details.'**
  String get authUpdateAccountFailedGeneric;

  /// No description provided for @authUpdatePinUnchanged.
  ///
  /// In en, this message translates to:
  /// **'The new PIN must be different from the current PIN.'**
  String get authUpdatePinUnchanged;

  /// No description provided for @authUpdateNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes were detected.'**
  String get authUpdateNoChanges;

  /// No description provided for @authGenericRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'The authentication request failed.'**
  String get authGenericRequestFailed;

  /// No description provided for @ownerDashboardLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the store dashboard data.'**
  String get ownerDashboardLoadFailed;

  /// No description provided for @ownerFinancialTermsAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to accept the financial terms.'**
  String get ownerFinancialTermsAcceptFailed;

  /// No description provided for @ownerFinancialTermsRejectFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to reject the financial terms.'**
  String get ownerFinancialTermsRejectFailed;

  /// No description provided for @ownerMerchantUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the store information.'**
  String get ownerMerchantUpdateFailed;

  /// No description provided for @ownerProductCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the product.'**
  String get ownerProductCreateFailed;

  /// No description provided for @ownerProductUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the product.'**
  String get ownerProductUpdateFailed;

  /// No description provided for @ownerProductDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete the product.'**
  String get ownerProductDeleteFailed;

  /// No description provided for @ownerCategoryCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the category.'**
  String get ownerCategoryCreateFailed;

  /// No description provided for @ownerCategoryUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the category.'**
  String get ownerCategoryUpdateFailed;

  /// No description provided for @ownerCategoryDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete the category.'**
  String get ownerCategoryDeleteFailed;

  /// No description provided for @ownerOrderStatusUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the order status.'**
  String get ownerOrderStatusUpdateFailed;

  /// No description provided for @ownerAssignDeliveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to assign the delivery account.'**
  String get ownerAssignDeliveryFailed;

  /// No description provided for @ownerOrderPreparationStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to start order preparation.'**
  String get ownerOrderPreparationStartFailed;

  /// No description provided for @ownerOrderReadyStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to mark the order as ready.'**
  String get ownerOrderReadyStatusFailed;

  /// No description provided for @ownerReceivablesInvoicesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the invoice list.'**
  String get ownerReceivablesInvoicesLoadFailed;

  /// No description provided for @ownerReceivablesPreviewSelectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to preview the selected invoices.'**
  String get ownerReceivablesPreviewSelectionFailed;

  /// No description provided for @ownerReceivablesRequestInvoicesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the eligible invoices.'**
  String get ownerReceivablesRequestInvoicesLoadFailed;

  /// No description provided for @ownerCouriersUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the courier profile.'**
  String get ownerCouriersUpdateFailed;

  /// No description provided for @ownerCreateDeliveryAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the delivery account.'**
  String get ownerCreateDeliveryAccountFailed;

  /// No description provided for @ownerCreateAccountantFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the accountant account.'**
  String get ownerCreateAccountantFailed;

  /// No description provided for @ownerCreateHrAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the HR account.'**
  String get ownerCreateHrAccountFailed;

  /// No description provided for @ownerAssignExistingDeliveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to assign the selected delivery account.'**
  String get ownerAssignExistingDeliveryFailed;

  /// No description provided for @adminDashboardLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the admin dashboard data.'**
  String get adminDashboardLoadFailed;

  /// No description provided for @adminCreateUserFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the managed account.'**
  String get adminCreateUserFailed;

  /// No description provided for @adminApproveMerchantTermsFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to send the financial terms to the merchant.'**
  String get adminApproveMerchantTermsFailed;

  /// No description provided for @adminMerchantStatusUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the merchant status.'**
  String get adminMerchantStatusUpdateFailed;

  /// No description provided for @adminSettlementApproveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to approve the settlement.'**
  String get adminSettlementApproveFailed;

  /// No description provided for @adminDeliveryAccountApproveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to approve the delivery account.'**
  String get adminDeliveryAccountApproveFailed;

  /// No description provided for @adminTaxiCaptainAccountApproveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to approve the taxi captain account.'**
  String get adminTaxiCaptainAccountApproveFailed;

  /// No description provided for @adminDeliveryTypeUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the delivery type.'**
  String get adminDeliveryTypeUpdateFailed;

  /// No description provided for @adminTaxiSubscriptionConfirmFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to confirm the taxi captain subscription payment.'**
  String get adminTaxiSubscriptionConfirmFailed;

  /// No description provided for @adminTaxiSubscriptionDiscountUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the taxi captain discount.'**
  String get adminTaxiSubscriptionDiscountUpdateFailed;

  /// No description provided for @adminTaxiProfileEditApproveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to approve the taxi captain edit request.'**
  String get adminTaxiProfileEditApproveFailed;

  /// No description provided for @adminTaxiProfileEditRejectFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to reject the taxi captain edit request.'**
  String get adminTaxiProfileEditRejectFailed;

  /// No description provided for @adminCustomerInsightsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the customer insight records.'**
  String get adminCustomerInsightsLoadFailed;

  /// No description provided for @adminCustomerInsightDetailsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the customer insight details.'**
  String get adminCustomerInsightDetailsLoadFailed;

  /// No description provided for @adminAuditFeedLoadMoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load more audit log items.'**
  String get adminAuditFeedLoadMoreFailed;

  /// No description provided for @adminReceivablesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load receivables.'**
  String get adminReceivablesLoadFailed;

  /// No description provided for @adminMerchantReceivablesDetailsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the merchant receivables profile.'**
  String get adminMerchantReceivablesDetailsLoadFailed;

  /// No description provided for @adminPaymentReceivedApproveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to confirm the payment receipt.'**
  String get adminPaymentReceivedApproveFailed;

  /// No description provided for @adminPaymentRejectFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to reject the payment request.'**
  String get adminPaymentRejectFailed;

  /// No description provided for @adminPaymentApproveRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to approve the payment request.'**
  String get adminPaymentApproveRequestFailed;

  /// No description provided for @adminPaymentAssignExecutorFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to assign the settlement executor.'**
  String get adminPaymentAssignExecutorFailed;

  /// No description provided for @adminPaymentMarkPaidFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to record the payment operation.'**
  String get adminPaymentMarkPaidFailed;

  /// No description provided for @adminPaymentReturnForRevisionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to return the request for revision.'**
  String get adminPaymentReturnForRevisionFailed;

  /// No description provided for @adminPayablesAdjustmentCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to add the payables adjustment.'**
  String get adminPayablesAdjustmentCreateFailed;

  /// No description provided for @adminCompetitionDetailsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the competition details.'**
  String get adminCompetitionDetailsLoadFailed;

  /// No description provided for @adminCompetitionWinnersLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the winners list.'**
  String get adminCompetitionWinnersLoadFailed;

  /// No description provided for @adminCompetitionsEndFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to end the competition.'**
  String get adminCompetitionsEndFailed;

  /// No description provided for @adminFinancialKpisLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the financial KPIs.'**
  String get adminFinancialKpisLoadFailed;

  /// No description provided for @adminCreateUserSuccess.
  ///
  /// In en, this message translates to:
  /// **'The managed account was created successfully.'**
  String get adminCreateUserSuccess;

  /// No description provided for @adminApproveMerchantTermsSuccess.
  ///
  /// In en, this message translates to:
  /// **'The financial terms were sent to the merchant.'**
  String get adminApproveMerchantTermsSuccess;

  /// No description provided for @adminMerchantDisabledSuccess.
  ///
  /// In en, this message translates to:
  /// **'The merchant was disabled.'**
  String get adminMerchantDisabledSuccess;

  /// No description provided for @adminMerchantEnabledSuccess.
  ///
  /// In en, this message translates to:
  /// **'The merchant was enabled.'**
  String get adminMerchantEnabledSuccess;

  /// No description provided for @adminSettlementApproveSuccess.
  ///
  /// In en, this message translates to:
  /// **'The settlement was approved.'**
  String get adminSettlementApproveSuccess;

  /// No description provided for @adminDeliveryAccountApproveSuccess.
  ///
  /// In en, this message translates to:
  /// **'The delivery account was approved.'**
  String get adminDeliveryAccountApproveSuccess;

  /// No description provided for @adminTaxiCaptainAccountApproveSuccess.
  ///
  /// In en, this message translates to:
  /// **'The taxi captain account was approved.'**
  String get adminTaxiCaptainAccountApproveSuccess;

  /// No description provided for @adminDeliveryTypeUpdateSuccess.
  ///
  /// In en, this message translates to:
  /// **'The delivery type was updated successfully.'**
  String get adminDeliveryTypeUpdateSuccess;

  /// No description provided for @adminTaxiSubscriptionConfirmSuccess.
  ///
  /// In en, this message translates to:
  /// **'The taxi captain subscription payment was confirmed.'**
  String get adminTaxiSubscriptionConfirmSuccess;

  /// No description provided for @adminTaxiSubscriptionDiscountUpdateSuccess.
  ///
  /// In en, this message translates to:
  /// **'The taxi captain subscription discount was updated.'**
  String get adminTaxiSubscriptionDiscountUpdateSuccess;

  /// No description provided for @adminTaxiProfileEditApproveSuccess.
  ///
  /// In en, this message translates to:
  /// **'The taxi captain edit request was approved.'**
  String get adminTaxiProfileEditApproveSuccess;

  /// No description provided for @adminTaxiProfileEditRejectSuccess.
  ///
  /// In en, this message translates to:
  /// **'The taxi captain edit request was rejected.'**
  String get adminTaxiProfileEditRejectSuccess;

  /// No description provided for @adminMerchantBillingSaveSuccess.
  ///
  /// In en, this message translates to:
  /// **'The billing profile was updated successfully.'**
  String get adminMerchantBillingSaveSuccess;

  /// No description provided for @adminPaymentReceivedApproveSuccess.
  ///
  /// In en, this message translates to:
  /// **'The payment receipt was approved.'**
  String get adminPaymentReceivedApproveSuccess;

  /// No description provided for @adminPaymentRejectSuccess.
  ///
  /// In en, this message translates to:
  /// **'The payment request was rejected.'**
  String get adminPaymentRejectSuccess;

  /// No description provided for @adminPaymentApproveRequestSuccess.
  ///
  /// In en, this message translates to:
  /// **'The payment request was approved.'**
  String get adminPaymentApproveRequestSuccess;

  /// No description provided for @adminPaymentAssignExecutorSuccess.
  ///
  /// In en, this message translates to:
  /// **'The settlement executor was assigned.'**
  String get adminPaymentAssignExecutorSuccess;

  /// No description provided for @adminPaymentMarkPaidSuccess.
  ///
  /// In en, this message translates to:
  /// **'The payment was recorded and is pending merchant confirmation.'**
  String get adminPaymentMarkPaidSuccess;

  /// No description provided for @adminPaymentReturnForRevisionSuccess.
  ///
  /// In en, this message translates to:
  /// **'The request was returned for revision.'**
  String get adminPaymentReturnForRevisionSuccess;

  /// No description provided for @adminPayablesAdjustmentCreateSuccess.
  ///
  /// In en, this message translates to:
  /// **'The payables adjustment entry was added.'**
  String get adminPayablesAdjustmentCreateSuccess;

  /// No description provided for @adminCompetitionsCreateSuccess.
  ///
  /// In en, this message translates to:
  /// **'The competition was created.'**
  String get adminCompetitionsCreateSuccess;

  /// No description provided for @adminCompetitionsUpdateSuccess.
  ///
  /// In en, this message translates to:
  /// **'The competition was updated.'**
  String get adminCompetitionsUpdateSuccess;

  /// No description provided for @adminCompetitionsEndSuccess.
  ///
  /// In en, this message translates to:
  /// **'The competition was ended.'**
  String get adminCompetitionsEndSuccess;

  /// No description provided for @companyBranchDetailInventorySettingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save the inventory settings.'**
  String get companyBranchDetailInventorySettingsSaveFailed;

  /// No description provided for @companyBranchDetailItemSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the inventory item.'**
  String get companyBranchDetailItemSaveFailed;

  /// No description provided for @companyBranchDetailDailyCheckConfirmFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to confirm today\'s stock check.'**
  String get companyBranchDetailDailyCheckConfirmFailed;

  /// No description provided for @accountantOptionalNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get accountantOptionalNoteLabel;

  /// No description provided for @accountantDashboardLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the accountant dashboard.'**
  String get accountantDashboardLoadFailed;

  /// No description provided for @accountantSettlementConfirmSuccess.
  ///
  /// In en, this message translates to:
  /// **'The settlement was confirmed successfully.'**
  String get accountantSettlementConfirmSuccess;

  /// No description provided for @accountantSettlementConfirmFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to confirm the settlement.'**
  String get accountantSettlementConfirmFailed;

  /// No description provided for @accountantOpeningBalanceAddSuccess.
  ///
  /// In en, this message translates to:
  /// **'The opening balance was recorded.'**
  String get accountantOpeningBalanceAddSuccess;

  /// No description provided for @accountantOpeningBalanceAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to add the opening balance.'**
  String get accountantOpeningBalanceAddFailed;

  /// No description provided for @accountantExpenseAddSuccess.
  ///
  /// In en, this message translates to:
  /// **'The expense was recorded.'**
  String get accountantExpenseAddSuccess;

  /// No description provided for @accountantExpenseAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to record the expense.'**
  String get accountantExpenseAddFailed;

  /// No description provided for @accountantPayrollBatchOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open the payroll batch.'**
  String get accountantPayrollBatchOpenFailed;

  /// No description provided for @accountantPayrollBatchAcknowledgeSuccess.
  ///
  /// In en, this message translates to:
  /// **'The payroll batch was acknowledged.'**
  String get accountantPayrollBatchAcknowledgeSuccess;

  /// No description provided for @accountantPayrollBatchAcknowledgeFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to acknowledge the payroll batch.'**
  String get accountantPayrollBatchAcknowledgeFailed;

  /// No description provided for @accountantPayrollItemPaidSuccess.
  ///
  /// In en, this message translates to:
  /// **'The payroll item was marked as paid.'**
  String get accountantPayrollItemPaidSuccess;

  /// No description provided for @accountantPayrollItemPaidFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to mark the payroll item as paid.'**
  String get accountantPayrollItemPaidFailed;

  /// No description provided for @authRegisterBlockLabel.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get authRegisterBlockLabel;

  /// No description provided for @authRegisterBuildingNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get authRegisterBuildingNumberLabel;

  /// No description provided for @authRegisterApartmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Apartment'**
  String get authRegisterApartmentLabel;

  /// No description provided for @addMerchantOwnersLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the available owner accounts.'**
  String get addMerchantOwnersLoadFailed;

  /// No description provided for @addMerchantCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the store right now.'**
  String get addMerchantCreateFailed;

  /// No description provided for @addMerchantOwnerNotFound.
  ///
  /// In en, this message translates to:
  /// **'The selected owner account could not be found.'**
  String get addMerchantOwnerNotFound;

  /// No description provided for @addMerchantOwnerAlreadyLinked.
  ///
  /// In en, this message translates to:
  /// **'This owner account is already linked to another store.'**
  String get addMerchantOwnerAlreadyLinked;

  /// No description provided for @addMerchantOwnerConflict.
  ///
  /// In en, this message translates to:
  /// **'Choose an existing owner or create a new one, not both.'**
  String get addMerchantOwnerConflict;

  /// No description provided for @addMerchantOwnerSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Link store owner account'**
  String get addMerchantOwnerSectionTitle;

  /// No description provided for @addMerchantExistingOwnerOption.
  ///
  /// In en, this message translates to:
  /// **'Existing account'**
  String get addMerchantExistingOwnerOption;

  /// No description provided for @addMerchantNewOwnerOption.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get addMerchantNewOwnerOption;

  /// No description provided for @addMerchantNoOwnersAvailable.
  ///
  /// In en, this message translates to:
  /// **'No owner accounts are available for linking right now.'**
  String get addMerchantNoOwnersAvailable;

  /// No description provided for @addMerchantCreateNewOwnerAction.
  ///
  /// In en, this message translates to:
  /// **'Create a new store account'**
  String get addMerchantCreateNewOwnerAction;

  /// No description provided for @addMerchantOwnerAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Store owner account'**
  String get addMerchantOwnerAccountLabel;

  /// No description provided for @addMerchantOwnerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Store owner name'**
  String get addMerchantOwnerNameLabel;

  /// No description provided for @addMerchantOwnerPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Store owner phone'**
  String get addMerchantOwnerPhoneLabel;

  /// No description provided for @addMerchantOwnerImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Store owner image (optional)'**
  String get addMerchantOwnerImageTitle;

  /// No description provided for @addMerchantSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Store details'**
  String get addMerchantSectionTitle;

  /// No description provided for @addMerchantNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Store name'**
  String get addMerchantNameLabel;

  /// No description provided for @addMerchantTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Store type'**
  String get addMerchantTypeLabel;

  /// No description provided for @addMerchantActivityTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Store activity'**
  String get addMerchantActivityTypeLabel;

  /// No description provided for @addMerchantDiscoverySubcategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Discovery subcategory'**
  String get addMerchantDiscoverySubcategoryLabel;

  /// No description provided for @addMerchantDiscoverySubcategoriesLabel.
  ///
  /// In en, this message translates to:
  /// **'Choose one or more discovery categories'**
  String get addMerchantDiscoverySubcategoriesLabel;

  /// No description provided for @addMerchantDiscoverySelectAllLabel.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get addMerchantDiscoverySelectAllLabel;

  /// No description provided for @addMerchantDiscoverySelectAllHint.
  ///
  /// In en, this message translates to:
  /// **'Show this store in all current and upcoming discovery categories for this activity.'**
  String get addMerchantDiscoverySelectAllHint;

  /// No description provided for @addMerchantTypeRestaurant.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get addMerchantTypeRestaurant;

  /// No description provided for @addMerchantTypeMarket.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get addMerchantTypeMarket;

  /// No description provided for @addMerchantDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get addMerchantDescriptionLabel;

  /// No description provided for @addMerchantPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Store phone'**
  String get addMerchantPhoneLabel;

  /// No description provided for @addMerchantPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'If left empty, the owner phone will be used.'**
  String get addMerchantPhoneHint;

  /// No description provided for @addMerchantImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Store image (optional)'**
  String get addMerchantImageTitle;

  /// No description provided for @paidUpgradesPlansLabel.
  ///
  /// In en, this message translates to:
  /// **'Requested plans'**
  String get paidUpgradesPlansLabel;

  /// No description provided for @couponManagementCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Coupon code'**
  String get couponManagementCodeLabel;

  /// No description provided for @couponManagementDiscountTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Discount type'**
  String get couponManagementDiscountTypeLabel;

  /// No description provided for @couponManagementDiscountValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Discount value'**
  String get couponManagementDiscountValueLabel;

  /// No description provided for @couponManagementMinOrderTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Minimum order total'**
  String get couponManagementMinOrderTotalLabel;

  /// No description provided for @couponManagementMaxUsesLabel.
  ///
  /// In en, this message translates to:
  /// **'Maximum uses'**
  String get couponManagementMaxUsesLabel;

  /// No description provided for @couponManagementStartDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get couponManagementStartDateLabel;

  /// No description provided for @couponManagementEndDateLabel.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get couponManagementEndDateLabel;

  /// No description provided for @couponValidationPercentMax.
  ///
  /// In en, this message translates to:
  /// **'Percentage discounts must be 100 or less.'**
  String get couponValidationPercentMax;

  /// No description provided for @couponValidationDateRange.
  ///
  /// In en, this message translates to:
  /// **'The end date must be after the start date.'**
  String get couponValidationDateRange;

  /// No description provided for @couponManagementGlobalOnlyError.
  ///
  /// In en, this message translates to:
  /// **'Super admin coupons must remain global.'**
  String get couponManagementGlobalOnlyError;

  /// No description provided for @couponManagementCreatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'The coupon was created successfully.'**
  String get couponManagementCreatedSuccess;

  /// No description provided for @couponManagementCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create the coupon.'**
  String get couponManagementCreateFailed;

  /// No description provided for @couponManagementLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the coupons.'**
  String get couponManagementLoadFailed;

  /// No description provided for @couponManagementLoadStatsFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load coupon statistics.'**
  String get couponManagementLoadStatsFailed;

  /// No description provided for @couponManagementToggleFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update the coupon status.'**
  String get couponManagementToggleFailed;

  /// No description provided for @couponManagementDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete coupon'**
  String get couponManagementDeleteTitle;

  /// No description provided for @couponManagementDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this coupon?'**
  String get couponManagementDeleteMessage;

  /// No description provided for @couponManagementDeletedSuccess.
  ///
  /// In en, this message translates to:
  /// **'The coupon was deleted.'**
  String get couponManagementDeletedSuccess;

  /// No description provided for @couponManagementDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete the coupon.'**
  String get couponManagementDeleteFailed;

  /// No description provided for @couponManagementScopeAllMerchants.
  ///
  /// In en, this message translates to:
  /// **'Global for all merchants'**
  String get couponManagementScopeAllMerchants;

  /// No description provided for @couponManagementScopeMerchantNamed.
  ///
  /// In en, this message translates to:
  /// **'Merchant-specific: {name}'**
  String couponManagementScopeMerchantNamed(Object name);

  /// No description provided for @couponManagementScopeMerchantById.
  ///
  /// In en, this message translates to:
  /// **'Merchant-specific #{id}'**
  String couponManagementScopeMerchantById(int id);

  /// No description provided for @couponManagementTitleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin coupon management'**
  String get couponManagementTitleAdmin;

  /// No description provided for @couponManagementTitleOwner.
  ///
  /// In en, this message translates to:
  /// **'Store coupon management'**
  String get couponManagementTitleOwner;

  /// No description provided for @couponManagementCreateGlobalDescription.
  ///
  /// In en, this message translates to:
  /// **'Create a global coupon that works across all stores.'**
  String get couponManagementCreateGlobalDescription;

  /// No description provided for @couponManagementCreateOwnerDescription.
  ///
  /// In en, this message translates to:
  /// **'Create a coupon that applies only to your store.'**
  String get couponManagementCreateOwnerDescription;

  /// No description provided for @couponManagementCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Example: MASLAKI10'**
  String get couponManagementCodeHint;

  /// No description provided for @couponManagementCodeHintShort.
  ///
  /// In en, this message translates to:
  /// **'Example: AB123'**
  String get couponManagementCodeHintShort;

  /// No description provided for @couponManagementDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get couponManagementDescriptionLabel;

  /// No description provided for @couponManagementDiscountTypePercentOption.
  ///
  /// In en, this message translates to:
  /// **'Percentage %'**
  String get couponManagementDiscountTypePercentOption;

  /// No description provided for @couponManagementDiscountTypeFixedOption.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount'**
  String get couponManagementDiscountTypeFixedOption;

  /// No description provided for @couponManagementCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create coupon'**
  String get couponManagementCreateAction;

  /// No description provided for @couponManagementActiveOnly.
  ///
  /// In en, this message translates to:
  /// **'Show active coupons only'**
  String get couponManagementActiveOnly;

  /// No description provided for @couponManagementEmpty.
  ///
  /// In en, this message translates to:
  /// **'No coupons available right now.'**
  String get couponManagementEmpty;

  /// No description provided for @couponManagementCouponFallback.
  ///
  /// In en, this message translates to:
  /// **'Coupon #{id}'**
  String couponManagementCouponFallback(int id);

  /// No description provided for @couponManagementTypeLine.
  ///
  /// In en, this message translates to:
  /// **'Type: {value}'**
  String couponManagementTypeLine(Object value);

  /// No description provided for @couponManagementDiscountLine.
  ///
  /// In en, this message translates to:
  /// **'Discount: {value}'**
  String couponManagementDiscountLine(Object value);

  /// No description provided for @couponManagementMinOrderLine.
  ///
  /// In en, this message translates to:
  /// **'Minimum order: {value}'**
  String couponManagementMinOrderLine(Object value);

  /// No description provided for @couponManagementUsageLine.
  ///
  /// In en, this message translates to:
  /// **'Usage: {value}'**
  String couponManagementUsageLine(Object value);

  /// No description provided for @couponManagementScopeLine.
  ///
  /// In en, this message translates to:
  /// **'Scope: {value}'**
  String couponManagementScopeLine(Object value);

  /// No description provided for @productReviewsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the product reviews.'**
  String get productReviewsLoadFailed;

  /// No description provided for @productReviewsSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to submit the review.'**
  String get productReviewsSubmitFailed;

  /// No description provided for @productReviewsSelectRating.
  ///
  /// In en, this message translates to:
  /// **'Choose a rating from 1 to 5 stars.'**
  String get productReviewsSelectRating;

  /// No description provided for @productReviewsRatingLabel.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get productReviewsRatingLabel;

  /// No description provided for @productReviewsCommentLabel.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get productReviewsCommentLabel;

  /// No description provided for @productReviewsCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Optional comment...'**
  String get productReviewsCommentHint;

  /// No description provided for @productReviewsAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your review'**
  String get productReviewsAddTitle;

  /// No description provided for @productReviewsSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit review'**
  String get productReviewsSubmit;

  /// No description provided for @commonClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get commonClosed;

  /// No description provided for @merchantListPromoFastDeliveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Fast delivery inside Bismayah'**
  String get merchantListPromoFastDeliveryTitle;

  /// No description provided for @merchantListPromoFastDeliverySubtitle.
  ///
  /// In en, this message translates to:
  /// **'From the store to your door with clear and stable delivery fees.'**
  String get merchantListPromoFastDeliverySubtitle;

  /// No description provided for @merchantListPromoNeighborhoodTitle.
  ///
  /// In en, this message translates to:
  /// **'Neighborhood stores at your fingertips'**
  String get merchantListPromoNeighborhoodTitle;

  /// No description provided for @merchantListPromoNeighborhoodSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Everything you need daily, collected in one polished local marketplace.'**
  String get merchantListPromoNeighborhoodSubtitle;

  /// No description provided for @merchantListGreetingLateNight.
  ///
  /// In en, this message translates to:
  /// **'Late night picks'**
  String get merchantListGreetingLateNight;

  /// No description provided for @merchantListGreetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Busy morning'**
  String get merchantListGreetingMorning;

  /// No description provided for @merchantListGreetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Fast afternoon'**
  String get merchantListGreetingAfternoon;

  /// No description provided for @merchantListGreetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Lively evening'**
  String get merchantListGreetingEvening;

  /// No description provided for @merchantListGreetingBismayahNight.
  ///
  /// In en, this message translates to:
  /// **'Bismayah at night'**
  String get merchantListGreetingBismayahNight;

  /// No description provided for @merchantListPulsePeakDemand.
  ///
  /// In en, this message translates to:
  /// **'Peak demand'**
  String get merchantListPulsePeakDemand;

  /// No description provided for @merchantListPulseModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate activity'**
  String get merchantListPulseModerate;

  /// No description provided for @merchantListPulseCalm.
  ///
  /// In en, this message translates to:
  /// **'Calm activity'**
  String get merchantListPulseCalm;

  /// No description provided for @merchantListSpendingBandBudget.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get merchantListSpendingBandBudget;

  /// No description provided for @merchantListSpendingBandBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get merchantListSpendingBandBalanced;

  /// No description provided for @merchantListSpendingBandPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get merchantListSpendingBandPremium;

  /// No description provided for @merchantListSpendingBandNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get merchantListSpendingBandNew;

  /// No description provided for @merchantListPriceSensitivityHigh.
  ///
  /// In en, this message translates to:
  /// **'Highly price-sensitive'**
  String get merchantListPriceSensitivityHigh;

  /// No description provided for @merchantListPriceSensitivityLow.
  ///
  /// In en, this message translates to:
  /// **'Quality-focused'**
  String get merchantListPriceSensitivityLow;

  /// No description provided for @merchantListPriceSensitivityBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced preference'**
  String get merchantListPriceSensitivityBalanced;

  /// No description provided for @merchantListFastestDeliverySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ranked by actual delivery speed.'**
  String get merchantListFastestDeliverySubtitle;

  /// No description provided for @merchantListTopRatedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The strongest service and product quality based on customer ratings.'**
  String get merchantListTopRatedSubtitle;

  /// No description provided for @merchantListBestPriceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Best value between price and quality.'**
  String get merchantListBestPriceSubtitle;

  /// No description provided for @merchantListTodayOffersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Discounts and delivery perks that are active right now.'**
  String get merchantListTodayOffersSubtitle;

  /// No description provided for @merchantListMostOrderedTitle.
  ///
  /// In en, this message translates to:
  /// **'Most ordered'**
  String get merchantListMostOrderedTitle;

  /// No description provided for @merchantListMostOrderedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The most active stores among daily customers.'**
  String get merchantListMostOrderedSubtitle;

  /// No description provided for @merchantListReorderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Quick access to stores you already ordered from.'**
  String get merchantListReorderSubtitle;

  /// No description provided for @merchantListQuickStatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick states'**
  String get merchantListQuickStatesTitle;

  /// No description provided for @merchantListQuickStatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Jump straight into stores that are active right now.'**
  String get merchantListQuickStatesSubtitle;

  /// No description provided for @merchantListSuggestedTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggested for you'**
  String get merchantListSuggestedTitle;

  /// No description provided for @merchantListSuggestedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The strongest options based on availability and live offers.'**
  String get merchantListSuggestedSubtitle;

  /// No description provided for @merchantListRecentlyViewedTitle.
  ///
  /// In en, this message translates to:
  /// **'Recently viewed'**
  String get merchantListRecentlyViewedTitle;

  /// No description provided for @merchantListRecentlyViewedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Return quickly to stores you recently opened.'**
  String get merchantListRecentlyViewedSubtitle;

  /// No description provided for @merchantListRecentlyViewedShort.
  ///
  /// In en, this message translates to:
  /// **'Recently viewed'**
  String get merchantListRecentlyViewedShort;

  /// No description provided for @merchantListFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get merchantListFavorites;

  /// No description provided for @merchantListOpenNowOnlyToggle.
  ///
  /// In en, this message translates to:
  /// **'Show only stores that are open right now'**
  String get merchantListOpenNowOnlyToggle;

  /// No description provided for @merchantListDiscoveryModesTitle.
  ///
  /// In en, this message translates to:
  /// **'What fits your mood now?'**
  String get merchantListDiscoveryModesTitle;

  /// No description provided for @merchantListDiscoveryModeQuick.
  ///
  /// In en, this message translates to:
  /// **'Quick'**
  String get merchantListDiscoveryModeQuick;

  /// No description provided for @merchantListDiscoveryModeSavings.
  ///
  /// In en, this message translates to:
  /// **'Savings'**
  String get merchantListDiscoveryModeSavings;

  /// No description provided for @merchantListDiscoveryModeFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get merchantListDiscoveryModeFavorites;

  /// No description provided for @merchantListDiscoveryModeSurprise.
  ///
  /// In en, this message translates to:
  /// **'Surprise me'**
  String get merchantListDiscoveryModeSurprise;

  /// No description provided for @merchantListCategoryIntelTitle.
  ///
  /// In en, this message translates to:
  /// **'Category intelligence board'**
  String get merchantListCategoryIntelTitle;

  /// No description provided for @merchantListCategoryIntelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ranking is based on speed, ratings, price, and offers without distance bias.'**
  String get merchantListCategoryIntelSubtitle;

  /// No description provided for @merchantListPurchasingPower.
  ///
  /// In en, this message translates to:
  /// **'Purchasing power'**
  String get merchantListPurchasingPower;

  /// No description provided for @merchantListPricePreference.
  ///
  /// In en, this message translates to:
  /// **'Price preference'**
  String get merchantListPricePreference;

  /// No description provided for @merchantListTypeRestaurant.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get merchantListTypeRestaurant;

  /// No description provided for @merchantListTypeMarket.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get merchantListTypeMarket;

  /// No description provided for @merchantListCustomizeView.
  ///
  /// In en, this message translates to:
  /// **'Customize store view'**
  String get merchantListCustomizeView;

  /// No description provided for @merchantListSortRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get merchantListSortRecommended;

  /// No description provided for @merchantListSortOpenFirst.
  ///
  /// In en, this message translates to:
  /// **'Open first'**
  String get merchantListSortOpenFirst;

  /// No description provided for @merchantListSortOffersFirst.
  ///
  /// In en, this message translates to:
  /// **'Best offers'**
  String get merchantListSortOffersFirst;

  /// No description provided for @merchantListSortAlphabetical.
  ///
  /// In en, this message translates to:
  /// **'Alphabetical'**
  String get merchantListSortAlphabetical;

  /// No description provided for @merchantListFavoritesOnly.
  ///
  /// In en, this message translates to:
  /// **'Favorites only'**
  String get merchantListFavoritesOnly;

  /// No description provided for @merchantListCategoryIntelLoading.
  ///
  /// In en, this message translates to:
  /// **'Building the smart merchant ranking for this category...'**
  String get merchantListCategoryIntelLoading;

  /// No description provided for @merchantListCategoryIntelLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load the smart merchant ranking. Try again.'**
  String get merchantListCategoryIntelLoadFailed;

  /// No description provided for @merchantListAddressesLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading addresses...'**
  String get merchantListAddressesLoading;

  /// No description provided for @merchantListAddressesAddToStart.
  ///
  /// In en, this message translates to:
  /// **'Add a delivery address to get started'**
  String get merchantListAddressesAddToStart;

  /// No description provided for @merchantListAddressesChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose a delivery address'**
  String get merchantListAddressesChoose;

  /// No description provided for @merchantListCardFallbackDescription.
  ///
  /// In en, this message translates to:
  /// **'A store from the heart of Bismayah'**
  String get merchantListCardFallbackDescription;

  /// No description provided for @merchantListBadgeDiscounts.
  ///
  /// In en, this message translates to:
  /// **'Discount offers'**
  String get merchantListBadgeDiscounts;

  /// No description provided for @merchantListBadgeFreeDelivery.
  ///
  /// In en, this message translates to:
  /// **'Free delivery'**
  String get merchantListBadgeFreeDelivery;

  /// No description provided for @merchantListEtaMinutesRange.
  ///
  /// In en, this message translates to:
  /// **'{min} - {max} min'**
  String merchantListEtaMinutesRange(int min, int max);

  /// No description provided for @merchantListEtaClosed.
  ///
  /// In en, this message translates to:
  /// **'Outside working hours'**
  String get merchantListEtaClosed;

  /// No description provided for @merchantListStatusOpenNow.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get merchantListStatusOpenNow;

  /// No description provided for @merchantListStatusClosedNow.
  ///
  /// In en, this message translates to:
  /// **'Closed now'**
  String get merchantListStatusClosedNow;

  /// No description provided for @mapPageBidAccepted.
  ///
  /// In en, this message translates to:
  /// **'The captain offer was accepted.'**
  String get mapPageBidAccepted;

  /// No description provided for @mapPageBidAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to accept the current offer right now.'**
  String get mapPageBidAcceptFailed;

  /// No description provided for @mapPageBidRejected.
  ///
  /// In en, this message translates to:
  /// **'The current offer was skipped and the next one is now active.'**
  String get mapPageBidRejected;

  /// No description provided for @mapPageBidRejectFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to reject the current offer.'**
  String get mapPageBidRejectFailed;

  /// No description provided for @mapPageActiveRideEditBlocked.
  ///
  /// In en, this message translates to:
  /// **'You already have an active ride, so the route points cannot be changed right now.'**
  String get mapPageActiveRideEditBlocked;

  /// No description provided for @mapPageApiActiveRideExists.
  ///
  /// In en, this message translates to:
  /// **'You already have an active ride. Finish it or cancel it first.'**
  String get mapPageApiActiveRideExists;

  /// No description provided for @mapPageApiRideNotAcceptingBids.
  ///
  /// In en, this message translates to:
  /// **'This ride request is no longer accepting offers.'**
  String get mapPageApiRideNotAcceptingBids;

  /// No description provided for @mapPageApiRideOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'The captain is outside the request range.'**
  String get mapPageApiRideOutOfRange;

  /// No description provided for @mapPageApiNoActiveBid.
  ///
  /// In en, this message translates to:
  /// **'There is no active offer right now. Wait for the next one.'**
  String get mapPageApiNoActiveBid;

  /// No description provided for @mapPageApiChatEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'An empty message cannot be sent.'**
  String get mapPageApiChatEmptyMessage;

  /// No description provided for @mapPageApiChatClosed.
  ///
  /// In en, this message translates to:
  /// **'Ride chat is available only during negotiation or while the ride is active.'**
  String get mapPageApiChatClosed;

  /// No description provided for @mapPageApiRideNotCompleted.
  ///
  /// In en, this message translates to:
  /// **'The ride must be completed before it can be rated.'**
  String get mapPageApiRideNotCompleted;

  /// No description provided for @mapPageApiRideCaptainNotFound.
  ///
  /// In en, this message translates to:
  /// **'No captain is linked to this ride.'**
  String get mapPageApiRideCaptainNotFound;

  /// No description provided for @taxiToolsTitle.
  ///
  /// In en, this message translates to:
  /// **'Taxi Tools'**
  String get taxiToolsTitle;

  /// No description provided for @taxiSavedPlacesTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved Places'**
  String get taxiSavedPlacesTitle;

  /// No description provided for @taxiFavoriteTripsTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorite Trips'**
  String get taxiFavoriteTripsTitle;

  /// No description provided for @taxiScheduledRidesTitle.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Rides'**
  String get taxiScheduledRidesTitle;

  /// No description provided for @taxiMyCouponsTitle.
  ///
  /// In en, this message translates to:
  /// **'My Taxi Coupons'**
  String get taxiMyCouponsTitle;

  /// No description provided for @taxiSavedPlacesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load saved places.'**
  String get taxiSavedPlacesLoadFailed;

  /// No description provided for @taxiSavedPlacesImport.
  ///
  /// In en, this message translates to:
  /// **'Import delivery addresses'**
  String get taxiSavedPlacesImport;

  /// No description provided for @taxiSavedPlacesImported.
  ///
  /// In en, this message translates to:
  /// **'Saved places were imported.'**
  String get taxiSavedPlacesImported;

  /// No description provided for @taxiSavedPlacesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No saved places yet.'**
  String get taxiSavedPlacesEmpty;

  /// No description provided for @taxiFavoriteTripsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load favorite trips.'**
  String get taxiFavoriteTripsLoadFailed;

  /// No description provided for @taxiFavoriteTripsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No favorite trips yet.'**
  String get taxiFavoriteTripsEmpty;

  /// No description provided for @taxiScheduledRidesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load scheduled rides.'**
  String get taxiScheduledRidesLoadFailed;

  /// No description provided for @taxiScheduledRidesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No scheduled rides yet.'**
  String get taxiScheduledRidesEmpty;

  /// No description provided for @taxiScheduledRidesWhen.
  ///
  /// In en, this message translates to:
  /// **'Scheduled at'**
  String get taxiScheduledRidesWhen;

  /// No description provided for @taxiMyCouponsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load taxi coupons.'**
  String get taxiMyCouponsLoadFailed;

  /// No description provided for @taxiCouponCodeField.
  ///
  /// In en, this message translates to:
  /// **'Coupon code'**
  String get taxiCouponCodeField;

  /// No description provided for @taxiCouponCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter coupon code if available'**
  String get taxiCouponCodeHint;

  /// No description provided for @taxiFareLabel.
  ///
  /// In en, this message translates to:
  /// **'Fare (IQD)'**
  String get taxiFareLabel;

  /// No description provided for @taxiCouponPreviewAction.
  ///
  /// In en, this message translates to:
  /// **'Preview coupon'**
  String get taxiCouponPreviewAction;

  /// No description provided for @taxiCouponOriginalFare.
  ///
  /// In en, this message translates to:
  /// **'Original fare'**
  String get taxiCouponOriginalFare;

  /// No description provided for @taxiCouponDiscountValue.
  ///
  /// In en, this message translates to:
  /// **'Discount value'**
  String get taxiCouponDiscountValue;

  /// No description provided for @taxiCouponFinalFare.
  ///
  /// In en, this message translates to:
  /// **'Final fare'**
  String get taxiCouponFinalFare;

  /// No description provided for @taxiMyCouponsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No active taxi coupons right now.'**
  String get taxiMyCouponsEmpty;

  /// No description provided for @taxiCouponRemainingUses.
  ///
  /// In en, this message translates to:
  /// **'Remaining uses'**
  String get taxiCouponRemainingUses;

  /// No description provided for @taxiCaptainLoyaltyTitle.
  ///
  /// In en, this message translates to:
  /// **'Captain Loyalty & Credits'**
  String get taxiCaptainLoyaltyTitle;

  /// No description provided for @taxiCaptainLoyaltyLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load captain loyalty data.'**
  String get taxiCaptainLoyaltyLoadFailed;

  /// No description provided for @taxiCaptainSubscriptionSummary.
  ///
  /// In en, this message translates to:
  /// **'Subscription Summary'**
  String get taxiCaptainSubscriptionSummary;

  /// No description provided for @taxiCaptainMonthlySubscription.
  ///
  /// In en, this message translates to:
  /// **'Monthly subscription'**
  String get taxiCaptainMonthlySubscription;

  /// No description provided for @taxiCaptainApprovedCredits.
  ///
  /// In en, this message translates to:
  /// **'Approved credits'**
  String get taxiCaptainApprovedCredits;

  /// No description provided for @taxiCaptainPayableAmount.
  ///
  /// In en, this message translates to:
  /// **'Payable amount'**
  String get taxiCaptainPayableAmount;

  /// No description provided for @taxiCaptainGovernanceStatus.
  ///
  /// In en, this message translates to:
  /// **'Captain status'**
  String get taxiCaptainGovernanceStatus;

  /// No description provided for @taxiCaptainWarningsCount.
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get taxiCaptainWarningsCount;

  /// No description provided for @taxiCaptainLedgerTitle.
  ///
  /// In en, this message translates to:
  /// **'Credit Ledger'**
  String get taxiCaptainLedgerTitle;

  /// No description provided for @taxiCaptainContestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Captain Contests'**
  String get taxiCaptainContestsTitle;

  /// No description provided for @taxiCaptainRewardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get taxiCaptainRewardsTitle;

  /// No description provided for @adminTaxiGovernanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Taxi Governance'**
  String get adminTaxiGovernanceTitle;

  /// No description provided for @adminTaxiGovernanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Coupons, contests, complaints and KPI'**
  String get adminTaxiGovernanceSubtitle;

  /// No description provided for @adminTaxiGovernanceLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load taxi governance data.'**
  String get adminTaxiGovernanceLoadFailed;

  /// No description provided for @adminTaxiKpiOverview.
  ///
  /// In en, this message translates to:
  /// **'Taxi KPI Overview'**
  String get adminTaxiKpiOverview;

  /// No description provided for @adminTaxiKpiTotalRides.
  ///
  /// In en, this message translates to:
  /// **'Total rides'**
  String get adminTaxiKpiTotalRides;

  /// No description provided for @adminTaxiKpiCompletedRides.
  ///
  /// In en, this message translates to:
  /// **'Completed rides'**
  String get adminTaxiKpiCompletedRides;

  /// No description provided for @adminTaxiKpiOpenComplaints.
  ///
  /// In en, this message translates to:
  /// **'Open complaints'**
  String get adminTaxiKpiOpenComplaints;

  /// No description provided for @adminTaxiCouponsTitle.
  ///
  /// In en, this message translates to:
  /// **'Taxi Coupons'**
  String get adminTaxiCouponsTitle;

  /// No description provided for @adminTaxiContestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Captain Contests'**
  String get adminTaxiContestsTitle;

  /// No description provided for @adminTaxiComplaintsTitle.
  ///
  /// In en, this message translates to:
  /// **'Captain Complaints'**
  String get adminTaxiComplaintsTitle;

  /// No description provided for @mapPageSavedPlacesAction.
  ///
  /// In en, this message translates to:
  /// **'Saved places'**
  String get mapPageSavedPlacesAction;

  /// No description provided for @mapPageFavoriteTripsAction.
  ///
  /// In en, this message translates to:
  /// **'Favorite trips'**
  String get mapPageFavoriteTripsAction;

  /// No description provided for @mapPageSaveAsFavoriteAction.
  ///
  /// In en, this message translates to:
  /// **'Save route'**
  String get mapPageSaveAsFavoriteAction;

  /// No description provided for @mapPageFavoriteSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save favorite trip'**
  String get mapPageFavoriteSaveTitle;

  /// No description provided for @mapPageFavoriteLabelField.
  ///
  /// In en, this message translates to:
  /// **'Trip label'**
  String get mapPageFavoriteLabelField;

  /// No description provided for @mapPageFavoriteTripSaved.
  ///
  /// In en, this message translates to:
  /// **'Favorite trip saved.'**
  String get mapPageFavoriteTripSaved;

  /// No description provided for @mapPageFavoriteTripApplied.
  ///
  /// In en, this message translates to:
  /// **'Favorite trip loaded.'**
  String get mapPageFavoriteTripApplied;

  /// No description provided for @mapPageScheduleSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Ride timing'**
  String get mapPageScheduleSectionTitle;

  /// No description provided for @mapPageScheduleModeNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get mapPageScheduleModeNow;

  /// No description provided for @mapPageScheduleModeLater.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get mapPageScheduleModeLater;

  /// No description provided for @mapPageScheduleChooseTime.
  ///
  /// In en, this message translates to:
  /// **'Choose date and time'**
  String get mapPageScheduleChooseTime;

  /// No description provided for @mapPageSchedulePickTimeAction.
  ///
  /// In en, this message translates to:
  /// **'Pick time'**
  String get mapPageSchedulePickTimeAction;

  /// No description provided for @mapPageScheduleInPast.
  ///
  /// In en, this message translates to:
  /// **'The scheduled time must be in the future.'**
  String get mapPageScheduleInPast;

  /// No description provided for @mapPageScheduleRideSubmit.
  ///
  /// In en, this message translates to:
  /// **'Schedule ride'**
  String get mapPageScheduleRideSubmit;

  /// No description provided for @mapPageScheduledRideCreated.
  ///
  /// In en, this message translates to:
  /// **'Ride scheduled for {when}.'**
  String mapPageScheduledRideCreated(Object when);

  /// No description provided for @mapPageCaptainRatingLine.
  ///
  /// In en, this message translates to:
  /// **'{rating} - {rides} rides'**
  String mapPageCaptainRatingLine(Object rating, Object rides);

  /// No description provided for @mapPageComplaintAction.
  ///
  /// In en, this message translates to:
  /// **'Submit complaint'**
  String get mapPageComplaintAction;

  /// No description provided for @mapPageComplaintTitle.
  ///
  /// In en, this message translates to:
  /// **'Captain complaint'**
  String get mapPageComplaintTitle;

  /// No description provided for @mapPageComplaintCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Complaint category'**
  String get mapPageComplaintCategoryLabel;

  /// No description provided for @mapPageComplaintReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get mapPageComplaintReasonLabel;

  /// No description provided for @mapPageComplaintDetailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Details (optional)'**
  String get mapPageComplaintDetailsLabel;

  /// No description provided for @mapPageComplaintSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit complaint'**
  String get mapPageComplaintSubmit;

  /// No description provided for @mapPageComplaintSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Complaint submitted successfully.'**
  String get mapPageComplaintSubmitted;

  /// No description provided for @mapPageComplaintSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to submit complaint right now.'**
  String get mapPageComplaintSubmitFailed;

  /// No description provided for @mapPageComplaintNotEligible.
  ///
  /// In en, this message translates to:
  /// **'Complaint is available only for recent completed rides.'**
  String get mapPageComplaintNotEligible;

  /// No description provided for @mapPageComplaintEligibilityFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to verify complaint eligibility.'**
  String get mapPageComplaintEligibilityFailed;

  /// No description provided for @taxiComplaintCategoryBadBehavior.
  ///
  /// In en, this message translates to:
  /// **'Bad behavior'**
  String get taxiComplaintCategoryBadBehavior;

  /// No description provided for @taxiComplaintCategoryDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay'**
  String get taxiComplaintCategoryDelay;

  /// No description provided for @taxiComplaintCategoryFare.
  ///
  /// In en, this message translates to:
  /// **'Fare dispute'**
  String get taxiComplaintCategoryFare;

  /// No description provided for @taxiComplaintCategoryRoute.
  ///
  /// In en, this message translates to:
  /// **'Route issue'**
  String get taxiComplaintCategoryRoute;

  /// No description provided for @taxiComplaintCategoryCleanliness.
  ///
  /// In en, this message translates to:
  /// **'Vehicle cleanliness'**
  String get taxiComplaintCategoryCleanliness;

  /// No description provided for @taxiComplaintCategoryDriving.
  ///
  /// In en, this message translates to:
  /// **'Driving quality'**
  String get taxiComplaintCategoryDriving;

  /// No description provided for @taxiComplaintCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get taxiComplaintCategoryOther;

  /// No description provided for @taxiSavedPlacesAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add place'**
  String get taxiSavedPlacesAddAction;

  /// No description provided for @taxiSavedPlaceCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Add saved place'**
  String get taxiSavedPlaceCreateTitle;

  /// No description provided for @taxiSavedPlaceLabelField.
  ///
  /// In en, this message translates to:
  /// **'Place label'**
  String get taxiSavedPlaceLabelField;

  /// No description provided for @taxiSavedPlaceTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Place type'**
  String get taxiSavedPlaceTypeLabel;

  /// No description provided for @taxiSavedPlaceTypeHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get taxiSavedPlaceTypeHome;

  /// No description provided for @taxiSavedPlaceTypeWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get taxiSavedPlaceTypeWork;

  /// No description provided for @taxiSavedPlaceTypeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get taxiSavedPlaceTypeCustom;

  /// No description provided for @taxiSavedPlaceAddressField.
  ///
  /// In en, this message translates to:
  /// **'Address text'**
  String get taxiSavedPlaceAddressField;

  /// No description provided for @taxiSavedPlaceLatitudeField.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get taxiSavedPlaceLatitudeField;

  /// No description provided for @taxiSavedPlaceLongitudeField.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get taxiSavedPlaceLongitudeField;

  /// No description provided for @taxiSavedPlaceSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save the place.'**
  String get taxiSavedPlaceSaveFailed;

  /// No description provided for @taxiSavedPlaceSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved place was added.'**
  String get taxiSavedPlaceSaved;

  /// No description provided for @taxiSavedPlaceDeleted.
  ///
  /// In en, this message translates to:
  /// **'Saved place was deleted.'**
  String get taxiSavedPlaceDeleted;

  /// No description provided for @taxiToolsOpenAsPickup.
  ///
  /// In en, this message translates to:
  /// **'Open as pickup'**
  String get taxiToolsOpenAsPickup;

  /// No description provided for @taxiToolsOpenAsDropoff.
  ///
  /// In en, this message translates to:
  /// **'Open as dropoff'**
  String get taxiToolsOpenAsDropoff;

  /// No description provided for @taxiFavoriteTripUseNow.
  ///
  /// In en, this message translates to:
  /// **'Use now'**
  String get taxiFavoriteTripUseNow;

  /// No description provided for @taxiScheduledRideCancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get taxiScheduledRideCancelAction;

  /// No description provided for @taxiScheduledRideCancelSuccess.
  ///
  /// In en, this message translates to:
  /// **'Scheduled ride was cancelled.'**
  String get taxiScheduledRideCancelSuccess;

  /// No description provided for @commonRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get commonRating;

  /// No description provided for @adminTaxiCashPaymentsReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review cash payment'**
  String get adminTaxiCashPaymentsReviewTitle;

  /// No description provided for @adminTaxiCashPaymentsCycleDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Cycle days'**
  String get adminTaxiCashPaymentsCycleDaysLabel;

  /// No description provided for @adminTaxiCashPaymentsApplyAndConfirm.
  ///
  /// In en, this message translates to:
  /// **'Apply and confirm'**
  String get adminTaxiCashPaymentsApplyAndConfirm;

  /// No description provided for @adminTaxiCaptainDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Captain details'**
  String get adminTaxiCaptainDetailsTitle;

  /// No description provided for @adminTaxiCaptainDetailsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load captain details.'**
  String get adminTaxiCaptainDetailsLoadFailed;

  /// No description provided for @adminTaxiCaptainDetailsActionsSection.
  ///
  /// In en, this message translates to:
  /// **'Captain actions'**
  String get adminTaxiCaptainDetailsActionsSection;

  /// No description provided for @adminTaxiCaptainDetailsSubscriptionSection.
  ///
  /// In en, this message translates to:
  /// **'Subscription summary'**
  String get adminTaxiCaptainDetailsSubscriptionSection;

  /// No description provided for @adminTaxiCaptainDetailsLedgerSection.
  ///
  /// In en, this message translates to:
  /// **'Credit ledger'**
  String get adminTaxiCaptainDetailsLedgerSection;

  /// No description provided for @adminTaxiCaptainDetailsWarningsSection.
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get adminTaxiCaptainDetailsWarningsSection;

  /// No description provided for @adminTaxiCaptainDetailsComplaintsSection.
  ///
  /// In en, this message translates to:
  /// **'Complaints'**
  String get adminTaxiCaptainDetailsComplaintsSection;

  /// No description provided for @adminTaxiCaptainDetailsStatusHistorySection.
  ///
  /// In en, this message translates to:
  /// **'Status history'**
  String get adminTaxiCaptainDetailsStatusHistorySection;

  /// No description provided for @adminTaxiCaptainDetailsRidesSection.
  ///
  /// In en, this message translates to:
  /// **'Recent rides'**
  String get adminTaxiCaptainDetailsRidesSection;

  /// No description provided for @adminTaxiCaptainDetailsIssueGift.
  ///
  /// In en, this message translates to:
  /// **'Issue gift or credit'**
  String get adminTaxiCaptainDetailsIssueGift;

  /// No description provided for @adminTaxiCaptainDetailsIssueWarning.
  ///
  /// In en, this message translates to:
  /// **'Issue warning'**
  String get adminTaxiCaptainDetailsIssueWarning;

  /// No description provided for @adminTaxiCaptainDetailsUpdateStatus.
  ///
  /// In en, this message translates to:
  /// **'Update status'**
  String get adminTaxiCaptainDetailsUpdateStatus;

  /// No description provided for @adminTaxiCaptainDetailsRewardType.
  ///
  /// In en, this message translates to:
  /// **'Reward type'**
  String get adminTaxiCaptainDetailsRewardType;

  /// No description provided for @adminTaxiCaptainDetailsSeverity.
  ///
  /// In en, this message translates to:
  /// **'Severity'**
  String get adminTaxiCaptainDetailsSeverity;

  /// No description provided for @adminTaxiCaptainDetailsStatusEffect.
  ///
  /// In en, this message translates to:
  /// **'Status effect'**
  String get adminTaxiCaptainDetailsStatusEffect;

  /// No description provided for @adminTaxiCaptainDetailsNoStatusEffect.
  ///
  /// In en, this message translates to:
  /// **'No status effect'**
  String get adminTaxiCaptainDetailsNoStatusEffect;

  /// No description provided for @adminTaxiCaptainDetailsReasonCode.
  ///
  /// In en, this message translates to:
  /// **'Reason code'**
  String get adminTaxiCaptainDetailsReasonCode;

  /// No description provided for @adminTaxiCaptainDetailsReasonText.
  ///
  /// In en, this message translates to:
  /// **'Reason details'**
  String get adminTaxiCaptainDetailsReasonText;

  /// No description provided for @adminTaxiCaptainDetailsAdminNote.
  ///
  /// In en, this message translates to:
  /// **'Admin note'**
  String get adminTaxiCaptainDetailsAdminNote;

  /// No description provided for @adminTaxiCaptainDetailsSuspendedUntil.
  ///
  /// In en, this message translates to:
  /// **'Suspended until'**
  String get adminTaxiCaptainDetailsSuspendedUntil;

  /// No description provided for @adminTaxiCaptainDetailsNoExpiry.
  ///
  /// In en, this message translates to:
  /// **'No end date'**
  String get adminTaxiCaptainDetailsNoExpiry;

  /// No description provided for @adminTaxiCaptainDetailsPickDateTime.
  ///
  /// In en, this message translates to:
  /// **'Pick date and time'**
  String get adminTaxiCaptainDetailsPickDateTime;

  /// No description provided for @adminTaxiCaptainStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get adminTaxiCaptainStatusActive;

  /// No description provided for @adminTaxiCaptainStatusWarned.
  ///
  /// In en, this message translates to:
  /// **'Warned'**
  String get adminTaxiCaptainStatusWarned;

  /// No description provided for @adminTaxiCaptainStatusTemporarilySuspended.
  ///
  /// In en, this message translates to:
  /// **'Temporarily suspended'**
  String get adminTaxiCaptainStatusTemporarilySuspended;

  /// No description provided for @adminTaxiCaptainStatusUnderReview.
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get adminTaxiCaptainStatusUnderReview;

  /// No description provided for @adminTaxiCaptainStatusBanned.
  ///
  /// In en, this message translates to:
  /// **'Banned'**
  String get adminTaxiCaptainStatusBanned;

  /// No description provided for @adminTaxiCaptainRewardTypeCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get adminTaxiCaptainRewardTypeCredit;

  /// No description provided for @adminTaxiCaptainRewardTypeCashEquivalent.
  ///
  /// In en, this message translates to:
  /// **'Cash equivalent'**
  String get adminTaxiCaptainRewardTypeCashEquivalent;

  /// No description provided for @adminTaxiCaptainRewardTypeSubscriptionDiscount.
  ///
  /// In en, this message translates to:
  /// **'Subscription discount'**
  String get adminTaxiCaptainRewardTypeSubscriptionDiscount;

  /// No description provided for @adminTaxiCaptainRewardTypeGift.
  ///
  /// In en, this message translates to:
  /// **'Gift'**
  String get adminTaxiCaptainRewardTypeGift;

  /// No description provided for @adminTaxiCaptainWarningSeverityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get adminTaxiCaptainWarningSeverityLow;

  /// No description provided for @adminTaxiCaptainWarningSeverityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get adminTaxiCaptainWarningSeverityMedium;

  /// No description provided for @adminTaxiCaptainWarningSeverityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get adminTaxiCaptainWarningSeverityHigh;

  /// No description provided for @adminTaxiCaptainWarningSeverityCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get adminTaxiCaptainWarningSeverityCritical;

  /// No description provided for @taxiCaptainAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Maslaki Captain'**
  String get taxiCaptainAppTitle;

  /// No description provided for @deliveryAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Maslaki Delivery'**
  String get deliveryAppTitle;

  /// No description provided for @adminOpsDrawerGroup.
  ///
  /// In en, this message translates to:
  /// **'Operations Centers'**
  String get adminOpsDrawerGroup;

  /// No description provided for @adminOpsNotificationCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification Center'**
  String get adminOpsNotificationCenterTitle;

  /// No description provided for @adminOpsNotificationCenterDescription.
  ///
  /// In en, this message translates to:
  /// **'Critical alerts and unresolved operational events.'**
  String get adminOpsNotificationCenterDescription;

  /// No description provided for @adminOpsNotificationCenterLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load operational alerts.'**
  String get adminOpsNotificationCenterLoadFailed;

  /// No description provided for @adminOpsNotificationCenterEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no operational alerts right now.'**
  String get adminOpsNotificationCenterEmpty;

  /// No description provided for @adminOpsNotificationCenterUntitled.
  ///
  /// In en, this message translates to:
  /// **'Operational alert'**
  String get adminOpsNotificationCenterUntitled;

  /// No description provided for @adminOpsNotificationCenterAckFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update alert status.'**
  String get adminOpsNotificationCenterAckFailed;

  /// No description provided for @adminOpsFilterStatus.
  ///
  /// In en, this message translates to:
  /// **'Status filter'**
  String get adminOpsFilterStatus;

  /// No description provided for @adminOpsFilterSeverity.
  ///
  /// In en, this message translates to:
  /// **'Severity filter'**
  String get adminOpsFilterSeverity;

  /// No description provided for @adminOpsSeverityCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get adminOpsSeverityCritical;

  /// No description provided for @adminOpsSeverityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get adminOpsSeverityHigh;

  /// No description provided for @adminOpsSeverityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get adminOpsSeverityMedium;

  /// No description provided for @adminOpsSeverityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get adminOpsSeverityLow;

  /// No description provided for @adminOpsSeverityInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get adminOpsSeverityInfo;

  /// No description provided for @adminOpsStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get adminOpsStatusOpen;

  /// No description provided for @adminOpsStatusAcknowledged.
  ///
  /// In en, this message translates to:
  /// **'Acknowledged'**
  String get adminOpsStatusAcknowledged;

  /// No description provided for @adminOpsStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get adminOpsStatusResolved;

  /// No description provided for @adminOpsStatusIgnored.
  ///
  /// In en, this message translates to:
  /// **'Ignored'**
  String get adminOpsStatusIgnored;

  /// No description provided for @adminOpsFieldSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get adminOpsFieldSource;

  /// No description provided for @adminOpsFieldType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get adminOpsFieldType;

  /// No description provided for @adminOpsActionAcknowledge.
  ///
  /// In en, this message translates to:
  /// **'Acknowledge'**
  String get adminOpsActionAcknowledge;

  /// No description provided for @adminOpsActionResolve.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get adminOpsActionResolve;

  /// No description provided for @adminOpsNotificationsOperationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications Operations'**
  String get adminOpsNotificationsOperationsTitle;

  /// No description provided for @adminOpsNotificationsOperationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Delivery reliability, retries, failures, and latency.'**
  String get adminOpsNotificationsOperationsDescription;

  /// No description provided for @adminOpsNotificationsOperationsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load notification operations overview.'**
  String get adminOpsNotificationsOperationsLoadFailed;

  /// No description provided for @adminOpsWindowHours.
  ///
  /// In en, this message translates to:
  /// **'Last {hours}h'**
  String adminOpsWindowHours(int hours);

  /// No description provided for @adminOpsDeliverySent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get adminOpsDeliverySent;

  /// No description provided for @adminOpsDeliveryRetry.
  ///
  /// In en, this message translates to:
  /// **'Retries'**
  String get adminOpsDeliveryRetry;

  /// No description provided for @adminOpsDeliveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get adminOpsDeliveryFailed;

  /// No description provided for @adminOpsDeliveryDeadTokens.
  ///
  /// In en, this message translates to:
  /// **'Dead tokens'**
  String get adminOpsDeliveryDeadTokens;

  /// No description provided for @adminOpsLatencyTitle.
  ///
  /// In en, this message translates to:
  /// **'Push delivery latency'**
  String get adminOpsLatencyTitle;

  /// No description provided for @adminOpsLatencyAverage.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get adminOpsLatencyAverage;

  /// No description provided for @adminOpsLatencyP95.
  ///
  /// In en, this message translates to:
  /// **'P95'**
  String get adminOpsLatencyP95;

  /// No description provided for @adminOpsTopErrorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Top delivery errors'**
  String get adminOpsTopErrorsTitle;

  /// No description provided for @adminOpsTopErrorsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No delivery errors in this window.'**
  String get adminOpsTopErrorsEmpty;

  /// No description provided for @adminOpsDeviceReliabilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Device Reliability'**
  String get adminOpsDeviceReliabilityTitle;

  /// No description provided for @adminOpsDeviceReliabilityDescription.
  ///
  /// In en, this message translates to:
  /// **'Token health, delivery status, and repeated failures per device.'**
  String get adminOpsDeviceReliabilityDescription;

  /// No description provided for @adminOpsDeviceReliabilityLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load device reliability data.'**
  String get adminOpsDeviceReliabilityLoadFailed;

  /// No description provided for @adminOpsDeviceReliabilityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No device reliability records found.'**
  String get adminOpsDeviceReliabilityEmpty;

  /// No description provided for @adminOpsDeviceReliabilitySuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get adminOpsDeviceReliabilitySuccess;

  /// No description provided for @adminOpsDeviceReliabilityFailures.
  ///
  /// In en, this message translates to:
  /// **'Failures'**
  String get adminOpsDeviceReliabilityFailures;

  /// No description provided for @adminOpsCrashCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Crash & Error Center'**
  String get adminOpsCrashCenterTitle;

  /// No description provided for @adminOpsCrashCenterDescription.
  ///
  /// In en, this message translates to:
  /// **'Captured crash events, platform failures, and stack traces.'**
  String get adminOpsCrashCenterDescription;

  /// No description provided for @adminOpsCrashCenterLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load crash events.'**
  String get adminOpsCrashCenterLoadFailed;

  /// No description provided for @adminOpsCrashCenterPlatformFilter.
  ///
  /// In en, this message translates to:
  /// **'Platform filter'**
  String get adminOpsCrashCenterPlatformFilter;

  /// No description provided for @adminOpsCrashCenterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No crash events were reported in this window.'**
  String get adminOpsCrashCenterEmpty;

  /// No description provided for @adminOpsCrashCenterUnknownCrash.
  ///
  /// In en, this message translates to:
  /// **'Unknown crash message'**
  String get adminOpsCrashCenterUnknownCrash;

  /// No description provided for @adminOpsCrashCenterNoStackTrace.
  ///
  /// In en, this message translates to:
  /// **'No stack trace attached.'**
  String get adminOpsCrashCenterNoStackTrace;

  /// No description provided for @adminOpsAuditSecurityTitle.
  ///
  /// In en, this message translates to:
  /// **'Audit & Security Center'**
  String get adminOpsAuditSecurityTitle;

  /// No description provided for @adminOpsAuditSecurityDescription.
  ///
  /// In en, this message translates to:
  /// **'Admin activity stream and sensitive operation traceability.'**
  String get adminOpsAuditSecurityDescription;

  /// No description provided for @adminOpsAuditSecurityLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load audit and security events.'**
  String get adminOpsAuditSecurityLoadFailed;

  /// No description provided for @adminOpsAuditSecurityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No audit events found.'**
  String get adminOpsAuditSecurityEmpty;

  /// No description provided for @adminOpsAuditSecurityActor.
  ///
  /// In en, this message translates to:
  /// **'Actor'**
  String get adminOpsAuditSecurityActor;

  /// No description provided for @adminOpsAuditSecurityScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get adminOpsAuditSecurityScope;

  /// No description provided for @adminOpsFeatureFlagsTitle.
  ///
  /// In en, this message translates to:
  /// **'Feature Flags Center'**
  String get adminOpsFeatureFlagsTitle;

  /// No description provided for @adminOpsFeatureFlagsDescription.
  ///
  /// In en, this message translates to:
  /// **'Enable and roll out operational features safely.'**
  String get adminOpsFeatureFlagsDescription;

  /// No description provided for @adminOpsFeatureFlagsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load feature flags.'**
  String get adminOpsFeatureFlagsLoadFailed;

  /// No description provided for @adminOpsFeatureFlagsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save this feature flag.'**
  String get adminOpsFeatureFlagsSaveFailed;

  /// No description provided for @adminOpsFeatureFlagsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No feature flags configured.'**
  String get adminOpsFeatureFlagsEmpty;

  /// No description provided for @adminOpsFeatureFlagsCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Add flag'**
  String get adminOpsFeatureFlagsCreateAction;

  /// No description provided for @adminOpsFeatureFlagsCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create feature flag'**
  String get adminOpsFeatureFlagsCreateTitle;

  /// No description provided for @adminOpsFeatureFlagsFlagKey.
  ///
  /// In en, this message translates to:
  /// **'Flag key'**
  String get adminOpsFeatureFlagsFlagKey;

  /// No description provided for @adminOpsFeatureFlagsFieldDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get adminOpsFeatureFlagsFieldDescription;

  /// No description provided for @adminOpsFeatureFlagsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get adminOpsFeatureFlagsEnabled;

  /// No description provided for @adminOpsFeatureFlagsRollout.
  ///
  /// In en, this message translates to:
  /// **'Rollout'**
  String get adminOpsFeatureFlagsRollout;

  /// No description provided for @adminOpsFeatureFlagsNoDescription.
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get adminOpsFeatureFlagsNoDescription;

  /// No description provided for @adminOpsPermissionsMatrixTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions Matrix Center'**
  String get adminOpsPermissionsMatrixTitle;

  /// No description provided for @adminOpsPermissionsMatrixDescription.
  ///
  /// In en, this message translates to:
  /// **'Role overrides and capability enforcement controls.'**
  String get adminOpsPermissionsMatrixDescription;

  /// No description provided for @adminOpsPermissionsMatrixLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load permission overrides.'**
  String get adminOpsPermissionsMatrixLoadFailed;

  /// No description provided for @adminOpsPermissionsMatrixSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save permission override.'**
  String get adminOpsPermissionsMatrixSaveFailed;

  /// No description provided for @adminOpsPermissionsMatrixEmpty.
  ///
  /// In en, this message translates to:
  /// **'No permission overrides configured.'**
  String get adminOpsPermissionsMatrixEmpty;

  /// No description provided for @adminOpsPermissionsMatrixCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Add override'**
  String get adminOpsPermissionsMatrixCreateAction;

  /// No description provided for @adminOpsPermissionsMatrixCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create permission override'**
  String get adminOpsPermissionsMatrixCreateTitle;

  /// No description provided for @adminOpsPermissionsMatrixRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get adminOpsPermissionsMatrixRole;

  /// No description provided for @adminOpsPermissionsMatrixCapability.
  ///
  /// In en, this message translates to:
  /// **'Capability key'**
  String get adminOpsPermissionsMatrixCapability;

  /// No description provided for @adminOpsPermissionsMatrixNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get adminOpsPermissionsMatrixNotes;

  /// No description provided for @adminOpsPermissionsMatrixEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get adminOpsPermissionsMatrixEnabled;

  /// No description provided for @adminOpsPermissionsMatrixOverridesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} overrides'**
  String adminOpsPermissionsMatrixOverridesCount(int count);

  /// No description provided for @adminOpsPermissionsMatrixNoOverrides.
  ///
  /// In en, this message translates to:
  /// **'No overrides for this role.'**
  String get adminOpsPermissionsMatrixNoOverrides;

  /// No description provided for @ownerMenuStoreSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Store settings'**
  String get ownerMenuStoreSettingsTitle;

  /// No description provided for @ownerMenuStoreSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update store profile, phone, and business details.'**
  String get ownerMenuStoreSettingsSubtitle;

  /// No description provided for @ownerMenuCatalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Products and categories'**
  String get ownerMenuCatalogTitle;

  /// No description provided for @ownerMenuCatalogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open catalog management for all items and categories.'**
  String get ownerMenuCatalogSubtitle;

  /// No description provided for @ownerMenuCreateProductTitle.
  ///
  /// In en, this message translates to:
  /// **'Create product/item'**
  String get ownerMenuCreateProductTitle;

  /// No description provided for @ownerMenuCreateProductSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open catalog tab to add a new product.'**
  String get ownerMenuCreateProductSubtitle;

  /// No description provided for @ownerMenuCreateCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Create category'**
  String get ownerMenuCreateCategoryTitle;

  /// No description provided for @ownerMenuCreateCategorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open catalog tab to add a new category.'**
  String get ownerMenuCreateCategorySubtitle;

  /// No description provided for @ownerMenuOffersTitle.
  ///
  /// In en, this message translates to:
  /// **'Offers management'**
  String get ownerMenuOffersTitle;

  /// No description provided for @ownerMenuOffersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create and manage promotional offers for products.'**
  String get ownerMenuOffersSubtitle;

  /// No description provided for @ownerMenuCouponsTitle.
  ///
  /// In en, this message translates to:
  /// **'Store coupons'**
  String get ownerMenuCouponsTitle;

  /// No description provided for @ownerMenuCouponsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create and manage coupons assigned to your store.'**
  String get ownerMenuCouponsSubtitle;

  /// No description provided for @ownerMenuPrinterHubSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Includes printer settings, test print, sample invoice, and print logs.'**
  String get ownerMenuPrinterHubSubtitle;

  /// No description provided for @pharmacyConversationTitle.
  ///
  /// In en, this message translates to:
  /// **'Pharmacy conversation'**
  String get pharmacyConversationTitle;

  /// No description provided for @pharmacyConversationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Pharmacy conversations'**
  String get pharmacyConversationsTitle;

  /// No description provided for @pharmacyConversationsDrawerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review active, completed, and closed conversations.'**
  String get pharmacyConversationsDrawerSubtitle;

  /// No description provided for @pharmacyConversationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No pharmacy conversations in this section.'**
  String get pharmacyConversationsEmpty;

  /// No description provided for @pharmacyBucketActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get pharmacyBucketActive;

  /// No description provided for @pharmacyBucketCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get pharmacyBucketCompleted;

  /// No description provided for @pharmacyBucketClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed without sale'**
  String get pharmacyBucketClosed;

  /// No description provided for @pharmacyNoMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet. Start the pharmacy conversation.'**
  String get pharmacyNoMessagesYet;

  /// No description provided for @pharmacyMessageInputHint.
  ///
  /// In en, this message translates to:
  /// **'Write your message to the pharmacy'**
  String get pharmacyMessageInputHint;

  /// No description provided for @pharmacyOpenAttachmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Open attachment'**
  String get pharmacyOpenAttachmentLabel;

  /// No description provided for @pharmacyCreateCartTitle.
  ///
  /// In en, this message translates to:
  /// **'Create proposed cart'**
  String get pharmacyCreateCartTitle;

  /// No description provided for @pharmacyCartItemsInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Cart items'**
  String get pharmacyCartItemsInputLabel;

  /// No description provided for @pharmacyCartItemsInputHint.
  ///
  /// In en, this message translates to:
  /// **'One item per line: Product name | Quantity | Price'**
  String get pharmacyCartItemsInputHint;

  /// No description provided for @pharmacyCartDeliveryFeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee'**
  String get pharmacyCartDeliveryFeeLabel;

  /// No description provided for @pharmacyProposedCartTitle.
  ///
  /// In en, this message translates to:
  /// **'Proposed cart v{version}'**
  String pharmacyProposedCartTitle(int version);

  /// No description provided for @pharmacyRequestRevisionLabel.
  ///
  /// In en, this message translates to:
  /// **'Request revision'**
  String get pharmacyRequestRevisionLabel;

  /// No description provided for @pharmacyConvertToOrderLabel.
  ///
  /// In en, this message translates to:
  /// **'Convert to order'**
  String get pharmacyConvertToOrderLabel;

  /// No description provided for @pharmacyStoreSettlementHint.
  ///
  /// In en, this message translates to:
  /// **'System settlement applies after customer confirmation.'**
  String get pharmacyStoreSettlementHint;

  /// No description provided for @pharmacyOrderCreated.
  ///
  /// In en, this message translates to:
  /// **'Order #{orderId} created successfully.'**
  String pharmacyOrderCreated(int orderId);

  /// No description provided for @pharmacyWorkflowBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Prescription and pharmacist review'**
  String get pharmacyWorkflowBannerTitle;

  /// No description provided for @pharmacyWorkflowBannerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send prescription photos/files and receive a reviewed proposed cart before checkout.'**
  String get pharmacyWorkflowBannerSubtitle;

  /// No description provided for @pharmacyChatCta.
  ///
  /// In en, this message translates to:
  /// **'Chat with pharmacy'**
  String get pharmacyChatCta;

  /// No description provided for @socialChatThreadPinnedMessagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Pinned messages'**
  String get socialChatThreadPinnedMessagesTitle;

  /// No description provided for @socialChatThreadPinnedMessage.
  ///
  /// In en, this message translates to:
  /// **'Pinned message'**
  String get socialChatThreadPinnedMessage;

  /// No description provided for @socialChatThreadPinMessage.
  ///
  /// In en, this message translates to:
  /// **'Pin message'**
  String get socialChatThreadPinMessage;

  /// No description provided for @socialChatThreadUnpinMessage.
  ///
  /// In en, this message translates to:
  /// **'Unpin message'**
  String get socialChatThreadUnpinMessage;

  /// No description provided for @socialChatThreadPinMessageFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to pin the message.'**
  String get socialChatThreadPinMessageFailed;

  /// No description provided for @socialChatThreadUnpinMessageFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to unpin the message.'**
  String get socialChatThreadUnpinMessageFailed;

  /// No description provided for @socialChatThreadsPinAction.
  ///
  /// In en, this message translates to:
  /// **'Pin chat'**
  String get socialChatThreadsPinAction;

  /// No description provided for @socialChatThreadsUnpinAction.
  ///
  /// In en, this message translates to:
  /// **'Unpin chat'**
  String get socialChatThreadsUnpinAction;

  /// No description provided for @socialChatThreadsPinSuccess.
  ///
  /// In en, this message translates to:
  /// **'Chat pinned.'**
  String get socialChatThreadsPinSuccess;

  /// No description provided for @socialChatThreadsUnpinSuccess.
  ///
  /// In en, this message translates to:
  /// **'Chat unpinned.'**
  String get socialChatThreadsUnpinSuccess;

  /// No description provided for @socialChatThreadsPinFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to pin the chat.'**
  String get socialChatThreadsPinFailed;

  /// No description provided for @socialChatThreadsUnpinFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to unpin the chat.'**
  String get socialChatThreadsUnpinFailed;

  /// No description provided for @socialChatThreadsMuteAction.
  ///
  /// In en, this message translates to:
  /// **'Mute chat'**
  String get socialChatThreadsMuteAction;

  /// No description provided for @socialChatThreadsUnmuteAction.
  ///
  /// In en, this message translates to:
  /// **'Unmute chat'**
  String get socialChatThreadsUnmuteAction;

  /// No description provided for @socialChatThreadsMuteFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to mute the chat.'**
  String get socialChatThreadsMuteFailed;

  /// No description provided for @socialChatThreadsUnmuteFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to unmute the chat.'**
  String get socialChatThreadsUnmuteFailed;

  /// No description provided for @socialCreatorTitle.
  ///
  /// In en, this message translates to:
  /// **'Maslaki camera creator'**
  String get socialCreatorTitle;

  /// No description provided for @socialCreatorUseCamera.
  ///
  /// In en, this message translates to:
  /// **'Use camera'**
  String get socialCreatorUseCamera;

  /// No description provided for @socialCreatorCameraStoryBody.
  ///
  /// In en, this message translates to:
  /// **'Capture a fresh story clip with filters and Maslaki styling.'**
  String get socialCreatorCameraStoryBody;

  /// No description provided for @socialCreatorStoryMode.
  ///
  /// In en, this message translates to:
  /// **'Story camera'**
  String get socialCreatorStoryMode;

  /// No description provided for @socialCreatorReelMode.
  ///
  /// In en, this message translates to:
  /// **'Reel camera'**
  String get socialCreatorReelMode;

  /// No description provided for @socialCreatorSwitchCamera.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get socialCreatorSwitchCamera;

  /// No description provided for @socialCreatorFlash.
  ///
  /// In en, this message translates to:
  /// **'Flash'**
  String get socialCreatorFlash;

  /// No description provided for @socialCreatorCameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The camera is not available on this device right now.'**
  String get socialCreatorCameraUnavailable;

  /// No description provided for @socialCreatorNoEffect.
  ///
  /// In en, this message translates to:
  /// **'No effect'**
  String get socialCreatorNoEffect;

  /// No description provided for @socialCreatorEffectsPhotoOnly.
  ///
  /// In en, this message translates to:
  /// **'Face effects are available for photo stories now. Video publishing keeps filters only.'**
  String get socialCreatorEffectsPhotoOnly;

  /// No description provided for @socialCreatorPhotoHint.
  ///
  /// In en, this message translates to:
  /// **'Tap once to capture a story photo with the selected look.'**
  String get socialCreatorPhotoHint;

  /// No description provided for @socialCreatorVideoHint.
  ///
  /// In en, this message translates to:
  /// **'Record, review, then continue into publishing with the processed clip.'**
  String get socialCreatorVideoHint;

  /// No description provided for @socialCreatorPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get socialCreatorPreviewTitle;

  /// No description provided for @socialCreatorCoverFrame.
  ///
  /// In en, this message translates to:
  /// **'Cover frame'**
  String get socialCreatorCoverFrame;

  /// No description provided for @socialCreatorRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get socialCreatorRetake;

  /// No description provided for @socialCreatorPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera and microphone access is required'**
  String get socialCreatorPermissionsTitle;

  /// No description provided for @socialCreatorPermissionsBody.
  ///
  /// In en, this message translates to:
  /// **'Allow camera and microphone access to record stories and reels.'**
  String get socialCreatorPermissionsBody;

  /// No description provided for @socialCreatorPermissionsPermanentlyDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera or microphone access is blocked. Open system settings, enable the permissions, then return to continue.'**
  String get socialCreatorPermissionsPermanentlyDenied;

  /// No description provided for @socialCreatorFaceNotFound.
  ///
  /// In en, this message translates to:
  /// **'No face was detected for the selected effect.'**
  String get socialCreatorFaceNotFound;

  /// No description provided for @socialCreatorStorySegmentsMissing.
  ///
  /// In en, this message translates to:
  /// **'This video needs valid story segments before publishing.'**
  String get socialCreatorStorySegmentsMissing;

  /// No description provided for @socialCreatorPhotoMode.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get socialCreatorPhotoMode;

  /// No description provided for @socialCreatorStorySegments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0 {No story segments yet} =1 {1 story segment} other {{count} story segments}}'**
  String socialCreatorStorySegments(int count);

  /// No description provided for @socialCreatorTimeMood.
  ///
  /// In en, this message translates to:
  /// **'Time Mood'**
  String get socialCreatorTimeMood;

  /// No description provided for @socialCreatorTimeMoodMorning.
  ///
  /// In en, this message translates to:
  /// **'Dawn mood'**
  String get socialCreatorTimeMoodMorning;

  /// No description provided for @socialCreatorTimeMoodForenoon.
  ///
  /// In en, this message translates to:
  /// **'Morning mood'**
  String get socialCreatorTimeMoodForenoon;

  /// No description provided for @socialCreatorTimeMoodNoon.
  ///
  /// In en, this message translates to:
  /// **'Noon mood'**
  String get socialCreatorTimeMoodNoon;

  /// No description provided for @socialCreatorTimeMoodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Afternoon mood'**
  String get socialCreatorTimeMoodAfternoon;

  /// No description provided for @socialCreatorTimeMoodSunset.
  ///
  /// In en, this message translates to:
  /// **'Sunset mood'**
  String get socialCreatorTimeMoodSunset;

  /// No description provided for @socialCreatorTimeMoodEvening.
  ///
  /// In en, this message translates to:
  /// **'Evening mood'**
  String get socialCreatorTimeMoodEvening;

  /// No description provided for @socialCreatorTimeMoodNight.
  ///
  /// In en, this message translates to:
  /// **'Night mood'**
  String get socialCreatorTimeMoodNight;

  /// No description provided for @socialCreatorTimeMoodLateNight.
  ///
  /// In en, this message translates to:
  /// **'Late-night mood'**
  String get socialCreatorTimeMoodLateNight;

  /// No description provided for @socialCreatorPlacePulse.
  ///
  /// In en, this message translates to:
  /// **'Place Pulse'**
  String get socialCreatorPlacePulse;

  /// No description provided for @socialCreatorPlacePulseHint.
  ///
  /// In en, this message translates to:
  /// **'Tag a location to your story'**
  String get socialCreatorPlacePulseHint;

  /// No description provided for @socialCreatorPlacePulseLocating.
  ///
  /// In en, this message translates to:
  /// **'Finding location…'**
  String get socialCreatorPlacePulseLocating;

  /// No description provided for @socialCreatorPlacePulseError.
  ///
  /// In en, this message translates to:
  /// **'Location unavailable'**
  String get socialCreatorPlacePulseError;

  /// No description provided for @socialCreatorPlacePulseSave.
  ///
  /// In en, this message translates to:
  /// **'Add location'**
  String get socialCreatorPlacePulseSave;

  /// No description provided for @socialCreatorMaslakiSeal.
  ///
  /// In en, this message translates to:
  /// **'Maslaki Seal'**
  String get socialCreatorMaslakiSeal;

  /// No description provided for @socialCreatorMaslakiSealOn.
  ///
  /// In en, this message translates to:
  /// **'Seal on'**
  String get socialCreatorMaslakiSealOn;

  /// No description provided for @socialStoryModeStory.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get socialStoryModeStory;

  /// No description provided for @socialStoryModeLayout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get socialStoryModeLayout;

  /// No description provided for @socialStoryModeText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get socialStoryModeText;

  /// No description provided for @socialCreatorGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get socialCreatorGallery;

  /// No description provided for @socialCreatorFiltersTool.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get socialCreatorFiltersTool;

  /// No description provided for @socialCreatorEffectsTool.
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get socialCreatorEffectsTool;

  /// No description provided for @socialCreatorMoodTool.
  ///
  /// In en, this message translates to:
  /// **'Mood'**
  String get socialCreatorMoodTool;

  /// No description provided for @socialCreatorLayoutDuo.
  ///
  /// In en, this message translates to:
  /// **'Duo'**
  String get socialCreatorLayoutDuo;

  /// No description provided for @socialCreatorLayoutTrio.
  ///
  /// In en, this message translates to:
  /// **'Daily strip'**
  String get socialCreatorLayoutTrio;

  /// No description provided for @socialCreatorLayoutQuad.
  ///
  /// In en, this message translates to:
  /// **'Four shots'**
  String get socialCreatorLayoutQuad;

  /// No description provided for @socialCreatorLayoutGrid.
  ///
  /// In en, this message translates to:
  /// **'Moments grid'**
  String get socialCreatorLayoutGrid;

  /// No description provided for @socialCreatorLayoutDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get socialCreatorLayoutDone;

  /// No description provided for @socialCreatorLayoutImagesOnly.
  ///
  /// In en, this message translates to:
  /// **'Layout supports images only.'**
  String get socialCreatorLayoutImagesOnly;

  /// No description provided for @socialCreatorLayoutHint.
  ///
  /// In en, this message translates to:
  /// **'Capture each section · {filled}/{total}'**
  String socialCreatorLayoutHint(int filled, int total);

  /// No description provided for @socialCreatorMoodQuickTrip.
  ///
  /// In en, this message translates to:
  /// **'Quick trip'**
  String get socialCreatorMoodQuickTrip;

  /// No description provided for @socialCreatorMoodBasmayaMorning.
  ///
  /// In en, this message translates to:
  /// **'Basmaya morning'**
  String get socialCreatorMoodBasmayaMorning;

  /// No description provided for @socialCreatorMoodDailyCoffee.
  ///
  /// In en, this message translates to:
  /// **'Coffee of the day'**
  String get socialCreatorMoodDailyCoffee;

  /// No description provided for @socialCreatorMoodOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'On the way'**
  String get socialCreatorMoodOnTheWay;

  /// No description provided for @socialCreatorMoodOrderArrived.
  ///
  /// In en, this message translates to:
  /// **'Order arrived'**
  String get socialCreatorMoodOrderArrived;

  /// No description provided for @socialCreatorPlacePulseCurrent.
  ///
  /// In en, this message translates to:
  /// **'Use my current location'**
  String get socialCreatorPlacePulseCurrent;

  /// No description provided for @socialCreatorPlacePulseSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search for a place'**
  String get socialCreatorPlacePulseSearchHint;

  /// No description provided for @socialCreatorPlacePulseClear.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get socialCreatorPlacePulseClear;

  /// No description provided for @socialCreatorTextHint.
  ///
  /// In en, this message translates to:
  /// **'Type something…'**
  String get socialCreatorTextHint;

  /// No description provided for @socialCreatorTextBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get socialCreatorTextBackground;

  /// No description provided for @socialCreatorTextColor.
  ///
  /// In en, this message translates to:
  /// **'Text color'**
  String get socialCreatorTextColor;

  /// No description provided for @socialCreatorTextSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get socialCreatorTextSize;

  /// No description provided for @socialCreatorTextAlign.
  ///
  /// In en, this message translates to:
  /// **'Align'**
  String get socialCreatorTextAlign;

  /// No description provided for @socialCreatorTextEmpty.
  ///
  /// In en, this message translates to:
  /// **'Write something first'**
  String get socialCreatorTextEmpty;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsPrivacyPolicyHint.
  ///
  /// In en, this message translates to:
  /// **'How we collect, use, and protect your data'**
  String get settingsPrivacyPolicyHint;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsDeleteAccountHint.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and associated data.'**
  String get settingsDeleteAccountHint;

  /// No description provided for @settingsDeleteAccountConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get settingsDeleteAccountConfirmTitle;

  /// No description provided for @settingsDeleteAccountConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account and associated data. This action cannot be undone.'**
  String get settingsDeleteAccountConfirmBody;

  /// No description provided for @settingsDeleteAccountConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get settingsDeleteAccountConfirmAction;

  /// No description provided for @settingsDeleteAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete your account. Please try again.'**
  String get settingsDeleteAccountFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
