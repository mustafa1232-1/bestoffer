# خريطة الراوتات والصلاحيات

> هذه الخريطة تركز على الراوتات التشغيلية الأساسية التي يحتاجها فريق الدعم والصيانة. ليست بديلاً عن قراءة ملفات `*.routes.js` نفسها.

## Auth
- `/api/auth/*`
  - الوصول: عام أو مستخدم مصادق بحسب المسار
  - يستخدمه: شاشات login/register/account في Flutter
  - الطبقة المرتبطة: `auth.routes.js` -> `auth.controller.js` -> `auth.service.js`

## Orders
- `/api/orders`
  - الوصول: عميل مصادق
  - الشاشة: checkout / طلباتي
- `/api/orders/my`
  - الوصول: عميل مصادق
  - الشاشة: قائمة طلباتي
- `/api/orders/:id/customer/confirm-received`
  - الوصول: عميل صاحب الطلب
  - الشاشة: تتبع الطلب / التأكيد النهائي
- `/api/orders/:id/reorder`
  - الوصول: عميل صاحب الطلب
  - الشاشة: إعادة الطلب

## Delivery
- `/api/delivery/*`
  - الوصول: حساب delivery مصادق ومعتمد
  - الشاشات: لوحة المندوب، الطلبات الجديدة، الطلبات الحالية
  - الطبقة: `delivery.routes.js` / `delivery.service.js`

## Taxi
- `/api/taxi/captain/register`
  - الوصول: عام
  - الشاشة: تسجيل كابتن التاكسي
- `/api/taxi/*`
  - الوصول: عميل أو كابتن مصادق بحسب endpoint
  - الشاشات: الرحلة، المزايدات، التتبع، سجل الرحلات
  - الطبقة: `taxi.routes.js` -> `taxi.service.js` -> `taxi.repo.js`

## Notifications
- `/api/notifications`
  - الوصول: مستخدم مصادق
  - الشاشة: صندوق الإشعارات
- `/api/notifications/stream`
  - الوصول: مستخدم مصادق
  - الشاشة: inbox + badge + routing
  - الطبقة: `notifications.routes.js` / `notifications.service.js`

## Feed / Social
- `/api/feed/*`
  - الوصول: مستخدم مصادق غالباً، وبعض browse/public بحسب المسار
  - الشاشات: المجتمع، المنشورات، القصص، المحادثات
  - الطبقة: `feed.routes.js` / `feed.service.js`

## Company
- `/api/company/auth/*`
  - الوصول: عام/مصادق حسب المسار
  - الشاشة: Company Login / bootstrap
- `/api/company/*`
  - الوصول: عضوية شركة مصادق عليها
  - الشاشة: Company Portal
- `/api/company/admin/companies*`
  - الوصول: `admin` و`super admin`
  - الشاشة: أدوات الأدمن الخاصة بالشركات
- `/api/company/admin/branch-requests*`
  - الوصول: `admin` و`super admin`
  - الشاشة: موافقات الفروع/الشركات

## Admin
- `/api/admin/*`
  - الوصول: admin أو super admin وبعض المسارات تسمح deputy_admin حسب الـ module
  - الشاشة: لوحات الأدمن والموافقات والتقارير

## Merchants / Owner
- `/api/owner/*`
  - الوصول: owner مصادق
  - الشاشة: تطبيق صاحب المتجر
- `/api/merchants/*`
  - الوصول: عام لبعض مسارات التصفح، ومصادق لبعض مسارات الإدارة
  - الشاشات: المتجر، التصفح، إدارة المتجر

## Jobs
- `/api/jobs/*`
  - الوصول: عام للتصفح، مصادق للتقديم والإدارة
  - الشاشات: الوظائف، الطلبات، إدارة المتقدمين

## Cars
- `/api/cars/*`
  - الوصول: عام للتصفح، ومصادق للإدارة أو الإجراءات الخاصة بالمستخدم
  - الشاشات: السيارات، البحث، الإعلانات

## Real Estate
- `/api/real-estate/*`
  - الوصول: عام للتصفح، مصادق للإدارة/الإضافة
- `/api/admin/real-estate/*`
  - الوصول: admin / super admin
  - الشاشة: مراجعات واعتمادات العقارات

## Paid Upgrades
- `/api/paid-upgrades/*`
  - الوصول: مصادق بحسب الميزة
- `/api/admin/paid-upgrades/*`
  - الوصول: admin / super admin

## كيف تستخدم هذه الخريطة
1. حدّد الشاشة المتضررة في Flutter.
2. حدّد endpoint الذي تستدعيه الشاشة.
3. قارن role المستخدم الفعلي مع الدور المتوقع هنا.
4. انتقل إلى route/controller/service المقابل لتحديد مصدر الرفض أو الخطأ.
