# خطة توسعة المنظومة التشغيلية المؤسسية (مسلكي)

> **المرحلة الصفرية — جرد الموجود ورسم خريطة الاعتماديات.**
> هذه الوثيقة حية: تُحدَّث بعد كل مرحلة. المبدأ الحاكم: **اكتشف الموجود، أكمِله، ووحِّده — لا تُنشئ نظاماً موازياً**.
>
> الفرع: `maslaki-final-v` — نقطة البداية المرجعية: `3b6cd3f` — HEAD عند بدء العمل: `d1b6c10f`.

---

## 1. نظرة عامة على البنية الفعلية (كما اكتُشفت من الكود)

| الطبقة | التقنية الفعلية | الموقع |
| --- | --- | --- |
| Backend API | Node.js (ESM) + Express 4 | `backend/src` |
| قاعدة البيانات | PostgreSQL عبر `pg` مباشرة (لا Prisma/ORM) | `backend/sql/*.sql` (166+ migration مرقّمة) |
| الترحيل | migrations نصية SQL مرقّمة، تشغيل عبر `npm run migrate:sql` | `backend/src/scripts/migrate.js` |
| Realtime | WebSocket (`ws`) + Supabase realtime bridge + outbox worker | `backend/src/modules/realtime`, `src/shared/realtime` |
| الإشعارات | firebase-admin (FCM) + طبقة i18n للإشعارات | `backend/src/modules/notifications` |
| التخزين | S3 (`@aws-sdk/client-s3`) + `uploads/` محلي + multer | `backend/src/shared/utils/upload.js` |
| الاختبارات | Node built-in test runner، عزل DB لكل ملف | `backend/src/tests/**/*.test.js` |
| العميل | Flutter متعدد نقاط الدخول (تطبيق واحد بعدة `main_*.dart`) | `lib/`, `apps/`, `packages/` |

**تطبيقات Flutter (نقاط الدخول):**
`main.dart` (المستخدم) · `main_captain.dart` (الكابتن) · `main_delivery.dart` (الدلفري) · `main_store.dart` (المتجر) · `main_company.dart` (الإدارة/الشركة) · `main_pharmacy.dart`.

**وحدات Backend الموجودة (`backend/src/modules`):**
`accountant, admin, analytics, assistant, auth, behavior, cars, commerce, company, coupons, delivery, feed, hr, jobs, merchants, notifications, orders, owner, paid-upgrades, pharmacy, products, real-estate, realtime, sections, security, services, subscriptions, taxi, users`.

---

## 2. جرد الأنظمة مقابل المراحل المطلوبة

يُصنَّف كل نظام: 🟢 موجود قابل للبناء عليه · 🟡 موجود جزئياً/يحتاج إكمالاً · 🔴 غير موجود.

### المرحلة 1 — قفل إلغاء رحلة التاكسي 🟡
**الموجود:**
- آلة حالة رحلة فعلية في `taxi_ride_request.status`:
  `searching → captain_assigned → captain_arriving → ride_started → completed` (+ `cancelled, expired, price_raise_required`).
  القيد: `chk_taxi_ride_request_status` (sql/154).
- انتقالات الكابتن في `repo.transitionRideStatus` داخل transaction مع `FOR UPDATE` وخريطة `allowed` للانتقالات.
- `service.cancelRide` (الزبون فقط) + جدول أحداث غير قابل للتعديل `taxi_ride_event` (timeline).
- إشعارات + realtime عبر `emitTaxiRealtimeEvents` / `queueNotification`.
- نظام شكاوى تاكسي موجود: `POST /api/taxi/complaints`, `GET /rides/:id/complaint-eligibility` (taxi.loyalty).
- زر «التوجه إلى الزبون» = `POST /rides/:rideId/arrive` → `markCaptainArrived` → الحالة `captain_arriving` (رسالة «الكابتن في طريقه إليك»).

