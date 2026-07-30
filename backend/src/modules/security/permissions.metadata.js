/**
 * Human-readable Arabic metadata for every grantable permission key, plus the
 * grouping and job-role display info used by the employee-creation UI.
 *
 * Rule: every capability a super-admin has is a grantable permission here — with
 * ONE hard exception, the chat/message quality monitor, which has no key and is
 * reachable only from the super-admin surface (never grantable, never shown to
 * any employee). See CHAT_MONITOR_SUPER_ADMIN_ONLY below.
 *
 * `permissions.catalog.js` owns the authoritative PERMISSION_KEYS list; every key
 * there must have an entry here (validated by a unit test).
 */

// The single capability that is NEVER a grantable permission — super-admin only.
export const CHAT_MONITOR_SUPER_ADMIN_ONLY = Object.freeze({
  id: "chat_quality_monitor",
  labelAr: "مراقبة جودة المحادثات",
  reason:
    "لا تُمنح لأي موظف ولا تظهر إلا من صفحة السوبر أدمن — حماية لخصوصية المحادثات.",
});

// Ordered groups shown as sections in the permission picker.
export const PERMISSION_GROUPS = Object.freeze([
  { key: "orders", labelAr: "الطلبات والمبيعات" },
  { key: "delivery", labelAr: "التوصيل والمندوبون" },
  { key: "taxi", labelAr: "التكسي والكباتن" },
  { key: "merchants", labelAr: "المتاجر والاشتراكات" },
  { key: "listings", labelAr: "الخدمات والعقارات والسيارات والوظائف" },
  { key: "community", labelAr: "الساكنون والمجتمع" },
  { key: "support", labelAr: "الدعم والشكاوى" },
  { key: "ops", labelAr: "مركز التنبيهات التشغيلية" },
  { key: "employees", labelAr: "الموظفون والرواتب والحضور" },
  { key: "marketing", labelAr: "التسويق والإعلانات والكوبونات" },
  { key: "reports", labelAr: "التقارير والتدقيق" },
  { key: "accounts", labelAr: "إدارة حسابات المستخدمين" },
  { key: "system", labelAr: "النظام والإعدادات" },
]);

