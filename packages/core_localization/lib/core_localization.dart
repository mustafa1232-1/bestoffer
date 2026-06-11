import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

enum RuntimeAppScope { user, store, delivery, taxiCaptain, company }

class CoreAppLocalizations {
  final Locale locale;

  const CoreAppLocalizations(this.locale);

  static const LocalizationsDelegate<CoreAppLocalizations> delegate =
      _CoreAppLocalizationsDelegate();

  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ];

  static CoreAppLocalizations of(BuildContext context) {
    return Localizations.of<CoreAppLocalizations>(
          context,
          CoreAppLocalizations,
        ) ??
        const CoreAppLocalizations(Locale('en'));
  }

  bool get _isAr => locale.languageCode.toLowerCase() == 'ar';

  String get appName => _isAr ? 'Ù…Ø³Ù„ÙƒÙŠ' : 'مسلكي';

  String get userAppWindowTitle =>
      _isAr ? 'Ù…Ø³Ù„ÙƒÙŠ - ØªØ·Ø¨ÙŠÙ‚ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù…' : 'مسلكي User';

  String get storePortalWindowTitle =>
      _isAr ? 'Ù…Ø³Ù„ÙƒÙŠ - Ø¨ÙˆØ§Ø¨Ø© Ø§Ù„Ù…ØªØ¬Ø±' : 'مسلكي Store Portal';

  String get deliveryAppTitle =>
      _isAr ? 'Ù…Ø³Ù„ÙƒÙŠ - ØªØ·Ø¨ÙŠÙ‚ Ø§Ù„Ø¯Ù„ÙØ±ÙŠ' : 'مسلكي Delivery App';

  String get taxiCaptainAppTitle =>
      _isAr ? 'Ù…Ø³Ù„ÙƒÙŠ - ØªØ·Ø¨ÙŠÙ‚ Ø§Ù„ÙƒØ§Ø¨ØªÙ†' : 'مسلكي Captain App';

  String get companyPortalWindowTitle =>
      _isAr ? 'Ù…Ø³Ù„ÙƒÙŠ - Ø¨ÙˆØ§Ø¨Ø© Ø§Ù„Ø¥Ø¯Ø§Ø±Ø©' : 'مسلكي Company Portal';

  String get commonLogout => _isAr ? 'ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø®Ø±ÙˆØ¬' : 'Logout';
  String get commonContinue => _isAr ? 'Ù…ØªØ§Ø¨Ø¹Ø©' : 'Continue';
  String get commonRefresh => _isAr ? 'ØªØ­Ø¯ÙŠØ«' : 'Refresh';
  String get commonOpenSettings => _isAr ? 'ÙØªØ­ Ø§Ù„Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª' : 'Open settings';
  String get commonEnable => _isAr ? 'ØªÙØ¹ÙŠÙ„' : 'Enable';

  String get loginHeadline =>
      _isAr ? 'Ø³Ø¬Ù‘Ù„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ù„Ù„Ù…ØªØ§Ø¨Ø¹Ø©' : 'Sign in to continue';

  String roleLoginTitle(RuntimeAppScope scope) {
    if (_isAr) {
      return switch (scope) {
        RuntimeAppScope.user => 'ØªØ³Ø¬ÙŠÙ„ Ø¯Ø®ÙˆÙ„ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù…',
        RuntimeAppScope.store => 'ØªØ³Ø¬ÙŠÙ„ Ø¯Ø®ÙˆÙ„ ØµØ§Ø­Ø¨ Ø§Ù„Ù…ØªØ¬Ø±',
        RuntimeAppScope.delivery => 'ØªØ³Ø¬ÙŠÙ„ Ø¯Ø®ÙˆÙ„ Ø§Ù„Ø¯Ù„ÙØ±ÙŠ',
        RuntimeAppScope.taxiCaptain => 'ØªØ³Ø¬ÙŠÙ„ Ø¯Ø®ÙˆÙ„ Ø§Ù„ÙƒØ§Ø¨ØªÙ†',
        RuntimeAppScope.company => 'ØªØ³Ø¬ÙŠÙ„ Ø¯Ø®ÙˆÙ„ Ø§Ù„Ø¥Ø¯Ø§Ø±Ø©',
      };
    }
    return switch (scope) {
      RuntimeAppScope.user => 'User Login',
      RuntimeAppScope.store => 'Store Owner Login',
      RuntimeAppScope.delivery => 'Delivery Login',
      RuntimeAppScope.taxiCaptain => 'Captain Login',
      RuntimeAppScope.company => 'Company Login',
    };
  }

  String loginButtonLabel(RuntimeAppScope scope) {
    if (_isAr) {
      return switch (scope) {
        RuntimeAppScope.user => 'ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„',
        RuntimeAppScope.store => 'ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ù„Ù„Ù…ØªØ¬Ø±',
        RuntimeAppScope.delivery => 'ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ù„Ù„Ø¯Ù„ÙØ±ÙŠ',
        RuntimeAppScope.taxiCaptain => 'ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ù„Ù„ÙƒØ§Ø¨ØªÙ†',
        RuntimeAppScope.company => 'ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ù„Ù„Ø¥Ø¯Ø§Ø±Ø©',
      };
    }
    return switch (scope) {
      RuntimeAppScope.user => 'Sign in',
      RuntimeAppScope.store => 'Sign in to Store',
      RuntimeAppScope.delivery => 'Sign in to Delivery',
      RuntimeAppScope.taxiCaptain => 'Sign in to Captain',
      RuntimeAppScope.company => 'Sign in to Company',
    };
  }

  String dashboardTitle(RuntimeAppScope scope) {
    if (_isAr) {
      return switch (scope) {
        RuntimeAppScope.user => 'Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠØ©',
        RuntimeAppScope.store => 'Ù„ÙˆØ­Ø© Ø§Ù„Ù…ØªØ¬Ø±',
        RuntimeAppScope.delivery => 'Ù„ÙˆØ­Ø© Ø§Ù„Ø¯Ù„ÙØ±ÙŠ',
        RuntimeAppScope.taxiCaptain => 'Ù„ÙˆØ­Ø© Ø§Ù„ÙƒØ§Ø¨ØªÙ†',
        RuntimeAppScope.company => 'Ù„ÙˆØ­Ø© Ø§Ù„Ø¥Ø¯Ø§Ø±Ø©',
      };
    }
    return switch (scope) {
      RuntimeAppScope.user => 'Home',
      RuntimeAppScope.store => 'Store Dashboard',
      RuntimeAppScope.delivery => 'Delivery Dashboard',
      RuntimeAppScope.taxiCaptain => 'Captain Dashboard',
      RuntimeAppScope.company => 'Company Dashboard',
    };
  }

  String get reelsLabel => _isAr ? 'Ø±ÙŠÙ„Ø²' : 'Reels';
  String get createStoreLabel => _isAr ? 'Ø¥Ù†Ø´Ø§Ø¡ Ù…ØªØ¬Ø±' : 'Create Store';
  String get ordersLabel => _isAr ? 'Ø§Ù„Ø·Ù„Ø¨Ø§Øª' : 'Orders';
  String get taxiLabel => _isAr ? 'ØªÙƒØ³ÙŠ' : 'Taxi';
  String get storesLabel => _isAr ? 'Ø§Ù„Ù…ØªØ§Ø¬Ø±' : 'Stores';
  String get notificationsLabel => _isAr ? 'Ø§Ù„Ø¥Ø´Ø¹Ø§Ø±Ø§Øª' : 'Notifications';
  String get profileLabel => _isAr ? 'Ø§Ù„Ø­Ø³Ø§Ø¨' : 'Profile';
  String get exploreLabel => _isAr ? 'Ø§ÙƒØªØ´Ù' : 'Discover';
  String get homeLabel => _isAr ? 'Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠØ©' : 'Home';
  String get settingsLabel => _isAr ? 'Ø§Ù„Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª' : 'Settings';

  String get userConsentTitle => _isAr ? 'Ø§Ø¨Ø¯Ø£ Ù…Ø¹ Ù…Ø³Ù„ÙƒÙŠ' : 'Start with مسلكي';

  String get userConsentSubtitle => _isAr
      ? 'Ù‚Ø¨Ù„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ù„Ù„ØªØ¬Ø±Ø¨Ø©ØŒ ÙØ¹Ù‘Ù„ Ø§Ù„Ø£Ø³Ø§Ø³ÙŠØ§Øª Ø§Ù„ØªÙŠ ØªØ³Ø§Ø¹Ø¯Ù†Ø§ Ù†ÙˆØµÙ„ Ù„Ùƒ Ø§Ù„Ø®Ø¯Ù…Ø§Øª Ø§Ù„Ù‚Ø±ÙŠØ¨Ø© ÙˆÙ†Ø±Ø³Ù„ Ù„Ùƒ ØªØ­Ø¯ÙŠØ«Ø§Øª Ø§Ù„Ø·Ù„Ø¨Ø§Øª.'
      : 'Before you continue, enable the essentials that help us find nearby services and send order updates.';

  String get locationPermissionTitle => _isAr ? 'Ø§Ù„Ù…ÙˆÙ‚Ø¹' : 'Location';

  String get locationPermissionDescription => _isAr
      ? 'Ù†Ø­ØªØ§Ø¬ Ø§Ù„Ù…ÙˆÙ‚Ø¹ Ù„ØªØ­Ø¯ÙŠØ¯ Ù†Ù‚Ø·Ø© Ø§Ù„Ø§Ù†Ø·Ù„Ø§Ù‚ ÙÙŠ Ø§Ù„ØªÙƒØ³ÙŠ ÙˆØ¹Ø±Ø¶ Ø§Ù„Ø®Ø¯Ù…Ø§Øª ÙˆØ§Ù„Ù…ØªØ§Ø¬Ø± Ø§Ù„Ù‚Ø±ÙŠØ¨Ø© Ù…Ù†Ùƒ.'
      : 'We use your location to set taxi pickup points and show nearby services and stores.';

  String get notificationsPermissionTitle =>
      _isAr ? 'Ø§Ù„Ø¥Ø´Ø¹Ø§Ø±Ø§Øª' : 'Notifications';

  String get notificationsPermissionDescription => _isAr
      ? 'ÙØ¹Ù‘Ù„ Ø§Ù„Ø¥Ø´Ø¹Ø§Ø±Ø§Øª Ù„ØªØµÙ„Ùƒ ØªØ­Ø¯ÙŠØ«Ø§Øª Ø§Ù„Ø·Ù„Ø¨Ø§Øª ÙˆØ§Ù„Ø±Ø­Ù„Ø§Øª ÙˆØ§Ù„Ø±Ø³Ø§Ø¦Ù„ Ø§Ù„Ù…Ù‡Ù…Ø© ÙÙŠ ÙˆÙ‚ØªÙ‡Ø§.'
      : 'Enable notifications to receive order, ride, and message updates on time.';

  String get continueToLoginLabel =>
      _isAr ? 'Ø§Ù„Ù…ØªØ§Ø¨Ø¹Ø© Ø¥Ù„Ù‰ ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„' : 'Continue to sign in';

  String get homeGreeting => _isAr ? 'Ø£Ù‡Ù„Ù‹Ø§ Ø¨Ùƒ' : 'Welcome back';

  String get homeSummary => _isAr
      ? 'ÙˆØ§Ø¬Ù‡Ø© Ø£Ø®Ù ÙˆØ£ÙˆØ¶Ø­ ØªØ±ÙƒÙ‘Ø² Ø¹Ù„Ù‰ Ø£Ù‡Ù… Ø§Ù„Ø®Ø¯Ù…Ø§Øª Ø§Ù„ØªÙŠ ØªØ­ØªØ§Ø¬Ù‡Ø§ Ø¨Ø³Ø±Ø¹Ø©.'
      : 'A lighter, clearer home focused on the services you need most.';

  String get quickActionsTitle => _isAr ? 'ÙˆØµÙˆÙ„ Ø³Ø±ÙŠØ¹' : 'Quick access';

  String get startupHighlightsTitle => _isAr ? 'Ø¬Ø§Ù‡Ø² Ù„Ù„Ø®Ø¯Ù…Ø©' : 'Ready to go';

  String get startupHighlightsSubtitle => _isAr
      ? 'Ù…Ù† Ù‡Ù†Ø§ ØªÙ‚Ø¯Ø± ØªÙØªØ­ Ø§Ù„Ù…ØªØ§Ø¬Ø±ØŒ ØªØ·Ù„Ø¨ ØªÙƒØ³ÙŠØŒ ÙˆØªØªØ§Ø¨Ø¹ Ø§Ù„Ø±ÙŠÙ„Ø² Ù…Ù† ÙˆØ§Ø¬Ù‡Ø© ÙˆØ§Ø­Ø¯Ø©.'
      : 'Open stores, request a ride, and follow reels from one place.';

  String get locationCardTitle => _isAr ? 'Ø­Ø§Ù„Ø© Ø§Ù„Ù…ÙˆÙ‚Ø¹' : 'Location status';

  String get locationPreciseGranted => _isAr
      ? 'Ø§Ù„Ù…ÙˆÙ‚Ø¹ Ø§Ù„Ø¯Ù‚ÙŠÙ‚ Ù…ÙØ¹Ù‘Ù„ ÙˆØ¬Ø§Ù‡Ø² Ù„Ù„ØªÙƒØ³ÙŠ ÙˆØ§Ù„Ø®Ø¯Ù…Ø§Øª Ø§Ù„Ù‚Ø±ÙŠØ¨Ø©.'
      : 'Precise location is enabled and ready for taxi and nearby services.';

  String get locationApproximateGranted => _isAr
      ? 'Ø§Ù„Ù…ÙˆÙ‚Ø¹ Ø§Ù„ØªÙ‚Ø±ÙŠØ¨ÙŠ Ù…ÙØ¹Ù‘Ù„. Ù„Ù„Ø­ØµÙˆÙ„ Ø¹Ù„Ù‰ Ù†ØªØ§Ø¦Ø¬ Ø£Ø¯Ù‚ØŒ ÙØ¹Ù‘Ù„ Ø§Ù„Ù…ÙˆÙ‚Ø¹ Ø§Ù„Ø¯Ù‚ÙŠÙ‚ Ù…Ù† Ø§Ù„Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª.'
      : 'Approximate location is enabled. Enable precise location from settings for better results.';

  String get locationDeniedMessage => _isAr
      ? 'ØµÙ„Ø§Ø­ÙŠØ© Ø§Ù„Ù…ÙˆÙ‚Ø¹ Ù…Ø±ÙÙˆØ¶Ø© Ø­Ø§Ù„ÙŠÙ‹Ø§. ÙŠÙ…ÙƒÙ†Ùƒ ØªÙØ¹ÙŠÙ„Ù‡Ø§ Ù…Ù† Ù‡Ù†Ø§ Ø£Ùˆ Ø§Ø®ØªÙŠØ§Ø± Ø§Ù„Ù…ÙˆÙ‚Ø¹ ÙŠØ¯ÙˆÙŠÙ‹Ø§ Ù„Ø§Ø­Ù‚Ù‹Ø§.'
      : 'Location permission is currently denied. You can enable it here or choose your location manually later.';

  String get locationDeniedForeverMessage => _isAr
      ? 'Ø§Ù„Ù…ÙˆÙ‚Ø¹ Ù…Ø±ÙÙˆØ¶ Ø¨Ø´ÙƒÙ„ Ø¯Ø§Ø¦Ù…. Ø§ÙØªØ­ Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ Ù„Ø¥Ø¹Ø§Ø¯Ø© Ø§Ù„ØªÙØ¹ÙŠÙ„.'
      : 'Location permission is permanently denied. Open app settings to enable it again.';

  String get locationServiceDisabledMessage => _isAr
      ? 'Ø®Ø¯Ù…Ø© Ø§Ù„Ù…ÙˆÙ‚Ø¹ ÙÙŠ Ø§Ù„Ø¬Ù‡Ø§Ø² Ù…ØªÙˆÙ‚ÙØ©. ÙØ¹Ù‘Ù„Ù‡Ø§ Ø£ÙˆÙ„Ù‹Ø§ Ø«Ù… Ø£Ø¹Ø¯ Ø§Ù„Ù…Ø­Ø§ÙˆÙ„Ø©.'
      : 'Location services are turned off on the device. Turn them on and try again.';

  String get requestLocationLabel => _isAr ? 'ØªÙØ¹ÙŠÙ„ Ø§Ù„Ù…ÙˆÙ‚Ø¹' : 'Enable location';

  String get openLocationSettingsLabel =>
      _isAr ? 'ÙØªØ­ Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª Ø§Ù„Ù…ÙˆÙ‚Ø¹' : 'Open location settings';

  String get chooseLocationManuallyLabel =>
      _isAr ? 'Ø§Ø®ØªÙŠØ§Ø± Ø§Ù„Ù…ÙˆÙ‚Ø¹ ÙŠØ¯ÙˆÙŠÙ‹Ø§' : 'Choose location manually';

  String get discoverStoresTitle => _isAr ? 'Ø§Ø³ØªÙƒØ´Ù Ø§Ù„Ù…ØªØ§Ø¬Ø±' : 'Explore stores';

  String get discoverStoresSubtitle => _isAr
      ? 'Ø§Ù„Ù…Ø·Ø§Ø¹Ù…ØŒ Ø§Ù„ØµÙŠØ¯Ù„ÙŠØ§ØªØŒ ÙˆØ§Ù„Ø³ÙˆØ¨Ø±Ù…Ø§Ø±ÙƒØª ÙÙŠ Ù…ÙƒØ§Ù† ÙˆØ§Ø­Ø¯.'
      : 'Restaurants, pharmacies, and supermarkets in one place.';

  String get requestTaxiTitle => _isAr ? 'Ø§Ø·Ù„Ø¨ ØªÙƒØ³ÙŠ' : 'Request a taxi';

  String get requestTaxiSubtitle => _isAr
      ? 'Ø­Ø¯Ù‘Ø¯ Ø§Ù„Ø§Ù†Ø·Ù„Ø§Ù‚ ÙˆØ§Ù„ÙˆØµÙˆÙ„ ÙˆØªØªØ¨Ø¹ Ø§Ù„Ø±Ø­Ù„Ø© Ø¨Ø³Ù‡ÙˆÙ„Ø©.'
      : 'Set pickup and drop-off, then track your ride with ease.';

  String get watchReelsTitle => _isAr ? 'ØªØ§Ø¨Ø¹ Ø§Ù„Ø±ÙŠÙ„Ø²' : 'Watch reels';

  String get watchReelsSubtitle => _isAr
      ? 'Ù…Ø­ØªÙˆÙ‰ Ø³Ø±ÙŠØ¹ Ù…Ù† Ø§Ù„Ù…Ø¬ØªÙ…Ø¹ ÙˆØ§Ù„Ù…ØªØ§Ø¬Ø±.'
      : 'Quick content from the community and stores.';

  String get ordersEmptyTitle =>
      _isAr ? 'Ù„Ø§ ØªÙˆØ¬Ø¯ Ø·Ù„Ø¨Ø§Øª Ø­ØªÙ‰ Ø§Ù„Ø¢Ù†' : 'No orders yet';

  String get ordersEmptySubtitle => _isAr
      ? 'Ø¹Ù†Ø¯Ù…Ø§ ØªØ¨Ø¯Ø£ Ø§Ù„Ø·Ù„Ø¨Ø§Øª ÙˆØ§Ù„Ø±Ø­Ù„Ø§ØªØŒ Ø³ØªØ¸Ù‡Ø± ØªØ­Ø¯ÙŠØ«Ø§ØªÙ‡Ø§ Ù‡Ù†Ø§.'
      : 'Your orders and ride updates will appear here once you start.';

  String get profileSectionTitle =>
      _isAr ? 'ØªØ®ØµÙŠØµ Ø§Ù„ØªØ¬Ø±Ø¨Ø©' : 'Personalize your experience';

  String get themeSectionTitle => _isAr ? 'Ù„ÙˆØ­Ø© Ø§Ù„Ø£Ù„ÙˆØ§Ù†' : 'Color preset';

  String get languageSectionTitle => _isAr ? 'Ø§Ù„Ù„ØºØ©' : 'Language';

  String get animationsLabel => _isAr ? 'ØªÙØ¹ÙŠÙ„ Ø§Ù„Ø­Ø±ÙƒØ©' : 'Enable animations';

  String get ambientEffectsLabel =>
      _isAr ? 'ØªØ£Ø«ÙŠØ±Ø§Øª Ø§Ù„Ø®Ù„ÙÙŠØ©' : 'Background effects';

  String get themePresetMidnightBlue =>
      _isAr ? 'Ø£Ø²Ø±Ù‚ Ù…Ù†ØªØµÙ Ø§Ù„Ù„ÙŠÙ„' : 'Midnight Blue';

  String get themePresetRoyalIndigo => _isAr ? 'Ù†ÙŠÙ„ÙŠ Ù…Ù„ÙƒÙŠ' : 'Royal Indigo';

  String get themePresetEmeraldNight => _isAr ? 'Ø²Ù…Ø±Ø¯ÙŠ Ù„ÙŠÙ„ÙŠ' : 'Emerald Night';

  String get themePresetSunsetNeon => _isAr ? 'Ù†ÙŠÙˆÙ† Ø§Ù„ØºØ±ÙˆØ¨' : 'Sunset Neon';

  String get languageArabic => _isAr ? 'Ø§Ù„Ø¹Ø±Ø¨ÙŠØ©' : 'Arabic';
  String get languageEnglish => _isAr ? 'Ø§Ù„Ø¥Ù†Ø¬Ù„ÙŠØ²ÙŠØ©' : 'English';

  String get storesHubTitle => _isAr ? 'Ø§Ù„Ù…ØªØ§Ø¬Ø± Ø§Ù„Ù‚Ø±ÙŠØ¨Ø©' : 'Nearby stores';

  String get storesHubSubtitle => _isAr
      ? 'Ø§ÙƒØªØ´Ù Ø§Ù„Ù…Ø·Ø§Ø¹Ù… ÙˆØ§Ù„ØµÙŠØ¯Ù„ÙŠØ§Øª ÙˆØ§Ù„Ù…ØªØ§Ø¬Ø± Ø§Ù„Ø³Ø±ÙŠØ¹Ø© Ù…Ù† ÙˆØ§Ø¬Ù‡Ø© Ù…Ø³ØªØ®Ø¯Ù… Ø®ÙÙŠÙØ©.'
      : 'Browse restaurants, pharmacies, and fast delivery stores from a lighter shell.';

  String get storesSearchHint =>
      _isAr ? 'Ø§Ø¨Ø­Ø« Ø¹Ù† Ù…ØªØ¬Ø± Ø£Ùˆ Ù†Ø´Ø§Ø·' : 'Search for a store or activity';

  String get storesCategoryRestaurants => _isAr ? 'Ù…Ø·Ø§Ø¹Ù…' : 'Restaurants';

  String get storesCategoryPharmacies => _isAr ? 'ØµÙŠØ¯Ù„ÙŠØ§Øª' : 'Pharmacies';

  String get storesCategorySupermarket => _isAr ? 'Ø³ÙˆØ¨Ø±Ù…Ø§Ø±ÙƒØª' : 'Supermarket';

  String get storesCategoryCoffee => _isAr ? 'Ù‚Ù‡ÙˆØ©' : 'Coffee';

  String get storesFeaturedSectionTitle =>
      _isAr ? 'ØªØ±Ø´ÙŠØ­Ø§Øª Ø³Ø±ÙŠØ¹Ø©' : 'Quick picks';

  String get storesDeliveryEtaLabel => _isAr ? 'Ø²Ù…Ù† Ø§Ù„ØªÙˆØµÙŠÙ„' : 'Delivery ETA';

  String get taxiHubTitle => _isAr ? 'Ù…Ø±ÙƒØ² Ø§Ù„ØªÙƒØ³ÙŠ' : 'Taxi hub';

  String get taxiHubSubtitle => _isAr
      ? 'Ø§Ø¨Ø¯Ø£ Ø§Ù„Ø±Ø­Ù„Ø© Ø¨Ø®Ø·ÙˆØ§Øª Ø£ÙˆØ¶Ø­: ØªØ­Ù‚Ù‚ Ù…Ù† Ø§Ù„Ù…ÙˆÙ‚Ø¹ Ø«Ù… Ø¬Ù‡Ù‘Ø² Ù†Ù‚Ø·Ø© Ø§Ù„Ø§Ù†Ø·Ù„Ø§Ù‚ ÙˆØ§Ù„ÙˆØµÙˆÙ„.'
      : 'Start a clearer ride flow: verify location, then prepare pickup and drop-off.';

  String get taxiPickupAction => _isAr ? 'Ø­Ø¯Ø¯ Ù†Ù‚Ø·Ø© Ø§Ù„Ø§Ù†Ø·Ù„Ø§Ù‚' : 'Choose pickup';

  String get taxiDropoffAction => _isAr ? 'Ø­Ø¯Ø¯ Ø§Ù„ÙˆØ¬Ù‡Ø©' : 'Choose drop-off';

  String get taxiOpenMapAction => _isAr ? 'Ø§ÙØªØ­ Ø®Ø±ÙŠØ·Ø© Ø§Ù„Ø±Ø­Ù„Ø©' : 'Open ride map';

  String get taxiLocationReady => _isAr
      ? 'Ø§Ù„Ù…ÙˆÙ‚Ø¹ Ø¬Ø§Ù‡Ø² Ù„Ø¨Ø¯Ø¡ Ø·Ù„Ø¨ Ø§Ù„ØªÙƒØ³ÙŠ.'
      : 'Location is ready to start your ride.';

  String get taxiLocationNeedsAttention => _isAr
      ? 'ÙØ¹Ù‘Ù„ Ø§Ù„Ù…ÙˆÙ‚Ø¹ Ø£ÙˆÙ„Ù‹Ø§ Ø£Ùˆ Ø§Ø®ØªØ± Ø§Ù„Ù†Ù‚Ø·Ø© ÙŠØ¯ÙˆÙŠÙ‹Ø§ Ù‚Ø¨Ù„ Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„Ø·Ù„Ø¨.'
      : 'Enable location first or choose the point manually before sending the request.';

  String get taxiEstimatedFareLabel =>
      _isAr ? 'Ø§Ù„Ø£Ø¬Ø±Ø© Ø§Ù„ØªÙ‚Ø±ÙŠØ¨ÙŠØ©' : 'Estimated fare';

  String get reelsHubTitle => _isAr ? 'Ø±ÙŠÙ„Ø² Ø§Ù„ÙŠÙˆÙ…' : 'Today\'s reels';

  String get reelsHubSubtitle => _isAr
      ? 'Ù„Ù‚Ø·Ø§Øª Ø³Ø±ÙŠØ¹Ø© Ù…Ù† Ø§Ù„Ù…Ø¬ØªÙ…Ø¹ ÙˆØ§Ù„Ù…ØªØ§Ø¬Ø±ØŒ Ù…Ø¹ ÙˆØ§Ø¬Ù‡Ø© Ø£Ø®Ù Ù„Ù„Ù…ØªØ§Ø¨Ø¹Ø©.'
      : 'Quick clips from the community and stores in a lighter viewing shell.';

  String get reelsFeaturedSectionTitle =>
      _isAr ? 'Ø£Ø­Ø¯Ø« Ø§Ù„Ù…Ù‚Ø§Ø·Ø¹' : 'Latest clips';

  String get notificationsHubTitle =>
      _isAr ? 'Ù…Ø±ÙƒØ² Ø§Ù„Ø¥Ø´Ø¹Ø§Ø±Ø§Øª' : 'Notifications hub';

  String get notificationsHubSubtitle => _isAr
      ? 'ØªØ§Ø¨Ø¹ Ø§Ù„Ø·Ù„Ø¨Ø§Øª ÙˆØ§Ù„ØªÙ†Ø¨ÙŠÙ‡Ø§Øª Ø§Ù„Ù…Ù‡Ù…Ø© Ø¨Ø¯ÙˆÙ† ÙØªØ­ ÙƒÙ„ Ø´Ø§Ø´Ø© Ø¹Ù„Ù‰ Ø­Ø¯Ø©.'
      : 'Track orders and important alerts without opening every screen.';

  String get notificationsEmptyTitle =>
      _isAr ? 'ÙƒÙ„ Ø´ÙŠØ¡ Ù‡Ø§Ø¯Ø¦ Ø§Ù„Ø¢Ù†' : 'Everything is quiet for now';

  String get notificationsEmptySubtitle => _isAr
      ? 'Ø¹Ù†Ø¯Ù…Ø§ ØªØµÙ„Ùƒ ØªØ­Ø¯ÙŠØ«Ø§Øª Ø¬Ø¯ÙŠØ¯Ø© Ø³ØªØ¸Ù‡Ø± Ù‡Ù†Ø§ Ø¨Ø´ÙƒÙ„ Ù…Ø±ØªØ¨.'
      : 'New updates will appear here in a clean timeline.';

  String get runtimeOpenLabel => _isAr ? 'ÙØªØ­' : 'Open';
  String get runtimeDetailsLabel => _isAr ? 'Ø§Ù„ØªÙØ§ØµÙŠÙ„' : 'Details';
  String get runtimeOpenOrdersLabel => _isAr ? 'ÙØªØ­ Ø§Ù„Ø·Ù„Ø¨Ø§Øª' : 'Open orders';
  String get runtimeOpenAnalyticsLabel =>
      _isAr ? 'ÙØªØ­ Ø§Ù„ØªØ­Ù„ÙŠÙ„Ø§Øª' : 'Open analytics';
  String get runtimeOpenStoreProfileLabel =>
      _isAr ? 'ÙØªØ­ Ù…Ù„Ù Ø§Ù„Ù…ØªØ¬Ø±' : 'Open store profile';
  String get runtimeOpenBranchesLabel =>
      _isAr ? 'ÙØªØ­ Ø§Ù„ÙØ±ÙˆØ¹' : 'Open branches';
  String get runtimeOpenUsersLabel =>
      _isAr ? 'ÙØªØ­ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù…ÙŠÙ†' : 'Open users';
  String get runtimeOpenProductsLabel =>
      _isAr ? 'ÙØªØ­ Ø§Ù„Ù…Ù†ØªØ¬Ø§Øª' : 'Open products';
  String get runtimeOpenCategoriesLabel =>
      _isAr ? 'ÙØªØ­ Ø§Ù„ÙØ¦Ø§Øª' : 'Open categories';
  String get runtimeOpenDeliveryAgentsLabel =>
      _isAr ? 'ÙØªØ­ Ø§Ù„Ù…Ù†Ø§Ø¯ÙŠØ¨' : 'Open delivery agents';
  String get runtimeClaimOrderLabel =>
      _isAr ? 'Ø§Ø³ØªÙ„Ø§Ù… Ø§Ù„Ø·Ù„Ø¨' : 'Claim order';
  String get runtimeStartDeliveryLabel =>
      _isAr ? 'Ø¨Ø¯Ø¡ Ø§Ù„ØªÙˆØµÙŠÙ„' : 'Start delivery';
  String get runtimeMarkArrivedLabel =>
      _isAr ? 'ØªÙ… Ø§Ù„ÙˆØµÙˆÙ„' : 'Mark arrived';
  String get runtimeDeliveredLabel =>
      _isAr ? 'ØªÙ… Ø§Ù„ØªØ³Ù„ÙŠÙ…' : 'Mark delivered';
  String get runtimeBidLabel => _isAr ? 'ØªÙ‚Ø¯ÙŠÙ… Ø¹Ø±Ø¶' : 'Place bid';
  String get runtimeDeclineLabel => _isAr ? 'Ø±ÙØ¶' : 'Decline';
  String get runtimeStartRideLabel =>
      _isAr ? 'Ø¨Ø¯Ø¡ Ø§Ù„Ø±Ø­Ù„Ø©' : 'Start ride';
  String get runtimeCompleteRideLabel =>
      _isAr ? 'Ø¥Ù†Ù‡Ø§Ø¡ Ø§Ù„Ø±Ø­Ù„Ø©' : 'Complete ride';
  String get runtimeCompanySelectorLabel =>
      _isAr ? 'Ø§Ù„Ø´Ø±ÙƒØ© Ø§Ù„Ø­Ø§Ù„ÙŠØ©' : 'Active company';
  String get runtimeActionCompletedLabel =>
      _isAr ? 'ØªÙ… ØªÙ†ÙÙŠØ° Ø§Ù„Ø¥Ø¬Ø±Ø§Ø¡ Ø¨Ù†Ø¬Ø§Ø­.' : 'Action completed successfully.';
  String get runtimeActionFailedLabel => _isAr
      ? 'ØªØ¹Ø°Ø± ØªÙ†ÙÙŠØ° Ø§Ù„Ø¥Ø¬Ø±Ø§Ø¡ Ø§Ù„Ø¢Ù†. Ø­Ø§ÙˆÙ„ Ù…Ø±Ø© Ø£Ø®Ø±Ù‰.'
      : 'Unable to complete the action right now. Please try again.';

  String get signInAsUserHint => _isAr
      ? 'Ù‡Ø°Ù‡ Ù†Ø³Ø®Ø© Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… Ø§Ù„Ù…Ù†ÙØµÙ„Ø©. Ø³Ø¬Ù‘Ù„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ù„ØªØ¬Ø±Ø¨Ø© Ø§Ù„Ù…Ø³Ø§Ø±Ø§Øª Ø§Ù„Ø£Ø³Ø§Ø³ÙŠØ©.'
      : 'This is the split user app. Sign in to try the main user flows.';
  String get storesOpenStatus => _isAr ? 'Ù…ÙØªÙˆØ­' : 'Open';

  String get storesClosedStatus => _isAr ? 'Ù…ØºÙ„Ù‚' : 'Closed';

  String get storesFreeDeliveryBadge => _isAr ? 'ØªÙˆØµÙŠÙ„ Ù…Ø¬Ø§Ù†ÙŠ' : 'Free delivery';

  String get storesOfferBadge => _isAr ? 'Ø¹Ø±Ø¶' : 'Offer';

  String get storesEmptyTitle =>
      _isAr ? 'Ù„Ø§ ØªÙˆØ¬Ø¯ Ù…ØªØ§Ø¬Ø± Ù…Ø·Ø§Ø¨Ù‚Ø© Ø§Ù„Ø¢Ù†' : 'No stores match right now';

  String get storesEmptySubtitle => _isAr
      ? 'Ø¬Ø±Ù‘Ø¨ ØªØºÙŠÙŠØ± Ø§Ù„Ø¨Ø­Ø« Ø£Ùˆ Ø§Ø®ØªØ± Ù†Ø´Ø§Ø·Ù‹Ø§ Ø¢Ø®Ø±.'
      : 'Try another search or switch the activity filter.';
  String get runtimeTaxiTimingTitle => _isAr ? 'ØªÙˆÙ‚ÙŠØª Ø§Ù„Ø±Ø­Ù„Ø©' : 'Ride timing';

  String get runtimeTaxiRideNowLabel => _isAr ? 'Ø§Ù„Ø¢Ù†' : 'Now';

  String get runtimeTaxiRideScheduleLabel => _isAr ? 'Ø¬Ø¯ÙˆÙ„Ø©' : 'Schedule';

  String get runtimeTaxiScheduleTitle =>
      _isAr ? 'ØªØ­Ø¯ÙŠØ¯ Ø§Ù„ØªØ§Ø±ÙŠØ® ÙˆØ§Ù„ÙˆÙ‚Øª' : 'Choose date and time';

  String get runtimeTaxiScheduleHint => _isAr
      ? 'Ø§Ø®ØªØ± ÙˆÙ‚ØªÙ‹Ø§ Ù„Ø§Ø­Ù‚Ù‹Ø§ ÙÙ‚Ø·ØŒ ÙˆÙ„Ø§ ÙŠÙ…ÙƒÙ† Ø§Ø¹ØªÙ…Ø§Ø¯ ÙˆÙ‚Øª Ø³Ø§Ø¨Ù‚.'
      : 'Choose a future time only.';

  String get runtimeTaxiChooseDateAction =>
      _isAr ? 'Ø§Ø®ØªØ± Ø§Ù„Ù…ÙˆØ¹Ø¯' : 'Choose time';

  String get runtimeTaxiPickupTitle => _isAr ? 'Ù†Ù‚Ø·Ø© Ø§Ù„Ø§Ù†Ø·Ù„Ø§Ù‚' : 'Pickup point';

  String get runtimeTaxiPickupHint =>
      _isAr ? 'Ø§ÙƒØªØ¨ Ø§Ø³Ù… Ø§Ù„Ù…ÙƒØ§Ù† Ø£Ùˆ Ø§Ù„Ø­ÙŠ' : 'Enter the place or district';

  String get runtimeTaxiCurrentLocationAction =>
      _isAr ? 'Ø§Ø³ØªØ®Ø¯Ù… Ù…ÙˆÙ‚Ø¹ÙŠ Ø§Ù„Ø­Ø§Ù„ÙŠ' : 'Use my current location';

  String get runtimeTaxiCurrentLocationLabel =>
      _isAr ? 'Ù…ÙˆÙ‚Ø¹ÙŠ Ø§Ù„Ø­Ø§Ù„ÙŠ' : 'My current location';

  String get runtimeTaxiDropoffTitle =>
      _isAr ? 'Ù†Ù‚Ø·Ø© Ø§Ù„ÙˆØµÙˆÙ„' : 'Drop-off point';

  String get runtimeTaxiDropoffHint =>
      _isAr ? 'Ø§ÙƒØªØ¨ Ø§Ù„ÙˆØ¬Ù‡Ø© Ø§Ù„Ù…Ø·Ù„ÙˆØ¨Ø©' : 'Enter the destination';

  String runtimeTaxiDistanceLabel(String value) =>
      _isAr ? 'Ø§Ù„Ù…Ø³Ø§ÙØ© Ø§Ù„ØªÙ‚Ø±ÙŠØ¨ÙŠØ©: $value ÙƒÙ…' : 'Approx. distance: $value km';

  String get runtimeTaxiDistanceValueLabel => _isAr ? 'Ø§Ù„Ù…Ø³Ø§ÙØ©' : 'Distance';

  String get runtimeTaxiEtaLabel => _isAr ? 'Ø§Ù„ÙˆÙ‚Øª Ø§Ù„Ù…ØªÙˆÙ‚Ø¹' : 'ETA';

  String get runtimeTaxiSummaryTitle => _isAr ? 'Ù…Ù„Ø®Øµ Ø§Ù„Ø±Ø­Ù„Ø©' : 'Ride summary';

  String get runtimeTaxiFareFieldLabel =>
      _isAr ? 'Ø§Ù„Ø³Ø¹Ø± Ø§Ù„Ø°ÙŠ Ø³ÙŠØ¸Ù‡Ø± Ù„Ù„ÙƒØ§Ø¨ØªÙ†' : 'Fare shown to captain';

  String get runtimeTaxiCouponFieldLabel => _isAr ? 'Ø§Ù„ÙƒÙˆØ¨ÙˆÙ†' : 'Coupon';

  String get runtimeTaxiFareWarning => _isAr
      ? 'Ø§Ù„Ø³Ø¹Ø± Ø§Ù„Ø£Ù‚Ù„ Ù…Ù† Ø§Ù„Ù…Ù‚ØªØ±Ø­ Ù‚Ø¯ ÙŠÙ‚Ù„Ù„ ÙØ±ØµØ© Ù‚Ø¨ÙˆÙ„ Ø§Ù„Ø·Ù„Ø¨.'
      : 'A lower fare may reduce captain acceptance.';

  String get runtimeTaxiPayloadPreviewTitle =>
      _isAr ? 'Ù…Ø¹Ø§ÙŠÙ†Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„Ù…Ø±Ø³Ù„Ø©' : 'Payload preview';

  String get runtimeTaxiContinueAction => _isAr ? 'Ù…ØªØ§Ø¨Ø¹Ø©' : 'Continue';

  String get runtimeTaxiBackAction => _isAr ? 'Ø±Ø¬ÙˆØ¹' : 'Back';

  String get runtimeTaxiSubmitAction =>
      _isAr ? 'Ø¥Ø±Ø³Ø§Ù„ Ø·Ù„Ø¨ Ø§Ù„ØªÙƒØ³ÙŠ' : 'Send taxi request';
  String get runtimeTrackRideLabel =>
      _isAr ? 'Ù…ØªØ§Ø¨Ø¹Ø© Ø§Ù„Ø±Ø­Ù„Ø©' : 'Track ride';
  String get runtimeCancelRideLabel =>
      _isAr ? 'Ø¥Ù„ØºØ§Ø¡ Ø§Ù„Ø±Ø­Ù„Ø©' : 'Cancel ride';
  String get runtimeShareRideLabel =>
      _isAr ? 'Ù…Ø´Ø§Ø±ÙƒØ© Ø§Ù„Ø±Ø­Ù„Ø©' : 'Share ride';
  String get runtimeShareRideCopiedMessage => _isAr
      ? 'ØªÙ… Ù†Ø³Ø® Ø±Ø§Ø¨Ø· Ù…ØªØ§Ø¨Ø¹Ø© Ø§Ù„Ø±Ø­Ù„Ø©.'
      : 'Ride tracking link copied.';

  String get runtimeTaxiSubmitSuccess => _isAr
      ? 'ØªÙ… ØªØ¬Ù‡ÙŠØ² Ø·Ù„Ø¨ Ø§Ù„ØªÙƒØ³ÙŠ Ø¯Ø§Ø®Ù„ Ù†Ø³Ø®Ø© runtime.'
      : 'Taxi request prepared inside the runtime shell.';

  String get runtimeTaxiScheduleValidation =>
      _isAr ? 'Ø§Ø®ØªØ± Ù…ÙˆØ¹Ø¯Ù‹Ø§ ØµØ§Ù„Ø­Ù‹Ø§ ÙÙŠ Ø§Ù„Ù…Ø³ØªÙ‚Ø¨Ù„.' : 'Choose a valid future time.';

  String get runtimeTaxiPickupValidation =>
      _isAr ? 'Ø­Ø¯Ø¯ Ù†Ù‚Ø·Ø© Ø§Ù„Ø§Ù†Ø·Ù„Ø§Ù‚ Ø£ÙˆÙ„Ù‹Ø§.' : 'Choose the pickup point first.';

  String get runtimeTaxiDropoffValidation =>
      _isAr ? 'Ø­Ø¯Ø¯ Ù†Ù‚Ø·Ø© Ø§Ù„ÙˆØµÙˆÙ„ Ø£ÙˆÙ„Ù‹Ø§.' : 'Choose the drop-off point first.';

  String get runtimeTaxiFareValidation => _isAr
      ? 'Ø£Ø¯Ø®Ù„ Ø³Ø¹Ø±Ù‹Ø§ ØµØ§Ù„Ø­Ù‹Ø§ Ù„Ø§ ÙŠÙ‚Ù„ Ø¹Ù† 1500 Ø¯.Ø¹.'
      : 'Enter a valid fare of at least 1500 IQD.';

  String get runtimeTaxiTimingShort => _isAr ? 'Ø§Ù„ØªÙˆÙ‚ÙŠØª' : 'Timing';

  String get runtimeTaxiPickupShort => _isAr ? 'Ø§Ù„Ø§Ù†Ø·Ù„Ø§Ù‚' : 'Pickup';

  String get runtimeTaxiDropoffShort => _isAr ? 'Ø§Ù„ÙˆØµÙˆÙ„' : 'Drop-off';

  String get runtimeTaxiSummaryShort => _isAr ? 'Ø§Ù„Ù…Ø±Ø§Ø¬Ø¹Ø©' : 'Review';
  String get runtimeAuthHint => _isAr
      ? 'Ø³Ø¬Ù‘Ù„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ø¨Ø±Ù‚Ù… Ø§Ù„Ù‡Ø§ØªÙ ÙˆØ§Ù„Ø±Ù…Ø² Ø§Ù„Ø³Ø±ÙŠ Ù„Ù„Ù…ØªØ§Ø¨Ø¹Ø© Ø¯Ø§Ø®Ù„ Ù†Ø³Ø®Ø© Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… Ø§Ù„Ù…Ù†ÙØµÙ„Ø©.'
      : 'Sign in with your phone number and PIN to continue in the split user app.';

  String get runtimePhoneLabel => _isAr ? 'Ø±Ù‚Ù… Ø§Ù„Ù‡Ø§ØªÙ' : 'Phone number';

  String get runtimePinLabel => _isAr ? 'Ø§Ù„Ø±Ù…Ø² Ø§Ù„Ø³Ø±ÙŠ' : 'PIN';
}

