import { isGenericNotificationKey } from "./notification.i18n.js";

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
    "notifications.orders.merchant_accepted.title": "تم قبول طلبك",
    "notifications.orders.merchant_accepted.body":
      "قبل {storeName} طلبك {orderRef} وبدأت مرحلة التحضير.",
    "notifications.orders.preparing.title": "طلبك قيد التحضير",
    "notifications.orders.preparing.body":
      "{storeName} يحضر طلبك {orderRef} الآن.",
    "notifications.orders.ready.title": "طلبك جاهز",
    "notifications.orders.ready.body":
      "طلبك {orderRef} جاهز وسيتم تسليمه للدلفري قريبا.",
    "notifications.orders.courier_assigned.title": "تم تعيين دلفري لطلبك",
    "notifications.orders.courier_assigned.body":
      "تم تعيين {courierName} لتوصيل طلبك {orderRef}.",
    "notifications.orders.courier_reassigned.title": "تم تغيير الدلفري",
    "notifications.orders.courier_reassigned.body":
      "تم تعيين {courierName} بدلا من الدلفري السابق لطلبك {orderRef}.",
    "notifications.orders.on_the_way.title": "طلبك في الطريق",
    "notifications.orders.on_the_way.body":
      "{courierName} خرج بطلبك {orderRef} وهو في الطريق إليك.",
    "notifications.orders.arrived.title": "الدلفري وصل",
    "notifications.orders.arrived.body":
      "{courierName} وصل إلى موقعك لتسليم طلبك {orderRef}.",
    "notifications.orders.delivered.title": "تم تسليم طلبك",
    "notifications.orders.delivered.body":
      "تم تسليم طلبك {orderRef}. شكرا لاستخدام مسلكي.",
    "notifications.orders.received.title": "تم استلام الطلب",
    "notifications.orders.received.body":
      "تم تأكيد استلام طلبك {orderRef}. اكتملت عملية الطلب.",
    "notifications.orders.cancelled.title": "تم إلغاء الطلب",
    "notifications.orders.cancelled.body":
      "تم إلغاء طلبك {orderRef}. افتح الطلب لمعرفة التفاصيل.",
    "notifications.orders.rejected.title": "تعذر قبول الطلب",
    "notifications.orders.rejected.body":
      "لم يتمكن {storeName} من قبول طلبك {orderRef}. افتح الطلب لمعرفة السبب أو اطلب من متجر آخر.",
    "notifications.orders.pending_no_driver.title": "نبحث عن دلفري",
    "notifications.orders.pending_no_driver.body":
      "طلبك {orderRef} مقبول، ونبحث الآن عن دلفري متاح لتوصيله.",
    "notifications.store.new_order.title": "طلب جديد في المتجر",
    "notifications.store.new_order.body":
      "وصل طلب {orderRef} من {customerName}. افتح الطلب لقبوله أو بدء التحضير.",
    "notifications.store.preparing.title": "تم بدء تحضير الطلب",
    "notifications.store.preparing.body":
      "طلب {orderRef} أصبح قيد التحضير داخل {storeName}.",
    "notifications.store.ready_for_pickup.title": "الطلب جاهز للتسليم",
    "notifications.store.ready_for_pickup.body":
      "طلب {orderRef} جاهز، وبانتظار استلام الدلفري له.",
    "notifications.store.courier_assigned.title": "تم تعيين دلفري للطلب",
    "notifications.store.courier_assigned.body":
      "تم تعيين {courierName} لاستلام طلب {orderRef} من {storeName}.",
    "notifications.store.courier_reassigned.title": "تم تغيير دلفري الطلب",
    "notifications.store.courier_reassigned.body":
      "تم تحديث دلفري طلب {orderRef}. الدلفري الحالي: {courierName}.",
    "notifications.store.no_driver.title": "لا يوجد دلفري متاح حالياً",
    "notifications.store.no_driver.body":
      "طلب {orderRef} ما زال بانتظار دلفري متاح. سنحدثك عند التعيين.",
    "notifications.store.customer_confirmed.title": "الزبون أكد استلام الطلب",
    "notifications.store.customer_confirmed.body":
      "تم تأكيد استلام طلب {orderRef} من الزبون. سيظهر ضمن الطلبات المكتملة.",
    "notifications.store.customer_cancelled.title": "الزبون ألغى الطلب",
    "notifications.store.customer_cancelled.body":
      "تم إلغاء طلب {orderRef}. افتح لوحة الطلبات لمعرفة التفاصيل.",
    "notifications.store.settlement_approved.title": "تمت الموافقة على المستحقات",
    "notifications.store.settlement_approved.body":
      "تمت الموافقة على مستحقات {storeName} بقيمة {amount} د.ع.",
    "notifications.store.settlement_rejected.title": "تحتاج المستحقات إلى مراجعة",
    "notifications.store.settlement_rejected.body":
      "طلب مستحقات {storeName} بقيمة {amount} د.ع يحتاج إلى مراجعة قبل الصرف.",
    "notifications.store.merchant_approved.title": "تم تفعيل المتجر",
    "notifications.store.merchant_approved.body":
      "تم تفعيل {storeName}. يمكن للزبائن الآن رؤية المتجر وإرسال الطلبات.",
    "notifications.delivery.title": "تحديث دلفري",
    "notifications.delivery.body": "تغيّرت حالة مندوب أو طلب دلفري.",
    "notifications.delivery.assigned.title": "طلب توصيل جديد",
    "notifications.delivery.assigned.body":
      "تم تعيينك لتوصيل طلب {orderRef} من {storeName} إلى {customerName}.",
    "notifications.delivery.reassigned.title": "تم تحديث مهمة التوصيل",
    "notifications.delivery.reassigned.body":
      "تم تغيير مهمة التوصيل لطلب {orderRef}. افتح طلبات الدلفري لمعرفة التفاصيل.",
    "notifications.delivery.removed.title": "تم إلغاء مهمة التوصيل",
    "notifications.delivery.removed.body":
      "لم تعد مسؤولا عن توصيل طلب {orderRef}.",
    "notifications.delivery.available.title": "طلب توصيل متاح",
    "notifications.delivery.available.body":
      "يوجد طلب توصيل جديد من {storeName}. افتح الطلب لقبوله.",
    "notifications.delivery.reconciliation_approved.title":
      "تم اعتماد تسوية الطلب",
    "notifications.delivery.reconciliation_approved.body":
      "اعتمدت الإدارة تسوية الطلب {orderRef}. اضغط لعرض التقرير المالي.",
    "notifications.delivery.reconciliation_rejected.title":
      "تسوية الطلب تحتاج تصحيحاً",
    "notifications.delivery.reconciliation_rejected.body":
      "رفضت الإدارة تسوية الطلب {orderRef}: {reviewNote}. اضغط لمراجعة التقرير.",
    "notifications.taxi.title": "تحديث رحلة",
    "notifications.taxi.body": "تم تحديث حالة رحلتك.",
    "notifications.taxi.ride_request.title": "طلب رحلة جديد",
    "notifications.taxi.ride_request.body": "طلب رحلة قريب منك — سعر مقترح {fare} د.ع",
    "notifications.taxi.assigned.title": "تم قبول رحلتك",
    "notifications.taxi.assigned.body":
      "تم تعيين {captainName} لرحلتك {rideRef}.",
    "notifications.taxi.arriving.title": "الكابتن في الطريق إليك",
    "notifications.taxi.arriving.body":
      "{captainName} يتحرك الآن باتجاه نقطة الانطلاق لرحلتك {rideRef}.",
    "notifications.taxi.arrived.title": "الكابتن وصل",
    "notifications.taxi.arrived.body":
      "{captainName} وصل إلى نقطة الانطلاق لرحلتك {rideRef}.",
    "notifications.taxi.started.title": "بدأت الرحلة",
    "notifications.taxi.started.body":
      "بدأت رحلتك {rideRef}. نتمنى لك رحلة آمنة.",
    "notifications.taxi.completed.title": "انتهت الرحلة",
    "notifications.taxi.completed.body":
      "تم إنهاء رحلتك {rideRef}. شكرا لاستخدام مسلكي.",
    "notifications.taxi.cancelled.title": "تم إلغاء الرحلة",
    "notifications.taxi.cancelled.body":
      "تم إلغاء رحلتك {rideRef}. افتح الرحلة لمعرفة التفاصيل.",
    "notifications.taxi.fare_update.title": "تحديث سعر الرحلة",
    "notifications.taxi.fare_update.body":
      "يوجد تحديث على سعر رحلتك {rideRef}. السعر الحالي {fare} د.ع.",
    "notifications.services.title": "تحديث خدمة",
    "notifications.services.body": "هناك تحديث جديد على طلب خدمة مسلكي.",
    "notifications.services.new_request.title": "طلب خدمة جديد",
    "notifications.services.new_request.body":
      "لديك طلب جديد لخدمة {serviceName} {requestRef}.",
    "notifications.services.accepted.title": "تم قبول طلب الخدمة",
    "notifications.services.accepted.body":
      "قبل {providerName} طلب {serviceName} {requestRef}.",
    "notifications.services.rejected.title": "تعذر قبول طلب الخدمة",
    "notifications.services.rejected.body":
      "لم يتمكن {providerName} من قبول طلب {serviceName} {requestRef}.",
    "notifications.services.quote_sent.title": "وصل عرض سعر",
    "notifications.services.quote_sent.body":
      "أرسل {providerName} عرض سعر لخدمة {serviceName} {requestRef}.",
    "notifications.services.completed.title": "اكتملت الخدمة",
    "notifications.services.completed.body":
      "تم إكمال طلب خدمة {serviceName} {requestRef}.",
    "notifications.services.cancelled.title": "تم إلغاء طلب الخدمة",
    "notifications.services.cancelled.body":
      "تم إلغاء طلب خدمة {serviceName} {requestRef}.",
    "notifications.services.message.title": "رسالة خدمة جديدة",
    "notifications.services.message.body":
      "أرسل {providerName} رسالة بخصوص خدمة {serviceName} {requestRef}.",
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
    "notifications.orders.merchant_accepted.title": "Your order was accepted",
    "notifications.orders.merchant_accepted.body":
      "{storeName} accepted your order {orderRef} and started preparing it.",
    "notifications.orders.preparing.title": "Your order is being prepared",
    "notifications.orders.preparing.body":
      "{storeName} is preparing your order {orderRef}.",
    "notifications.orders.ready.title": "Your order is ready",
    "notifications.orders.ready.body":
      "Your order {orderRef} is ready and will be handed to the courier soon.",
    "notifications.orders.courier_assigned.title": "Courier assigned",
    "notifications.orders.courier_assigned.body":
      "{courierName} was assigned to deliver your order {orderRef}.",
    "notifications.orders.courier_reassigned.title": "Courier changed",
    "notifications.orders.courier_reassigned.body":
      "{courierName} is now assigned to deliver your order {orderRef}.",
    "notifications.orders.on_the_way.title": "Your order is on the way",
    "notifications.orders.on_the_way.body":
      "{courierName} picked up your order {orderRef} and is heading to you.",
    "notifications.orders.arrived.title": "Courier arrived",
    "notifications.orders.arrived.body":
      "{courierName} has arrived to deliver your order {orderRef}.",
    "notifications.orders.delivered.title": "Order delivered",
    "notifications.orders.delivered.body":
      "Your order {orderRef} was delivered. Thank you for using Maslaki.",
    "notifications.orders.received.title": "Order received",
    "notifications.orders.received.body":
      "You confirmed receipt of order {orderRef}. The order is complete.",
    "notifications.orders.cancelled.title": "Order cancelled",
    "notifications.orders.cancelled.body":
      "Your order {orderRef} was cancelled. Open the order for details.",
    "notifications.orders.rejected.title": "Order could not be accepted",
    "notifications.orders.rejected.body":
      "{storeName} could not accept your order {orderRef}. Open the order for details or try another store.",
    "notifications.orders.pending_no_driver.title": "Finding a courier",
    "notifications.orders.pending_no_driver.body":
      "Your order {orderRef} is accepted, and we are looking for an available courier.",
    "notifications.store.new_order.title": "New store order",
    "notifications.store.new_order.body":
      "Order {orderRef} from {customerName} arrived. Open it to accept or start preparing.",
    "notifications.store.preparing.title": "Order preparation started",
    "notifications.store.preparing.body":
      "Order {orderRef} is now being prepared at {storeName}.",
    "notifications.store.ready_for_pickup.title": "Order ready for handoff",
    "notifications.store.ready_for_pickup.body":
      "Order {orderRef} is ready. Hand it to the courier or confirm pickup.",
    "notifications.store.courier_assigned.title": "Courier assigned to order",
    "notifications.store.courier_assigned.body":
      "{courierName} was assigned to pick up order {orderRef} from {storeName}.",
    "notifications.store.courier_reassigned.title": "Order courier changed",
    "notifications.store.courier_reassigned.body":
      "The courier for order {orderRef} changed. Current courier: {courierName}.",
    "notifications.store.no_driver.title": "No courier available yet",
    "notifications.store.no_driver.body":
      "Order {orderRef} is still waiting for an available courier. We will update you when one is assigned.",
    "notifications.store.customer_confirmed.title": "Customer confirmed delivery",
    "notifications.store.customer_confirmed.body":
      "The customer confirmed receiving order {orderRef}. It will appear under completed orders.",
    "notifications.store.customer_cancelled.title": "Customer cancelled the order",
    "notifications.store.customer_cancelled.body":
      "Order {orderRef} was cancelled. Open the orders dashboard for details.",
    "notifications.store.settlement_approved.title": "Store payout approved",
    "notifications.store.settlement_approved.body":
      "The payout for {storeName} was approved for {amount} IQD.",
    "notifications.store.settlement_rejected.title": "Payout needs review",
    "notifications.store.settlement_rejected.body":
      "The payout request for {storeName} worth {amount} IQD needs review before payment.",
    "notifications.store.merchant_approved.title": "Store activated",
    "notifications.store.merchant_approved.body":
      "{storeName} is now active. Customers can see the store and place orders.",
    "notifications.delivery.title": "Delivery update",
    "notifications.delivery.body": "A delivery request or courier status has changed.",
    "notifications.delivery.assigned.title": "New delivery task",
    "notifications.delivery.assigned.body":
      "You were assigned to deliver order {orderRef} from {storeName} to {customerName}.",
    "notifications.delivery.reassigned.title": "Delivery task updated",
    "notifications.delivery.reassigned.body":
      "The delivery task for order {orderRef} changed. Open current delivery orders for details.",
    "notifications.delivery.removed.title": "Delivery task removed",
    "notifications.delivery.removed.body":
      "You are no longer assigned to deliver order {orderRef}.",
    "notifications.delivery.available.title": "Delivery task available",
    "notifications.delivery.available.body":
      "A new delivery task from {storeName} is available. Open it to accept.",
    "notifications.delivery.reconciliation_approved.title":
      "Order settlement approved",
    "notifications.delivery.reconciliation_approved.body":
      "Admin approved the settlement for order {orderRef}. Open the financial report for details.",
    "notifications.delivery.reconciliation_rejected.title":
      "Order settlement needs correction",
    "notifications.delivery.reconciliation_rejected.body":
      "Admin rejected the settlement for order {orderRef}: {reviewNote}. Open the report to review it.",
    "notifications.taxi.title": "Ride update",
    "notifications.taxi.body": "Your ride status has been updated.",
    "notifications.taxi.ride_request.title": "New ride request",
    "notifications.taxi.ride_request.body": "A ride request near you — suggested fare {fare} IQD",
    "notifications.taxi.assigned.title": "Your ride was accepted",
    "notifications.taxi.assigned.body":
      "{captainName} was assigned to your ride {rideRef}.",
    "notifications.taxi.arriving.title": "Captain is on the way",
    "notifications.taxi.arriving.body":
      "{captainName} is heading to the pickup point for ride {rideRef}.",
    "notifications.taxi.arrived.title": "Captain arrived",
    "notifications.taxi.arrived.body":
      "{captainName} arrived at the pickup point for ride {rideRef}.",
    "notifications.taxi.started.title": "Ride started",
    "notifications.taxi.started.body":
      "Your ride {rideRef} has started. Have a safe trip.",
    "notifications.taxi.completed.title": "Ride completed",
    "notifications.taxi.completed.body":
      "Your ride {rideRef} was completed. Thank you for using Maslaki.",
    "notifications.taxi.cancelled.title": "Ride cancelled",
    "notifications.taxi.cancelled.body":
      "Your ride {rideRef} was cancelled. Open the ride for details.",
    "notifications.taxi.fare_update.title": "Ride fare update",
    "notifications.taxi.fare_update.body":
      "There is a fare update for ride {rideRef}. Current fare: {fare} IQD.",
    "notifications.services.title": "Service update",
    "notifications.services.body": "There is a new update on your Maslaki service request.",
    "notifications.services.new_request.title": "New service request",
    "notifications.services.new_request.body":
      "You have a new request for {serviceName} {requestRef}.",
    "notifications.services.accepted.title": "Service request accepted",
    "notifications.services.accepted.body":
      "{providerName} accepted your {serviceName} request {requestRef}.",
    "notifications.services.rejected.title": "Service request declined",
    "notifications.services.rejected.body":
      "{providerName} could not accept your {serviceName} request {requestRef}.",
    "notifications.services.quote_sent.title": "Service quote received",
    "notifications.services.quote_sent.body":
      "{providerName} sent a quote for {serviceName} {requestRef}.",
    "notifications.services.completed.title": "Service completed",
    "notifications.services.completed.body":
      "Your {serviceName} request {requestRef} was completed.",
    "notifications.services.cancelled.title": "Service request cancelled",
    "notifications.services.cancelled.body":
      "Your {serviceName} request {requestRef} was cancelled.",
    "notifications.services.message.title": "New service message",
    "notifications.services.message.body":
      "{providerName} sent a message about {serviceName} {requestRef}.",
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

