function normalizeLocaleCode(raw) {
  return String(raw || "").trim().toLowerCase().startsWith("en") ? "en" : "ar";
}

function interpolate(template, args = {}) {
  const map =
    args && typeof args === "object" && !Array.isArray(args) ? args : {};
  return String(template || "").replace(/\{(\w+)\}/g, (_, key) => {
    const value = map[key];
    return value == null ? "" : String(value);
  });
}

function defaultArgsForLocale(locale, args = null) {
  const normalizedLocale = normalizeLocaleCode(locale);
  const base =
    args && typeof args === "object" && !Array.isArray(args) ? { ...args } : {};
  if (!String(base.senderName || "").trim()) {
    base.senderName = normalizedLocale === "en" ? "Someone" : "مستخدم";
  }
  return base;
}

const TEMPLATES = {
  ar: {
    "notifications.generic.title": "إشعار جديد",
    "notifications.generic.body": "لديك تحديث جديد في التطبيق.",
    "notifications.orders.title": "تحديث طلب",
    "notifications.orders.body": "هناك تحديث جديد على طلبك.",
    "notifications.orders.status.title": "تحديث حالة الطلب",
    "notifications.orders.status.body":
      "قام {storeName} بتحديث حالة طلبك رقم #{orderNumber}: {statusText}",
    "notifications.delivery.title": "تحديث دلفري",
    "notifications.delivery.body": "تغيّرت حالة مندوب أو طلب دلفري.",
    "notifications.taxi.title": "تحديث رحلة",
    "notifications.taxi.body": "تم تحديث حالة رحلتك.",
    "notifications.taxi.ride_request.title": "طلب رحلة جديد",
    "notifications.taxi.ride_request.body": "طلب رحلة قريب منك — سعر مقترح {fare} د.ع",
    "notifications.jobs.title": "تحديث وظيفة",
    "notifications.jobs.body": "هناك تحديث جديد متعلق بالوظائف أو الطلبات.",
    "notifications.real_estate.title": "تحديث عقاري",
    "notifications.real_estate.body": "تم تحديث إعلان عقاري أو نشاط مرتبط به.",
    "notifications.paid_upgrades.title": "تحديث الباقة",
    "notifications.paid_upgrades.body": "هناك تحديث جديد بخصوص الباقة أو الترقية.",
    "notifications.company.title": "تحديث الشركة",
    "notifications.company.body": "هناك تحديث جديد متعلق بمساحة عمل الشركة.",
    "notifications.admin.title": "تحديث إداري",
    "notifications.admin.body": "هناك إجراء أو مراجعة جديدة من الإدارة.",
    "notifications.hr.title": "تحديث الموارد البشرية",
    "notifications.hr.body": "هناك تحديث جديد متعلق بالدوام أو الرواتب أو الطلبات.",
    "notifications.profile.title": "تحديث الحساب",
    "notifications.profile.body": "هناك تحديث جديد متعلق ببيانات حسابك.",
    "notifications.social.activity.title": "تحديث اجتماعي",
    "notifications.social.activity.body": "هناك نشاط اجتماعي جديد على حسابك.",
    "notifications.social.post.like.title": "إعجاب جديد بالمنشور",
    "notifications.social.post.like.body": "أعجب أحدهم بمنشورك.",
    "notifications.social.reel.like.title": "إعجاب جديد بالريل",
    "notifications.social.reel.like.body": "أعجب أحدهم بالريل الخاص بك.",
    "notifications.social.comment.title": "تعليق جديد",
    "notifications.social.comment.body": "علق أحدهم على محتواك.",
    "notifications.social.mention.title": "تمت الإشارة إليك",
    "notifications.social.mention.body": "أشار إليك أحدهم داخل محتوى اجتماعي.",
    "notifications.social.relation.title": "تحديث اجتماعي جديد",
    "notifications.social.relation.body": "هناك تحديث جديد متعلق بعلاقاتك الاجتماعية.",
    "notifications.social.story.title": "تحديث على الستوري",
    "notifications.social.story.body": "{senderName} أضاف نشاطاً جديداً على الستوري.",
    "notifications.social.report.title": "تحديث على التبليغ",
    "notifications.social.report.body": "هناك تحديث جديد متعلق بالتبليغ أو المراجعة.",
    "notifications.social.community.title": "تحديث المجتمع",
    "notifications.social.community.body": "هناك تحديث جديد داخل مجتمعك.",
    "notifications.social.call.title": "مكالمة اجتماعية",
    "notifications.social.call.body": "{senderName} يحاول الاتصال بك.",
    "notifications.chat.message.title": "رسالة جديدة",
    "notifications.chat.message.body": "أرسل {senderName} رسالة إليك.",
  },
  en: {
    "notifications.generic.title": "New notification",
    "notifications.generic.body": "You have a new update in the app.",
    "notifications.orders.title": "Order update",
    "notifications.orders.body": "There is a new update on your order.",
    "notifications.orders.status.title": "Order status update",
    "notifications.orders.status.body":
      "{storeName} updated your order #{orderNumber}: {statusText}",
    "notifications.delivery.title": "Delivery update",
    "notifications.delivery.body": "A delivery request or courier status has changed.",
    "notifications.taxi.title": "Ride update",
    "notifications.taxi.body": "Your ride status has been updated.",
    "notifications.taxi.ride_request.title": "New ride request",
    "notifications.taxi.ride_request.body": "A ride request near you — suggested fare {fare} IQD",
    "notifications.jobs.title": "Job update",
    "notifications.jobs.body": "There is a new update related to jobs or applications.",
    "notifications.real_estate.title": "Real estate update",
    "notifications.real_estate.body": "A real estate listing or seller activity has been updated.",
    "notifications.paid_upgrades.title": "Plan update",
    "notifications.paid_upgrades.body": "There is a new update about your plan or upgrade.",
    "notifications.company.title": "Company update",
    "notifications.company.body": "There is a new update related to your company workspace.",
    "notifications.admin.title": "Admin update",
    "notifications.admin.body": "There is a new administrative review or action.",
    "notifications.hr.title": "HR update",
    "notifications.hr.body": "There is a new update related to attendance, payroll, or requests.",
    "notifications.profile.title": "Account update",
    "notifications.profile.body": "There is a new update related to your profile data.",
    "notifications.social.activity.title": "Social update",
    "notifications.social.activity.body": "There is new social activity on your account.",
    "notifications.social.post.like.title": "New post like",
    "notifications.social.post.like.body": "Someone liked your post.",
    "notifications.social.reel.like.title": "New reel like",
    "notifications.social.reel.like.body": "Someone liked your reel.",
    "notifications.social.comment.title": "New comment",
    "notifications.social.comment.body": "Someone commented on your content.",
    "notifications.social.mention.title": "You were mentioned",
    "notifications.social.mention.body": "Someone mentioned you in social content.",
    "notifications.social.relation.title": "New social update",
    "notifications.social.relation.body": "There is a new update about your social connections.",
    "notifications.social.story.title": "Story update",
    "notifications.social.story.body": "{senderName} added a new story update.",
    "notifications.social.report.title": "Report update",
    "notifications.social.report.body": "There is a new update related to a report or moderation review.",
    "notifications.social.community.title": "Community update",
    "notifications.social.community.body": "There is a new update inside your community.",
    "notifications.social.call.title": "Incoming social call",
    "notifications.social.call.body": "{senderName} is trying to call you.",
    "notifications.chat.message.title": "New message",
    "notifications.chat.message.body": "{senderName} sent you a message.",
  },
};

