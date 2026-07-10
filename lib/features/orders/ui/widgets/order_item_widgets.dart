import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/media/cached_app_image.dart';
import '../../../../core/utils/currency.dart';
import '../../models/order_item_presentation_model.dart';

String _lt(BuildContext context, {required String ar, required String en}) {
  return Localizations.localeOf(context).languageCode.toLowerCase() == 'ar'
      ? ar
      : en;
}

IconData _fallbackIconForActivity(String? activityType) {
  switch (activityType?.trim().toLowerCase()) {
    case 'restaurant':
    case 'meal':
      return Icons.restaurant_rounded;
    case 'fashion':
    case 'fashion_clothing':
      return Icons.checkroom_rounded;
    case 'pharmacy':
      return Icons.medical_services_rounded;
    case 'grocery':
    case 'supermarket':
      return Icons.shopping_bag_rounded;
    case 'electronics':
    case 'electronics_mobile':
    case 'electrical_lighting':
      return Icons.devices_rounded;
    case 'construction':
      return Icons.construction_rounded;
    default:
      return Icons.inventory_2_rounded;
  }
}

Color _fallbackTint(BuildContext context, String? activityType) {
  final scheme = Theme.of(context).colorScheme;
  switch (activityType?.trim().toLowerCase()) {
    case 'restaurant':
      return Colors.orangeAccent;
    case 'fashion':
    case 'fashion_clothing':
      return Colors.pinkAccent;
    case 'pharmacy':
      return Colors.tealAccent;
    case 'grocery':
    case 'supermarket':
      return Colors.greenAccent;
    case 'electronics':
    case 'electronics_mobile':
    case 'electrical_lighting':
      return scheme.primary;
    case 'construction':
      return Colors.amberAccent;
    default:
      return scheme.secondary;
  }
}

class OrderItemThumbnail extends StatelessWidget {
  final String? imageUrl;
  final String? activityType;
  final double size;
  final BorderRadius borderRadius;
  final BoxFit fit;

  const OrderItemThumbnail({
    super.key,
    required this.imageUrl,
    this.activityType,
    this.size = 60,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.fit = BoxFit.cover,
  });

  Widget _fallback(BuildContext context) {
    final tint = _fallbackTint(context, activityType);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: borderRadius,
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Center(
        child: Icon(
          _fallbackIconForActivity(activityType),
          color: tint,
          size: size * 0.42,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = imageUrl?.trim();
    final fallback = _fallback(context);
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: resolved == null || resolved.isEmpty
            ? fallback
            : CachedAppImage(
                imageUrl: resolved,
                width: size,
                height: size,
                fit: fit,
                maxWidthDiskCache: 128,
                maxHeightDiskCache: 128,
                placeholder: (context, error) => fallback,
                errorWidget: (context, error, stackTrace) => fallback,
              ),
      ),
    );
  }
}

class OrderItemSpecsChips extends StatelessWidget {
  final List<OrderItemPresentationEntry> entries;
  final bool compact;
  final String? title;
  final EdgeInsetsGeometry padding;