function readLocalizedOverride(payload, locale) {
  if (normalizeLocaleCode(locale) !== "en") return {};
  const raw = payload?.textEn;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const pick = (value) => {
    const text = String(value ?? "").trim();
    return text || null;
  };
  return { title: pick(raw.title), body: pick(raw.body) };
}

function renderPieceWithSpecificFallback({ locale, key, args, fallback }) {
  const hasFallback = String(fallback ?? "").trim().length > 0;
  // A stored category-level key (legacy rows) must not hide the specific copy.
  if (hasFallback && isGenericNotificationKey(key)) return String(fallback);
  return renderNotificationPiece({ locale, key, args, fallback });
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
  const override = readLocalizedOverride(normalizedPayload, locale);
  const renderedTitle =
    renderPieceWithSpecificFallback({
      locale,
      key: normalizedPayload.i18nTitleKey,
      args: normalizedPayload.i18nTitleArgs,
      fallback: override.title || title,
    }) || interpolate(TEMPLATES[normalizeLocaleCode(locale)]["notifications.generic.title"]);
  const renderedBody = renderPieceWithSpecificFallback({
    locale,
    key: normalizedPayload.i18nBodyKey,
    args: normalizedPayload.i18nBodyArgs,
    fallback: override.body || body,
  });
  return {
    title: renderedTitle,
    body: renderedBody == null ? null : String(renderedBody),
  };
}

export function normalizeNotificationLocale(locale) {
  return normalizeLocaleCode(locale);
}