// key -> { group, labelAr, descriptionAr }
export const PERMISSION_METADATA = Object.freeze({
  "dashboard.command_center.view": {
    group: "ops",
    labelAr: "لوحة المتابعة",
    descriptionAr:
      "الدخول إلى لوحة المتابعة التشغيلية الموحّدة ورؤية المؤشّرات حسب صلاحياته.",
  },

  // ── الطلبات ──
  "orders.read": {
    group: "orders",
    labelAr: "رؤية الطلبات وتتبّعها",
    descriptionAr:
      "رؤية طلبات المتاجر وتتبّع حالتها ومراحلها ورؤية تفاصيلها ومشاكلها — دون تعديل.",
  },
  "orders.customer_phone.read": {
    group: "orders",
    labelAr: "رؤية هاتف الزبون في الطلب",
    descriptionAr: "إظهار رقم هاتف الزبون داخل الطلب للتواصل عند الحاجة.",
  },
  "orders.modify": {
    group: "orders",
    labelAr: "تعديل الطلبات",
    descriptionAr: "تعديل محتوى الطلب: إضافة أو حذف مواد وتغيير الكميات.",
  },
  "orders.cancel": {
    group: "orders",
    labelAr: "إلغاء الطلبات",
    descriptionAr: "إلغاء طلب قائم عند وجود سبب مبرّر.",
  },
  "orders.revisions.create": {
    group: "orders",
    labelAr: "إنشاء تعديل على الطلب",
    descriptionAr: "بدء طلب تعديل (مراجعة) على طلب قائم قبل اعتماده.",
  },
  "orders.revisions.submit": {
    group: "orders",
    labelAr: "إرسال تعديل الطلب",
    descriptionAr: "إرسال التعديل المقترح على الطلب لاعتماده.",
  },
  "orders.revisions.apply": {
    group: "orders",
    labelAr: "اعتماد وتطبيق تعديل الطلب",
    descriptionAr: "تطبيق التعديل على الطلب فعلياً بعد مراجعته.",
  },
  "orders.refund": {
    group: "orders",
    labelAr: "استرجاع مبالغ الطلبات",
    descriptionAr: "تنفيذ استرجاع مالي للزبون على طلب.",
  },
  "orders.messages.read": {
    group: "orders",
    labelAr: "قراءة رسائل الطلب",
    descriptionAr: "الاطّلاع على محادثة الطلب المرتبطة بالحالة.",
  },

  // ── التوصيل ──
  "delivery.couriers.phone.read": {
    group: "delivery",
    labelAr: "رؤية هاتف المندوب",
    descriptionAr: "إظهار رقم هاتف مندوب التوصيل للتواصل التشغيلي.",
  },
  "delivery.accounts.create": {
    group: "delivery",
    labelAr: "إنشاء حسابات مندوبين",
    descriptionAr: "إنشاء واعتماد حسابات مندوبي التوصيل.",
  },

  // ── التكسي ──
  "taxi.rides.read": {
    group: "taxi",
    labelAr: "رؤية رحلات التكسي",
    descriptionAr: "رؤية رحلات التكسي وحالتها وتفاصيلها.",
  },
  "taxi.rides.track_live": {
    group: "taxi",
    labelAr: "التتبّع الحيّ للرحلات",
    descriptionAr: "متابعة موقع الرحلة مباشرةً على الخريطة.",
  },
  "taxi.rides.history": {
    group: "taxi",
    labelAr: "سجل الرحلات",
    descriptionAr: "الاطّلاع على سجل الرحلات السابقة.",
  },
  "taxi.rides.messages.read": {
    group: "taxi",
    labelAr: "قراءة رسائل الرحلة",
    descriptionAr: "الاطّلاع على محادثة الرحلة المرتبطة بالحالة.",
  },
  "taxi.rides.emergency_cancel": {
    group: "taxi",
    labelAr: "إلغاء طارئ للرحلة",
    descriptionAr: "إلغاء رحلة قسراً في الحالات الطارئة (صلاحية حسّاسة).",
  },
  "taxi.captains.approve": {
    group: "taxi",
    labelAr: "اعتماد الكباتن واشتراكاتهم",
    descriptionAr:
      "مراجعة طلبات الكباتن واعتمادها وتعديلات ملفاتهم ومتابعة اشتراكاتهم.",
  },

  // ── المتاجر ──
  "merchants.approve": {
    group: "merchants",
    labelAr: "اعتماد المتاجر وإدارتها",
    descriptionAr:
      "مراجعة طلبات المتاجر واعتمادها وإدارة حالتها (تفعيل/إيقاف).",
  },
  "merchants.create": {
    group: "merchants",
    labelAr: "إنشاء حساب متجر",
    descriptionAr: "إنشاء حساب صاحب متجر ومتجره كاملاً واعتماده.",
  },
  "merchants.financial_terms.send": {
    group: "merchants",
    labelAr: "إرسال الشروط المالية للمتجر",
    descriptionAr: "إرسال شروط العمولة والاشتراك المالية للمتجر.",
  },
  "merchants.financial_terms.approve": {
    group: "merchants",
    labelAr: "اعتماد الشروط المالية للمتجر",
    descriptionAr: "اعتماد الشروط المالية المرسلة للمتجر لتفعيلها.",
  },

  // ── الخدمات والعقارات والسيارات والوظائف ──
  "services.read": {
    group: "listings",
    labelAr: "متابعة الخدمات ومقدّميها",
    descriptionAr: "مراجعة مقدّمي الخدمة والخدمات وطلباتها واشتراكاتهم.",
  },
  "services.messages.case_bound_read": {
    group: "listings",
    labelAr: "قراءة رسائل حالة الخدمة",
    descriptionAr: "الاطّلاع على رسائل مرتبطة بحالة خدمة محدّدة.",
  },
  "services.modify": {
    group: "listings",
    labelAr: "تعديل الخدمات",
    descriptionAr: "تعديل بيانات الخدمات أو حالتها.",
  },
  "real_estate.read": {
    group: "listings",
    labelAr: "رؤية إعلانات العقارات",
    descriptionAr: "رؤية إعلانات العقارات وتفاصيلها.",
  },
  "real_estate.contact.read": {
    group: "listings",
    labelAr: "رؤية تواصل معلن العقار",
    descriptionAr: "إظهار وسيلة التواصل مع معلن العقار.",
  },
  "real_estate.moderate": {
    group: "listings",
    labelAr: "إشراف إعلانات العقارات",
    descriptionAr: "قبول أو رفض أو إخفاء إعلانات العقارات.",
  },
  "cars.read": {
    group: "listings",
    labelAr: "رؤية إعلانات السيارات",
    descriptionAr: "رؤية إعلانات السيارات وتفاصيلها.",
  },
  "cars.contact.read": {
    group: "listings",
    labelAr: "رؤية تواصل معلن السيارة",
    descriptionAr: "إظهار وسيلة التواصل مع معلن السيارة.",
  },
  "cars.moderate": {
    group: "listings",
    labelAr: "إشراف إعلانات السيارات",
    descriptionAr: "قبول أو رفض أو إخفاء إعلانات السيارات.",
  },
  "jobs.read": {
    group: "listings",
    labelAr: "رؤية الوظائف",
    descriptionAr: "رؤية إعلانات الوظائف وطلبات التوظيف.",
  },
  "jobs.applications.read": {
    group: "listings",
    labelAr: "رؤية طلبات التوظيف",
    descriptionAr: "الاطّلاع على طلبات المتقدّمين للوظائف.",
  },
  "jobs.cv.download": {
    group: "listings",
    labelAr: "تنزيل السير الذاتية",
    descriptionAr: "تنزيل ملفات السير الذاتية للمتقدّمين.",
  },
  "jobs.manage": {
    group: "listings",
    labelAr: "إدارة الوظائف",
    descriptionAr: "إدارة إعلانات الوظائف ومتابعة المتقدّمين والمراجعة.",
  },

  // ── الساكنون والمجتمع ──
  "community.posts.read": {
    group: "community",
    labelAr: "رؤية منشورات المجتمع",
    descriptionAr: "رؤية منشورات وبلاغات المجتمع للمراجعة.",
  },
  "community.moderate": {
    group: "community",
    labelAr: "إشراف محتوى المجتمع",
    descriptionAr: "إخفاء أو إزالة المنشورات المخالفة والتعامل مع البلاغات.",
  },
  "community.users.read": {
    group: "community",
    labelAr: "رؤية حسابات الساكنين",
    descriptionAr: "البحث في حسابات المستخدمين ورؤية ملفاتهم للمراجعة.",
  },
  "community.messages.case_bound_read": {
    group: "community",
    labelAr: "قراءة رسائل حالة المجتمع",
    descriptionAr: "الاطّلاع على رسائل مرتبطة بحالة بلاغ محدّدة.",
  },
  "feed.moderate": {
    group: "community",
    labelAr: "إشراف التغذية الاجتماعية",
    descriptionAr: "مراجعة وإدارة منشورات التغذية الاجتماعية العامة.",
  },

  // ── الدعم ──
  "support.tickets.read": {
    group: "support",
    labelAr: "رؤية تذاكر الدعم",
    descriptionAr: "استلام ورؤية شكاوى وتذاكر الدعم.",
  },
  "support.tickets.assign": {
    group: "support",
    labelAr: "إسناد التذاكر",
    descriptionAr: "توزيع تذاكر الدعم على الموظفين.",
  },
  "support.tickets.reply": {
    group: "support",
    labelAr: "الرد على التذاكر",
    descriptionAr: "الرد على الزبون داخل تذكرة الدعم (خدمة العملاء).",
  },
  "support.tickets.resolve": {
    group: "support",
    labelAr: "إغلاق التذاكر",
    descriptionAr: "إنهاء ومعالجة تذاكر الدعم.",
  },
  "support.tickets.escalate": {
    group: "support",
    labelAr: "تصعيد التذاكر",
    descriptionAr: "تصعيد التذكرة لمستوى أعلى عند الحاجة.",
  },
  "support.sla.manage": {
    group: "support",
    labelAr: "إدارة مستويات الخدمة",
    descriptionAr: "ضبط عتبات وأولويات معالجة تذاكر الدعم.",
  },

  // ── مركز التنبيهات ──
  "ops.alerts.read": {
    group: "ops",
    labelAr: "رؤية التنبيهات التشغيلية",
    descriptionAr: "رؤية تنبيهات النظام التشغيلية.",
  },
  "ops.alerts.acknowledge": {
    group: "ops",
    labelAr: "استلام التنبيهات",
    descriptionAr: "الإقرار باستلام تنبيه تشغيلي.",
  },
  "ops.alerts.assign": {
    group: "ops",
    labelAr: "إسناد التنبيهات",
    descriptionAr: "توزيع التنبيهات على الموظفين.",
  },
  "ops.alerts.resolve": {
    group: "ops",
    labelAr: "معالجة التنبيهات",
    descriptionAr: "إغلاق التنبيهات التشغيلية بعد معالجتها.",
  },

  // ── الموظفون والرواتب ──
  "employees.read": {
    group: "employees",
    labelAr: "رؤية الموظفين",
    descriptionAr: "رؤية قائمة الموظفين وأقسامهم وملفاتهم.",
  },
  "employees.create": {
    group: "employees",
    labelAr: "إنشاء حسابات الموظفين",
    descriptionAr:
      "إنشاء حسابات موظفين جديدة مستقلة تماماً بأدوارها وواجهتها.",
  },
  "employees.update": {
    group: "employees",
    labelAr: "تعديل بيانات الموظفين",
    descriptionAr: "تعديل بيانات الموظف: القسم والوظيفة والحالة والراتب.",
  },
  "employees.permissions.manage": {
    group: "employees",
    labelAr: "إدارة صلاحيات الموظفين",
    descriptionAr:
      "منح وتعديل صلاحيات الموظفين وأدوارهم الوظيفية (صلاحية حسّاسة).",
  },
  "employees.salary.read": {
    group: "employees",
    labelAr: "رؤية رواتب الموظفين",
    descriptionAr: "الاطّلاع على الرواتب الأساسية وسجلها.",
  },
  "employees.salary.update": {
    group: "employees",
    labelAr: "تعديل رواتب الموظفين",
    descriptionAr: "تحديث الراتب الأساسي للموظف مع تسجيل السبب.",
  },
  "attendance.read": {
    group: "employees",
    labelAr: "رؤية الحضور والغياب",
    descriptionAr: "رؤية سجلّ حضور وغياب الموظفين.",
  },
  "attendance.approve": {
    group: "employees",
    labelAr: "تسجيل واعتماد الحضور",
    descriptionAr:
      "تسجيل حالات الحضور والغياب والإجازات يدوياً واعتمادها للموظفين.",
  },
  "payroll.prepare": {
    group: "employees",
    labelAr: "احتساب الرواتب",
    descriptionAr: "احتساب دورة الرواتب وإضافة المكافآت والخصومات.",
  },
  "payroll.review": {
    group: "employees",
    labelAr: "مراجعة الرواتب",
    descriptionAr: "مراجعة دورة الرواتب قبل اعتمادها.",
  },
  "payroll.approve": {
    group: "employees",
    labelAr: "اعتماد الرواتب",
    descriptionAr: "اعتماد دورة الرواتب (صلاحية حسّاسة).",
  },
  "payroll.release": {
    group: "employees",
    labelAr: "إطلاق الرواتب",
    descriptionAr: "إطلاق الرواتب المعتمدة للصرف (صلاحية حسّاسة).",
  },
  "payroll.mark_paid": {
    group: "employees",
    labelAr: "تأكيد صرف الرواتب",
    descriptionAr: "تأشير الرواتب كمدفوعة بعد صرفها.",
  },

  // ── التسويق والإعلانات والكوبونات ──
  "ads.manage": {
    group: "marketing",
    labelAr: "إدارة الإعلانات",
    descriptionAr:
      "إنشاء وإدارة الحملات الإعلانية داخل التطبيق وأماكن ظهورها.",
  },
  "competitions.manage": {
    group: "marketing",
    labelAr: "إدارة المسابقات",
    descriptionAr: "إنشاء وإدارة مسابقات المندوبين والحملات التحفيزية.",
  },
  "coupons.manage": {
    group: "marketing",
    labelAr: "إدارة الكوبونات العامة",
    descriptionAr: "إنشاء وإدارة كوبونات الخصم العامة للمنصّة.",
  },
  "coupons.agents.manage": {
    group: "marketing",
    labelAr: "كوبونات الموظفين (الإحالة)",
    descriptionAr:
      "إنشاء ومتابعة كوبونات الإحالة الخاصة بالموظفين وتعديل خصمها ونسب مبيعاتهم.",
  },

  // ── التقارير والتدقيق ──
  "reports.export": {
    group: "reports",
    labelAr: "التقارير المالية والمبيعات",
    descriptionAr: "رؤية وتصدير التقارير المالية والمبيعات والمستحقّات.",
  },
  "audit.read": {
    group: "reports",
    labelAr: "سجل التدقيق",
    descriptionAr: "الاطّلاع على سجلّ التدقيق وتتبّع تغييرات النظام.",
  },

  // ── إدارة الحسابات ──
  "accounts.restrict": {
    group: "accounts",
    labelAr: "تقييد حسابات الساكنين",
    descriptionAr:
      "تقييد حساب مستخدم: منعه من التعليق فقط أو النشر فقط أو إرسال طلبات المتابعة.",
  },
  "accounts.suspend": {
    group: "accounts",
    labelAr: "تعطيل حسابات المستخدمين",
    descriptionAr: "تعطيل (تبنيد) حساب مستخدم ومنعه من الدخول.",
  },
  "accounts.delete_request": {
    group: "accounts",
    labelAr: "طلب حذف حساب",
    descriptionAr: "تقديم طلب حذف حساب مستخدم للاعتماد.",
  },
  "accounts.delete_approve": {
    group: "accounts",
    labelAr: "اعتماد حذف الحساب",
    descriptionAr: "اعتماد وتنفيذ حذف حساب مستخدم (صلاحية حسّاسة).",
  },

  // ── النظام والإعدادات ──
  "residence.requests.manage": {
    group: "system",
    labelAr: "طلبات تغيير السكن",
    descriptionAr: "مراجعة واعتماد طلبات تغيير عنوان السكن للمستخدمين.",
  },
  "paid_upgrades.manage": {
    group: "system",
    labelAr: "طلبات الترقيات المدفوعة",
    descriptionAr: "مراجعة واعتماد طلبات الترقيات المدفوعة.",
  },
  "companies.manage": {
    group: "system",
    labelAr: "إدارة الشركات",
    descriptionAr: "إدارة الشركات وفروعها وطلبات ربطها ببوابة الشركات.",
  },
  "sections.availability.manage": {
    group: "system",
    labelAr: "إتاحة الأقسام",
    descriptionAr: "فتح وإغلاق أقسام التطبيق وضبط رسائل الإتاحة للمستخدم.",
  },
  "customer_reliability.manage": {
    group: "system",
    labelAr: "سياسة موثوقية العميل",
    descriptionAr: "ضبط أوزان وعتبات تقييم مخاطر العملاء والتنبيهات.",
  },
  "settings.support_phone.update": {
    group: "system",
    labelAr: "رقم الدعم المركزي",
    descriptionAr: "تعديل رقم الدعم الموحّد الذي يصل كل التطبيقات دون تحديث.",
  },
  "settings.themes.manage": {
    group: "system",
    labelAr: "إدارة السمات",
    descriptionAr: "ضبط سمات وألوان التطبيق.",
  },
  "settings.guides.manage": {
    group: "system",
    labelAr: "إدارة الأدلّة والإشعارات التشغيلية",
    descriptionAr: "إدارة أدلّة الاستخدام وعمليات الإشعارات التشغيلية.",
  },
  "system.notifications.view": {
    group: "system",
    labelAr: "مركز الإشعارات",
    descriptionAr: "مركز إشعارات النظام التشغيلي.",
  },
  "system.device_reliability.view": {
    group: "system",
    labelAr: "موثوقية الأجهزة",
    descriptionAr: "متابعة موثوقية أجهزة المستخدمين وجلساتهم.",
  },
  "system.crash_center.view": {
    group: "system",
    labelAr: "مركز الأعطال",
    descriptionAr: "متابعة أعطال وأخطاء التطبيق.",
  },
  "system.feature_flags.manage": {
    group: "system",
    labelAr: "مفاتيح الميزات",
    descriptionAr: "تفعيل وإيقاف ميزات التطبيق (أدوات مالك المنصّة).",
  },
  "system.maintenance.manage": {
    group: "system",
    labelAr: "مركز الصيانة",
    descriptionAr: "أدوات صيانة النظام (أدوات مالك المنصّة).",
  },
});