extension CoreRuntimeAuthLocalization on CoreAppLocalizations {
  String get runtimeAuthUnavailableError => _isAr
      ? 'ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ø§Ù„Ø´Ø¨ÙƒÙŠ ØºÙŠØ± Ù…ØªØ§Ø­ Ø­Ø§Ù„ÙŠÙ‹Ø§ ÙÙŠ Ù‡Ø°Ù‡ Ø§Ù„Ù†Ø³Ø®Ø©.'
      : 'Network sign-in is not available in this runtime.';

  String get runtimeAuthRoleMismatchError => _isAr
      ? 'Ù‡Ø°Ø§ Ø§Ù„Ø­Ø³Ø§Ø¨ Ù„Ø§ ÙŠØ·Ø§Ø¨Ù‚ Ø¯ÙˆØ± Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ Ø§Ù„Ø­Ø§Ù„ÙŠ.'
      : 'This account does not match the current app role.';

  String get runtimeAuthSignInFailedError => _isAr
      ? 'ØªØ¹Ø°Ø± ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ø§Ù„Ø¢Ù†. ØªØ­Ù‚Ù‚ Ù…Ù† Ø±Ù‚Ù… Ø§Ù„Ù‡Ø§ØªÙ ÙˆØ§Ù„Ø±Ù…Ø² Ø§Ù„Ø³Ø±ÙŠ.'
      : 'Unable to sign in right now. Check your phone number and PIN.';
}

