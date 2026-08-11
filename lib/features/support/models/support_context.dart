/// وصف سياق طلب الدعم: من أين فُتح، وبأي قسم يرتبط، وهل يُربط بكيان محدد.
///
/// يُمرَّر إلى `showSupportRequestSheet` فتُهيّأ التذكرة تلقائياً (القسم + الربط)
/// دون أن يبحث المستخدم عن التفاصيل بنفسه. في «الوضع العام» (الرئيسية/القائمة)
/// يبقى `domain` فارغاً فيُطلب من المستخدم تحديد المشكلة.
class SupportContext {
  /// قسم التذكرة الثابت (SHOPPING/TAXI/…). فارغ = يختاره المستخدم.
  final String? domain;

  /// كيان الربط (order/ride/merchant/…) — يطابق تصنيف الباك اند.
  final String? entityType;
  final int? entityId;

  /// وصف بشري للسياق يظهر في أعلى النموذج ("بخصوص رحلتك #123").
  final String? entityLabel;

  /// نوع افتراضي (PROBLEM/COMPLAINT/…) مناسب للسياق.
  final String defaultType;

  const SupportContext({
    this.domain,
    this.entityType,
    this.entityId,
    this.entityLabel,
    this.defaultType = 'PROBLEM',
  });

  bool get isAskMode => domain == null || domain!.trim().isEmpty;
  bool get hasEntity =>
      entityType != null &&
      entityType!.trim().isNotEmpty &&
      entityId != null &&
      entityId! > 0;

  /// عام — يُطلب فيه من المستخدم تحديد القسم (الرئيسية / قائمة التطبيق).
  const SupportContext.general() : this();

  /// من السلة — قسم التسوق، مع ربط اختياري بمتجر السلة إن كانت لمتجر واحد.
  const SupportContext.cart({int? merchantId, String? merchantName})
    : this(
        domain: 'SHOPPING',
        entityType: merchantId != null ? 'merchant' : null,
        entityId: merchantId,
        entityLabel: merchantName ?? 'سلة المشتريات',
      );

  /// من داخل متجر — قسم التسوق، مرتبط بالمتجر.
  const SupportContext.merchant({
    required int merchantId,
    required String merchantName,
  }) : this(
         domain: 'SHOPPING',
         entityType: 'merchant',
         entityId: merchantId,
         entityLabel: merchantName,
       );

  /// من السوق العام — قسم التسوق دون كيان محدد.
  const SupportContext.market()
    : this(domain: 'SHOPPING', entityLabel: 'السوق');

  /// من طلب — مرتبط بالطلب.
  const SupportContext.order({required int orderId})
    : this(
        domain: 'SHOPPING',
        entityType: 'order',
        entityId: orderId,
        entityLabel: 'طلب #$orderId',
      );

  /// من التكسي عموماً — قسم التكسي دون رحلة محددة.
  const SupportContext.taxi() : this(domain: 'TAXI', entityLabel: 'خدمة التكسي');

  /// من داخل رحلة — قسم التكسي مرتبط بالرحلة (أولوية أعلى افتراضياً).
  const SupportContext.ride({required int rideId})
    : this(
        domain: 'TAXI',
        entityType: 'ride',
        entityId: rideId,
        entityLabel: 'رحلة #$rideId',
        defaultType: 'PROBLEM',
      );
}
