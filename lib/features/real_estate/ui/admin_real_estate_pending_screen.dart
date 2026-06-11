import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../data/real_estate_api.dart';
import '../models/real_estate_models.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class AdminRealEstatePendingScreen extends ConsumerStatefulWidget {
  const AdminRealEstatePendingScreen({super.key});

  @override
  ConsumerState<AdminRealEstatePendingScreen> createState() =>
      _AdminRealEstatePendingScreenState();
}

class _AdminRealEstatePendingScreenState
    extends ConsumerState<AdminRealEstatePendingScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<RealEstateListingModel> _items = const [];

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
      final raw = await ref
          .read(realEstateApiProvider)
          .listPendingAdminListings(limit: 120);
      if (!mounted) return;
      setState(() {
        _items = raw
            .map(RealEstateListingModel.fromJson)
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.adminRealEstatePendingLoadFailed,
        );
      });
    }
  }

  Future<String?> _askNote({required String title}) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, textDirection: context.appTextDirection),
        content: TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 4,
          textDirection: context.appTextDirection,
          decoration: InputDecoration(
            hintText: context.l10n.adminRealEstatePendingOptionalReviewNote,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.commonConfirm),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return null;
    return text;
  }

  Future<void> _review(
    RealEstateListingModel item, {
    required bool approve,
  }) async {
    if (_busy) return;
    final note = await _askNote(
      title: approve
          ? context.l10n.adminRealEstatePendingApproveTitle
          : context.l10n.adminRealEstatePendingRejectTitle,
    );
    if (note == null) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(realEstateApiProvider);
      if (approve) {
        await api.approveListing(item.id, reviewNote: note);
      } else {
        await api.rejectListing(item.id, reviewNote: note);
      }
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.adminRealEstatePendingReviewFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminRealEstatePendingTitle),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                children: [
                  const SizedBox(height: 140),
                  Center(
                    child: Text(
                      _error!,
                      textDirection: context.appTextDirection,
                    ),
                  ),
                ],
              )
            : _items.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 140),
                  Center(
                    child: Text(
                      l10n.adminRealEstatePendingEmpty,
                      textDirection: context.appTextDirection,
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final cover = item.media.isNotEmpty
                      ? item.media.first.imageUrl
                      : null;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if ((cover ?? '').isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: CachedAppImage(
                                    imageUrl: cover!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            if ((cover ?? '').isNotEmpty)
                              const SizedBox(height: 12),
                            Text(
                              item.title,
                              textDirection: context.appTextDirection,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.adminRealEstatePendingOwnerLine(
                                item.ownerFullName ?? '-',
                                item.ownerId,
                              ),
                              textDirection: context.appTextDirection,
                            ),
                            if ((item.ownerPhone ?? '').trim().isNotEmpty)
                              Text(
                                l10n.adminRealEstatePendingOwnerPhoneLine(
                                  item.ownerPhone!,
                                ),
                                textDirection: context.appTextDirection,
                              ),
                            Text(
                              '${item.purpose == 'sale' ? l10n.adminRealEstatePendingPurposeSale : l10n.adminRealEstatePendingPurposeRent} • ${item.areaSqm}m² • ${formatIqd(item.price)}',
                              textDirection: context.appTextDirection,
                            ),
                            Text(
                              l10n.adminRealEstatePendingPhoneLine(item.phone),
                              textDirection: context.appTextDirection,
                            ),
                            if ((item.description ?? '').trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  item.description!,
                                  textDirection: context.appTextDirection,
                                ),
                              ),
                            const SizedBox(height: 12),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _review(item, approve: false),
                                  icon: const Icon(Icons.close_rounded),
                                  label: Text(
                                    l10n.adminRealEstatePendingRejectAction,
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _review(item, approve: true),
                                  icon: const Icon(Icons.check_rounded),
                                  label: Text(
                                    l10n.adminRealEstatePendingApproveAction,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
