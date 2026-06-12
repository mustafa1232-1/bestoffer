# دليل تدفق البيانات

## 1. تدفق المصادقة
1. المستخدم يدخل بياناته من Flutter.
2. `AuthController` يستدعي `AuthApi`.
3. الـ backend يتحقق من الهاتف/PIN والجهاز والصلاحيات.
4. عند النجاح:
   - token يحفظ في `SecureStore`
   - `AuthState` يتحدث
   - `main.dart` يعيد التوجيه حسب الدور

### أين ينكسر عادة
- validation في الواجهة
- mapping الخطأ في `api_error_mapper`
- token/session في التخزين
- role claims غير متوافقة مع user model

## 2. تدفق إنشاء الطلب
1. `OrdersController.checkout` يقرأ السلة والعنوان.
2. `OrdersApi.createOrder` يرسل الطلب إلى `/api/orders`.
3. `orders.service.js` يطبع المدخلات ويحل العنوان.
4. `orders.repo.js#createOrderWithItems` ينفذ transaction:
   - merchant check
   - product/inventory check
   - offer/coupon pricing
   - insert order
   - insert items
   - inventory adjustments
5. بعد النجاح:
   - تحديث الواجهة
   - الإشعارات للطرف المناسب

## 3. تدفق الرسائل الاجتماعية
1. الواجهة تفتح thread وتحمّل الرسائل من feed API.
2. `feed.service.js#sendMessage` يتحقق من العلاقة والحظر وحالة الطلب.
3. الرسالة تكتب في DB.
4. يتم تحديث last message metadata.
5. يرسل event realtime للطرف الآخر.
6. الواجهة تحدث القائمة والعدادات وread state.

### الترتيب التشخيصي
DB write -> realtime emit -> notifications -> UI state update

## 4. تدفق الإشعارات
1. backend ينشئ notification record.
2. `payload` قد يحمل مفاتيح i18n بالإضافة إلى fallback title/body.
3. SSE أو push notification تصل إلى Flutter.
4. `NotificationsController` يحدث unread/list.
5. `NotificationNavigation` يحول payload إلى شاشة.

## 5. تدفق رحلة التاكسي
1. العميل ينشئ `ride_request` في حالة `searching`.
2. الكباتن المؤهلون يرون الطلب أو يزايدون عليه.
3. العميل يقبل bid واحداً فقط.
4. الحالة تنتقل:
   - `captain_assigned`
   - `captain_arriving`
   - `ride_started`
   - `completed`
5. presence/location updates تستمر أثناء الرحلة.

### نقاط الانتباه
- قبول مزدوج = راجع locking
- رحلة عالقة = راجع status transitions
- تتبع ضعيف = راجع location insert + realtime

## 6. تدفق بوابة الشركات
1. `CompanySessionController` يقرأ token البوابة أو يطلب login.
2. `bootstrap/login` يعيدان user + memberships.
3. controller يحدد `activeCompanyId`.
4. الشاشات الفرعية تستخدم الشركة النشطة في كل API call.

## 7. تدفق الوسائط والرفع
1. Flutter يرسل multipart أو ملفاً إلى endpoint مناسب.
2. `upload.js` يتحقق من النوع والحجم.
3. في الإنتاج:
   - التخزين الأساسي R2
4. في البيئات المحلية:
   - قد يستخدم local fallback إذا كان مسموحاً
5. backend يعيد public URL تستخدمه الواجهة

## 8. تدفق الموافقات الإدارية
1. الأدمن يفتح شاشة pending approvals.
2. Flutter يستدعي مسارات الأدمن المناسبة.
3. service تنفذ ownership/role checks.
4. repo يحدث الحالة والجداول المرتبطة.
5. notification أو refresh يعكس النتيجة في الواجهة.