**الناقص (الثغرة الأساسية):**
- `cancelRide` **يسمح للزبون بالإلغاء في أي حالة غير نهائية** — بما فيها `captain_arriving` و`ride_started`. لا يوجد قفل.
- **لا يوجد إلغاء من طرف الكابتن** بعد القبول (توجد `decline` قبل القبول فقط).
- لا يُطلب **سبب إلغاء**، ولا يُخزَّن **من ألغى** ولا **الحالة السابقة** كأعمدة.
- لا يوجد **مسار طوارئ** بعد القفل (زر مساعدة → تذكرة عاجلة → إلغاء طارئ من موظف مخوّل).

**Migration المطلوبة (Phase 1):** `168_taxi_cancellation_lock_and_emergency.sql`
- أعمدة على `taxi_ride_request`: `cancelled_by_role`, `cancelled_by_user_id`, `cancel_reason_code`, `cancel_reason_text`, `cancel_previous_status`, `cancel_is_emergency`.
- جدول `taxi_ride_emergency` (تذكرة السلامة العاجلة المرتبطة بالرحلة، مع `resolution`, `resolved_by`, `second_approval_*`).
- index على `taxi_ride_emergency(status, created_at)`.

**APIs المطلوبة:** `POST /rides/:id/cancel` (تعديل: يتطلب سبباً + قفل) · `POST /rides/:id/captain/cancel` (جديد) · `POST /rides/:id/emergency` (جديد، للطرفين) · `POST /admin/taxi/rides/:id/emergency-cancel` (جديد، موظف مخوّل).

**الشاشات المتأثرة:** `taxi_live_tracking_screen.dart`, `map_page.dart`, شاشات الكابتن (`taxi_pages.dart`) — إظهار/تعطيل أزرار الإلغاء حسب الحالة + حوار سبب الإلغاء + زر الطوارئ.

### المرحلة 2 — أساس صلاحيات RBAC ✅ (أساس منفّذ)
**الموجود سابقاً:** أدوار عبر `req.userRole` + `super_admin` flag، middlewares، جدول `role_permission_override` (sql/085) كجدول إعدادات (بلا فرض runtime).
**ما نُفِّذ (commit مستقل):** كتالوج مفاتيح صلاحيات دقيقة كامل + قوالب أدوار (`permissions.catalog.js`)، حسم صلاحيات فعّالة **بقراءة حيّة لكل طلب** (لا صلاحيات في التوكن) يجمع: قالب الدور + `role_permission_override` + منح فردية بنطاق وتاريخ انتهاء، `requirePermission(key,{scope})` deny-by-default، جدولا `admin_user_permission` و`admin_permission_change_log` + `app_user.permission_version/admin_role_key` (migration 169)، endpoints إدارة (`/admin/rbac/*`, `/admin/me/permissions`)، وربط `taxi.rides.emergency_cancel` + `taxi.rides.read` على مسارات الطوارئ. اختبارات: كتالوج (6/6) + مصفوفة تفويض DB (8/8).
**المتبقي/لاحقاً:** إبطال التوكن عبر `pv` (حالياً الضمان بالقراءة الحيّة — لا صلاحيات قديمة في التوكن)؛ Maker→Approver للعمليات الحساسة؛ توسيع `requireBackoffice` لأدوار الموظفين غير-admin (يعتمد على نموذج موظفي المرحلة 6)؛ إنشاء أدوار مخصّصة عبر واجهة.