extension CoreRuntimeTaxiLocalization on CoreAppLocalizations {
  String get runtimeTaxiSubmitCreated =>
      _isAr ? 'ØªÙ… Ø¥Ø±Ø³Ø§Ù„ Ø·Ù„Ø¨ Ø§Ù„ØªÙƒØ³ÙŠ Ø¨Ù†Ø¬Ø§Ø­.' : 'Taxi request sent successfully.';

  String get runtimeTaxiSubmitFailed => _isAr
      ? 'ØªØ¹Ø°Ø± Ø¥Ø±Ø³Ø§Ù„ Ø·Ù„Ø¨ Ø§Ù„ØªÙƒØ³ÙŠ Ø§Ù„Ø¢Ù†.'
      : 'Unable to send the taxi request right now.';
}

extension CoreRuntimeDashboardLocalization on CoreAppLocalizations {
  String get commonToday => _isAr ? 'Ã˜Â§Ã™â€žÃ™Å Ã™Ë†Ã™â€¦' : 'Today';

  String get runtimeCurrentRideTitle =>
      _isAr ? 'Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â­Ã™â€žÃ˜Â© Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å Ã˜Â©' : 'Current ride';

  String get runtimeNoRideTitle =>
      _isAr ? 'Ã™â€žÃ˜Â§ Ã˜ÂªÃ™Ë†Ã˜Â¬Ã˜Â¯ Ã˜Â±Ã˜Â­Ã™â€žÃ˜Â© Ã™â€ Ã˜Â´Ã˜Â·Ã˜Â©' : 'No active ride';

