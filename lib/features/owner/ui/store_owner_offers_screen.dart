import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/currency.dart';
import '../models/merchant_offer_model.dart';
import '../state/owner_controller.dart';

class StoreOwnerOffersScreen extends ConsumerStatefulWidget {
  const StoreOwnerOffersScreen({super.key});

  @override
  ConsumerState<StoreOwnerOffersScreen> createState() =>
      _StoreOwnerOffersScreenState();
}

class _StoreOwnerOffersScreenState
    extends ConsumerState<StoreOwnerOffersScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (!mounted) return;
      await ref.read(ownerControllerProvider.notifier).bootstrap();
    });
  }

  Future<void> _refresh() async {
    await ref.read(ownerControllerProvider.notifier).bootstrap();
  }

  Future<void> _openOfferSheet({MerchantOfferModel? offer}) async {
    final state = ref.read(ownerControllerProvider);
    if (state.products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف منتجات أولًا قبل إنشاء أي عرض.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OfferEditorSheet(offer: offer),
    );
  }

  Future<void> _toggleOffer(MerchantOfferModel offer) async {
    final controller = ref.read(ownerControllerProvider.notifier);
    final nextStatus = offer.configuredStatus == 'active'
        ? 'disabled'
        : 'active';
    await controller.updateOffer(
      offerId: offer.id,
      title: offer.title,
      description: offer.description,
      offerType: offer.offerType,
      discountValue: offer.discountValue,
      buyQuantity: offer.buyQuantity,
      getQuantity: offer.getQuantity,
      startsAt: offer.startsAt,
      endsAt: offer.endsAt,
      status: nextStatus,
      maxUsage: offer.maxUsage,
      productIds: offer.products.map((product) => product.id).toList(),
    );
    if (!mounted) return;
    final nextState = ref.read(ownerControllerProvider);
    if (nextState.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextStatus == 'active' ? 'تم تفعيل العرض.' : 'تم إيقاف العرض.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteOffer(MerchantOfferModel offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف العرض'),
          content: Text('هل تريد حذف العرض "${offer.title}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await ref.read(ownerControllerProvider.notifier).deleteOffer(offer.id);
    if (!mounted) return;
    final state = ref.read(ownerControllerProvider);
    if (state.error == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حذف العرض.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('العروض')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: state.savingProduct ? null : () => _openOfferSheet(),
        icon: const Icon(Icons.local_offer_outlined),
        label: const Text('عرض جديد'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: state.loading && state.offers.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.offers.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.local_offer_outlined, size: 56),
                  SizedBox(height: 16),
                  Center(
                    child: Text(
                      'لا توجد عروض حتى الآن.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: 8),
                  Center(
                    child: Text(
                      'أنشئ عروضًا على المنتجات لتظهر تلقائيًا في الصفحة والسلة والطلب.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: state.offers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final offer = state.offers[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      offer.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if ((offer.description ?? '')
                                        .trim()
                                        .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(offer.description!),
                                      ),
                                  ],
                                ),
                              ),
                              _OfferStatusChip(status: offer.status),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _OfferInfoChip(
                                icon: Icons.sell_outlined,
                                label: _offerTypeLabel(offer),
                              ),
                              if ((offer.label ?? '').trim().isNotEmpty)
                                _OfferInfoChip(
                                  icon: Icons.auto_awesome_outlined,
                                  label: offer.label!,
                                ),
                              _OfferInfoChip(
                                icon: Icons.inventory_2_outlined,
                                label: '${offer.products.length} منتج',
                              ),
                              if (offer.maxUsage != null)
                                _OfferInfoChip(
                                  icon: Icons.pin_outlined,
                                  label: 'حد الاستخدام ${offer.maxUsage}',
                                ),
                              if (offer.startsAt != null ||
                                  offer.endsAt != null)
                                _OfferInfoChip(
                                  icon: Icons.schedule_outlined,
                                  label: _dateWindowLabel(offer),
                                ),
                            ],
                          ),
                          if (offer.products.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: offer.products
                                  .map(
                                    (product) =>
                                        Chip(label: Text(product.name)),
                                  )
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: state.savingProduct
                                      ? null
                                      : () => _openOfferSheet(offer: offer),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('تعديل'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: state.savingProduct
                                      ? null
                                      : () => _toggleOffer(offer),
                                  icon: Icon(
                                    offer.configuredStatus == 'active'
                                        ? Icons.pause_circle_outline
                                        : Icons.play_circle_outline,
                                  ),
                                  label: Text(
                                    offer.configuredStatus == 'active'
                                        ? 'إيقاف'
                                        : 'تفعيل',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                onPressed: state.savingProduct
                                    ? null
                                    : () => _deleteOffer(offer),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _OfferEditorSheet extends ConsumerStatefulWidget {
  const _OfferEditorSheet({this.offer});

  final MerchantOfferModel? offer;

  @override
  ConsumerState<_OfferEditorSheet> createState() => _OfferEditorSheetState();
}

class _OfferEditorSheetState extends ConsumerState<_OfferEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _discountCtrl;
  late final TextEditingController _buyCtrl;
  late final TextEditingController _getCtrl;
  late final TextEditingController _maxUsageCtrl;

  late String _offerType;
  late String _status;
  late Set<int> _selectedProductIds;
  DateTime? _startsAt;
  DateTime? _endsAt;

  @override
  void initState() {
    super.initState();
    final offer = widget.offer;
    final offerDiscount = offer?.discountValue;
    final offerDiscountText = offerDiscount == null
        ? ''
        : offerDiscount.toStringAsFixed(
            offerDiscount == offerDiscount.roundToDouble() ? 0 : 2,
          );
    _titleCtrl = TextEditingController(text: offer?.title ?? '');
    _descriptionCtrl = TextEditingController(text: offer?.description ?? '');
    _discountCtrl = TextEditingController(text: offerDiscountText);
    _buyCtrl = TextEditingController(
      text: offer?.buyQuantity?.toString() ?? '',
    );
    _getCtrl = TextEditingController(
      text: offer?.getQuantity?.toString() ?? '',
    );
    _maxUsageCtrl = TextEditingController(
      text: offer?.maxUsage?.toString() ?? '',
    );
    _offerType = offer?.offerType ?? 'percentage';
    _status = offer?.configuredStatus ?? 'draft';
    _selectedProductIds = {...?offer?.products.map((product) => product.id)};
    _startsAt = offer?.startsAt;
    _endsAt = offer?.endsAt;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _discountCtrl.dispose();
    _buyCtrl.dispose();
    _getCtrl.dispose();
    _maxUsageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startsAt ?? now)
        : (_endsAt ?? _startsAt ?? now);
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDate: initial,
      locale: Localizations.localeOf(context),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    final merged = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? (isStart ? 0 : 23),
      time?.minute ?? (isStart ? 0 : 59),
    );
    setState(() {
      if (isStart) {
        _startsAt = merged;
      } else {
        _endsAt = merged;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر منتجًا واحدًا على الأقل.')),
      );
      return;
    }
    if (_startsAt != null && _endsAt != null && _endsAt!.isBefore(_startsAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('وقت انتهاء العرض يجب أن يكون بعد البداية.'),
        ),
      );
      return;
    }

    final controller = ref.read(ownerControllerProvider.notifier);
    final discountValue = _discountCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_discountCtrl.text.trim());
    final buyQuantity = _buyCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_buyCtrl.text.trim());
    final getQuantity = _getCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_getCtrl.text.trim());
    final maxUsage = _maxUsageCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_maxUsageCtrl.text.trim());

    if (widget.offer == null) {
      await controller.createOffer(
        title: _titleCtrl.text,
        description: _descriptionCtrl.text,
        offerType: _offerType,
        discountValue: discountValue,
        buyQuantity: buyQuantity,
        getQuantity: getQuantity,
        startsAt: _startsAt,
        endsAt: _endsAt,
        status: _status,
        maxUsage: maxUsage,
        productIds: _selectedProductIds.toList()..sort(),
      );
    } else {
      await controller.updateOffer(
        offerId: widget.offer!.id,
        title: _titleCtrl.text,
        description: _descriptionCtrl.text,
        offerType: _offerType,
        discountValue: discountValue,
        buyQuantity: buyQuantity,
        getQuantity: getQuantity,
        startsAt: _startsAt,
        endsAt: _endsAt,
        status: _status,
        maxUsage: maxUsage,
        productIds: _selectedProductIds.toList()..sort(),
      );
    }

    if (!mounted) return;
    final state = ref.read(ownerControllerProvider);
    if (state.error == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.offer == null ? 'تم إنشاء العرض.' : 'تم تحديث العرض.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    final products = state.products;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.offer == null ? 'إنشاء عرض جديد' : 'تعديل العرض',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'عنوان العرض'),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'أدخل عنوان العرض';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'وصف العرض'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _offerType,
                  decoration: const InputDecoration(labelText: 'نوع العرض'),
                  items: const [
                    DropdownMenuItem(
                      value: 'percentage',
                      child: Text('خصم بنسبة مئوية'),
                    ),
                    DropdownMenuItem(
                      value: 'fixed_amount',
                      child: Text('خصم بمبلغ ثابت'),
                    ),
                    DropdownMenuItem(
                      value: 'buy_x_get_y',
                      child: Text('اشترِ X واحصل على Y'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _offerType = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'حالة العرض'),
                  items: const [
                    DropdownMenuItem(value: 'draft', child: Text('مسودة')),
                    DropdownMenuItem(value: 'scheduled', child: Text('مجدول')),
                    DropdownMenuItem(value: 'active', child: Text('نشط')),
                    DropdownMenuItem(value: 'disabled', child: Text('موقوف')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _status = value);
                  },
                ),
                const SizedBox(height: 12),
                if (_offerType == 'percentage' || _offerType == 'fixed_amount')
                  TextFormField(
                    controller: _discountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _offerType == 'percentage'
                          ? 'قيمة الخصم (%)'
                          : 'قيمة الخصم (د.ع)',
                    ),
                    validator: (value) {
                      final parsed = double.tryParse((value ?? '').trim());
                      if (parsed == null || parsed <= 0) {
                        return 'أدخل قيمة خصم صحيحة';
                      }
                      if (_offerType == 'percentage' && parsed > 100) {
                        return 'نسبة الخصم يجب أن تكون 100 أو أقل';
                      }
                      return null;
                    },
                  ),
                if (_offerType == 'buy_x_get_y')
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _buyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'الكمية المطلوبة X',
                          ),
                          validator: (value) {
                            final parsed = int.tryParse((value ?? '').trim());
                            if (parsed == null || parsed <= 0) {
                              return 'أدخل قيمة صحيحة';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _getCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'الكمية المجانية Y',
                          ),
                          validator: (value) {
                            final parsed = int.tryParse((value ?? '').trim());
                            if (parsed == null || parsed <= 0) {
                              return 'أدخل قيمة صحيحة';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _maxUsageCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'حد الاستخدام (اختياري)',
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) return null;
                    final parsed = int.tryParse(value!.trim());
                    if (parsed == null || parsed <= 0) {
                      return 'أدخل عددًا صحيحًا أكبر من صفر';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isStart: true),
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          _startsAt == null
                              ? 'بداية العرض'
                              : 'من ${_formatDateTime(_startsAt!)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isStart: false),
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text(
                          _endsAt == null
                              ? 'نهاية العرض'
                              : 'إلى ${_formatDateTime(_endsAt!)}',
                        ),
                      ),
                    ),
                  ],
                ),
                if (_startsAt != null || _endsAt != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _startsAt = null;
                          _endsAt = null;
                        });
                      },
                      icon: const Icon(Icons.clear_outlined),
                      label: const Text('مسح التوقيت'),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'المنتجات المشمولة',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: products.map((product) {
                    final selected = _selectedProductIds.contains(product.id);
                    return FilterChip(
                      label: Text(
                        '${product.name} • ${formatIqd(product.price)}',
                      ),
                      selected: selected,
                      onSelected: (value) {
                        setState(() {
                          if (value) {
                            _selectedProductIds.add(product.id);
                          } else {
                            _selectedProductIds.remove(product.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: state.savingProduct ? null : _submit,
                  icon: state.savingProduct
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    widget.offer == null ? 'إنشاء العرض' : 'حفظ التعديل',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfferStatusChip extends StatelessWidget {
  const _OfferStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => Colors.green,
      'scheduled' => Colors.orange,
      'expired' => Colors.red,
      'disabled' => Colors.grey,
      _ => Colors.blueGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(switch (status) {
        'active' => 'نشط',
        'scheduled' => 'مجدول',
        'expired' => 'منتهي',
        'disabled' => 'موقوف',
        _ => 'مسودة',
      }, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _OfferInfoChip extends StatelessWidget {
  const _OfferInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(label)],
      ),
    );
  }
}

String _offerTypeLabel(MerchantOfferModel offer) {
  switch (offer.offerType) {
    case 'percentage':
      return 'خصم ${offer.discountValue?.toStringAsFixed(offer.discountValue == offer.discountValue?.roundToDouble() ? 0 : 2) ?? ''}%';
    case 'fixed_amount':
      return 'خصم ${formatIqd(offer.discountValue ?? 0)}';
    case 'buy_x_get_y':
      return 'كل ${offer.buyQuantity ?? 0} + ${offer.getQuantity ?? 0} مجانًا';
    default:
      return offer.offerType;
  }
}

String _dateWindowLabel(MerchantOfferModel offer) {
  final from = offer.startsAt == null ? null : _formatDateTime(offer.startsAt!);
  final to = offer.endsAt == null ? null : _formatDateTime(offer.endsAt!);
  if (from != null && to != null) return '$from - $to';
  if (from != null) return 'من $from';
  if (to != null) return 'حتى $to';
  return 'بلا توقيت';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} $hh:$mm';
}