### المرحلة 3 — لوحة المتابعة الموحدة ✅ (Backend + واجهة تاكسي منفّذان)
**واجهة Flutter (commit مستقل):** صفحة «لوحة المتابعة» (`CommandCenterScreen`) أعلى تطبيق الإدارة تستهلك `/admin/monitoring/overview` وترسم البطاقات المحكومة بالصلاحيات بحالات Loading/Error/Empty، وdeep link إلى `MonitoringTaxiRidesScreen` (قائمة مُصفّحة خادمياً بفلاتر الحالة + علم الطوارئ). العدّادات غير الموصولة تظهر «قيد الربط» بلا أرقام وهمية.
**الموجود سابقاً:** `admin.ops.controller/repo`، `SUPER_ADMIN_DRAWER_INVENTORY.md`.
**ما نُفِّذ (Backend، commit مستقل):** `GET /admin/monitoring/overview` يعرض البطاقات **حسب صلاحيات الموظف فقط** بعدّادات فورية حقيقية (تاكسي: نشطة/بحث/ملغاة اليوم/مكتملة اليوم/طوارئ مفتوحة؛ طلبات: نشطة/مكتملة اليوم/ملغاة اليوم — بتوقيت Asia/Baghdad)، والوحدات غير الموصولة تُعلَّم `available:false` (بلا أرقام وهمية). `GET /admin/monitoring/taxi/rides` قائمة مُصفّحة خادمياً بفلاتر (status/from/to) + بيانات الإلغاء + علم تذكرة طوارئ مفتوحة، خلف `requirePermission`. اختبارات DB (3/3).
**المتبقي:** صفحة «لوحة المتابعة» في تطبيق الإدارة (Flutter) تستهلك الـendpoints أعلاه وترسم البطاقات المحكومة بالصلاحيات + deep links؛ وصل عدّادات بقية الوحدات (خدمات/عقارات/سيارات/وظائف/مجتمع/تذاكر) تباعاً مع كل مرحلة.

### المرحلة 4 — الدعم والشكاوى (Tickets) 🟡
**الموجود:** شكاوى تاكسي (`taxi_captain_complaint` + loyalty)، شكاوى متفرقة في وحدات أخرى.
**الناقص:** نظام تذاكر موحّد polymorphic (`entityType/entityId`)، حالات SLA، تصعيد، محادثة دعم، فصل الملاحظة الداخلية عن رسالة المستخدم، Order Revision/Amendment.

### المرحلة 5 — تقييم الموظفين 🔴 (يعتمد على 4 و6).
### المرحلة 6 — إدارة الموظفين ✅ (موظفو الشركة + عزل المجتمع)
**ما نُفِّذ (commit مستقل):** وحدة `employees` لموظفي مسلكي (منفصلة عن HR المتاجر `merchant_*`): `company_employee_profile` + تصنيفات الأقسام (delivery/customer_service/hr/monitoring/accounting/marketing/management/tech) + `company_salary_contract` بتاريخ سريان (لا يُستبدل القديم) — migration 178. **عزل هوية الموظف عن المجتمع في Backend**: `app_user.is_internal_staff` + فلترة في استعلامات اكتشاف/بحث المجتمع (`feed.discovery.repo`, `feed.repo`). endpoints `/admin/employees*` خلف `employees.read/create/update` وراتب خلف `employees.salary.read/update` مع تدقيق. اختبارات (3/3 — منها إثبات إخفاء الموظف من بحث المجتمع). **المتبقي:** ملف موظف موحّد أعمق (يجمع التذاكر/الحضور/الأداء) يتكامل مع 5 و7.

### المرحلة 6-قديم (مرجع) 🟡
**الموجود:** وحدة `hr` كاملة (controller/repo/service/routes/validators)، migration `036_hr_leave_and_salary_actions.sql`.
**الناقص:** تصنيفات وظائف، فصل هوية الموظف الإدارية عن الاجتماعية (`isInternalStaff` + إخفاء backend)، ملف موظف موحّد.

### المرحلة 7 — الحضور والرواتب 🟡
**الموجود:** بذور HR (إجازات/رواتب في 036)، `accountant` module.
**الناقص:** حضور/خروج بوقت الخادم (`Asia/Baghdad`)، إضافات/مصاريف، دورة راتب `DRAFT→...→ARCHIVED` بمراجعة ومصادقة، PDF/Excel.