  String get runtimeNoRideSubtitle => _isAr
      ? 'Ã˜Â³Ã˜ÂªÃ˜Â¸Ã™â€¡Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â­Ã™â€žÃ˜Â© Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å Ã˜Â© Ã™â€¡Ã™â€ Ã˜Â§ Ã™â€¦Ã˜Â¬Ã˜Â±Ã˜Â¯ Ã™â€šÃ˜Â¨Ã™Ë†Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â·Ã™â€žÃ˜Â¨.'
      : 'The active ride will appear here once a request is accepted.';

  String get runtimeRideRequestsTitle =>
      _isAr ? 'Ã˜Â§Ã™â€žÃ˜Â·Ã™â€žÃ˜Â¨Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ™â€šÃ˜Â±Ã™Å Ã˜Â¨Ã˜Â©' : 'Nearby requests';

  String emptyStateTitle(RuntimeAppScope scope, String sectionLabel) => _isAr
      ? 'Ã™â€žÃ˜Â§ Ã™Å Ã™Ë†Ã˜Â¬Ã˜Â¯ $sectionLabel Ã˜Â¶Ã™â€¦Ã™â€  ${dashboardTitle(scope)} Ã˜Â§Ã™â€žÃ˜Â¢Ã™â€ .'
      : 'No $sectionLabel available in ${dashboardTitle(scope)} right now.';

