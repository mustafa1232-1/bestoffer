# دليل ترحيل ونشر التوسعة التشغيلية (المرحلة 13)

> يغطي نشر المراحل 1–12 المُضافة على فرع `maslaki-final-v`. كل الـmigrations
> **forward-only وidempotent** (IF NOT EXISTS / ADD COLUMN IF NOT EXISTS / أعمدة
> nullable مع backfill)، فلا تكسر البيانات القائمة ولا الرحلات/الطلبات القديمة.

## 1. الـMigrations المُضافة (بالترتيب)

| # | الملف | المرحلة |
| --- | --- | --- |
| 168 | `taxi_cancellation_lock_and_emergency` | 1 |
| 169 | `admin_rbac_foundation` | 2 |
| 170 | `unified_audit_log` | 11 |
| 171 | `platform_settings` | 8 |
| 172 | `support_tickets` | 4 |
| 173 | `order_revision_support_workflow` | 4 (تعديل الطلب) |
| 174 | `admin_role_management_security_closure` | 2 |
| 175–177 | `monitoring_*_indexes` | 3 |
| 178 | `company_employees` | 6 |
| 179 | `company_attendance_payroll` | 7 |
| 180 | `employee_evaluation` | 5 |
| 181 | `support_tickets_backfill_tables` | 4 (تصحيح hygiene) |
| 182 | `app_guides` | 10 |

التشغيل: `npm run migrate:sql` (يتتبّع المطبَّق بالاسم ويطبّق الجديد فقط).

> 🔴 **سبب شائع لاختفاء البيانات (خدمات/فئات لا تظهر…):** عند الإقلاع
> `server.js` يستدعي `runSqlMigrations()` لكنها **مُعطّلة افتراضياً** ما لم
> يُضبط `RUN_SQL_MIGRATIONS=true`. أي أن الـmigrations (ومنها بذور فئات الخدمات
> 148–150 و183) **لا تُطبَّق تلقائياً** على بيئة لم تُفعّل العلم. الحل: إمّا ضبط
> `RUN_SQL_MIGRATIONS=true`، أو تشغيل `npm run migrate:sql` يدوياً مقابل قاعدة
> تلك البيئة بعد كل نشر. فئات الخدمات موجودة ومختبَرة؛ عدم ظهورها يعني أن هذه
> الخطوة لم تُنفَّذ على قاعدتك.

> ⚠️ **تنبيه hygiene:** migration 172 عُدِّل في مكانه بعد تطبيقه (أُضيفت جداول
> داخل نفس الملف). المُشغِّل يتتبّع بالاسم فلن يعيد تشغيل 172. لذلك **يجب تشغيل
> 181** الذي يعيد إنشاء تلك الجداول بأمان على أي بيئة سبق أن طبّقت 172 القديم.
> **قاعدة عامة:** لا تُعدّل migration مطبَّقاً؛ أضِف migration جديداً دائماً.

## 2. ما قبل النشر (إثبات الاختبارات)

شغّل على دفعات مع timeout (لا تترك المجموعة كاملة عالقة):

```bash
cd backend
# نقية (بلا DB) — سريعة:
node --test src/tests/taxi.cancellation.test.js src/tests/permissions.catalog.test.js src/tests/support.policy.test.js src/tests/payroll.policy.test.js
# مدعومة بقاعدة QA (دفعات):
node --env-file=.env.test --test src/tests/taxi.cancellation-lock.test.js src/tests/permissions.authorization-matrix.test.js src/tests/audit.log.test.js src/tests/settings.support.test.js src/tests/guides.test.js
node --env-file=.env.test --test src/tests/employees.company.test.js src/tests/attendance-payroll.test.js src/tests/employee-evaluation.test.js src/tests/authorization-matrix.middleware.test.js
node --env-file=.env.test --test src/tests/monitoring.taxi.test.js src/tests/support.tickets.test.js
```

آخر تشغيل معروف: **56/56** في الدفعات أعلاه + monitoring/support.tickets خضراء.

Flutter:
```bash
flutter analyze lib/features/admin lib/features/guides lib/features/taxi lib/features/tracking packages/core_design_system
flutter test test/theme_variants_test.dart
```

## 3. تسلسل النشر

1. طبّق الـmigrations على قاعدة الإنتاج (forward-only، آمنة).
2. **انشر Backend أولاً** قبل تفعيل أي واجهة تعتمد عليه (RBAC/التذاكر/المتابعة/الرواتب).
3. بعد ثبات Backend، أطلق تحديث تطبيق الإدارة (لوحة المتابعة/التذاكر/الموظفين/الأدلة/الثيمات).
4. راقب الأخطاء (Sentry) وأداء قوائم الإدارة بعد النشر.

## 4. أعلام الميزات (feature flags) والتدرّج

- المراحل الكبيرة (RBAC، لوحة المتابعة، التذاكر) قابلة للتقييد بالصلاحيات نفسها:
  لا تمنح مفاتيح الصلاحيات للموظفين إلا بعد التحقق التشغيلي — وهذا يعمل كعلم
  ميزة طبيعي (deny-by-default).
- رقم الدعم/الأدلة/الثيمات: قابلة للتحديث من الإدارة دون إعادة نشر.

## 5. التراجع (rollback) دون فقدان بيانات

- الـmigrations إضافية (جداول/أعمدة جديدة) — التراجع = نشر النسخة السابقة من
  الكود؛ الجداول الجديدة تبقى غير مستخدمة (لا حذف).
- **لا** تُنفَّذ عمليات حذف أعمدة قديمة؛ لم يُحذف أي عمود قائم.
- سحب مفاتيح الصلاحيات فوري (قراءة حيّة لكل طلب) لإيقاف ميزة إدارية عند الحاجة.

## 6. بوابات لا يجوز تجاوزها

- لا نشر إلى Production/Railway قبل إثبات الاختبارات والتأكد من الفرع والخدمة.
- لا رفع تطبيقات المتاجر قبل اختبار جهاز فعلي (تدفقات: إلغاء التاكسي، لوحة
  المتابعة، التذاكر، الحضور، اختيار الثيم).
- العمليات المالية الكبيرة (إطلاق الرواتب) تحترم فصل المهام؛ راجع قواعد الضرائب
  العراقية مع محاسب قبل تفعيل أي استقطاعات إلزامية (اجعلها configurable).
