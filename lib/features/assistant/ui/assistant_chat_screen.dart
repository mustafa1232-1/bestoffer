import 'dart:math' as math;

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
        _scrollCtrl.position.maxScrollExtent + 160,
        duration: const Duration(milliseconds: 280),
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
        title: const Text('مساعد الطلب الذكي'),
        actions: [
          IconButton(
            tooltip: 'جلسة جديدة',
            onPressed: state.loading || state.sending
                ? null
                : () async {
                    setState(() => _selectedAddressId = null);
                    await ref
                        .read(assistantControllerProvider.notifier)
                        .startNewSession();
                  },
            icon: const Icon(Icons.add_comment_rounded),
          ),
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
          _AssistantHero(
            subtitle:
                'اكتب براحتك، وأنا أرتب لك المتاجر حسب السعر والتقييم وتاريخ طلباتك.',
            profile: state.profile,
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
            onTapCheap: () => _sendPreset('أريد أرخص الخيارات'),
            onTapTopRated: () => _sendPreset('أريد أعلى تقييم'),
            onTapBasedHistory: () => _sendPreset('اقترح لي حسب طلباتي السابقة'),
            onTapQuickDraft: () => _sendPreset(
              'سويلي طلب جاهز بسرعة عندي ضيوف',
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
                        hintText: 'اكتب طلبك... مثال: بركر رخيص مع توصيل مجاني',
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

class _AssistantHero extends StatefulWidget {
  final String subtitle;
  final Map<String, dynamic>? profile;

  const _AssistantHero({required this.subtitle, required this.profile});

  @override
  State<_AssistantHero> createState() => _AssistantHeroState();
}

class _AssistantHeroState extends State<_AssistantHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final favoriteTokensRaw = widget.profile?['favoriteTokens'];
    final favoriteTokens = favoriteTokensRaw is List
        ? favoriteTokensRaw
              .map((e) => (e is Map ? e['key'] : null)?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .take(3)
              .toList()
        : const <String>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final glow = 0.08 + (_pulse.value * 0.12);
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
                  Colors.cyan.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.05),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.38),
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: glow),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      child: Icon(Icons.smart_toy_outlined),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'AI BestOffer | بسماية',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(widget.subtitle, textDirection: TextDirection.rtl),
                if (favoriteTokens.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: favoriteTokens
                        .map((token) => Chip(label: Text(token)))
                        .toList(),
                  ),
                ],
              ],
            ),
          );
        },
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
    final bubbleColor = isUser
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.24)
        : Colors.white.withValues(alpha: 0.08);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: bubbleColor,
          border: Border.all(
            color: isUser
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser)
              Icon(
                Icons.smart_toy_outlined,
                size: 16,
                color: Colors.cyan.shade200,
              ),
            if (!isUser) const SizedBox(width: 6),
            Flexible(
              child: Text(message.text, textDirection: TextDirection.rtl),
            ),
            if (isUser) const SizedBox(width: 6),
            if (isUser)
              Icon(
                Icons.person_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final phase = _controller.value * math.pi * 2;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final shift = math.sin(phase + index * 0.9).abs();
                final size = 5.0 + (shift * 3.5);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: Colors.cyan.withValues(alpha: 0.75),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }),
            );
          },
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
            label: const Text('الأرخص'),
            onPressed: onTapCheap,
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.star_rate_rounded, size: 16),
            label: const Text('الأعلى تقييما'),
            onPressed: onTapTopRated,
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.history_rounded, size: 16),
            label: const Text('من طلباتي'),
            onPressed: onTapBasedHistory,
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.local_shipping_rounded, size: 16),
            label: const Text('طلب سريع'),
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
                  (p) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      color: Colors.white.withValues(alpha: 0.03),
                    ),
                    child: Row(
                      children: [
                        _ItemImage(
                          url: p.productImageUrl,
                          icon: Icons.fastfood_rounded,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                p.productName,
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.merchantName,
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.78),
                                  fontSize: 12,
                                ),
                              ),
                              if (p.offerLabel?.trim().isNotEmpty == true)
                                Text(
                                  p.offerLabel!,
                                  textDirection: TextDirection.rtl,
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatIqd(p.effectivePrice),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (p.freeDelivery)
                              const Text(
                                'توصيل مجاني',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 11,
                                ),
                              ),
                          ],
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
              'أفضل المتاجر لك',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...merchants
                .take(4)
                .map(
                  (m) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _ItemImage(
                      url: m.merchantImageUrl,
                      icon: Icons.storefront_rounded,
                    ),
                    title: Text(
                      m.merchantName,
                      textDirection: TextDirection.rtl,
                    ),
                    subtitle: Text(
                      'Rating ${m.avgRating.toStringAsFixed(1)} | ${formatIqd(m.minPrice)} - ${formatIqd(m.maxPrice)}',
                      textDirection: TextDirection.rtl,
                    ),
                    trailing: m.hasFreeDelivery
                        ? const Icon(Icons.local_shipping_rounded, size: 18)
                        : null,
                  ),
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
              'المجموع: ${formatIqd(draft.subtotal)}\n'
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
                          '${a.label} - ${a.block}-${a.buildingNumber}-${a.apartment}',
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
              label: Text(confirming ? 'جاري التأكيد...' : 'تأكيد الطلب'),
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
              'تم تأكيد الطلب #${order.id}',
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

class _ItemImage extends StatelessWidget {
  final String? url;
  final IconData icon;

  const _ItemImage({required this.url, required this.icon});

  @override
  Widget build(BuildContext context) {
    final clean = url?.trim();
    if (clean == null || clean.isEmpty) {
      return CircleAvatar(radius: 18, child: Icon(icon, size: 18));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        clean,
        width: 38,
        height: 38,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            CircleAvatar(radius: 18, child: Icon(icon, size: 18)),
      ),
    );
  }
}