  String emptyStateSubtitle(RuntimeAppScope scope, String sectionLabel) => _isAr
      ? 'Ã˜Â³Ã™Å Ã˜Â¸Ã™â€¡Ã˜Â± Ã™â€¡Ã˜Â°Ã˜Â§ Ã˜Â§Ã™â€žÃ™â€šÃ˜Â³Ã™â€¦ Ã™â€¡Ã™â€ Ã˜Â§ Ã˜Â¹Ã™â€ Ã˜Â¯Ã™â€¦Ã˜Â§ Ã˜ÂªÃ˜ÂªÃ™Ë†Ã™ÂÃ˜Â± Ã˜Â¨Ã™Å Ã˜Â§Ã™â€ Ã˜Â§Ã˜Âª $sectionLabel.'
      : 'This section will appear here when $sectionLabel data becomes available.';
}

extension CoreRuntimeOpsLocalization on CoreAppLocalizations {
  String get runtimeTodayLabel => _isAr ? 'Ø§Ù„ÙŠÙˆÙ…' : 'Today';

  String get runtimeCurrentRideLabel =>
      _isAr ? 'Ø§Ù„Ø±Ø­Ù„Ø© Ø§Ù„Ø­Ø§Ù„ÙŠØ©' : 'Current ride';

  String get runtimeNoActiveRideTitle =>
      _isAr ? 'Ù„Ø§ ØªÙˆØ¬Ø¯ Ø±Ø­Ù„Ø© Ù†Ø´Ø·Ø©' : 'No active ride';

