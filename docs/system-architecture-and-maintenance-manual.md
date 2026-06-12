# الدليل الكامل للنظام: البناء + المنطق + الصيانة

## 1) نظرة عامة
التطبيق مبني كـ Super App متعدد الوحدات:
- **BESTOFFER**: متاجر/مطاعم/طلبات.
- **SHAKAKY**: تكسي ومكالمات.
- **شديصير بسماية**: مجتمع/منشورات/ستوري/ريلز/محادثات.
- **وظائف بسماية**: نشر وظائف + تقديم + متابعة.
- **لوحات تشغيل**: سوبر أدمن/أدمن/متجر/دلفري/HR/محاسب.

الواجهة: Flutter + Riverpod.
الخلفية: Node.js + PostgreSQL + SSE/WebSocket patterns for realtime.

## 2) قواعد عدم كسر المنطق (مهم جدًا)
1. **العزل حسب الدور**:
- لا تسمح لواجهة بدور أن تعرض إجراءات دور آخر.
- التحقق يكون Front + Backend معًا.

2. **العزل حسب المجتمع**:
- منشورات/محادثات/تبليغات/فواتير البلوك والمجمع والعمارة تبقى ضمن نطاقها.

3. **الإشعار يجب أن يقود لشاشته**:
- أي Notification جديد يجب أن يملك Target واضح + Payload كافٍ.

4. **الترميز UTF-8 دائمًا**:
- أي نص عربي مشوه يعالج من طبقة parsing (`normalizeText`) ومن مصدر البيانات.

5. **إصلاحات الصيانة لا تكون تدميرية**:
- لا حذف جماعي للإنتاج من واجهة المستخدم.
- عمليات إعادة المزامنة يجب أن تكون idempotent.

## 3) الطبقات الأساسية
1. **UI**
- شاشات كل موديول (customer, social, taxi, jobs, admin...).
- ثيم موحد + مكونات مشتركة.

2. **State (Riverpod)**
- Controllers لكل موديول.
- إدارة loading/error/realtime status.

3. **Data/API**
- طبقة API لكل موديول (`.../data/..._api.dart`).
- كل endpoint يجب أن يكون له parser واضح.

4. **Core**
- Notifications navigation.
- Local notification service.
- i18n/locale helpers.
- Parsing and encoding normalization.

5. **Backend**
- Modules مفصولة (`auth`, `orders`, `social`, `jobs`, `admin`, ...).
- SQL migrations لكل منطق جديد.

## 4) آلية الصيانة (يدوي + أوتوماتك)
### أوتوماتك من التطبيق
من `مركز الصيانة`:
1. **صيانة سريعة تلقائية**:
- إعادة ربط realtime.
- تحديث بيانات الأدمن.
- إعادة فحص شامل.

2. **إعادة ربط الإشعارات**:
- مفيدة عند تأخر/انقطاع التنبيهات.

3. **فحص سلامة النص**:
- يرصد النصوص المشوهة في العينة الحالية.

### يدوي (للدعم الفني)
1. فحص `/health`.
2. فحص سجلات Railway.
3. فحص `schema_migration`.
4. فحص SSE/realtime status.
5. إعادة نشر backend إذا المشكلة من سيرفر runtime.

## 5) نقاط المراقبة اليومية
1. unread notifications behavior.
2. realtime connection state (`connected/reconnecting`).
3. admin approval queues.
4. pending settlements / taxi pending edits.
5. community scope access correctness.

## 6) سيناريو إصلاح سريع عند ظهور خلل
1. افتح مركز الصيانة.
2. شغّل إعادة الفحص.
3. شغّل الصيانة السريعة.
4. اختبر:
- إشعار رسالة -> يفتح المحادثة.
- إشعار مجتمع -> يفتح المجتمع الصحيح.
- إشعار طلب -> يفتح شاشة الطلب.
5. إذا فشل: انتقل لصيانة backend (logs + migrations + deploy).

## 7) المعايير قبل اعتماد نسخة Production
1. لا أخطاء build/analyze حرجة.
2. مسارات الإشعارات تعمل end-to-end.
3. اللغة العربية/الإنكليزية تعمل في نفس الشاشة بدون نص مكسور.
4. كل زر إداري يقود لصفحة/عملية صحيحة.
5. الفحوصات في مركز الصيانة مستقرة.

## 8) مرجع الملفات الحساسة
- Notifications:
  - `lib/core/notifications/notification_navigation.dart`
  - `lib/features/notifications/state/notifications_controller.dart`
  - `lib/features/notifications/ui/notifications_screen.dart`
- Community UI:
  - `lib/features/social/ui/social_community_screen.dart`
  - `lib/features/social/ui/widgets/basmaya_shell_bars.dart`
- Admin:
  - `lib/features/admin/ui/admin_dashboard_screen.dart`
  - `lib/features/admin/ui/admin_maintenance_screen.dart`

## 9) قاعدة الفريق الأساسية
أي تعديل جديد يجب أن يحافظ على:
- الدور الصحيح.
- النطاق الصحيح.
- إشعار يفتح صفحته.
- ترميز نص صحيح.
- قابلية الصيانة عبر مركز الصيانة.
