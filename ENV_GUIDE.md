# دليل متغيرات البيئة

> المرجع التنفيذي النهائي هو `backend/src/config/env.js`. هذا الملف يلخص أهم المتغيرات وما الذي يحدث إذا كانت ناقصة أو خاطئة.

## متغيرات حرجة لا يعمل النظام بدونها

### `DATABASE_URL`
- يستخدم في: PostgreSQL primary connection
- أين: `config/db.runtime.js` عبر `config/db.js`
- عند الخطأ:
  - يفشل boot
  - `/health` و`/ready` يتأثران
  - كل endpoints المعتمدة على DB تتوقف

### `JWT_SECRET`
- يستخدم في: توقيع/التحقق من access tokens
- أين: auth/session layer
- عند الخطأ:
  - login/token verification يفشل
  - `validateRuntimeEnv()` يوقف الإقلاع

## متغيرات موصى بها بقوة

### `REDIS_URL`
- يستخدم في:
  - rate limiting
  - cache قصير
  - تنسيق خفيف لبعض الحالات
- عند غيابه:
  - بعض المزايا قد تعمل degraded أو fallback بحسب التنفيذ

### `CF_R2_BUCKET`
### `CF_R2_ENDPOINT`
### `CF_R2_ACCESS_KEY_ID`
### `CF_R2_SECRET_ACCESS_KEY`
### `CF_R2_PUBLIC_BASE_URL`
- تستخدم في: رفع وعرض الوسائط
- عند الخطأ في production:
  - `validateRuntimeEnv()` يوقف boot
  - upload/media readiness تصبح غير سليمة

## متغيرات الشبكة والـ API
- `HOST`
- `PORT`
- `CORS_ORIGINS`
- `JSON_BODY_LIMIT`
- `REQUEST_TIMEOUT_MS`

## متغيرات الأمان والمحددات
- `RATE_LIMIT_WINDOW_MS`
- `RATE_LIMIT_MAX_REQUESTS`
- `RATE_LIMIT_AUTH_MAX_REQUESTS`
- `RATE_LIMIT_TRUSTED_IPS`
- `FIREWALL_ENABLED`
- `FIREWALL_ALLOWED_METHODS`
- `FIREWALL_TRUSTED_IPS`
- `FIREWALL_MAX_PATH_LENGTH`
- `FIREWALL_MAX_QUERY_LENGTH`
- `FIREWALL_MAX_HEADER_BYTES`
- `FIREWALL_VIOLATION_WINDOW_MS`
- `FIREWALL_VIOLATION_MAX`
- `FIREWALL_BLOCK_DURATION_MS`
- `FIREWALL_BLOCK_SQLI`
- `FIREWALL_BLOCK_XSS`
- `FIREWALL_BLOCK_PATH_TRAVERSAL`
- `FIREWALL_BLOCK_BAD_USER_AGENT`

## متغيرات المصادقة والجلسات
- `JWT_SECRET_PREVIOUS`
  - لتوافق rotation
- `JWT_ISSUER`
- `JWT_AUDIENCE`
- `JWT_ACCESS_TTL`
- `AUTH_MAX_FAILED_ATTEMPTS`
- `AUTH_LOCK_MINUTES`
- `AUTH_SESSION_TTL_DAYS`
- `AUTH_MAX_ACTIVE_SESSIONS_PER_USER`
- `AUTH_DEVICE_BINDING_REQUIRED`
- `AUTH_ALLOW_LEGACY_TOKENS`
- `AUTH_SESSION_TOUCH_INTERVAL_SEC`

## متغيرات RTC / TURN
- `RTC_TURN_URLS`
- `RTC_TURN_SECRET`
- `RTC_TURN_CREDENTIAL_TTL_SEC`
- `RTC_TURN_PROVIDER`
- `RTC_TURN_ENABLED`

تستخدم في:
- إعداد مكالمات realtime
- `/api/system/rtc-config`

## متغيرات OCR / Google Vision
- `RESIDENCE_CARD_OCR_PROVIDER`
- `RESIDENCE_CARD_OCR_MIN_CONFIDENCE`
- `GOOGLE_VISION_API_KEY`
- `GOOGLE_VISION_API_URL`

## متغيرات Twilio
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_NTS_TTL_SEC`

## متغيرات seed الإدارية
- `SUPER_ADMIN_PHONE`
- `SUPER_ADMIN_PIN`
- `SUPER_ADMIN_NAME`

## نصيحة تشغيلية
إذا فشل backend في الإقلاع:
1. ابدأ من `validateRuntimeEnv()` في `env.js`
2. راجع القيم الحرجة أعلاه
3. افحص logs الخاصة بـ migrations/schema
4. بعدها فقط انتقل إلى مشاكل الشبكة أو الكود