### المرحلة 8 — رقم الدعم المركزي ✅
**ما نُفِّذ (commit مستقل):** جدول `platform_setting` (key/value، migration 171)، وحدة `settings` بتحقق E164 وتنظيف نصوص (إزالة أحرف التحكم و`<>` لمنع الحقن)، `GET /api/settings/public` عام (مع Cache-Control) يخدم كل التطبيقات بلا تحديث، `GET/PUT /admin/settings/support` خلف `settings.support_phone.update` مع تدقيق before/after عبر سجل المرحلة 11. واجهة Flutter: `AdminSupportSettingsScreen` + مدخل في لوحة الإدارة + طرق `AdminApi`. اختبارات (3/3). **المتبقي:** استهلاك `/settings/public` في صفحات دعم التطبيقات (مع cache وfallback محلي) — الـendpoint جاهز.

### المرحلة 9 — ثلاثة ثيمات 🟡
**الموجود:** `packages/core_design_system`، `UNIFIED_IDENTITY_AND_DESIGN_SYSTEM.md`.
**الناقص:** 3 ثيمات (الأصلي/الشفق/المرجاني) عبر semantic tokens + `ThemeExtension`، حفظ/مزامنة الاختيار، preview، Golden tests.

### المرحلة 10 — أدلة الاستخدام لكل تطبيق 🔴 (versioned + scope-aware).
### المرحلة 11 — سجل التدقيق والخصوصية ✅ (أساس منفّذ)
**ما نُفِّذ (commit مستقل):** توحيد على جدول `admin_audit_event` (بلا جدول موازٍ) — migration 170 يضيف `reason/result/permission_key/ip_address/session_id/ticket_id/before_json/after_json` + فهارس بحث. `recordAudit(...)` best-effort مع **إخفاء الحقول الحساسة** (pin/password/token/secret/card/iban...) في before/after، `auditContextFromReq`, و`searchAuditEvents` (بحث بالفاعل/المورد/الفعل/التاريخ + pagination). endpoint `GET /admin/audit/events` خلف `audit.read` (وقراءته تُسجَّل). ربط تسجيل الأفعال الحساسة: الإلغاء الطارئ للتاكسي، قراءة صلاحيات موظف. اختبارات (3/3). **المتبقي:** ربط بقية القراءات الحساسة (محادثات/سير/رواتب/مواقع حية) مع مراحلها، تنبيهات النشاط المشبوه، سياسة الاحتفاظ.
### المرحلة 12 — الاختبارات والأمان: Authorization Matrix آلية موسّعة.
### المرحلة 13 — الترحيل والنشر: forward-only + feature flags + Railway بعد إثبات الاختبارات.

---

## 3. جداول قائمة قابلة لإعادة الاستخدام (لا تُكرَّر)

| الغرض | الجدول/الأصل الموجود | المرحلة |
| --- | --- | --- |
| رحلات التاكسي وحالتها | `taxi_ride_request`, `taxi_ride_bid`, `taxi_ride_event`, `taxi_ride_decline` | 1 |
| شكاوى التاكسي | `taxi_captain_complaint` + taxi.loyalty | 1, 4 |
| صلاحيات الأدوار | `role_permission_override`, `workspace_employee_permissions` | 2 |
| HR/إجازات/رواتب | مخرجات `036_hr_leave_and_salary_actions.sql` + وحدة `hr` | 6, 7 |
| التدقيق | `activity-audit.middleware.js` + وحدة `security` | 11 |
| الإشعارات | وحدة `notifications` + FCM | كل المراحل |
| Realtime | `realtime` module + outbox worker | 1, 3, 4 |

---

## 4. ترتيب التنفيذ و commits المستقلة

