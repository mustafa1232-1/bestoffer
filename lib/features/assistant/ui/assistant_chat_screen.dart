import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/currency.dart';
import '../../orders/ui/customer_orders_screen.dart';
import '../models/assistant_chat_models.dart';
import '../state/assistant_controller.dart';

class AssistantChatScreen extends ConsumerStatefulWidget {
  const AssistantChatScreen({super.key});

  @override
  ConsumerState<AssistantChatScreen> createState() =>
      _AssistantChatScreenState();
}

class _AssistantChatScreenState extends ConsumerState<AssistantChatScreen> {
  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  int? _selectedAddressId;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(assistantControllerProvider.notifier).loadCurrentSession(),
    );
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 140,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _sendCurrentMessage({bool createDraft = false}) async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    _messageCtrl.clear();
    await ref
        .read(assistantControllerProvider.notifier)
        .sendMessage(
          text,
          addressId: _selectedAddressId,
          createDraft: createDraft,
        );
  }

  Future<void> _sendPreset(String text, {bool createDraft = false}) async {
    _messageCtrl.text = text;
    await _sendCurrentMessage(createDraft: createDraft);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantControllerProvider);

    ref.listen<AssistantState>(assistantControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }

      if (next.messages.length != prev?.messages.length) {
        _scrollToBottom();
      }

      if (_selectedAddressId == null && next.addresses.isNotEmpty) {
        final defaultAddress = next.addresses.firstWhere(
          (a) => a.isDefault,
          orElse: () => next.addresses.first,
        );
        if (mounted) {
          setState(() => _selectedAddressId = defaultAddress.id);
        }
      }
    });

    final selectedAddressId = _selectedAddressId ?? state.draftOrder?.addressId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المساعد الذكي'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: state.loading
                ? null
                : () => ref
                      .read(assistantControllerProvider.notifier)
                      .loadCurrentSession(sessionId: state.sessionId),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _AssistantHeader(
            subtitle:
                'اكلي شنو تحب، وأنا أرشح لك المطاعم حسب السعر والتقييم وتاريخ طلباتك',
          ),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                    children: [
                      ...state.messages.map((m) => _ChatBubble(message: m)),
                      if (state.sending) const _TypingBubble(),
                      if (state.products.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _ProductSuggestionsPanel(products: state.products),
                      ],
                      if (state.merchants.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _MerchantSuggestionsPanel(merchants: state.merchants),
                      ],
                      if (state.draftOrder != null) ...[
                        const SizedBox(height: 10),
                        _DraftOrderCard(
                          draft: state.draftOrder!,
                          addresses: state.addresses,
                          selectedAddressId: selectedAddressId,
                          confirming: state.sending,
                          onAddressChanged: (value) =>
                              setState(() => _selectedAddressId = value),
                          onConfirm: () async {
                            await ref
                                .read(assistantControllerProvider.notifier)
                                .confirmDraft(
                                  token: state.draftOrder!.token,
                                  addressId:
                                      _selectedAddressId ??
                                      state.draftOrder!.addressId,
                                );
                          },
                        ),
                      ],
                      if (state.createdOrder != null) ...[
                        const SizedBox(height: 10),
                        _CreatedOrderCard(
                          order: state.createdOrder!,
                          onTrack: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CustomerOrdersScreen(
                                  initialOrderId: state.createdOrder!.id,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
          ),
          _QuickPrompts(
            onTapCheap: () => _sendPreset('أريد أرخص الخيارات المتاحة الآن'),
            onTapTopRated: () => _sendPreset('رشحلي الأعلى تقييماً اليوم'),
            onTapBasedHistory: () =>
                _sendPreset('اعتمد على طلباتي السابقة واقترح شي مناسب'),
            onTapQuickDraft: () => _sendPreset(
              'سويلي طلب سريع وجهز مسودة مباشرة',
              createDraft: true,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageCtrl,
                      textDirection: TextDirection.rtl,
                      minLines: 1,
                      maxLines: 3,
                      onSubmitted: (_) => _sendCurrentMessage(),
                      decoration: const InputDecoration(
                        hintText: 'اكتب طلبك هنا... مثال: أريد أرخص بركر',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: state.sending ? null : _sendCurrentMessage,
                    child: const Icon(Icons.send_rounded),
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

class _AssistantHeader extends StatelessWidget {
  final String subtitle;

  const _AssistantHeader({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.smart_toy_outlined)),
          title: const Text(
            'AI BestOffer',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle, textDirection: TextDirection.rtl),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final AssistantMessageModel message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isUser
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: isUser
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Text(message.text, textDirection: TextDirection.rtl),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: const SizedBox(
          width: 56,
          child: LinearProgressIndicator(minHeight: 4),
        ),
      ),
    );
  }
}

class _QuickPrompts extends StatelessWidget {
  final VoidCallback onTapCheap;
  final VoidCallback onTapTopRated;
  final VoidCallback onTapBasedHistory;
  final VoidCallback onTapQuickDraft;

  const _QuickPrompts({
    required this.onTapCheap,
    required this.onTapTopRated,
    required this.onTapBasedHistory,
    required this.onTapQuickDraft,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          ActionChip(
            avatar: const Icon(Icons.savings_outlined, size: 16),
            label: const Text('أرخص خيارات'),
            onPressed: onTapCheap,
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.star_rate_rounded, size: 16),
            label: const Text('أعلى تقييم'),
            onPressed: onTapTopRated,
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.history_rounded, size: 16),
            label: const Text('حسب طلباتي'),
            onPressed: onTapBasedHistory,
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.local_shipping_rounded, size: 16),
            label: const Text('سويلي مسودة'),
            onPressed: onTapQuickDraft,
          ),
        ],
      ),
    );
  }
}