export function renderNotificationPiece({
  locale,
  key,
  args = null,
  fallback = null,
}) {
  const normalizedLocale = normalizeLocaleCode(locale);
  const normalizedKey = String(key || "").trim();
  if (!normalizedKey) {
    return fallback == null ? null : String(fallback);
  }
  const template = TEMPLATES[normalizedLocale]?.[normalizedKey];
  if (!template) {
    return fallback == null ? null : String(fallback);
  }
  return interpolate(template, defaultArgsForLocale(normalizedLocale, args));
}

export function renderNotificationTextForLocale({
  locale,
  title,
  body,
  payload,
}) {
  const normalizedPayload =
    payload && typeof payload === "object" && !Array.isArray(payload)
      ? payload
      : {};
  const renderedTitle =
    renderNotificationPiece({
      locale,
      key: normalizedPayload.i18nTitleKey,
      args: normalizedPayload.i18nTitleArgs,
      fallback: title,
    }) || interpolate(TEMPLATES[normalizeLocaleCode(locale)]["notifications.generic.title"]);
  const renderedBody = renderNotificationPiece({
    locale,
    key: normalizedPayload.i18nBodyKey,
    args: normalizedPayload.i18nBodyArgs,
    fallback: body,
  });
  return {
    title: renderedTitle,
    body: renderedBody == null ? null : String(renderedBody),
  };
}

export function normalizeNotificationLocale(locale) {
  return normalizeLocaleCode(locale);
}