// Job-role display names + Arabic descriptions (for the role picker).
export const JOB_ROLE_METADATA = Object.freeze({
  follow_up_manager: {
    labelAr: "مدير المتابعة",
    descriptionAr:
      "يتابع الطلبات والموظفين وحلّهم للمشاكل، ويدير الموظفين وينشئهم، ويسجّل الحضور والغياب والخصومات والمكافآت، ويطلق الرواتب.",
  },
  sales_agent: {
    labelAr: "موظف مبيعات",
    descriptionAr:
      "يتابع الطلبات والمبيعات والتقارير، وله كوبون إحالة تُحتسب عليه مبيعاته.",
  },
  marketing_agent: {
    labelAr: "موظف تسويق وترويج",
    descriptionAr:
      "يضيف ويدير الإعلانات والمسابقات والكوبونات الترويجية ويتابع تقارير الأداء.",
  },
  subscriptions_monitor: {
    labelAr: "متابعة الاشتراكات",
    descriptionAr:
      "يتابع اشتراكات التكسي والمتاجر واعتمادها وشروطها المالية ومدفوعاتها.",
  },
  residents_moderator: {
    labelAr: "إشراف الساكنين",
    descriptionAr:
      "يتابع الساكنين ومحتواهم، ويقيّدهم (منع تعليق/نشر/طلبات متابعة) أو يعطّل حساباتهم.",
  },
});

export function permissionMetadata(key) {
  return PERMISSION_METADATA[String(key || "").trim()] || null;
}