class _ProductSuggestionsPanel extends StatelessWidget {
  final List<AssistantProductSuggestionModel> products;

  const _ProductSuggestionsPanel({required this.products});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'اقتراحات ذكية',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...products
                .take(6)
                .map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${p.productName} • ${p.merchantName}',
                            textDirection: TextDirection.rtl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatIqd(p.effectivePrice),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _MerchantSuggestionsPanel extends StatelessWidget {
  final List<AssistantMerchantSuggestionModel> merchants;

  const _MerchantSuggestionsPanel({required this.merchants});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'أفضل متاجر لك',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: merchants
                  .take(4)
                  .map(
                    (m) => Chip(
                      label: Text(
                        '${m.merchantName} • ${m.avgRating.toStringAsFixed(1)}★',
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftOrderCard extends StatelessWidget {
  final AssistantDraftOrderModel draft;
  final List<AssistantAddressOptionModel> addresses;
  final int? selectedAddressId;
  final bool confirming;
  final ValueChanged<int?> onAddressChanged;
  final VoidCallback onConfirm;

  const _DraftOrderCard({
    required this.draft,
    required this.addresses,
    required this.selectedAddressId,
    required this.confirming,
    required this.onAddressChanged,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'مسودة طلب من ${draft.merchantName}',
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...draft.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '- ${item.productName} x ${item.quantity} (${formatIqd(item.lineTotal)})',
                  textDirection: TextDirection.rtl,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'المجموع الفرعي: ${formatIqd(draft.subtotal)}\n'
              'رسوم الخدمة: ${formatIqd(draft.serviceFee)}\n'
              'أجور التوصيل: ${formatIqd(draft.deliveryFee)}\n'
              'الإجمالي: ${formatIqd(draft.totalAmount)}',
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 10),
            if (addresses.isNotEmpty)
              DropdownButtonFormField<int>(
                initialValue:
                    selectedAddressId ?? draft.addressId ?? addresses.first.id,
                decoration: const InputDecoration(labelText: 'عنوان التوصيل'),
                items: addresses
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          '${a.label} • ${a.block}-${a.buildingNumber}-${a.apartment}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: onAddressChanged,
              ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: confirming ? null : onConfirm,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text(confirming ? 'جارٍ التثبيت...' : 'تثبيت الطلب'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatedOrderCard extends StatelessWidget {
  final AssistantCreatedOrderModel order;
  final VoidCallback onTrack;

  const _CreatedOrderCard({required this.order, required this.onTrack});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تم تثبيت الطلب #${order.id}',
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'المتجر: ${order.merchantName}\nالإجمالي: ${formatIqd(order.totalAmount)}',
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onTrack,
              icon: const Icon(Icons.route_rounded),
              label: const Text('تتبع الطلب الآن'),
            ),
          ],
        ),
      ),
    );
  }
}