  const OrderItemSpecsChips({
    super.key,
    required this.entries,
    this.compact = false,
    this.title,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              textDirection: ui.TextDirection.rtl,
              style: style?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: compact ? 6 : 8,
            runSpacing: compact ? 6 : 8,
            children: entries.map((entry) {
              final text = entry.displayText;
              return Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: compact ? 4 : 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection: ui.TextDirection.rtl,
                  children: [
                    if (entry.hex != null && entry.hex!.trim().isNotEmpty) ...[
                      Container(
                        width: compact ? 8 : 10,
                        height: compact ? 8 : 10,
                        margin: const EdgeInsetsDirectional.only(end: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _parseHexColor(entry.hex!) ?? Theme.of(context).colorScheme.primary,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.32),
                          ),
                        ),
                      ),
                    ],
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: compact ? 140 : 180),
                      child: Text(
                        text,
                        textDirection: ui.TextDirection.rtl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class OrderItemPriceBreakdownRow extends StatelessWidget {
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final double? lineDiscountTotal;
  final bool compact;

  const OrderItemPriceBreakdownRow({
    super.key,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.lineDiscountTotal,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );
    final discount = lineDiscountTotal ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          textDirection: ui.TextDirection.rtl,
          children: [
            Text(
              formatIqd(lineTotal),
              style: textStyle?.copyWith(
                fontSize: compact ? 14 : 15,
              ),
            ),
            const Spacer(),
            Text(
              '$quantity x ${formatIqd(unitPrice)}',
              textDirection: ui.TextDirection.rtl,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
            ),
          ],
        ),
        if (discount > 0) ...[
          const SizedBox(height: 2),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _lt(
                context,
                ar: 'خصم ${formatIqd(discount)}',
                en: 'Discount ${formatIqd(discount)}',
              ),
              textDirection: ui.TextDirection.rtl,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.greenAccent.shade400,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

class OrderItemMiniCard extends StatelessWidget {
  final OrderItemPresentationModel item;
  final bool compact;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool showStoreName;
  final bool showSections;

  const OrderItemMiniCard({
    super.key,
    required this.item,
    this.compact = false,
    this.onTap,
    this.padding = EdgeInsets.zero,
    this.showStoreName = false,
    this.showSections = true,
  });

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.42);
    final border = Theme.of(context).colorScheme.outline.withValues(alpha: 0.14);
    final card = Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        textDirection: ui.TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrderItemThumbnail(
            imageUrl: item.displayImageUrl,
            activityType: item.activityType,
            size: compact ? 56 : 64,
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  textDirection: ui.TextDirection.rtl,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.displayTitle,
                        textDirection: ui.TextDirection.rtl,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    if (item.hasNote) ...[
                      const SizedBox(width: 8),
                      _NoteBadge(
                        text: _lt(context, ar: 'ملاحظة', en: 'Note'),
                      ),
                    ],
                  ],
                ),
                if (showStoreName && (item.storeName?.trim().isNotEmpty == true)) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.storeName!,
                    textDirection: ui.TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                  ),
                ],
                if (compact) ...[
                  const SizedBox(height: 8),
                  OrderItemSpecsChips(
                    entries: item.visibleSpecs.take(3).toList(growable: false),
                    compact: true,
                  ),
                ] else ...[
                  if (item.visibleSpecs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OrderItemSpecsChips(
                      entries: item.visibleSpecs,
                      compact: false,
                    ),
                  ],
                  if (showSections && item.options.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OrderItemSpecsChips(
                      title: _lt(context, ar: 'الخيارات', en: 'Options'),
                      entries: item.options,
                      compact: false,
                    ),
                  ],
                  if (showSections && item.addons.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OrderItemSpecsChips(
                      title: _lt(context, ar: 'الإضافات', en: 'Add-ons'),
                      entries: item.addons,
                      compact: false,
                    ),
                  ],
                  if (showSections && item.removals.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OrderItemSpecsChips(
                      title: _lt(context, ar: 'المحذوفات', en: 'Removals'),
                      entries: item.removals,
                      compact: false,
                    ),
                  ],
                  if (showSections && item.hasNote) ...[
                    const SizedBox(height: 8),
                    Text(
                      _lt(context, ar: 'ملاحظة: ', en: 'Note: ') +
                          (item.userNote ?? ''),
                      textDirection: ui.TextDirection.rtl,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.76),
                          ),
                    ),
                  ],
                ],
                const SizedBox(height: 10),
                OrderItemPriceBreakdownRow(
                  quantity: item.quantity,
                  unitPrice: item.unitPrice,
                  lineTotal: item.lineTotal,
                  compact: compact,
                ),
              ],
            ),
          ),
          if (onTap != null && !compact) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onTap,
              icon: const Icon(Icons.chevron_left_rounded),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: padding,
      child: Material(
        color: Colors.transparent,
        child: onTap == null
            ? card
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(18),
                child: card,
              ),
      ),
    );
  }
}

class OrderItemsSummaryList extends StatelessWidget {
  final List<OrderItemPresentationModel> items;
  final bool compact;
  final bool groupByStore;
  final EdgeInsetsGeometry padding;
  final String? emptyLabel;
  final bool showStoreHeaders;

  const OrderItemsSummaryList({
    super.key,
    required this.items,
    this.compact = false,
    this.groupByStore = false,
    this.padding = EdgeInsets.zero,
    this.emptyLabel,
    this.showStoreHeaders = true,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: padding,
        child: Text(
          emptyLabel ?? _lt(context, ar: 'لا توجد عناصر', en: 'No items'),
          textDirection: ui.TextDirection.rtl,
        ),
      );
    }