1. `feat(taxi): lock cancellation after captain en route` ← **الجاري**
2. `feat(admin): add permission and audit foundations`
3. `feat(admin): add unified monitoring command center`
4. `feat(support): add linked ticketing and SLA workflows`
5. `feat(support): add order amendment workflow`
6. `feat(hr): add employee and attendance management`
7. `feat(payroll): add reviewed payroll runs`
8. `feat(settings): add dynamic support configuration`
9. `feat(theme): add three Maslaki themes`
10. `feat(guides): add app-scoped usage guides`
11. `test(security): add authorization matrix coverage`

---

## 5. مخاطر الخصوصية والأمان (شاملة)

- **قفل الإلغاء يجب أن يكون في Backend داخل transaction** — إخفاء الزر ليس حماية؛ Backend يرفض بـ `409 TAXI_CANCELLATION_LOCKED`.
- **Idempotency**: إعادة إرسال الإلغاء/التوجه يجب ألا تكرّر الرسوم أو الإشعارات.
- **سباق الطرفين** (إلغاء + توجه معاً): يُحسَم بـ `SELECT ... FOR UPDATE` وترتيب الحالات.
- **الطوارئ**: لا مخرج مقفول تماماً بعد `captain_arriving` — تذكرة عاجلة + إلغاء طارئ بموظف مخوّل مع سبب إلزامي وتسجيل كامل (من/متى/لماذا/الحالة السابقة) + موافقة ثانية اختيارية.
- **المحادثات/السير/الرواتب/المواقع الحية**: وصول case-bound بصلاحية دقيقة + تسجيل كل قراءة حساسة (المرحلة 11).
- **عزل موظفي مسلكي** عن المجتمع في Backend لا الواجهة (المرحلة 6).
- **عدم كسر الرحلات القديمة**: migrations forward-only، أعمدة nullable مع backfill، إبقاء أسماء الحالات الحالية.

---

## 6. قرار معماري: أسماء الحالات

المهمة تذكر أسماء نموذجية (`REQUESTED, DRIVER_ASSIGNED, CAPTAIN_EN_ROUTE...`) **كنموذج مفاهيمي**. الكود الحالي يستخدم أسماء مستقرة في قاعدة البيانات وفي قيد `chk_taxi_ride_request_status` وفي رحلات قائمة. إعادة التسمية تكسر الرحلات القديمة وتخالف «لا تكسر القديم». لذلك **نُبقي الأسماء الحالية** ونطبّق منطق القفل عليها بالمطابقة التالية:

| النموذج المفاهيمي | الحالة الفعلية في الكود |
| --- | --- |
| REQUESTED / BIDDING | `searching`, `price_raise_required` |
| DRIVER_ASSIGNED | `captain_assigned` |
| CAPTAIN_EN_ROUTE (التوجه للزبون) | `captain_arriving` |
| TRIP_STARTED | `ride_started` |
| COMPLETED | `completed` |
| CANCELLED | `cancelled` |
| EMERGENCY_REVIEW | `taxi_ride_emergency.status = 'open'` (سجل منفصل، لا تُغيَّر حالة الرحلة تلقائياً) |

**قاعدة القفل:** الإلغاء العادي مسموح فقط في `searching / price_raise_required / captain_assigned`. من `captain_arriving` فصاعداً → مقفول للطرفين (`409 TAXI_CANCELLATION_LOCKED`)، ويبقى مسار الطوارئ + الإلغاء الطارئ الإداري.

---

## 7. خطة الاختبارات والترحيل

- **اختبارات وحدة نقية** لسياسة القفل (`canCancelRide(status, actorRole)`) على نمط `taxi.hardening.test.js` — لا تحتاج DB، تعمل فوراً.
- **migration** تُطبَّق على قاعدة اختبار قبل الدمج؛ forward-only وnullable + backfill.
- **flutter analyze** على الملفات المتأثرة.
- سيناريوهات القبول المذكورة في المهمة (إلغاء قبل/بعد القبول، سباق الطرفين، إلغاء بعد التوجه، إلغاء طارئ بموظف مخوّل/غير مخوّل، idempotency).
