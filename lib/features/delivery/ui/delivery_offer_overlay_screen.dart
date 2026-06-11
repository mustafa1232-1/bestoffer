import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../state/delivery_controller.dart';

class DeliveryOfferOverlayScreen extends ConsumerStatefulWidget {
  const DeliveryOfferOverlayScreen({
    super.key,
    required this.orderId,
    this.remoteDisplayName,
  });

  final int orderId;
  final String? remoteDisplayName;

  @override
  ConsumerState<DeliveryOfferOverlayScreen> createState() =>
      _DeliveryOfferOverlayScreenState();
}

class _DeliveryOfferOverlayScreenState
    extends ConsumerState<DeliveryOfferOverlayScreen> {
  static const Duration _missingRequestGrace = Duration(seconds: 12);
  final DateTime _openedAt = DateTime.now();
  bool _bootstrapped = false;
  late final DeliveryController _deliveryController;

  @override
  void initState() {
    super.initState();
    _deliveryController = ref.read(deliveryControllerProvider.notifier);
    Future.microtask(() async {
      if (!mounted) return;
      await _deliveryController.bootstrap();
      if (!mounted) return;
      _deliveryController.startLiveOrders(interval: const Duration(seconds: 6));
      if (!mounted) return;
      setState(() => _bootstrapped = true);
    });
  }

  @override
  void dispose() {
    _deliveryController.stopLiveOrders();
    super.dispose();
  }

  Future<void> _refresh() async {
    await _deliveryController.refreshCurrentOrders();
  }

  Future<void> _accept() async {
    await _deliveryController.acceptRequest(widget.orderId);
    if (!mounted) return;
    if (ref.read(deliveryControllerProvider).error == null) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _reject() async {
    await _deliveryController.rejectRequest(widget.orderId);
    if (!mounted) return;
    if (ref.read(deliveryControllerProvider).error == null) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(deliveryControllerProvider);
    final request = state.pendingRequests.cast<Map?>().firstWhere((entry) {
      if (entry == null) return false;
      final map = Map<String, dynamic>.from(entry);
      final rawId = map['orderId'] ?? map['order_id'] ?? map['id'];
      return int.tryParse('$rawId') == widget.orderId;
    }, orElse: () => null);
    final requestMap = request == null
        ? null
        : Map<String, dynamic>.from(request);
    final merchantName =
        '${requestMap?['merchant_name'] ?? requestMap?['merchantName'] ?? widget.remoteDisplayName ?? '-'}';
    final customerName =
        '${requestMap?['customer_name'] ?? requestMap?['customerName'] ?? '-'}';
    final totalAmount =
        num.tryParse(
          '${requestMap?['total_amount'] ?? requestMap?['totalAmount'] ?? ''}',
        ) ??
        0;
    final deliveryFee =
        num.tryParse(
          '${requestMap?['delivery_fee'] ?? requestMap?['deliveryFee'] ?? ''}',
        ) ??
        0;
    final distanceText =
        '${requestMap?['distance_label'] ?? requestMap?['distanceLabel'] ?? requestMap?['distance_km'] ?? requestMap?['distanceKm'] ?? ''}'
            .trim();
    final pickupText =
        '${requestMap?['pickup_address'] ?? requestMap?['pickupAddress'] ?? requestMap?['merchant_address'] ?? requestMap?['merchantAddress'] ?? ''}'
            .trim();
    final dropoffText =
        '${requestMap?['dropoff_address'] ?? requestMap?['dropoffAddress'] ?? requestMap?['customer_address'] ?? requestMap?['customerAddress'] ?? ''}'
            .trim();
    final expired =
        _bootstrapped &&
        requestMap == null &&
        !state.saving &&
        state.error == null &&
        DateTime.now().difference(_openedAt) > _missingRequestGrace;

    return PopScope(
      canPop: !state.saving,
      child: Scaffold(
        backgroundColor: const Color(0xFF071424),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: state.saving
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                    ),
                    Expanded(
                      child: Text(
                        l10n.deliveryOfferNewRequestTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF123B66), Color(0xFF0E2240)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x44000000),
                        blurRadius: 32,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.local_shipping_rounded),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.deliveryOfferOrderTitle(widget.orderId),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  expired
                                      ? l10n.deliveryOfferExpired
                                      : l10n.deliveryOfferReviewPrompt,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (state.error != null)
                        _OverlayBanner(text: state.error!, danger: true),
                      if (expired)
                        _OverlayBanner(text: l10n.deliveryOfferExpiredHint),
                      const SizedBox(height: 8),
                      _InfoTile(
                        icon: Icons.storefront_outlined,
                        label: l10n.commonMerchant,
                        value: merchantName,
                      ),
                      _InfoTile(
                        icon: Icons.person_outline,
                        label: l10n.commonCustomer,
                        value: customerName,
                      ),
                      if (pickupText.isNotEmpty)
                        _InfoTile(
                          icon: Icons.inventory_2_outlined,
                          label: l10n.deliveryOfferPickupPoint,
                          value: pickupText,
                        ),
                      if (dropoffText.isNotEmpty)
                        _InfoTile(
                          icon: Icons.location_on_outlined,
                          label: l10n.deliveryOfferDropOffPoint,
                          value: dropoffText,
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: _MetricPill(
                              label: l10n.commonTotal,
                              value: formatIqd(totalAmount),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MetricPill(
                              label: l10n.commonDeliveryFee,
                              value: formatIqd(deliveryFee),
                            ),
                          ),
                        ],
                      ),
                      if (distanceText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _MetricPill(
                          label: l10n.deliveryOfferEstimatedDistance,
                          value: distanceText,
                          expanded: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (!_bootstrapped && state.loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else ...[
                  FilledButton.icon(
                    onPressed: expired || state.saving ? null : _accept,
                    icon: state.saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(l10n.deliveryOfferAcceptRequest),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(58),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: expired || state.saving ? null : _reject,
                    icon: const Icon(Icons.close_rounded),
                    label: Text(l10n.deliveryOfferRejectRequest),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.deliveryOfferLiveHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    this.expanded = false,
  });

  final String label;
  final String value;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: expanded ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _OverlayBanner extends StatelessWidget {
  const _OverlayBanner({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger
            ? const Color(0xFF5D1F2B).withValues(alpha: 0.78)
            : const Color(0xFF1D3B55).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: danger
              ? const Color(0xFFFF8095).withValues(alpha: 0.42)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Text(text),
    );
  }
}