  String get runtimeNoActiveRideSubtitle => _isAr
      ? 'Ø³ØªØ¸Ù‡Ø± Ø§Ù„Ø±Ø­Ù„Ø© Ø§Ù„Ø­Ø§Ù„ÙŠØ© Ù‡Ù†Ø§ Ø¨Ù…Ø¬Ø±Ø¯ Ù‚Ø¨ÙˆÙ„ Ø§Ù„Ø·Ù„Ø¨.'
      : 'The active ride will appear here once a request is accepted.';

  String get runtimeNearbyRequestsLabel =>
      _isAr ? 'Ø§Ù„Ø·Ù„Ø¨Ø§Øª Ø§Ù„Ù‚Ø±ÙŠØ¨Ø©' : 'Nearby requests';

  String runtimeEmptyTitle(String sectionLabel) => _isAr
      ? 'Ù„Ø§ ØªÙˆØ¬Ø¯ Ø¨ÙŠØ§Ù†Ø§Øª $sectionLabel Ø§Ù„Ø¢Ù†.'
      : 'No $sectionLabel available right now.';

  String runtimeEmptySubtitle(String sectionLabel) => _isAr
      ? 'Ø³ÙŠØ¸Ù‡Ø± Ù‡Ø°Ø§ Ø§Ù„Ù‚Ø³Ù… Ù‡Ù†Ø§ Ø¹Ù†Ø¯Ù…Ø§ ØªØªÙˆÙØ± Ø¨ÙŠØ§Ù†Ø§Øª $sectionLabel.'
      : 'This section will appear here when $sectionLabel data becomes available.';

