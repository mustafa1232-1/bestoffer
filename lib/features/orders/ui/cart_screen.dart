import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/pricing.dart';
import '../../../core/utils/currency.dart';
import '../../auth/state/auth_controller.dart';
import '../state/cart_controller.dart';
import '../state/delivery_address_controller.dart';
import '../state/orders_controller.dart';
import 'delivery_addresses_screen.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final noteCtrl = TextEditingController();
  final budgetCtrl = TextEditingController();
  int? budgetCapIqd;
  bool optimizingBudget = false;
  int splitPeople = 1;

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
      await ref.read(deliveryAddressControllerProvider.notifier).bootstrap();
      await _loadBudgetCap();
    });
  }

  void _persistDraftNote() {
    ref.read(cartControllerProvider.notifier).setDraftNote(noteCtrl.text);
  }

  @override
  void dispose() {
    noteCtrl.removeListener(_persistDraftNote);
    noteCtrl.dispose();
    budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBudgetCap() async {
    final auth = ref.read(authControllerProvider);
    final userId = auth.user?.id;
    if (userId == null) return;
    final raw = await ref
        .read(secureStoreProvider)
        .readString(_budgetCapKey(userId));
    if (raw == null || raw.trim().isEmpty) return;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) return;
    if (!mounted) return;
    setState(() {
      budgetCapIqd = parsed;
      budgetCtrl.text = '$parsed';
    });
  }

  Future<void> _saveBudgetCap(int? value) async {
    final auth = ref.read(authControllerProvider);
    final userId = auth.user?.id;
    if (userId == null) return;
    final store = ref.read(secureStoreProvider);
    if (value == null || value <= 0) {
      await store.delete(_budgetCapKey(userId));
      return;
    }
    await store.writeString(_budgetCapKey(userId), '$value');
  }

  String _budgetCapKey(int userId) => 'cart_budget_cap_iqd:$userId';

  int? _parseBudgetInput(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return null;
    final parsed = int.tryParse(digits);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  Future<void> _applyBudgetOptimization() async {
    final cap = budgetCapIqd;
    if (cap == null || cap <= 0 || optimizingBudget) return;
    final notifier = ref.read(cartControllerProvider.notifier);
    final initial = ref.read(cartControllerProvider);
    if (initial.items.isEmpty || initial.total <= cap) return;

    setState(() => optimizingBudget = true);
    var loops = 0;
    while (loops < 600) {
      loops++;
      final current = ref.read(cartControllerProvider);
      if (current.items.isEmpty || current.total <= cap) break;

      final sorted = [...current.items]
        ..sort((a, b) {
          final aPrice = a.product.discountedPrice ?? a.product.price;
          final bPrice = b.product.discountedPrice ?? b.product.price;
          return bPrice.compareTo(aPrice);
        });

      var reduced = false;
      for (final item in sorted) {
        if (item.quantity > 1) {
          notifier.decrementItem(item.product.id);
          reduced = true;
          break;
        }
      }

      if (reduced) continue;
      if (sorted.length > 1) {
        notifier.removeItem(sorted.first.product.id);
      } else {
        break;
      }
    }

    if (!mounted) return;
    setState(() => optimizingBudget = false);
    final finalState = ref.read(cartControllerProvider);
    final success = finalState.total <= cap;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'تم ضبط السلة ضمن الميزانية (${formatIqd(cap.toDouble())})'
              : 'تم التقليل قدر الإمكان، لكن أقل إجمالي ما زال أعلى من الميزانية',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final orders = ref.watch(ordersControllerProvider);
    final addresses = ref.watch(deliveryAddressControllerProvider);
    final selectedAddress = addresses.selectedAddress;
    final providerDraft = cart.draftNote ?? '';
    if (noteCtrl.text != providerDraft) {
      noteCtrl.value = noteCtrl.value.copyWith(
        text: providerDraft,
        selection: TextSelection.collapsed(offset: providerDraft.length),
        composing: TextRange.empty,
      );
    }
    final budget = budgetCapIqd;
    final exceedsBudget = budget != null && cart.total > budget;
    final remainingBudget = budget == null ? null : (budget - cart.total);
    final budgetProgress = budget == null || budget <= 0
        ? 0.0
        : (cart.total / budget).clamp(0.0, 1.0);
    final peopleCount = splitPeople <= 0 ? 1 : splitPeople;
    final perPersonTotal = cart.total / peopleCount;

    ref.listen<OrdersState>(ordersControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          cart.merchantName == null
              ? '\u0633\u0644\u0629 \u0627\u0644\u062a\u0633\u0648\u0642'
              : '\u0633\u0644\u0629 ${cart.merchantName}',
        ),
      ),
      body: cart.items.isEmpty
          ? const Center(
              child: Text(
                '\u0627\u0644\u0633\u0644\u0629 \u0641\u0627\u0631\u063a\u0629',
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: cart.items.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final item = cart.items[index];
                        final price =
                            item.product.discountedPrice ?? item.product.price;
                        final total = price * item.quantity;

                        return Card(
                          child: ListTile(
                            title: Text(
                              item.product.name,
                              textDirection: TextDirection.rtl,
                            ),
                            subtitle: Text(
                              '\u0627\u0644\u0633\u0639\u0631: ${formatIqd(price)} - \u0627\u0644\u0643\u0645\u064a\u0629: ${item.quantity} - \u0627\u0644\u0645\u062c\u0645\u0648\u0639: ${formatIqd(total)}',
                              textDirection: TextDirection.rtl,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => ref
                                      .read(cartControllerProvider.notifier)
                                      .decrementItem(item.product.id),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                IconButton(
                                  onPressed: () => ref
                                      .read(cartControllerProvider.notifier)
                                      .addItem(
                                        product: item.product,
                                        merchantId: cart.merchantId!,
                                        merchantName: cart.merchantName ?? '',
                                      ),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                                IconButton(
                                  onPressed: () => ref
                                      .read(cartControllerProvider.notifier)
                                      .removeItem(item.product.id),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText:
                          '\u0645\u0644\u0627\u062d\u0638\u0627\u062a \u0639\u0644\u0649 \u0627\u0644\u0637\u0644\u0628 (\u0627\u062e\u062a\u064a\u0627\u0631\u064a)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'حارس الميزانية الذكي',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: budgetCtrl,
                            keyboardType: TextInputType.number,
                            textDirection: TextDirection.rtl,
                            decoration: InputDecoration(
                              labelText: 'سقف الميزانية (دينار عراقي)',
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'حفظ',
                                    onPressed: () async {
                                      final parsed = _parseBudgetInput(
                                        budgetCtrl.text,
                                      );
                                      setState(() => budgetCapIqd = parsed);
                                      await _saveBudgetCap(parsed);
                                    },
                                    icon: const Icon(Icons.save_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'إزالة',
                                    onPressed: () async {
                                      budgetCtrl.clear();
                                      setState(() => budgetCapIqd = null);
                                      await _saveBudgetCap(null);
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                            onSubmitted: (value) async {
                              final parsed = _parseBudgetInput(value);
                              setState(() => budgetCapIqd = parsed);
                              await _saveBudgetCap(parsed);
                            },
                          ),
                          if (budget != null) ...[
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: budgetProgress,
                              minHeight: 7,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.1,
                              ),
                              color: exceedsBudget
                                  ? Colors.redAccent
                                  : Colors.greenAccent,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              exceedsBudget
                                  ? 'تجاوزت الميزانية بمقدار ${formatIqd((cart.total - budget).toDouble())}'
                                  : 'المتبقي من الميزانية: ${formatIqd((remainingBudget ?? 0).toDouble())}',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: exceedsBudget
                                    ? Colors.red.shade300
                                    : Colors.green.shade300,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
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
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'تقسيم الفاتورة الذكي',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'إذا الطلب جماعي، احسب الحصة لكل شخص مباشرة',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [1, 2, 4, 6, 8].map((count) {
                              return ChoiceChip(
                                label: Text('$count أشخاص'),
                                selected: splitPeople == count,
                                onSelected: (_) =>
                                    setState(() => splitPeople = count),
                              );
                            }).toList(),
                          ),
                          Slider(
                            min: 1,
                            max: 12,
                            divisions: 11,
                            value: peopleCount.toDouble(),
                            label: '$peopleCount',
                            onChanged: (value) =>
                                setState(() => splitPeople = value.round()),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                            child: Text(
                              'حصة الشخص الواحد تقريباً: ${formatIqd(perPersonTotal)}',
                              key: ValueKey<int>(peopleCount),
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      title: const Text(
                        '\u0639\u0646\u0648\u0627\u0646 \u0627\u0644\u062a\u0648\u0635\u064a\u0644',
                        textDirection: TextDirection.rtl,
                      ),
                      subtitle: Text(
                        selectedAddress?.shortText ??
                            '\u0627\u0644\u0631\u062c\u0627\u0621 \u0625\u0636\u0627\u0641\u0629 \u0623\u0648 \u0627\u062e\u062a\u064a\u0627\u0631 \u0639\u0646\u0648\u0627\u0646 \u062a\u0648\u0635\u064a\u0644',
                        textDirection: TextDirection.rtl,
                      ),
                      trailing: IconButton(
                        tooltip:
                            '\u0625\u062f\u0627\u0631\u0629 \u0627\u0644\u0639\u0646\u0627\u0648\u064a\u0646',
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
                              .read(deliveryAddressControllerProvider.notifier)
                              .bootstrap(silent: true);
                        },
                        icon: const Icon(Icons.place_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          _SummaryRow(
                            '\u0627\u0644\u0645\u062c\u0645\u0648\u0639 \u0627\u0644\u0641\u0631\u0639\u064a',
                            formatIqd(cart.subtotal),
                          ),
                          _SummaryRow(
                            '\u0631\u0633\u0648\u0645 \u0627\u0644\u062e\u062f\u0645\u0629 (${formatIqd(serviceFeeIqd)})',
                            formatIqd(cart.serviceFee),
                          ),
                          _SummaryRow(
                            cart.deliveryFee <= 0
                                ? '\u0623\u062c\u0648\u0631 \u0627\u0644\u062a\u0648\u0635\u064a\u0644 (\u062a\u0648\u0635\u064a\u0644 \u0645\u062c\u0627\u0646\u064a)'
                                : '\u0623\u062c\u0648\u0631 \u0627\u0644\u062a\u0648\u0635\u064a\u0644',
                            formatIqd(cart.deliveryFee),
                          ),
                          const Divider(),
                          _SummaryRow(
                            '\u0627\u0644\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u0646\u0647\u0627\u0626\u064a',
                            formatIqd(cart.total),
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: orders.placingOrder
                          ? null
                          : () async {
                              final ok = await ref
                                  .read(ordersControllerProvider.notifier)
                                  .checkout(note: noteCtrl.text);
                              if (!context.mounted || !ok) return;
                              Navigator.of(context).pop(true);
                            },
                      child: orders.placingOrder
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              '\u0625\u062a\u0645\u0627\u0645 \u0627\u0644\u0637\u0644\u0628',
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _SummaryRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(value, textAlign: TextAlign.left, style: style),
          ),
          Expanded(
            child: Text(
              label,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
