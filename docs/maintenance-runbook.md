# دليل الصيانة التشغيلية

## الهدف
هذا الدليل يوضح طريقة صيانة النظام بشكل عملي وآمن بدون كسر المنطق بين `backend` و `flutter`.

## نقطة الرجوع الأساسية
- مرجع العمل الحالي محفوظ في [checkpoints.md](/d:/new apps/storeapp/bestoffer/docs/checkpoints.md) تحت:
  - `نقطة رقم 1: الكود يعمل بشكل صحيح تمامًا`
- عند طلب الرجوع لنقطة ثابتة: يتم اعتماد هذه النقطة كـ baseline.

## خريطة الوحدات
- `backend/src/modules/auth`: تسجيل الدخول/التسجيل والصلاحيات الأساسية.
- `backend/src/modules/merchants`: المتاجر + قوائم المتاجر + discovery.
- `backend/src/modules/orders`: الطلبات وحالاتها.
- `backend/src/modules/taxi`: منطق التكسي.
- `backend/src/modules/feed` + `backend/src/modules/admin`: مجتمع شديصير + الإشراف.
- `lib/features/...`: كل واجهة Flutter حسب الدور/الميزة.

## Checklist قبل أي نشر
1. شغّل تحليل Flutter:
   - `flutter analyze`
2. شغّل فحص backend syntax:
   - `node --check backend/src/server.js`
3. تأكد من عدم وجود كسر ترميز:
   - ابحث عن نمط mojibake داخل `lib/` و `backend/src/`.
4. افحص تدفق رئيسي لكل دور:
   - مستخدم، متجر، دلفري، كابتن، أدمن، سوبر أدمن.
5. افحص deep-link للإشعارات:
   - كل إشعار يفتح الصفحة المرتبطة به.

## صيانة الأداء
1. backend:
   - راقب استعلامات endpoint عالية التكرار.
   - راقب أخطاء `401/403/500` من logs.
2. flutter:
   - قلل polling غير الضروري.
   - اعتمد realtime مع fallback polling فقط عند الحاجة.

## صيانة اللغة والترميز
1. كل نص جديد يجب أن يكون ثنائي اللغة (ar/en).
2. أي نص مشوّه في الواجهة يعالج فورًا قبل الدمج.
3. عند ظهور نصوص مكسورة في شاشة:
   - افحص الملف نفسه أولًا.
   - ثم افحص بيانات backend المرتجعة.

## صيانة الملفات الكبيرة
1. أي ملف يتجاوز ~1200 سطر يدخل خطة تقسيم.
2. أسلوب التقسيم:
   - `ui/screen.dart`
   - `ui/widgets/...`
   - `state/controller.dart`
   - `data/api.dart`
3. لا تبدأ refactor شامل دفعة واحدة:
   - قسّم شاشة واحدة في كل دفعة.
4. راجع تقرير الحجم:
   - [large-files-audit.md](/d:/new apps/storeapp/bestoffer/docs/large-files-audit.md)

## قواعد عدم الكسر
1. لا يوجد fallback يخلط أنواع بيانات مختلفة (مثال: restaurant داخل market).
2. أي فلترة تخصصية يجب أن تكون:
   - محددة بالنوع
   - ومقيدة بكلمات تخصص واضحة.
3. لا يتم حذف صلاحيات/منطق سابق إلا بطلب صريح.

## أوامر فحص سريعة مقترحة
1. Flutter:
   - `flutter analyze`
   - `flutter test`
2. Backend:
   - `npm --prefix backend run start`
   - فحص endpoints الحرجة يدويًا عبر Postman/curl.
