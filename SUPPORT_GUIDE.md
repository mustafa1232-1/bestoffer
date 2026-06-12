# دليل فريق الدعم والصيانة

## كيف تقرأ المشروع بسرعة
ابدأ دائماً من الأعلى إلى الأسفل:
1. حدّد هل العطل في الواجهة أم الـ API أم قاعدة البيانات أم الإشعارات.
2. حدّد الـ module المرتبط: auth, orders, social, taxi, company...
3. راجع controller/state في Flutter أو controller/route في backend.
4. انزل بعد ذلك إلى service ثم repo/SQL فقط إذا احتجت.

## قاعدة التشخيص الأساسية

### إذا كان المستخدم يرى زر لا يعمل أو شاشة لا تتحدث
ابدأ من Flutter:
- screen/widget
- controller/state notifier
- API client
- ثم افحص response الفعلي من backend

### إذا كان الـ API يعيد خطأ business صحيح لكن النتيجة في القاعدة خاطئة
ابدأ من backend:
- route
- controller
- service
- repo
- الجداول المتأثرة في PostgreSQL

### إذا وصل الطلب أو الرسالة أو الإشعار متأخراً
افصل المشكلة إلى طبقات:
- هل الكتابة في DB تمت؟
- هل الحدث اللحظي بُث؟
- هل الواجهة مشتركة بالقناة؟
- هل يوجد polling fallback؟
- هل push notification أرسلت أم لا؟

## أين تبدأ حسب نوع المشكلة

### مشاكل تسجيل الدخول أو فقدان الجلسة
- Flutter:
  - `lib/features/auth/state/auth_controller.dart`
  - `lib/core/network/dio_client.dart`
  - `lib/core/storage/secure_storage.dart`
- Backend:
  - `backend/src/modules/auth`
  - `backend/src/shared/middleware/auth.middleware.js`
  - `backend/src/config/env.js`

### مشاكل إنشاء الطلب أو انتقال حالته
- Flutter:
  - `lib/features/orders/state/orders_controller.dart`
  - `lib/features/orders/data/orders_api.dart`
- Backend:
  - `backend/src/modules/orders/orders.service.js`
  - `backend/src/modules/orders/orders.repo.js`
- قاعدة البيانات:
  - `customer_order`
  - `order_item`
  - جداول المخزون والعروض والقسائم

### مشاكل الرسائل أو المحادثات
- Flutter:
  - شاشات social/chat
  - `notifications_controller.dart` إذا كانت المشكلة unread أو routing
- Backend:
  - `backend/src/modules/feed/feed.service.js`
  - `backend/src/modules/feed/feed.repo.js`
- راجع:
  - write في DB
  - event broadcast
  - read receipts / typing / presence

### مشاكل التاكسي
- Flutter:
  - شاشات التتبع والرحلة والكابتن
- Backend:
  - `backend/src/modules/taxi/taxi.service.js`
  - `backend/src/modules/taxi/taxi.repo.js`
- قاعدة البيانات:
  - `taxi_ride_request`
  - `taxi_ride_bid`
  - `taxi_captain_presence`
  - `taxi_ride_location`

### مشاكل بوابة الشركات
- Flutter:
  - `company_session_controller.dart`
  - شاشات company shell
- Backend:
  - `backend/src/modules/company/company.routes.js`
  - `backend/src/modules/company/company.service.js`

## كيف تميز مصدر الخلل

### Frontend problem غالباً إذا
- request ناجح لكن الواجهة لا تتحدث
- المشكلة تختفي بعد restart أو refresh
- هناك خطأ navigation أو mounted/state

### Backend problem غالباً إذا
- response shape غير متوقع
- status code خاطئ
- transition business غير صحيح
- log الخادم يحتوي AppError/DB error متوافقاً مع الشكوى

### Database problem غالباً إذا
- البيانات نفسها غير صحيحة أو متناقضة
- transition تم جزئياً
- uniqueness/foreign key/transaction errors ظهرت

### Storage / Media problem غالباً إذا
- السجل موجود لكن الصورة/الفيديو لا يفتح
- فشل upload أو URL broken
- `/health` يظهر مشكلة في R2 أو upload runtime

## ترتيب القراءة المقترح للمنضمين الجدد
1. [SYSTEM_OVERVIEW.md](./SYSTEM_OVERVIEW.md)
2. [ENV_GUIDE.md](./ENV_GUIDE.md)
3. [DATA_FLOW_GUIDE.md](./DATA_FLOW_GUIDE.md)
4. [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
5. التوثيق الداخلي داخل الملفات الحرجة في `auth`, `orders`, `notifications`, `feed`, `taxi`, `company`
