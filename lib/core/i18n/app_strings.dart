import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings_controller.dart';

class AppStrings {
  final String _lang;

  const AppStrings(this._lang);

  bool get isEnglish => _lang == 'en';

  String t(String key) {
    final entry = _translations[key];
    if (entry == null) return key;
    return entry[_lang] ?? entry['ar'] ?? key;
  }
}

final appStringsProvider = Provider<AppStrings>((ref) {
  final locale = ref.watch(
    appSettingsControllerProvider.select((s) => s.locale),
  );
  return AppStrings(locale.languageCode.toLowerCase());
});

const Map<String, Map<String, String>> _translations = {
  'settings': {'ar': 'الإعدادات', 'en': 'Settings'},
  'logout': {'ar': 'تسجيل الخروج', 'en': 'Logout'},
  'myOrders': {'ar': 'طلباتي', 'en': 'My Orders'},
  'customerHomeTitle': {
    'ar': 'مَسْلَكي | سوقك اليومي',
    'en': 'Maslaki | Your Daily Market',
  },
  'backofficeMerchantsTitle': {
    'ar': 'إدارة المتاجر',
    'en': 'Merchants Management',
  },
  'ownerDashboard': {'ar': 'لوحة صاحب المتجر', 'en': 'Owner Dashboard'},
  'deliveryDashboard': {'ar': 'واجهة الدلفري', 'en': 'Delivery Dashboard'},
  'adminDashboard': {'ar': 'لوحة تحكم الأدمن', 'en': 'Admin Dashboard'},
  'deputyAdminDashboard': {
    'ar': 'لوحة تحكم نائب الأدمن',
    'en': 'Deputy Admin Dashboard',
  },

  'drawerWorkspace': {'ar': 'مساحة العمل', 'en': 'Workspace'},
  'drawerHome': {'ar': 'الواجهة الرئيسية', 'en': 'Home'},
  'drawerRefresh': {'ar': 'تحديث البيانات', 'en': 'Refresh Data'},
  'drawerCart': {'ar': 'السلة', 'en': 'Cart'},
  'drawerCreateMerchant': {'ar': 'إنشاء متجر', 'en': 'Create Merchant'},
  'drawerCreateUser': {'ar': 'إنشاء حساب', 'en': 'Create Account'},
  'drawerAddProduct': {'ar': 'إضافة منتج', 'en': 'Add Product'},
  'drawerMerchantsSub': {
    'ar': 'تصفح المتاجر والطلبات',
    'en': 'Browse merchants and orders',
  },
  'drawerOwnerSub': {
    'ar': 'إدارة المتجر والطلبات',
    'en': 'Manage store and orders',
  },
  'drawerOwnerPendingSub': {
    'ar': 'متابعة حالة المراجعة',
    'en': 'Track approval status',
  },
  'drawerOwnerPendingStatus': {
    'ar': 'طلب المتجر قيد المراجعة',
    'en': 'Store request under review',
  },
  'drawerDeliverySub': {
    'ar': 'إدارة التوصيل والمهام اليومية',
    'en': 'Delivery tasks and daily work',
  },
  'drawerAdminSub': {
    'ar': 'متابعة التحليلات والموافقات',
    'en': 'Analytics and approvals',
  },
  'drawerDeputyAdminSub': {
    'ar': 'متابعة العمليات اليومية',
    'en': 'Daily operations overview',
  },
  'drawerPendingApprovals': {
    'ar': 'المتاجر بانتظار الموافقة',
    'en': 'Pending merchant approvals',
  },
  'drawerPendingSettlements': {
    'ar': 'طلبات تسديد المستحقات',
    'en': 'Pending settlement requests',
  },
  'drawerProfile': {'ar': 'الملف الشخصي', 'en': 'Profile'},
  'drawerCancel': {'ar': 'إلغاء', 'en': 'Cancel'},
  'drawerEnter': {'ar': 'دخول', 'en': 'Enter'},
  'drawerManualSelection': {'ar': 'اختيار يدوي', 'en': 'Manual selection'},
  'drawerBlockCommunity': {'ar': 'مجتمع البلوك', 'en': 'Block Community'},
  'drawerCompoundCommunity': {'ar': 'مجتمع المجمع', 'en': 'Compound Community'},
  'drawerBuildingCommunity': {
    'ar': 'مجتمع العمارة',
    'en': 'Building Community',
  },
  'drawerEnterBlockCode': {'ar': 'ادخل رمز البلوك', 'en': 'Enter block code'},
  'drawerEnterCompoundCode': {
    'ar': 'ادخل رمز المجمع',
    'en': 'Enter compound code',
  },
  'drawerEnterBuildingCode': {
    'ar': 'ادخل رمز العمارة',
    'en': 'Enter building code',
  },
  'drawerBlockCodeHint': {
    'ar': 'اكتب رمز البلوك مثل A أو B',
    'en': 'Type block code like A or B',
  },
  'drawerCompoundCodeHint': {
    'ar': 'اكتب رمز المجمع مثل A1 أو B4',
    'en': 'Type compound code like A1 or B4',
  },
  'drawerBuildingCodeHint': {
    'ar': 'اكتب رمز العمارة مثل A711',
    'en': 'Type building code like A711',
  },
  'drawerChats': {'ar': 'المحادثات', 'en': 'Chats'},
  'drawerNewPost': {'ar': 'إضافة منشور', 'en': 'New Post'},
  'drawerNewStory': {'ar': 'إضافة ستوري', 'en': 'New Story'},
  'drawerBasmayaTitle': {'ar': 'شديصير بسماية', 'en': 'Shdysir Basmaya'},
  'drawerBasmayaSubtitle': {
    'ar': 'تابع مجتمع بسماية لحظة بلحظة',
    'en': 'Follow Basmaya community updates',
  },

  'ownerApprovalPendingTitle': {
    'ar': 'طلبك قيد المراجعة',
    'en': 'Your request is under review',
  },

  'language': {'ar': 'اللغة', 'en': 'Language'},
  'languageHint': {
    'ar': 'تغيير لغة التطبيق بالكامل',
    'en': 'Change app language',
  },
  'currentLanguage': {'ar': 'اللغة الحالية', 'en': 'Current language'},
  'arabic': {'ar': 'العربية', 'en': 'Arabic'},
  'english': {'ar': 'English', 'en': 'English'},

  'appearance': {'ar': 'المظهر والحركة', 'en': 'Appearance & Motion'},
  'appearanceHint': {
    'ar': 'خيارات الأنيميشن وتأثيرات الطقس والخلفية',
    'en': 'Animation, weather effects, and visual options',
  },
  'animation': {'ar': 'الأنيميشن', 'en': 'Animation'},
  'animationHint': {
    'ar': 'تشغيل أو إيقاف حركات الواجهة والخلفية',
    'en': 'Enable or disable UI and background animation',
  },
  'weatherFx': {'ar': 'تأثيرات الطقس', 'en': 'Weather Effects'},
  'weatherFxHint': {
    'ar': 'إظهار المطر والغبار والضباب حسب الطقس',
    'en': 'Show rain, dust, and fog based on weather',
  },
  'resetVisual': {'ar': 'إعادة ضبط المظهر', 'en': 'Reset Visual Defaults'},
  'resetVisualHint': {
    'ar': 'إرجاع كل خيارات المظهر إلى الإعدادات الافتراضية',
    'en': 'Restore visual options to default values',
  },

  'accountSecurity': {'ar': 'الحساب والأمان', 'en': 'Account & Security'},
  'accountSecurityHintAuthed': {
    'ar': 'تعديل رقم الهاتف والرمز السري',
    'en': 'Update phone number and PIN',
  },
  'loginRequiredAccount': {
    'ar': 'سجل الدخول أولاً لتعديل بيانات الحساب',
    'en': 'Please login first to edit account data',
  },
  'currentPin': {'ar': 'PIN الحالي', 'en': 'Current PIN'},
  'newPhone': {'ar': 'رقم الهاتف الجديد', 'en': 'New phone number'},
  'newPin': {'ar': 'PIN الجديد', 'en': 'New PIN'},
  'confirmNewPin': {'ar': 'تأكيد PIN الجديد', 'en': 'Confirm new PIN'},
  'changePhone': {'ar': 'تغيير رقم الهاتف', 'en': 'Change phone number'},
  'changePin': {'ar': 'تغيير الرمز السري', 'en': 'Change PIN'},
  'savePhone': {'ar': 'حفظ رقم الهاتف', 'en': 'Save phone number'},
  'savePin': {'ar': 'حفظ PIN', 'en': 'Save PIN'},
  'phoneUpdated': {'ar': 'تم تحديث رقم الهاتف بنجاح', 'en': 'Phone updated'},
  'pinUpdated': {'ar': 'تم تحديث PIN بنجاح', 'en': 'PIN updated'},
  'enterCurrentPin': {'ar': 'أدخل PIN الحالي', 'en': 'Enter current PIN'},
  'enterPhone': {'ar': 'أدخل رقم هاتف جديد', 'en': 'Enter a new phone number'},
  'pinMinDigits': {
    'ar': 'الـ PIN يجب أن يكون من 4 إلى 8 أرقام',
    'en': 'PIN must be 4 to 8 digits',
  },
  'pinMismatch': {
    'ar': 'تأكيد PIN غير مطابق',
    'en': 'PIN confirmation mismatch',
  },

  'supportAndSystem': {'ar': 'الدعم والنظام', 'en': 'Support & System'},
  'supportAndSystemHint': {
    'ar': 'معلومات التواصل ومساعدة الاستخدام',
    'en': 'Contact and help information',
  },
  'supportNumber': {'ar': 'رقم الدعم', 'en': 'Support Number'},
  'supportWhatsApp': {'ar': 'واتساب الدعم', 'en': 'Support WhatsApp'},
  'supportTips': {
    'ar':
        'لخدمة أسرع، أرسل رقم الطلب وصورة المشكلة إن وجدت. فريق الدعم متاح يوميًا لمساعدتك.',
    'en':
        'For faster support, send order number and a screenshot if available. Support is available daily.',
  },
  'copied': {'ar': 'تم النسخ', 'en': 'Copied'},

  'login': {'ar': 'تسجيل الدخول', 'en': 'Login'},
  'createUserAccount': {'ar': 'إنشاء حساب مستخدم', 'en': 'Create User Account'},
  'createOwnerAccount': {
    'ar': 'إنشاء حساب صاحب متجر',
    'en': 'Create Owner Account',
  },
  'phoneLabel': {'ar': 'رقم الهاتف', 'en': 'Phone Number'},
  'pinLabel': {'ar': 'الرمز السري (PIN)', 'en': 'PIN'},
  'loginTagline': {
    'ar': 'مَسْلَكي وياك • كلشي يلگاگ',
    'en': 'Maslaki with you • everything you need in one place',
  },
};
