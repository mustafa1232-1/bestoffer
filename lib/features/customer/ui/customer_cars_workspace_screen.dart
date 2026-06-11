import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../paid_upgrades/ui/paid_upgrades_home_screen.dart';
import '../data/cars_api.dart';
import '../models/car_listing_model.dart';
import 'customer_car_listing_details_screen.dart';
import 'customer_car_listing_editor_screen.dart';
import 'widgets/customer_car_listing_card.dart';

class CustomerCarsWorkspaceScreen extends ConsumerStatefulWidget {
  const CustomerCarsWorkspaceScreen({super.key});

  @override
  ConsumerState<CustomerCarsWorkspaceScreen> createState() =>
      _CustomerCarsWorkspaceScreenState();
}

class _CustomerCarsWorkspaceScreenState
    extends ConsumerState<CustomerCarsWorkspaceScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  CarsWorkspaceModel? _workspace;

  CarsApi get _api => ref.read(carsApiProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _api.workspace();
      if (!mounted) return;
      setState(() {
        _workspace = CarsWorkspaceModel.fromJson(raw);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.carsWorkspaceLoadFailed,
        );
      });
    }
  }

  Future<void> _openUpgrade() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PaidUpgradesHomeScreen()));
    if (!mounted) return;
    await _load();
  }

  Future<void> _openEditor({CarListingModel? listing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerCarListingEditorScreen(existing: listing),
      ),
    );
    if (changed == true && mounted) {
      await _load();
    }
  }

  Future<void> _markStatus(CarListingModel listing, String nextStatus) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _api.markSellerListingStatus(listing.id, nextStatus: nextStatus);
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(error, fallback: context.l10n.carsStatusUpdateFailed),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.trim());
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final workspace = _workspace;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.carsWorkspaceTitle),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.commonRefresh,
          ),
        ],
      ),
      floatingActionButton: workspace == null
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              onPressed: workspace.carSellerMonthly
                  ? () => _openEditor()
                  : _openUpgrade,
              icon: Icon(
                workspace.carSellerMonthly
                    ? Icons.add_circle_outline_rounded
                    : Icons.workspace_premium_outlined,
              ),
              label: Text(
                workspace.carSellerMonthly
                    ? l10n.carsAddListing
                    : l10n.carsActivateSelling,
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                children: [
                  const SizedBox(height: 140),
                  Center(child: Text(_error!)),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  if (workspace != null && !workspace.carSellerMonthly)
                    _PlanInactiveBanner(onOpenUpgrade: _openUpgrade),
                  if (workspace != null)
                    _WorkspaceSummary(workspace: workspace),
                  const SizedBox(height: 12),
                  if (workspace != null &&
                      workspace.syncChangedListingIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        context.l10n.carsWorkspaceSyncedHint,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  if (workspace == null || workspace.listings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Center(child: Text(l10n.carsNoListings)),
                    )
                  else
                    ...workspace.listings.map(
                      (listing) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          children: [
                            CustomerCarListingCard(
                              listing: listing,
                              compact: true,
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CustomerCarListingDetailsScreen(
                                          listingId: listing.id,
                                          initialListing: listing,
                                        ),
                                  ),
                                );
                                if (mounted) {
                                  await _load();
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.start,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: _busy
                                      ? null
                                      : () => _openEditor(listing: listing),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: Text(l10n.commonEdit),
                                ),
                                if (listing.status == 'active')
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _markStatus(listing, 'sold'),
                                    icon: const Icon(Icons.sell_outlined),
                                    label: Text(l10n.carsStatusSold),
                                  ),
                                if (listing.status == 'active')
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () =>
                                              _markStatus(listing, 'archived'),
                                    icon: const Icon(Icons.archive_outlined),
                                    label: Text(l10n.carsStatusArchived),
                                  ),
                                if (listing.status == 'archived' ||
                                    listing.status ==
                                        'hidden_due_subscription_expiry')
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _markStatus(listing, 'active'),
                                    icon: const Icon(Icons.unarchive_outlined),
                                    label: Text(l10n.carsStatusActive),
                                  ),
                                FilledButton.tonalIcon(
                                  onPressed: _busy
                                      ? null
                                      : () => _call(listing.phone),
                                  icon: const Icon(Icons.call_outlined),
                                  label: Text(l10n.commonCall),
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

class _PlanInactiveBanner extends StatelessWidget {
  final VoidCallback onOpenUpgrade;

  const _PlanInactiveBanner({required this.onOpenUpgrade});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.carsActivateSelling,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(l10n.carsSellerBannerInactive),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onOpenUpgrade,
              icon: const Icon(Icons.workspace_premium_outlined),
              label: Text(l10n.carsOpenUpgrades),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceSummary extends StatelessWidget {
  final CarsWorkspaceModel workspace;

  const _WorkspaceSummary({required this.workspace});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final counts = workspace.counts;

    Widget chip(String label, int count) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        ),
        child: Text(
          '$label: $count',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.carsListingsSummary,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                chip(
                  l10n.carsStatusActive,
                  (counts['active'] as num?)?.toInt() ?? 0,
                ),
                chip(
                  l10n.carsStatusSold,
                  (counts['sold'] as num?)?.toInt() ?? 0,
                ),
                chip(
                  l10n.carsStatusArchived,
                  (counts['archived'] as num?)?.toInt() ?? 0,
                ),
                chip(
                  l10n.carsStatusHiddenByExpiry,
                  (counts['hidden_due_subscription_expiry'] as num?)?.toInt() ??
                      0,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
