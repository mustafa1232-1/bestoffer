import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../paid_upgrades/ui/paid_upgrades_home_screen.dart';
import '../data/real_estate_api.dart';
import '../models/real_estate_models.dart';
import 'real_estate_listing_details_screen.dart';
import 'real_estate_listing_editor_screen.dart';
import 'widgets/real_estate_listing_card.dart';

class RealEstateWorkspaceScreen extends ConsumerStatefulWidget {
  const RealEstateWorkspaceScreen({super.key});

  @override
  ConsumerState<RealEstateWorkspaceScreen> createState() =>
      _RealEstateWorkspaceScreenState();
}

class _RealEstateWorkspaceScreenState
    extends ConsumerState<RealEstateWorkspaceScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  RealEstateWorkspaceModel? _workspace;

  RealEstateApi get _api => ref.read(realEstateApiProvider);

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
        _workspace = RealEstateWorkspaceModel.fromJson(raw);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.realEstateWorkspaceLoadFailed,
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

  Future<void> _openEditor({RealEstateListingModel? listing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RealEstateListingEditorScreen(existing: listing),
      ),
    );
    if (changed == true && mounted) {
      await _load();
    }
  }

  Future<void> _markStatus(RealEstateListingModel listing, String nextStatus) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _api.markStatus(listing.id, nextStatus: nextStatus);
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(error, fallback: context.l10n.realEstateStatusUpdateFailed),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final realEstateSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.realEstate, displayName: 'العقارات');
    if (realEstateSection.isBlocked) {
      return SectionUnavailableScreen(entry: realEstateSection);
    }
    final l10n = context.l10n;
    final workspace = _workspace;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.realEstateWorkspaceTitle),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: workspace == null
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              onPressed: workspace.propertySellerMonthly
                  ? () => _openEditor()
                  : _openUpgrade,
              icon: Icon(
                workspace.propertySellerMonthly
                    ? Icons.add_home_work_outlined
                    : Icons.workspace_premium_outlined,
              ),
              label: Text(
                workspace.propertySellerMonthly
                    ? l10n.realEstateAddListing
                    : l10n.realEstateActivatePlan,
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
                  if (workspace != null && !workspace.propertySellerMonthly)
                    _PlanInactiveBanner(onOpenUpgrade: _openUpgrade),
                  if (workspace != null) _WorkspaceSummary(workspace: workspace),
                  const SizedBox(height: 12),
                  if (workspace == null || workspace.listings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Center(child: Text(l10n.realEstateNoListings)),
                    )
                  else
                    ...workspace.listings.map(
                      (listing) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          children: [
                            RealEstateListingCard(
                              listing: listing,
                              compact: true,
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RealEstateListingDetailsScreen(
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
                                    label: Text(l10n.realEstateSold),
                                  ),
                                if (listing.status == 'active')
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _markStatus(listing, 'rented'),
                                    icon: const Icon(Icons.key_outlined),
                                    label: Text(l10n.realEstateRented),
                                  ),
                                if (listing.status == 'active' ||
                                    listing.status == 'pending_admin_review' ||
                                    listing.status == 'hidden_due_subscription_expiry')
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _markStatus(listing, 'archived'),
                                    icon: const Icon(Icons.archive_outlined),
                                    label: Text(l10n.realEstateArchived),
                                  ),
                                if (listing.status == 'archived')
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _markStatus(listing, 'active'),
                                    icon: const Icon(Icons.unarchive_outlined),
                                    label: Text(l10n.realEstateAvailable),
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
              l10n.realEstatePlanInactive,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(l10n.realEstatePlanInactiveBody),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onOpenUpgrade,
              icon: const Icon(Icons.workspace_premium_outlined),
              label: Text(l10n.realEstateOpenUpgrades),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceSummary extends StatelessWidget {
  final RealEstateWorkspaceModel workspace;

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
              l10n.realEstateListingsSummary,
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
                  l10n.realEstateReviewStatusActive,
                  (counts['active'] as num?)?.toInt() ?? 0,
                ),
                chip(
                  l10n.realEstateReviewStatusPending,
                  (counts['pending_admin_review'] as num?)?.toInt() ?? 0,
                ),
                chip(
                  l10n.realEstateSold,
                  (counts['sold'] as num?)?.toInt() ?? 0,
                ),
                chip(
                  l10n.realEstateRented,
                  (counts['rented'] as num?)?.toInt() ?? 0,
                ),
                chip(
                  l10n.realEstateArchived,
                  (counts['archived'] as num?)?.toInt() ?? 0,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
