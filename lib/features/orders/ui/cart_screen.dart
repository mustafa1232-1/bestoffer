import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/product_offer_pricing.dart';
import '../../auth/state/auth_controller.dart';
import '../models/order_item_presentation_model.dart';
import '../logic/order_preview_errors.dart';
import '../state/cart_controller.dart';
import '../state/delivery_address_controller.dart';
import '../state/orders_controller.dart';
import 'delivery_addresses_screen.dart';
import 'widgets/order_item_widgets.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final ScrollController _scrollController = ScrollController();
  final noteCtrl = TextEditingController();
  final budgetCtrl = TextEditingController();
  final couponCtrl = TextEditingController();
  final GlobalKey _itemsSectionKey = GlobalKey();
  final GlobalKey _noteBudgetSectionKey = GlobalKey();
  final GlobalKey _addressSectionKey = GlobalKey();
  final GlobalKey _couponSectionKey = GlobalKey();
  final GlobalKey _summarySectionKey = GlobalKey();
  int? budgetCapIqd;
  bool optimizingBudget = false;
  int splitPeople = 1;
  bool openingFinalReview = false;
  OutOfStockDetails? _outOfStockDetails;

  Map<String, dynamic>? _appliedCoupon;
  int _couponDiscount = 0;
  bool _checkingCoupon = false;
  String? _couponError;

  @override
  void initState() {
    super.initState();
    final draftNote = ref.read(cartControllerProvider).draftNote;
    if (draftNote != null && draftNote.isNotEmpty) {
      noteCtrl.text = draftNote;
      noteCtrl.selection = TextSelection.collapsed(offset: draftNote.length);
    }
    noteCtrl.addListener(_persistDraftNote);
    Future.microtask(() async {
      if (!mounted) return;
      await ref.read(deliveryAddressControllerProvider.notifier).bootstrap();
      if (!mounted) return;
      await _loadBudgetCap();
    });
  }

  void _persistDraftNote() {
    ref.read(cartControllerProvider.notifier).setDraftNote(noteCtrl.text);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    noteCtrl.removeListener(_persistDraftNote);
    noteCtrl.dispose();
    budgetCtrl.dispose();
    couponCtrl.dispose();
    super.dispose();
  }

  Future<void> _scrollToSection(GlobalKey sectionKey) async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sectionContext = sectionKey.currentContext;
      if (sectionContext == null) return;
      Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    });
  }

  Future<void> _validateCoupon() async {
    final code = couponCtrl.text.trim();
    if (code.isEmpty) return;
    final cart = ref.read(cartControllerProvider);
    if (cart.isMultiStore) {
      setState(() {
        _couponError = 'الكوبون في هذه النسخة متاح للطلبات من متجر واحد فقط.';
        _appliedCoupon = null;
        _couponDiscount = 0;
      });
      return;
    }
    setState(() {
      _checkingCoupon = true;
      _couponError = null;
    });
    try {
      final api = ref.read(ordersApiProvider);
      final result = await api.validateCoupon(
        code: code,
        merchantId: cart.merchantId,
        orderSubtotal: cart.subtotal,
      );
      if (!mounted) return;
      setState(() {
        _appliedCoupon = result['coupon'] as Map<String, dynamic>?;
        _couponDiscount = (result['discountAmount'] as num?)?.toInt() ?? 0;
        _checkingCoupon = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _appliedCoupon = null;
        _couponDiscount = 0;
        _couponError = mapAnyError(
          e,
          fallback: 'الكوبون غير صالح',
          customMessages: {
            'COUPON_NOT_FOUND': 'الكوبون غير موجود.',
            'COUPON_EXPIRED': 'انتهت صلاحية هذا الكوبون.',
            'COUPON_NOT_STARTED': 'هذا الكوبون غير متاح بعد.',
            'COUPON_INACTIVE': 'هذا الكوبون غير مفعل حالياً.',
            'COUPON_NOT_TARGETED': 'هذا الكوبون غير مخصص لحسابك الحالي.',
            'COUPON_USER_LIMIT_REACHED':
                'استنفدت عدد الاستخدامات المسموح بها لهذا الكوبون.',
            'COUPON_TOTAL_LIMIT_REACHED': 'تم استنفاد هذا الكوبون بالكامل.',
            'COUPON_NO_TIERS': 'لا توجد شرائح خصم صالحة لهذا الكوبون حالياً.',
          },
        );
        _checkingCoupon = false;
      });
    }
  }

  void _removeCoupon() {
    couponCtrl.clear();
    setState(() {
      _appliedCoupon = null;
      _couponDiscount = 0;
      _couponError = null;
    });
  }

  Future<void> _loadBudgetCap() async {
    final userId = ref.read(authControllerProvider).user?.id;
    if (userId == null) return;
    final raw = await ref
        .read(secureStoreProvider)
        .readString('cart_budget_cap_iqd:$userId');
    final parsed = int.tryParse(raw ?? '');
    if (!mounted || parsed == null || parsed <= 0) return;
    setState(() {
      budgetCapIqd = parsed;
      budgetCtrl.text = '$parsed';
    });
  }

  Future<void> _saveBudgetCap(int? value) async {
    final userId = ref.read(authControllerProvider).user?.id;
    if (userId == null) return;
    final store = ref.read(secureStoreProvider);
    if (value == null || value <= 0) {
      await store.delete('cart_budget_cap_iqd:$userId');
      return;
    }
    await store.writeString('cart_budget_cap_iqd:$userId', '$value');
  }

  int? _parseBudgetInput(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    final parsed = int.tryParse(digits);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  Future<void> _applyBudgetOptimization() async {
    final cap = budgetCapIqd;
    if (cap == null || cap <= 0 || optimizingBudget) return;
    final notifier = ref.read(cartControllerProvider.notifier);
    if (ref.read(cartControllerProvider).total <= cap) return;
    setState(() => optimizingBudget = true);
    var loops = 0;
    while (loops < 600) {
      loops++;
      final current = ref.read(cartControllerProvider);
      if (current.items.isEmpty || current.total <= cap) break;
      final sorted = [...current.items]
        ..sort((a, b) {
          final pa = a.product.discountedPrice ?? a.product.price;
          final pb = b.product.discountedPrice ?? b.product.price;
          return pb.compareTo(pa);
        });
      final withQty = sorted.where((e) => e.quantity > 1).toList();
      if (withQty.isNotEmpty) {
        notifier.decrementItem(
          withQty.first.product.id,
          merchantId: withQty.first.merchantId,
          selectedModifiers: withQty.first.selectedModifiers,
          selectedVariantId: withQty.first.selectedVariantId,
          selectedVariantSelections: withQty.first.selectedVariantSelections,
        );
      } else if (sorted.length > 1) {
        notifier.removeItem(
          sorted.first.product.id,
          merchantId: sorted.first.merchantId,
          selectedModifiers: sorted.first.selectedModifiers,
          selectedVariantId: sorted.first.selectedVariantId,
          selectedVariantSelections: sorted.first.selectedVariantSelections,
        );
      } else {
        break;
      }
    }
    if (!mounted) return;
    setState(() => optimizingBudget = false);
    final success = ref.read(cartControllerProvider).total <= cap;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'تم ضبط السلة ضمن الميزانية (${formatIqd(cap.toDouble())})'
              : 'تم التقليل قدر الإمكان لكن الإجمالي ما زال أعلى من الميزانية',
        ),
      ),
    );
  }

  Map<String, dynamic> _buildCheckoutPayload({
    required CartState cart,
    required int addressId,
  }) {
    final cleanedNote = noteCtrl.text.trim();
    final payload = <String, dynamic>{
      'note': cleanedNote.isEmpty ? null : cleanedNote,
      'addressId': addressId,
    };
    if (cart.storesCount > 1) {
      payload['storeOrders'] = cart.storeSections
          .map(
            (section) => {
              'merchantId': section.merchantId,
              'items': section.items
                  .map(
                    (item) => {
                      'productId': item.product.id,
                      'quantity': item.quantity,
                      if (item.selectedModifiers.isNotEmpty)
                        'selectedModifiers': item.selectedModifiers,
                      if (item.selectedVariantPayload != null)
                        'selectedVariant': item.selectedVariantPayload,
                      if (item.selectedVariantSelections.isNotEmpty)
                        'selectedVariantSelections':
                            item.selectedVariantSelections,
                    },
                  )
                  .toList(),
            },
          )
          .toList();
    } else {
      payload['merchantId'] = cart.merchantId;
      payload['items'] = cart.items
          .map(
            (item) => {
              'productId': item.product.id,
              'quantity': item.quantity,
              if (item.selectedModifiers.isNotEmpty)
                'selectedModifiers': item.selectedModifiers,
              if (item.selectedVariantPayload != null)
                'selectedVariant': item.selectedVariantPayload,
              if (item.selectedVariantSelections.isNotEmpty)
                'selectedVariantSelections': item.selectedVariantSelections,
            },
          )
          .toList();
      final couponId = (_appliedCoupon?['id'] as num?)?.toInt();
      if (couponId != null && couponId > 0) payload['couponId'] = couponId;
      final couponCode = _appliedCoupon?['code']?.toString().trim();
      if (couponCode != null && couponCode.isNotEmpty) {
        payload['couponCode'] = couponCode;
      }
    }
    return payload;
  }

  Future<bool> _showFinalReviewSheet(Map<String, dynamic> preview) async {
    final stores = List<Map<String, dynamic>>.from(
      (preview['stores'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final totals = Map<String, dynamic>.from(
      (preview['totals'] as Map? ?? const <String, dynamic>{}),
    );
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'مراجعة نهائية للطلب',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                if (stores.length > 1) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'الطلب من أكثر من متجر وقد يستغرق وقتًا أطول قليلًا.',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 10),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ...stores.map((store) {
                        final items = List<Map<String, dynamic>>.from(
                          (store['items'] as List? ?? const []).map(
                            (entry) => Map<String, dynamic>.from(entry as Map),
                          ),
                        );
                        final pricing = Map<String, dynamic>.from(
                          (store['pricing'] as Map? ??
                              const <String, dynamic>{}),
                        );
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${store['merchantName'] ?? 'متجر'}',
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...items.map(
                                (item) => _buildCartReviewItem(
                                  item,
                                  TextDirection.rtl,
                                ),
                              ),
                              const Divider(height: 18),
                              Row(
                                children: [
                                  Text(
                                    formatIqd(
                                      (pricing['totalAmount'] as num?)
                                              ?.toDouble() ??
                                          0,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Text(
                                    'إجمالي المتجر',
                                    textDirection: TextDirection.rtl,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              _SummaryRow(
                                'إجمالي قبل الخصم',
                                formatIqd(
                                  (totals['grossSubtotal'] as num?)
                                          ?.toDouble() ??
                                      0,
                                ),
                              ),
                              _SummaryRow(
                                'خصومات المنتجات',
                                '- ${formatIqd((totals['productDiscountTotal'] as num?)?.toDouble() ?? 0)}',
                                color: Colors.greenAccent,
                              ),
                              _SummaryRow(
                                'خصم الكوبون',
                                '- ${formatIqd((totals['couponDiscountTotal'] as num?)?.toDouble() ?? 0)}',
                                color: Colors.greenAccent,
                              ),
                              _SummaryRow(
                                'رسوم الخدمة',
                                formatIqd(
                                  (totals['serviceFeeTotal'] as num?)
                                          ?.toDouble() ??
                                      0,
                                ),
                              ),
                              _SummaryRow(
                                'أجور التوصيل',
                                formatIqd(
                                  (totals['deliveryFeeTotal'] as num?)
                                          ?.toDouble() ??
                                      0,
                                ),
                              ),
                              const Divider(),
                              _SummaryRow(
                                'الإجمالي النهائي',
                                formatIqd(
                                  (totals['totalAmount'] as num?)?.toDouble() ??
                                      0,
                                ),
                                bold: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('رجوع للتعديل'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('تأكيد نهائي'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return confirm == true;
  }

  Future<void> _submitCheckout() async {
    if (openingFinalReview || ref.read(ordersControllerProvider).placingOrder) {
      return;
    }
    final cart = ref.read(cartControllerProvider);
    final selectedAddress = ref
        .read(deliveryAddressControllerProvider)
        .selectedAddress;
    if (selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار عنوان التوصيل أولًا.')),
      );
      return;
    }
    setState(() {
      openingFinalReview = true;
      _outOfStockDetails = null;
    });
    try {
      final payload = _buildCheckoutPayload(
        cart: cart,
        addressId: selectedAddress.id,
      );
      final preview = await ref.read(ordersApiProvider).previewOrder(payload);
      if (!mounted) return;
      final confirmed = await _showFinalReviewSheet(preview);
      if (!mounted || !confirmed) return;
      final ok = await ref
          .read(ordersControllerProvider.notifier)
          .checkout(
            note: noteCtrl.text,
            couponId: (_appliedCoupon?['id'] as num?)?.toInt(),
            couponCode: _appliedCoupon?['code']?.toString(),
          );
      if (mounted && ok) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        final outOfStock = OutOfStockDetails.fromError(e);
        if (outOfStock != null) {
          setState(() => _outOfStockDetails = outOfStock);
        }
        final localeMessage = outOfStock?.messageForLanguageCode(
                Localizations.localeOf(context).languageCode,
              );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localeMessage ??
                  mapAnyError(e, fallback: 'تعذر مراجعة الطلب الآن'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => openingFinalReview = false);
      } else {
        openingFinalReview = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final orders = ref.watch(ordersControllerProvider);
    final selectedAddress = ref
        .watch(deliveryAddressControllerProvider)
        .selectedAddress;
    final providerDraft = cart.draftNote ?? '';
    if (noteCtrl.text != providerDraft) {
      noteCtrl.value = noteCtrl.value.copyWith(
        text: providerDraft,
        selection: TextSelection.collapsed(offset: providerDraft.length),
        composing: TextRange.empty,
      );
    }
    final budget = budgetCapIqd;
    final budgetOver = budget != null && cart.total > budget;
    final budgetProgress = budget == null || budget <= 0
        ? 0.0
        : (cart.total / budget).clamp(0.0, 1.0);
    final peopleCount = splitPeople <= 0 ? 1 : splitPeople;
    final finalTotal = (cart.total - _couponDiscount)
        .clamp(0, double.infinity)
        .toDouble();

    ref.listen<OrdersState>(ordersControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final tokens = context.maslakiTokens;

    return Scaffold(
      appBar: MaslakiTopBar(
        title: cart.merchantName == null
            ? 'سلة التسوق'
            : 'سلة ${cart.merchantName}',
        subtitle: 'مراجعة الطلب والعنوان والخصومات قبل الإرسال',
        actions: cart.items.isEmpty
            ? const []
            : [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: FilledButton.icon(
                    onPressed: (orders.placingOrder || openingFinalReview)
                        ? null
                        : _submitCheckout,
                    icon: (orders.placingOrder || openingFinalReview)
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('مراجعة نهائية'),
                  ),
                ),
              ],
      ),
      bottomNavigationBar: cart.items.isEmpty
          ? null
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: MaslakiCard(
                backgroundColor: tokens.surfacePrimary,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${cart.totalItems} منتج',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            formatIqd(finalTotal),
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 160,
                      child: MaslakiPrimaryButton(
                        label: 'مراجعة نهائية',
                        onPressed: (orders.placingOrder || openingFinalReview)
                            ? null
                            : _submitCheckout,
                        icon: Icons.done_all_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: cart.items.isEmpty
            ? const Center(
                child: MaslakiEmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'السلة فارغة',
                  body: 'ابدأ بإضافة منتجات من المتجر ثم عد هنا لمراجعة الطلب.',
                ),
              )
            : ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 120),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  SizedBox(
                    height: 90,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      children: [
                        _CartQuickCard(
                          icon: Icons.shopping_bag_outlined,
                          title: 'المنتجات',
                          subtitle: '${cart.totalItems} عنصر',
                          onTap: () => _scrollToSection(_itemsSectionKey),
                        ),
                        const SizedBox(width: 8),
                        _CartQuickCard(
                          icon: Icons.note_alt_outlined,
                          title: 'ملاحظات',
                          subtitle: 'و الميزانية',
                          onTap: () => _scrollToSection(_noteBudgetSectionKey),
                        ),
                        const SizedBox(width: 8),
                        _CartQuickCard(
                          icon: Icons.place_outlined,
                          title: 'العنوان',
                          subtitle: 'تحديد التوصيل',
                          onTap: () => _scrollToSection(_addressSectionKey),
                        ),
                        const SizedBox(width: 8),
                        _CartQuickCard(
                          icon: Icons.confirmation_number_outlined,
                          title: 'الكوبون',
                          subtitle: 'تطبيق خصم',
                          onTap: () => _scrollToSection(_couponSectionKey),
                        ),
                        const SizedBox(width: 8),
                        _CartQuickCard(
                          icon: Icons.receipt_long_outlined,
                          title: 'الملخص',
                          subtitle: formatIqd(finalTotal),
                          onTap: () => _scrollToSection(_summarySectionKey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(
                            Icons.storefront_outlined,
                            '${cart.storesCount} متجر',
                          ),
                          _chip(
                            Icons.shopping_bag_outlined,
                            '${cart.totalItems} منتج',
                          ),
                          _chip(
                            Icons.receipt_outlined,
                            'قبل الخصم ${formatIqd(cart.grossSubtotal)}',
                          ),
                          _chip(
                            Icons.payments_outlined,
                            'تقديري ${formatIqd(finalTotal)}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (cart.isMultiStore) ...[
                    const SizedBox(height: 10),
                    Card(
                      color: Colors.amber.withValues(alpha: 0.12),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'الطلب يحتوي على أكثر من متجر، وقد يستغرق وقتًا أطول قليلًا في التجهيز والتسليم.',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: _itemsSectionKey,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: cart.items.map((item) {
                            final presentation =
                                OrderItemPresentationModel.fromCartItemModel(
                                  item,
                                );
                            final pricing = computeProductOfferPricing(
                              item.product,
                              quantity: item.quantity,
                            );
                            final markedOutOfStock =
                                _outOfStockDetails?.matchesCartItem(
                                  productId: item.product.id,
                                  variantId: item.selectedVariantId,
                                ) ==
                                true;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: markedOutOfStock
                                      ? Colors.redAccent.withValues(alpha: 0.7)
                                      : Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  OrderItemMiniCard(
                                    item: presentation,
                                    compact: false,
                                    showStoreName: cart.isMultiStore,
                                    showSections: true,
                                  ),
                                  if (pricing.lineDiscountTotal > 0) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      '\u062e\u0635\u0645 ${formatIqd(pricing.lineDiscountTotal)}${pricing.freeUnits > 0 ? ' \u2022 \u0645\u062c\u0627\u0646\u064a ${pricing.freeUnits}' : ''}',
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                  if ((pricing.offerLabel ?? '')
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      pricing.offerLabel!,
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.72,
                                        ),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                  if (markedOutOfStock) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      _outOfStockDetails
                                              ?.messageForLanguageCode(
                                                Localizations.localeOf(
                                                  context,
                                                ).languageCode,
                                              ) ??
                                          'هذا الخيار غير متوفر حالياً — احذف المنتج أو اختر لوناً/مقاساً آخر.',
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        onPressed: () => ref
                                            .read(
                                              cartControllerProvider.notifier,
                                            )
                                            .decrementItem(
                                              item.product.id,
                                              merchantId: item.merchantId,
                                              selectedModifiers:
                                                  item.selectedModifiers,
                                              selectedVariantId:
                                                  item.selectedVariantId,
                                              selectedVariantSelections:
                                                  item.selectedVariantSelections,
                                            ),
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => ref
                                            .read(
                                              cartControllerProvider.notifier,
                                            )
                                            .addItem(
                                              product: item.product,
                                              merchantId: item.merchantId,
                                              merchantName: item.merchantName,
                                              selectedModifiers:
                                                  item.selectedModifiers,
                                              selectedVariantId:
                                                  item.selectedVariantId,
                                              selectedVariantSelections:
                                                  item.selectedVariantSelections,
                                            ),
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => ref
                                            .read(
                                              cartControllerProvider.notifier,
                                            )
                                            .removeItem(
                                              item.product.id,
                                              merchantId: item.merchantId,
                                              selectedModifiers:
                                                  item.selectedModifiers,
                                              selectedVariantId:
                                                  item.selectedVariantId,
                                              selectedVariantSelections:
                                                  item.selectedVariantSelections,
                                            ),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: _noteBudgetSectionKey,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: noteCtrl,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: 'ملاحظات على الطلب (اختياري)',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: budgetCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'سقف الميزانية (دينار عراقي)',
                              ),
                              onSubmitted: (v) async {
                                final parsed = _parseBudgetInput(v);
                                setState(() => budgetCapIqd = parsed);
                                await _saveBudgetCap(parsed);
                              },
                            ),
                            if (budget != null) ...[
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: budgetProgress,
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(999),
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.1,
                                ),
                                color: budgetOver
                                    ? Colors.redAccent
                                    : Colors.greenAccent,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                budgetOver
                                    ? 'فوق الميزانية بـ ${formatIqd((cart.total - budget).toDouble())}'
                                    : 'المتبقي ${formatIqd((budget - cart.total).toDouble())}',
                                style: TextStyle(
                                  color: budgetOver
                                      ? Colors.red.shade300
                                      : Colors.green.shade300,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              OutlinedButton.icon(
                                onPressed: optimizingBudget
                                    ? null
                                    : _applyBudgetOptimization,
                                icon: optimizingBudget
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.auto_fix_high_rounded),
                                label: const Text('ضبط السلة ضمن الميزانية'),
                              ),
                            ],
                            const Divider(height: 20),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [1, 2, 4, 6, 8]
                                  .map(
                                    (count) => ChoiceChip(
                                      label: Text('$count أشخاص'),
                                      selected: splitPeople == count,
                                      onSelected: (_) =>
                                          setState(() => splitPeople = count),
                                    ),
                                  )
                                  .toList(),
                            ),
                            Slider(
                              min: 1,
                              max: 12,
                              divisions: 11,
                              value: peopleCount.toDouble(),
                              onChanged: (v) =>
                                  setState(() => splitPeople = v.round()),
                            ),
                            Text(
                              'حصة الشخص: ${formatIqd(cart.total / peopleCount)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: _addressSectionKey,
                    child: Card(
                      child: ListTile(
                        title: Text(
                          selectedAddress?.shortText ??
                              'الرجاء إضافة أو اختيار عنوان توصيل',
                        ),
                        trailing: IconButton.filledTonal(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const DeliveryAddressesScreen(
                                  selectOnTap: true,
                                ),
                              ),
                            );
                            if (!mounted) return;
                            await ref
                                .read(
                                  deliveryAddressControllerProvider.notifier,
                                )
                                .bootstrap(silent: true);
                          },
                          icon: const Icon(Icons.edit_location_alt_outlined),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: _couponSectionKey,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: cart.isMultiStore
                            ? const Text(
                                'الكوبونات متاحة حاليًا للطلبات من متجر واحد فقط.',
                                textDirection: TextDirection.rtl,
                              )
                            : _appliedCoupon == null
                            ? Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: couponCtrl,
                                          textCapitalization:
                                              TextCapitalization.characters,
                                          decoration: const InputDecoration(
                                            hintText: 'أدخل رمز الكوبون',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                          onSubmitted: (_) => _validateCoupon(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton(
                                        onPressed: _checkingCoupon
                                            ? null
                                            : _validateCoupon,
                                        child: _checkingCoupon
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Text('تطبيق'),
                                      ),
                                    ],
                                  ),
                                  if (_couponError != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          _couponError!,
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              )
                            : Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.greenAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'تم تطبيق "${_appliedCoupon!['code']}" بخصم ${formatIqd(_couponDiscount.toDouble())}',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _removeCoupon,
                                    child: const Text('إزالة'),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: _summarySectionKey,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            _SummaryRow(
                              '\u0625\u062c\u0645\u0627\u0644\u064a \u0642\u0628\u0644 \u0627\u0644\u062e\u0635\u0645',
                              formatIqd(cart.grossSubtotal),
                            ),
                            if (cart.productDiscountTotal > 0)
                              _SummaryRow(
                                '\u062e\u0635\u0648\u0645\u0627\u062a \u0627\u0644\u0639\u0631\u0648\u0636',
                                '- ${formatIqd(cart.productDiscountTotal)}',
                                color: Colors.greenAccent,
                              ),
                            _SummaryRow(
                              '\u0627\u0644\u0645\u062c\u0645\u0648\u0639 \u0628\u0639\u062f \u0627\u0644\u0639\u0631\u0648\u0636',
                              formatIqd(cart.subtotal),
                            ),
                            _SummaryRow(
                              'رسوم الخدمة التقديرية',
                              formatIqd(cart.serviceFee, withCode: false),
                            ),
                            _SummaryRow(
                              cart.deliveryFee <= 0
                                  ? 'أجور التوصيل (توصيل مجاني)'
                                  : 'أجور التوصيل',
                              formatIqd(cart.deliveryFee),
                            ),
                            if (_couponDiscount > 0)
                              _SummaryRow(
                                'خصم الكوبون',
                                '- ${formatIqd(_couponDiscount.toDouble())}',
                                color: Colors.greenAccent,
                              ),
                            const Divider(),
                            _SummaryRow(
                              'الإجمالي التقديري',
                              formatIqd(finalTotal),
                              bold: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.09),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 15), const SizedBox(width: 5), Text(text)],
      ),
    );
  }
}

Widget _buildCartReviewItem(
  Map<String, dynamic> item,
  TextDirection textDirection,
) {
  final variantSelections = List<dynamic>.from(
    item['selectedVariantSelections'] as List? ??
        item['selected_variant_options_json'] as List? ??
        const [],
  );
  final variantLabel = variantSelections.isEmpty
      ? null
      : variantSelections
            .map((selection) {
              final map = Map<String, dynamic>.from(selection as Map);
              final group = '${map['groupLabel'] ?? map['groupCode'] ?? ''}'
                  .trim();
              final option = '${map['optionLabel'] ?? map['optionCode'] ?? ''}'
                  .trim();
              if (group.isEmpty) return option;
              if (option.isEmpty) return group;
              return '$group: $option';
            })
            .join(' • ');

  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            Text(formatIqd((item['lineTotal'] as num?)?.toDouble() ?? 0)),
            const Spacer(),
            Expanded(
              child: Text(
                '${item['productName'] ?? 'منتج'} x ${(item['quantity'] as num?)?.toInt() ?? 0}',
                textAlign: TextAlign.right,
                textDirection: textDirection,
              ),
            ),
          ],
        ),
        if (variantLabel != null && variantLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              variantLabel,
              textDirection: textDirection,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 11,
              ),
            ),
          ),
      ],
    ),
  );
}

class _CartQuickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CartQuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          width: 162,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: scheme.primary.withValues(alpha: 0.18),
                child: Icon(icon, size: 17, color: scheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      textDirection: TextDirection.rtl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      textDirection: TextDirection.rtl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  const _SummaryRow(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      fontSize: bold ? 16 : 14,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(value, textAlign: TextAlign.left, style: style),
          ),
          Expanded(
            child: Text(label, textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}
