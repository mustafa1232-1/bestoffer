# نظرة عامة على النظام

## الهدف
هذا المشروع منصة متعددة الواجهات تجمع:
- تطبيق Flutter رئيسي للمستخدمين والعملاء والأدمن والموظفين
- تطبيق Flutter مقيد لصاحب المتجر
- بوابة Flutter مستقلة للشركات
- Backend موحد مبني على `Express + PostgreSQL + Redis + Cloudflare R2`

الهدف من هذا الملف هو إعطاء فريق الصيانة صورة سريعة عن الطبقات الرئيسية قبل الدخول إلى التفاصيل داخل الكود.

## الطبقات الرئيسية

### 1. طبقة الواجهة `lib/`
- `main.dart`
  مسؤول عن إقلاع التطبيق العام، bootstrap المصادقة، إعدادات اللغة، وربط الإشعارات والتنقل.
- `main_store.dart`
  نسخة إقلاع مقيدة بأصحاب المتاجر.
- `main_company.dart`
  نسخة إقلاع مستقلة لبوابة الشركات.
- `core/`
  يحتوي البنية المشتركة: الشبكة، التخزين الآمن، الإشعارات، الثيم، الـ i18n، أدوات التنقل.
- `features/`
  الوحدات الوظيفية: auth, orders, notifications, social, taxi, delivery, company, admin, jobs, cars, real_estate وغيرها.

### 2. طبقة الـ API `backend/src/`
- `server.js`
  ينسق boot الكامل: env validation، SQL migrations، schema guard، workers، ثم بدء الخادم.
- `app.js`
  يركب middleware chain، health/readiness endpoints، ويربط كل route module.
- `config/`
  إعدادات البيئة، الاتصال بقاعدة البيانات، Redis، runtime guards.
- `modules/`
  المنطق الوظيفي مقسم حسب المجال: auth, orders, delivery, taxi, feed, company, admin...
- `shared/`
  middleware، helpers، realtime، uploads، error contract، security.

### 3. طبقة البيانات
- PostgreSQL
  المصدر النهائي للحقيقة لمعظم البيانات التشغيلية.
- Redis
  يستخدم لمحددات الطلبات، بعض الـ cache القصير، التنسيق الخفيف بين العمليات، وبعض حالات realtime.
- Cloudflare R2
  التخزين العام للوسائط والملفات.

## كيف تتصل الطبقات ببعضها

### Flutter -> Backend
- جميع الاستدعاءات تمر عبر `DioClient` في `lib/core/network/dio_client.dart`
- المصادقة تحمل access token من `SecureStore`
- بعض الشاشات تستخدم polling منظم
- الإشعارات والرسائل تعتمد على REST + SSE / push بحسب السياق

### Backend -> Database
- الاستعلامات الحساسة موجودة في `*.repo.js`
- منطق الأعمال في `*.service.js`
- `controllers` تجهز الطلب وتعيد response/error shape موحد

### Backend -> Realtime / Notifications
- الرسائل والإشعارات الحية تعتمد على بث events للمستخدمين
- push notifications تمر عبر طبقة `notifications`
- الإشعارات الآن ترفق `i18nTitleKey/i18nBodyKey` داخل payload للتوافق مع الواجهة

## الوحدات الأكثر حساسية
- `auth`
  لأنها تتحكم في الجلسة والأدوار والصلاحيات.
- `orders`
  لأنها تعتمد على transactions ومخزون وانتقالات متعددة الأطراف.
- `notifications`
  لأنها تربط UI + backend + push + realtime.
- `feed`
  لأنها تجمع community + chat + presence + read receipts.
- `taxi`
  لأنها حساسة لحالات السباق وقبول العروض وتحديث الموقع.
- `company`
  لأنها تملك صلاحيات إدارية وعضويات وشركات نشطة متعددة.

## ما الذي يقرأه فريق الصيانة أولاً
1. [SUPPORT_GUIDE.md](./SUPPORT_GUIDE.md)
2. [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
3. [DATA_FLOW_GUIDE.md](./DATA_FLOW_GUIDE.md)
4. [ROUTES_AND_PERMISSIONS_MAP.md](./ROUTES_AND_PERMISSIONS_MAP.md)
5. [ENV_GUIDE.md](./ENV_GUIDE.md)

## مراجع مكملة موجودة مسبقاً
- [docs/system-architecture-and-maintenance-manual.md](./docs/system-architecture-and-maintenance-manual.md)
- [docs/maintenance-runbook.md](./docs/maintenance-runbook.md)
- [docs/postgres-failover-runbook.md](./docs/postgres-failover-runbook.md)
- [docs/railway-cleanup-checklist.md](./docs/railway-cleanup-checklist.md)