    final groups = groupByStore
        ? _groupByStore(items)
        : <_OrderItemGroup>[_OrderItemGroup(label: null, items: items)];

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in groups) ...[
            if (showStoreHeaders && group.label != null) ...[
              Text(
                group.label!,
                textDirection: ui.TextDirection.rtl,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
            ],
            for (final item in group.items) ...[
              OrderItemMiniCard(
                item: item,
                compact: compact,
                showStoreName: !groupByStore,
                showSections: !compact,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  List<_OrderItemGroup> _groupByStore(List<OrderItemPresentationModel> input) {
    final groups = <String, _OrderItemGroup>{};
    for (final item in input) {
      final key = '${item.storeId ?? item.storeName ?? 'store'}';
      groups.putIfAbsent(
        key,
        () => _OrderItemGroup(
          label: item.storeName?.trim().isNotEmpty == true ? item.storeName : null,
          items: <OrderItemPresentationModel>[],
        ),
      );
      groups[key]!.items.add(item);
    }
    return groups.values.toList(growable: false);
  }
}

class OrderInvoiceSection extends StatelessWidget {
  final List<OrderItemPresentationModel> items;
  final bool groupByStore;
  final String? title;
  final String? orderNumber;
  final DateTime? orderTime;
  final String? paymentMethod;
  final double subtotal;
  final double serviceFee;
  final double deliveryFee;
  final double couponDiscountTotal;
  final double totalAmount;
  final String? helperText;

  const OrderInvoiceSection({
    super.key,
    required this.items,
    required this.subtotal,
    required this.serviceFee,
    required this.deliveryFee,
    required this.couponDiscountTotal,
    required this.totalAmount,
    this.groupByStore = false,
    this.title,
    this.orderNumber,
    this.orderTime,
    this.paymentMethod,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (title != null) ...[
        Text(
          title!,
          textDirection: ui.TextDirection.rtl,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 8),
      ],
      if (orderNumber != null || orderTime != null || paymentMethod != null)
        _InvoiceMetaRow(
          orderNumber: orderNumber,
          orderTime: orderTime,
          paymentMethod: paymentMethod,
        ),
      if (orderNumber != null || orderTime != null || paymentMethod != null)
        const SizedBox(height: 10),
      OrderItemsSummaryList(
        items: items,
        compact: false,
        groupByStore: groupByStore,
        padding: EdgeInsets.zero,
      ),
      const SizedBox(height: 4),
      _MoneyRow(
        label: _lt(context, ar: 'المجموع الفرعي', en: 'Subtotal'),
        value: formatIqd(subtotal),
      ),
      _MoneyRow(
        label: _lt(context, ar: 'رسوم الخدمة', en: 'Service fee'),
        value: formatIqd(serviceFee),
      ),
      _MoneyRow(
        label: _lt(context, ar: 'رسوم التوصيل', en: 'Delivery fee'),
        value: formatIqd(deliveryFee),
      ),
      if (couponDiscountTotal > 0)
        _MoneyRow(
          label: _lt(context, ar: 'الخصم', en: 'Discount'),
          value: '-${formatIqd(couponDiscountTotal)}',
          valueColor: Colors.greenAccent.shade400,
        ),
      const Divider(height: 24),
      _MoneyRow(
        label: _lt(context, ar: 'الإجمالي النهائي', en: 'Grand total'),
        value: formatIqd(totalAmount),
        emphasized: true,
      ),
      if (helperText != null) ...[
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Text(
            helperText!,
            textDirection: ui.TextDirection.rtl,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _InvoiceMetaRow extends StatelessWidget {
  final String? orderNumber;
  final DateTime? orderTime;
  final String? paymentMethod;

  const _InvoiceMetaRow({
    required this.orderNumber,
    required this.orderTime,
    required this.paymentMethod,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (orderNumber != null) {
      chips.add(_MetaChip(
        label: _lt(context, ar: 'الطلب', en: 'Order'),
        value: orderNumber!,
      ));
    }
    if (orderTime != null) {
      chips.add(
        _MetaChip(
          label: _lt(context, ar: 'الوقت', en: 'Time'),
          value: DateFormat('yyyy-MM-dd HH:mm').format(orderTime!.toLocal()),
        ),
      );
    }
    if (paymentMethod != null) {
      chips.add(
        _MetaChip(
          label: _lt(context, ar: 'الدفع', en: 'Payment'),
          value: paymentMethod!,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetaChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.14),
        ),
      ),
      child: Text(
        '$label: $value',
        textDirection: ui.TextDirection.rtl,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;
  final Color? valueColor;

  const _MoneyRow({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
          fontSize: emphasized ? 16 : 14,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        textDirection: ui.TextDirection.rtl,
        children: [
          Expanded(
            child: Text(label, textDirection: ui.TextDirection.rtl, style: style),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textDirection: ui.TextDirection.rtl,
            style: style?.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}

class _NoteBadge extends StatelessWidget {
  final String text;

  const _NoteBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.20),
        ),
      ),
      child: Text(
        text,
        textDirection: ui.TextDirection.rtl,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _OrderItemGroup {
  final String? label;
  final List<OrderItemPresentationModel> items;

  _OrderItemGroup({required this.label, required this.items});
}

Color? _parseHexColor(String value) {
  final cleaned = value.trim().replaceFirst('#', '');
  if (cleaned.length != 6 && cleaned.length != 8) return null;
  final normalized = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}
