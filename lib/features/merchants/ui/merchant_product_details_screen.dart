import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../../merchants/models/merchant_model.dart';
import '../../products/models/product_model.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class MerchantProductDetailsScreen extends StatefulWidget {
  final MerchantModel merchant;
  final ProductModel product;
  final List<ProductModel> similarProducts;
  final bool canOrder;
  final String unavailableLabel;
  final Future<void> Function(ProductModel product, int quantity)? onAddToCart;
  final ValueChanged<ProductModel>? onOpenProduct;

  const MerchantProductDetailsScreen({
    super.key,
    required this.merchant,
    required this.product,
    required this.similarProducts,
    required this.canOrder,
    required this.unavailableLabel,
    required this.onAddToCart,
    required this.onOpenProduct,
  });

  @override
  State<MerchantProductDetailsScreen> createState() =>
      _MerchantProductDetailsScreenState();
}

class _MerchantProductDetailsScreenState
    extends State<MerchantProductDetailsScreen> {
  int _quantity = 1;
  bool _submitting = false;

  double get _effectivePrice =>
      widget.product.discountedPrice ?? widget.product.price;

  bool get _usesPharmacyConversation =>
      widget.merchant.supportsPharmacyWorkflow &&
      widget.product.requiresPharmacyConversation;

  Future<void> _addCurrentProduct() async {
    if (!widget.canOrder ||
        widget.onAddToCart == null ||
        _submitting ||
        _quantity < 1) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onAddToCart!(widget.product, _quantity);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss)
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            content: Text(
              _usesPharmacyConversation
                  ? context.lt(
                      ar: 'تم إرسال المنتج للصيدلية للمراجعة.',
                      en: 'The product was sent to the pharmacy for review.',
                    )
                  : context.lt(
                      ar: 'تمت إضافة المنتج إلى السلة.',
                      en: 'The product was added to cart.',
                    ),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _addSimilar(ProductModel product) async {
    if (widget.onAddToCart == null) return;
    await widget.onAddToCart!(product, 1);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss)
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          content: Text(
            context.lt(
              ar: 'تمت إضافة المنتج إلى السلة.',
              en: 'The product was added to cart.',
            ),
          ),
        ),
      );
  }

  List<String> _specLines() {
    final raw = widget.product.description?.trim() ?? '';
    if (raw.isEmpty) return const <String>[];

    final newlineParts = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (newlineParts.length > 1) return newlineParts;

    final commaParts = raw
        .split(RegExp(r'[,،]'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (commaParts.length > 1) return commaParts;

    return <String>[raw];
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = context.appTextDirection;
    final specs = _specLines();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child:
                          widget.product.imageUrl == null ||
                              widget.product.imageUrl!.isEmpty
                          ? Container(
                              color: Colors.white.withValues(alpha: 0.08),
                              alignment: Alignment.center,
                              child: Icon(
                                widget.merchant.type == 'restaurant'
                                    ? Icons.fastfood_rounded
                                    : Icons.inventory_2_rounded,
                                size: 42,
                              ),
                            )
                          : CachedAppImage(
                              imageUrl: widget.product.imageUrl!,
                              cacheIdentity: 'product_${widget.product.id}',
                              fit: BoxFit.cover,
                              errorWidget: (context, error, stackTrace) =>
                                  Container(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.image_not_supported_rounded,
                                    ),
                                  ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.product.name,
                    textDirection: textDirection,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatIqd(_effectivePrice),
                    textDirection: textDirection,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.product.hasDiscount) ...[
                    const SizedBox(height: 4),
                    Text(
                      formatIqd(widget.product.price),
                      style: TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                  if (widget.product.requiresPrescription ||
                      widget.product.requiresReview) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        if (widget.product.requiresPrescription)
                          _ProductFlagBadge(
                            text: context.lt(
                              ar: 'وصفة مطلوبة',
                              en: 'Prescription required',
                            ),
                            color: Colors.purple.withValues(alpha: 0.18),
                          ),
                        if (widget.product.requiresReview)
                          _ProductFlagBadge(
                            text: context.lt(
                              ar: 'مراجعة صيدلانية',
                              en: 'Pharmacist review',
                            ),
                            color: Colors.lightBlue.withValues(alpha: 0.18),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    context.lt(
                      ar: 'المواصفات / المكونات',
                      en: 'Specifications / ingredients',
                    ),
                    textDirection: textDirection,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (specs.isEmpty)
                    Text(
                      context.lt(
                        ar: 'لا توجد تفاصيل إضافية حالياً.',
                        en: 'No extra details available right now.',
                      ),
                      textDirection: textDirection,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.74),
                      ),
                    )
                  else
                    ...specs.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          textDirection: textDirection,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.circle, size: 7),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line,
                                textDirection: textDirection,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (widget.onAddToCart != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: context.lt(ar: 'زيادة', en: 'Increase'),
                                icon: const Icon(Icons.add_rounded),
                                onPressed: () => setState(() => _quantity += 1),
                              ),
                              Text(
                                '$_quantity',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                tooltip: context.lt(ar: 'تنقيص', en: 'Decrease'),
                                icon: const Icon(Icons.remove_rounded),
                                onPressed: () => setState(
                                  () => _quantity = _quantity > 1
                                      ? _quantity - 1
                                      : 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: widget.canOrder
                                ? _addCurrentProduct
                                : null,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _usesPharmacyConversation
                                        ? Icons.chat_bubble_outline_rounded
                                        : Icons.add_shopping_cart_rounded,
                                  ),
                            label: Text(
                              widget.canOrder
                                  ? _usesPharmacyConversation
                                      ? context.lt(
                                          ar: 'إرسال للوصفة/المراجعة',
                                          en: 'Send for prescription/review',
                                        )
                                      : context.lt(
                                          ar: 'إضافة إلى السلة',
                                          en: 'Add to cart',
                                        )
                                  : widget.unavailableLabel,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    context.lt(
                      ar: 'مواد مشابهة من نفس المتجر',
                      en: 'Similar items from this store',
                    ),
                    textDirection: textDirection,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: widget.similarProducts.isEmpty
                        ? Center(
                            child: Text(
                              context.lt(
                                ar: 'لا توجد مواد مشابهة حالياً.',
                                en: 'No similar items available right now.',
                              ),
                              textDirection: textDirection,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: widget.similarProducts.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = widget.similarProducts[index];
                              final canOrderSimilar =
                                  widget.merchant.isOpen && item.isAvailable;
                              final price = item.discountedPrice ?? item.price;

                              return Card(
                                margin: EdgeInsets.zero,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: widget.onOpenProduct == null
                                      ? null
                                      : () => widget.onOpenProduct!(item),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: SizedBox(
                                            width: 56,
                                            height: 56,
                                            child:
                                                item.imageUrl == null ||
                                                    item.imageUrl!.isEmpty
                                                ? Container(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                    alignment: Alignment.center,
                                                    child: const Icon(
                                                      Icons.image_outlined,
                                                      size: 18,
                                                    ),
                                                  )
                                                : CachedAppImage(
                                                    imageUrl: item.imageUrl!,
                                                    cacheIdentity:
                                                        'product_${item.id}',
                                                    fit: BoxFit.cover,
                                                    errorWidget:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => Container(
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha: 0.08,
                                                              ),
                                                          alignment:
                                                              Alignment.center,
                                                          child: const Icon(
                                                            Icons
                                                                .broken_image_rounded,
                                                            size: 18,
                                                          ),
                                                        ),
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                item.name,
                                                textDirection: textDirection,
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                formatIqd(price),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (widget.onAddToCart != null &&
                                            canOrderSimilar)
                                          IconButton(
                                            tooltip: context.lt(
                                              ar: 'إضافة للسلة',
                                              en: 'Add to cart',
                                            ),
                                            onPressed: () => _addSimilar(item),
                                            icon: const Icon(
                                              Icons.add_shopping_cart_rounded,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductFlagBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _ProductFlagBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
