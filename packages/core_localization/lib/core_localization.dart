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

  String get appName => _isAr ? 'مسلكي' : 'مسلكي';

  String get userAppWindowTitle =>
      _isAr ? 'مسلكي - تطبيق المستخدم' : 'مسلكي User';

  String get storePortalWindowTitle =>
      _isAr ? 'مسلكي - بوابة المتجر' : 'مسلكي Store Portal';

  String get deliveryAppTitle =>
      _isAr ? 'مسلكي - تطبيق الدلفري' : 'مسلكي Delivery App';

  String get taxiCaptainAppTitle =>
      _isAr ? 'مسلكي - تطبيق الكابتن' : 'مسلكي Captain App';

  String get companyPortalWindowTitle =>
      _isAr ? 'مسلكي - بوابة الإدارة' : 'مسلكي Company Portal';

  String get commonLogout => _isAr ? 'تسجيل الخروج' : 'Logout';
  String get commonContinue => _isAr ? 'متابعة' : 'Continue';
  String get commonRefresh => _isAr ? 'تحديث' : 'Refresh';
  String get commonOpenSettings => _isAr ? 'فتح الإعدادات' : 'Open settings';
  String get commonEnable => _isAr ? 'تفعيل' : 'Enable';

  String get loginHeadline =>
      _isAr ? 'سجّل الدخول للمتابعة' : 'Sign in to continue';

  String roleLoginTitle(RuntimeAppScope scope) {
    if (_isAr) {
      return switch (scope) {
        RuntimeAppScope.user => 'تسجيل دخول المستخدم',
        RuntimeAppScope.store => 'تسجيل دخول صاحب المتجر',
        RuntimeAppScope.delivery => 'تسجيل دخول الدلفري',
        RuntimeAppScope.taxiCaptain => 'تسجيل دخول الكابتن',
        RuntimeAppScope.company => 'تسجيل دخول الإدارة',
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
        RuntimeAppScope.user => 'تسجيل الدخول',
        RuntimeAppScope.store => 'تسجيل الدخول للمتجر',
        RuntimeAppScope.delivery => 'تسجيل الدخول للدلفري',
        RuntimeAppScope.taxiCaptain => 'تسجيل الدخول للكابتن',
        RuntimeAppScope.company => 'تسجيل الدخول للإدارة',
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
        RuntimeAppScope.user => 'الرئيسية',
        RuntimeAppScope.store => 'لوحة المتجر',
        RuntimeAppScope.delivery => 'لوحة الدلفري',
        RuntimeAppScope.taxiCaptain => 'لوحة الكابتن',
        RuntimeAppScope.company => 'لوحة الإدارة',
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

  String get reelsLabel => _isAr ? 'ريلز' : 'Reels';
  String get createStoreLabel => _isAr ? 'إنشاء متجر' : 'Create Store';
  String get ordersLabel => _isAr ? 'الطلبات' : 'Orders';
  String get taxiLabel => _isAr ? 'تكسي' : 'Taxi';
  String get storesLabel => _isAr ? 'المتاجر' : 'Stores';
  String get notificationsLabel => _isAr ? 'الإشعارات' : 'Notifications';
  String get profileLabel => _isAr ? 'الحساب' : 'Profile';
  String get exploreLabel => _isAr ? 'اكتشف' : 'Discover';
  String get homeLabel => _isAr ? 'الرئيسية' : 'Home';
  String get settingsLabel => _isAr ? 'الإعدادات' : 'Settings';

  String get userConsentTitle => _isAr ? 'ابدأ مع مسلكي' : 'Start with مسلكي';

  String get userConsentSubtitle => _isAr
      ? 'قبل الدخول للتجربة، فعّل الأساسيات التي تساعدنا نوصل لك الخدمات القريبة ونرسل لك تحديثات الطلبات.'
      : 'Before you continue, enable the essentials that help us find nearby services and send order updates.';

  String get locationPermissionTitle => _isAr ? 'الموقع' : 'Location';

  String get locationPermissionDescription => _isAr
      ? 'نحتاج الموقع لتحديد نقطة الانطلاق في التكسي وعرض الخدمات والمتاجر القريبة منك.'
      : 'We use your location to set taxi pickup points and show nearby services and stores.';

  String get notificationsPermissionTitle =>
      _isAr ? 'الإشعارات' : 'Notifications';

  String get notificationsPermissionDescription => _isAr
      ? 'فعّل الإشعارات لتصلك تحديثات الطلبات والرحلات والرسائل المهمة في وقتها.'
      : 'Enable notifications to receive order, ride, and message updates on time.';

  String get continueToLoginLabel =>
      _isAr ? 'المتابعة إلى تسجيل الدخول' : 'Continue to sign in';

  String get homeGreeting => _isAr ? 'أهلًا بك' : 'Welcome back';

  String get homeSummary => _isAr
      ? 'واجهة أخف وأوضح تركّز على أهم الخدمات التي تحتاجها بسرعة.'
      : 'A lighter, clearer home focused on the services you need most.';

  String get quickActionsTitle => _isAr ? 'وصول سريع' : 'Quick access';

  String get startupHighlightsTitle => _isAr ? 'جاهز للخدمة' : 'Ready to go';

  String get startupHighlightsSubtitle => _isAr
      ? 'من هنا تقدر تفتح المتاجر، تطلب تكسي، وتتابع الريلز من واجهة واحدة.'
      : 'Open stores, request a ride, and follow reels from one place.';

  String get locationCardTitle => _isAr ? 'حالة الموقع' : 'Location status';

  String get locationPreciseGranted => _isAr
      ? 'الموقع الدقيق مفعّل وجاهز للتكسي والخدمات القريبة.'
      : 'Precise location is enabled and ready for taxi and nearby services.';

  String get locationApproximateGranted => _isAr
      ? 'الموقع التقريبي مفعّل. للحصول على نتائج أدق، فعّل الموقع الدقيق من الإعدادات.'
      : 'Approximate location is enabled. Enable precise location from settings for better results.';

  String get locationDeniedMessage => _isAr
      ? 'صلاحية الموقع مرفوضة حاليًا. يمكنك تفعيلها من هنا أو اختيار الموقع يدويًا لاحقًا.'
      : 'Location permission is currently denied. You can enable it here or choose your location manually later.';

  String get locationDeniedForeverMessage => _isAr
      ? 'الموقع مرفوض بشكل دائم. افتح إعدادات التطبيق لإعادة التفعيل.'
      : 'Location permission is permanently denied. Open app settings to enable it again.';

  String get locationServiceDisabledMessage => _isAr
      ? 'خدمة الموقع في الجهاز متوقفة. فعّلها أولًا ثم أعد المحاولة.'
      : 'Location services are turned off on the device. Turn them on and try again.';

  String get requestLocationLabel => _isAr ? 'تفعيل الموقع' : 'Enable location';

  String get openLocationSettingsLabel =>
      _isAr ? 'فتح إعدادات الموقع' : 'Open location settings';

  String get chooseLocationManuallyLabel =>
      _isAr ? 'اختيار الموقع يدويًا' : 'Choose location manually';

  String get discoverStoresTitle => _isAr ? 'استكشف المتاجر' : 'Explore stores';

  String get discoverStoresSubtitle => _isAr
      ? 'المطاعم، الصيدليات، والسوبرماركت في مكان واحد.'
      : 'Restaurants, pharmacies, and supermarkets in one place.';

  String get requestTaxiTitle => _isAr ? 'اطلب تكسي' : 'Request a taxi';

  String get requestTaxiSubtitle => _isAr
      ? 'حدّد الانطلاق والوصول وتتبع الرحلة بسهولة.'
      : 'Set pickup and drop-off, then track your ride with ease.';

  String get watchReelsTitle => _isAr ? 'تابع الريلز' : 'Watch reels';

  String get watchReelsSubtitle => _isAr
      ? 'محتوى سريع من المجتمع والمتاجر.'
      : 'Quick content from the community and stores.';

  String get ordersEmptyTitle =>
      _isAr ? 'لا توجد طلبات حتى الآن' : 'No orders yet';

  String get ordersEmptySubtitle => _isAr
      ? 'عندما تبدأ الطلبات والرحلات، ستظهر تحديثاتها هنا.'
      : 'Your orders and ride updates will appear here once you start.';

  String get profileSectionTitle =>
      _isAr ? 'تخصيص التجربة' : 'Personalize your experience';

  String get themeSectionTitle => _isAr ? 'لوحة الألوان' : 'Color preset';

  String get languageSectionTitle => _isAr ? 'اللغة' : 'Language';

  String get animationsLabel => _isAr ? 'تفعيل الحركة' : 'Enable animations';

  String get ambientEffectsLabel =>
      _isAr ? 'تأثيرات الخلفية' : 'Background effects';

  String get themePresetMidnightBlue =>
      _isAr ? 'أزرق منتصف الليل' : 'Midnight Blue';

  String get themePresetRoyalIndigo => _isAr ? 'نيلي ملكي' : 'Royal Indigo';

  String get themePresetEmeraldNight => _isAr ? 'زمردي ليلي' : 'Emerald Night';

  String get themePresetSunsetNeon => _isAr ? 'نيون الغروب' : 'Sunset Neon';

  String get languageArabic => _isAr ? 'العربية' : 'Arabic';
  String get languageEnglish => _isAr ? 'الإنجليزية' : 'English';

  String get storesHubTitle => _isAr ? 'المتاجر القريبة' : 'Nearby stores';

  String get storesHubSubtitle => _isAr
      ? 'اكتشف المطاعم والصيدليات والمتاجر السريعة من واجهة مستخدم خفيفة.'
      : 'Browse restaurants, pharmacies, and fast delivery stores from a lighter shell.';

  String get storesSearchHint =>
      _isAr ? 'ابحث عن متجر أو نشاط' : 'Search for a store or activity';

  String get storesCategoryRestaurants => _isAr ? 'مطاعم' : 'Restaurants';

  String get storesCategoryPharmacies => _isAr ? 'صيدليات' : 'Pharmacies';

  String get storesCategorySupermarket => _isAr ? 'سوبرماركت' : 'Supermarket';

  String get storesCategoryCoffee => _isAr ? 'قهوة' : 'Coffee';

  String get storesFeaturedSectionTitle =>
      _isAr ? 'ترشيحات سريعة' : 'Quick picks';

  String get storesDeliveryEtaLabel => _isAr ? 'زمن التوصيل' : 'Delivery ETA';

  String get taxiHubTitle => _isAr ? 'مركز التكسي' : 'Taxi hub';

  String get taxiHubSubtitle => _isAr
      ? 'ابدأ الرحلة بخطوات أوضح: تحقق من الموقع ثم جهّز نقطة الانطلاق والوصول.'
      : 'Start a clearer ride flow: verify location, then prepare pickup and drop-off.';

  String get taxiPickupAction => _isAr ? 'حدد نقطة الانطلاق' : 'Choose pickup';

  String get taxiDropoffAction => _isAr ? 'حدد الوجهة' : 'Choose drop-off';

  String get taxiOpenMapAction => _isAr ? 'افتح خريطة الرحلة' : 'Open ride map';

  String get taxiLocationReady => _isAr
      ? 'الموقع جاهز لبدء طلب التكسي.'
      : 'Location is ready to start your ride.';

  String get taxiLocationNeedsAttention => _isAr
      ? 'فعّل الموقع أولًا أو اختر النقطة يدويًا قبل إرسال الطلب.'
      : 'Enable location first or choose the point manually before sending the request.';

  String get taxiEstimatedFareLabel =>
      _isAr ? 'الأجرة التقريبية' : 'Estimated fare';

  String get reelsHubTitle => _isAr ? 'ريلز اليوم' : 'Today\'s reels';

  String get reelsHubSubtitle => _isAr
      ? 'لقطات سريعة من المجتمع والمتاجر، مع واجهة أخف للمتابعة.'
      : 'Quick clips from the community and stores in a lighter viewing shell.';

  String get reelsFeaturedSectionTitle =>
      _isAr ? 'أحدث المقاطع' : 'Latest clips';

  String get notificationsHubTitle =>
      _isAr ? 'مركز الإشعارات' : 'Notifications hub';

  String get notificationsHubSubtitle => _isAr
      ? 'تابع الطلبات والتنبيهات المهمة بدون فتح كل شاشة على حدة.'
      : 'Track orders and important alerts without opening every screen.';

  String get notificationsEmptyTitle =>
      _isAr ? 'كل شيء هادئ الآن' : 'Everything is quiet for now';

  String get notificationsEmptySubtitle => _isAr
      ? 'عندما تصلك تحديثات جديدة ستظهر هنا بشكل مرتب.'
      : 'New updates will appear here in a clean timeline.';

  String get runtimeOpenLabel => _isAr ? 'فتح' : 'Open';
  String get runtimeDetailsLabel => _isAr ? 'التفاصيل' : 'Details';
  String get runtimeOpenOrdersLabel => _isAr ? 'فتح الطلبات' : 'Open orders';
  String get runtimeOpenAnalyticsLabel =>
      _isAr ? 'فتح التحليلات' : 'Open analytics';
  String get runtimeOpenStoreProfileLabel =>
      _isAr ? 'فتح ملف المتجر' : 'Open store profile';
  String get runtimeOpenBranchesLabel => _isAr ? 'فتح الفروع' : 'Open branches';
  String get runtimeOpenUsersLabel => _isAr ? 'فتح المستخدمين' : 'Open users';
  String get runtimeOpenProductsLabel =>
      _isAr ? 'فتح المنتجات' : 'Open products';
  String get runtimeOpenCategoriesLabel =>
      _isAr ? 'فتح الفئات' : 'Open categories';
  String get runtimeOpenDeliveryAgentsLabel =>
      _isAr ? 'فتح المناديب' : 'Open delivery agents';
  String get runtimeClaimOrderLabel => _isAr ? 'استلام الطلب' : 'Claim order';
  String get runtimeStartDeliveryLabel =>
      _isAr ? 'بدء التوصيل' : 'Start delivery';
  String get runtimeMarkArrivedLabel => _isAr ? 'تم الوصول' : 'Mark arrived';
  String get runtimeDeliveredLabel => _isAr ? 'تم التسليم' : 'Mark delivered';
  String get runtimeBidLabel => _isAr ? 'تقديم عرض' : 'Place bid';
  String get runtimeDeclineLabel => _isAr ? 'رفض' : 'Decline';
  String get runtimeStartRideLabel => _isAr ? 'بدء الرحلة' : 'Start ride';
  String get runtimeCompleteRideLabel =>
      _isAr ? 'إنهاء الرحلة' : 'Complete ride';
  String get runtimeCompanySelectorLabel =>
      _isAr ? 'الشركة الحالية' : 'Active company';
  String get runtimeActionCompletedLabel =>
      _isAr ? 'تم تنفيذ الإجراء بنجاح.' : 'Action completed successfully.';
  String get runtimeActionFailedLabel => _isAr
      ? 'تعذر تنفيذ الإجراء الآن. حاول مرة أخرى.'
      : 'Unable to complete the action right now. Please try again.';

  String get signInAsUserHint => _isAr
      ? 'هذه نسخة المستخدم المنفصلة. سجّل الدخول لتجربة المسارات الأساسية.'
      : 'This is the split user app. Sign in to try the main user flows.';
  String get storesOpenStatus => _isAr ? 'مفتوح' : 'Open';

  String get storesClosedStatus => _isAr ? 'مغلق' : 'Closed';

  String get storesFreeDeliveryBadge => _isAr ? 'توصيل مجاني' : 'Free delivery';

  String get storesOfferBadge => _isAr ? 'عرض' : 'Offer';

  String get storesEmptyTitle =>
      _isAr ? 'لا توجد متاجر مطابقة الآن' : 'No stores match right now';

  String get storesEmptySubtitle => _isAr
      ? 'جرّب تغيير البحث أو اختر نشاطًا آخر.'
      : 'Try another search or switch the activity filter.';
  String get runtimeTaxiTimingTitle => _isAr ? 'توقيت الرحلة' : 'Ride timing';

  String get runtimeTaxiRideNowLabel => _isAr ? 'الآن' : 'Now';

  String get runtimeTaxiRideScheduleLabel => _isAr ? 'جدولة' : 'Schedule';

  String get runtimeTaxiScheduleTitle =>
      _isAr ? 'تحديد التاريخ والوقت' : 'Choose date and time';

  String get runtimeTaxiScheduleHint => _isAr
      ? 'اختر وقتًا لاحقًا فقط، ولا يمكن اعتماد وقت سابق.'
      : 'Choose a future time only.';

  String get runtimeTaxiChooseDateAction =>
      _isAr ? 'اختر الموعد' : 'Choose time';

  String get runtimeTaxiPickupTitle => _isAr ? 'نقطة الانطلاق' : 'Pickup point';

  String get runtimeTaxiPickupHint =>
      _isAr ? 'اكتب اسم المكان أو الحي' : 'Enter the place or district';

  String get runtimeTaxiCurrentLocationAction =>
      _isAr ? 'استخدم موقعي الحالي' : 'Use my current location';

  String get runtimeTaxiCurrentLocationLabel =>
      _isAr ? 'موقعي الحالي' : 'My current location';

  String get runtimeTaxiDropoffTitle =>
      _isAr ? 'نقطة الوصول' : 'Drop-off point';

  String get runtimeTaxiDropoffHint =>
      _isAr ? 'اكتب الوجهة المطلوبة' : 'Enter the destination';

  String runtimeTaxiDistanceLabel(String value) =>
      _isAr ? 'المسافة التقريبية: $value كم' : 'Approx. distance: $value km';

  String get runtimeTaxiDistanceValueLabel => _isAr ? 'المسافة' : 'Distance';

  String get runtimeTaxiEtaLabel => _isAr ? 'الوقت المتوقع' : 'ETA';

  String get runtimeTaxiSummaryTitle => _isAr ? 'ملخص الرحلة' : 'Ride summary';

  String get runtimeTaxiFareFieldLabel =>
      _isAr ? 'السعر الذي سيظهر للكابتن' : 'Fare shown to captain';

  String get runtimeTaxiCouponFieldLabel => _isAr ? 'الكوبون' : 'Coupon';

  String get runtimeTaxiFareWarning => _isAr
      ? 'السعر الأقل من المقترح قد يقلل فرصة قبول الطلب.'
      : 'A lower fare may reduce captain acceptance.';

  String get runtimeTaxiPayloadPreviewTitle =>
      _isAr ? 'معاينة البيانات المرسلة' : 'Payload preview';

  String get runtimeTaxiContinueAction => _isAr ? 'متابعة' : 'Continue';

  String get runtimeTaxiBackAction => _isAr ? 'رجوع' : 'Back';

  String get runtimeTaxiSubmitAction =>
      _isAr ? 'إرسال طلب التكسي' : 'Send taxi request';
  String get runtimeTrackRideLabel => _isAr ? 'متابعة الرحلة' : 'Track ride';
  String get runtimeCancelRideLabel => _isAr ? 'إلغاء الرحلة' : 'Cancel ride';
  String get runtimeShareRideLabel => _isAr ? 'مشاركة الرحلة' : 'Share ride';
  String get runtimeShareRideCopiedMessage =>
      _isAr ? 'تم نسخ رابط متابعة الرحلة.' : 'Ride tracking link copied.';

  String get runtimeTaxiSubmitSuccess => _isAr
      ? 'تم تجهيز طلب التكسي داخل نسخة runtime.'
      : 'Taxi request prepared inside the runtime shell.';

  String get runtimeTaxiScheduleValidation =>
      _isAr ? 'اختر موعدًا صالحًا في المستقبل.' : 'Choose a valid future time.';

  String get runtimeTaxiPickupValidation =>
      _isAr ? 'حدد نقطة الانطلاق أولًا.' : 'Choose the pickup point first.';

  String get runtimeTaxiDropoffValidation =>
      _isAr ? 'حدد نقطة الوصول أولًا.' : 'Choose the drop-off point first.';

  String get runtimeTaxiFareValidation => _isAr
      ? 'أدخل سعرًا صالحًا لا يقل عن 1500 د.ع.'
      : 'Enter a valid fare of at least 1500 IQD.';

  String get runtimeTaxiTimingShort => _isAr ? 'التوقيت' : 'Timing';

  String get runtimeTaxiPickupShort => _isAr ? 'الانطلاق' : 'Pickup';

  String get runtimeTaxiDropoffShort => _isAr ? 'الوصول' : 'Drop-off';

  String get runtimeTaxiSummaryShort => _isAr ? 'المراجعة' : 'Review';
  String get runtimeAuthHint => _isAr
      ? 'سجّل الدخول برقم الهاتف والرمز السري للمتابعة داخل التطبيق.'
      : 'Sign in with your phone number and PIN to continue in this app.';

  String get runtimePhoneLabel => _isAr ? 'رقم الهاتف' : 'Phone number';

  String get runtimePinLabel => _isAr ? 'الرمز السري' : 'PIN';
}

extension CoreRuntimeAuthLocalization on CoreAppLocalizations {
  String get runtimeAuthUnavailableError => _isAr
      ? 'تسجيل الدخول الشبكي غير متاح حاليًا في هذه النسخة.'
      : 'Network sign-in is not available in this runtime.';

  String get runtimeAuthRoleMismatchError => _isAr
      ? 'هذا الحساب لا يطابق دور التطبيق الحالي.'
      : 'This account does not match the current app role.';

  String get runtimeAuthSignInFailedError => _isAr
      ? 'تعذر تسجيل الدخول الآن. تحقق من رقم الهاتف والرمز السري.'
      : 'Unable to sign in right now. Check your phone number and PIN.';
}

extension CoreRuntimeTaxiLocalization on CoreAppLocalizations {
  String get runtimeTaxiSubmitCreated =>
      _isAr ? 'تم إرسال طلب التكسي بنجاح.' : 'Taxi request sent successfully.';

  String get runtimeTaxiSubmitFailed => _isAr
      ? 'تعذر إرسال طلب التكسي الآن.'
      : 'Unable to send the taxi request right now.';
}

extension CoreRuntimeDashboardLocalization on CoreAppLocalizations {
  String get commonToday => _isAr ? 'اليوم' : 'Today';

  String get runtimeCurrentRideTitle =>
      _isAr ? 'الرحلة الحالية' : 'Current ride';

  String get runtimeNoRideTitle =>
      _isAr ? 'لا توجد رحلة نشطة' : 'No active ride';

  String get runtimeNoRideSubtitle => _isAr
      ? 'ستظهر الرحلة الحالية هنا مجرد قبول الطلب.'
      : 'The active ride will appear here once a request is accepted.';

  String get runtimeRideRequestsTitle =>
      _isAr ? 'الطلبات القريبة' : 'Nearby requests';

  String emptyStateTitle(RuntimeAppScope scope, String sectionLabel) => _isAr
      ? 'لا يوجد $sectionLabel ضمن ${dashboardTitle(scope)} الآن.'
      : 'No $sectionLabel available in ${dashboardTitle(scope)} right now.';

  String emptyStateSubtitle(RuntimeAppScope scope, String sectionLabel) => _isAr
      ? 'سيظهر هذا القسم هنا عندما تتوفر بيانات $sectionLabel.'
      : 'This section will appear here when $sectionLabel data becomes available.';
}

extension CoreRuntimeOpsLocalization on CoreAppLocalizations {
  String get runtimeTodayLabel => _isAr ? 'اليوم' : 'Today';

  String get runtimeCurrentRideLabel =>
      _isAr ? 'الرحلة الحالية' : 'Current ride';

  String get runtimeNoActiveRideTitle =>
      _isAr ? 'لا توجد رحلة نشطة' : 'No active ride';

  String get runtimeNoActiveRideSubtitle => _isAr
      ? 'ستظهر الرحلة الحالية هنا بمجرد قبول الطلب.'
      : 'The active ride will appear here once a request is accepted.';

  String get runtimeNearbyRequestsLabel =>
      _isAr ? 'الطلبات القريبة' : 'Nearby requests';

  String runtimeEmptyTitle(String sectionLabel) => _isAr
      ? 'لا توجد بيانات $sectionLabel الآن.'
      : 'No $sectionLabel available right now.';

  String runtimeEmptySubtitle(String sectionLabel) => _isAr
      ? 'سيظهر هذا القسم هنا عندما تتوفر بيانات $sectionLabel.'
      : 'This section will appear here when $sectionLabel data becomes available.';

  String get runtimeProductsLabel => _isAr ? 'المنتجات' : 'Products';

  String get runtimeCategoriesLabel => _isAr ? 'الفئات' : 'Categories';

  String get runtimeAssignDeliveryLabel =>
      _isAr ? 'تعيين مندوب' : 'Assign delivery';

  String get runtimeOrderStatusLabel => _isAr ? 'حالة الطلب' : 'Order status';

  String get runtimeSyncCaptainPresenceLabel =>
      _isAr ? 'تحديث حالة الكابتن' : 'Sync captain presence';

  String get runtimeSendRideLocationLabel =>
      _isAr ? 'إرسال الموقع الحالي' : 'Send current location';

  String get runtimeCompanySelectionRequiredTitle =>
      _isAr ? 'اختر الشركة أولًا' : 'Choose a company first';

  String get runtimeCompanySelectionRequiredSubtitle => _isAr
      ? 'حدد الشركة التي تريد إدارتها قبل فتح اللوحات والتقارير.'
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