  String get runtimeProductsLabel => _isAr ? 'Ø§Ù„Ù…Ù†ØªØ¬Ø§Øª' : 'Products';

  String get runtimeCategoriesLabel => _isAr ? 'Ø§Ù„ÙØ¦Ø§Øª' : 'Categories';

  String get runtimeAssignDeliveryLabel =>
      _isAr ? 'ØªØ¹ÙŠÙŠÙ† Ù…Ù†Ø¯ÙˆØ¨' : 'Assign delivery';

  String get runtimeOrderStatusLabel =>
      _isAr ? 'Ø­Ø§Ù„Ø© Ø§Ù„Ø·Ù„Ø¨' : 'Order status';

  String get runtimeSyncCaptainPresenceLabel => _isAr
      ? 'ØªØ­Ø¯ÙŠØ« Ø­Ø§Ù„Ø© Ø§Ù„ÙƒØ§Ø¨ØªÙ†'
      : 'Sync captain presence';

  String get runtimeSendRideLocationLabel => _isAr
      ? 'Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„Ù…ÙˆÙ‚Ø¹ Ø§Ù„Ø­Ø§Ù„ÙŠ'
      : 'Send current location';

  String get runtimeCompanySelectionRequiredTitle => _isAr
      ? 'Ø§Ø®ØªØ± Ø§Ù„Ø´Ø±ÙƒØ© Ø£ÙˆÙ„Ù‹Ø§'
      : 'Choose a company first';

  String get runtimeCompanySelectionRequiredSubtitle => _isAr
      ? 'Ø­Ø¯Ø¯ Ø§Ù„Ø´Ø±ÙƒØ© Ø§Ù„ØªÙŠ ØªØ±ÙŠØ¯ Ø¥Ø¯Ø§Ø±ØªÙ‡Ø§ Ù‚Ø¨Ù„ ÙØªØ­ Ø§Ù„Ù„ÙˆØ­Ø§Øª ÙˆØ§Ù„ØªÙ‚Ø§Ø±ÙŠØ±.'
      : 'Select the company context before opening dashboards and reports.';
}

class _CoreAppLocalizationsDelegate
    extends LocalizationsDelegate<CoreAppLocalizations> {
  const _CoreAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => CoreAppLocalizations.supportedLocales.any(
    (item) => item.languageCode == locale.languageCode,
  );

  @override
  Future<CoreAppLocalizations> load(Locale locale) {
    return SynchronousFuture<CoreAppLocalizations>(
      CoreAppLocalizations(locale),
    );
  }

  @override
  bool shouldReload(_CoreAppLocalizationsDelegate old) => false;
}

extension CoreLocalizationContext on BuildContext {
  CoreAppLocalizations get l10n => CoreAppLocalizations.of(this);
}

