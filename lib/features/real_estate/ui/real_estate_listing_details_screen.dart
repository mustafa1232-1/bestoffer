import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../../auth/state/auth_controller.dart';
import '../../social/data/social_api.dart';
import '../../social/models/social_models.dart';
import '../../social/state/social_controller.dart';
import '../../social/ui/social_chat_thread_screen.dart';
import '../../social/ui/social_share_sheet.dart';
import '../data/real_estate_api.dart';
import '../models/real_estate_models.dart';
import 'widgets/real_estate_listing_card.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class RealEstateListingDetailsScreen extends ConsumerStatefulWidget {
  final int listingId;
  final RealEstateListingModel? initialListing;

  const RealEstateListingDetailsScreen({
    super.key,
    required this.listingId,
    this.initialListing,
  });

  @override
  ConsumerState<RealEstateListingDetailsScreen> createState() =>
      _RealEstateListingDetailsScreenState();
}

class _RealEstateListingDetailsScreenState
    extends ConsumerState<RealEstateListingDetailsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  RealEstateListingModel? _listing;
  List<RealEstateListingModel> _similar = const [];

  RealEstateApi get _api => ref.read(realEstateApiProvider);
  SocialApi get _socialApi => ref.read(socialApiProvider);

  @override
  void initState() {
    super.initState();
    _listing = widget.initialListing;
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listingRaw = await _api.getListing(widget.listingId);
      List<Map<String, dynamic>> similarRows = const [];
      try {
        similarRows = await _api.listSimilarListings(widget.listingId);
      } catch (_) {
        similarRows = const [];
      }
      if (!mounted) return;
      setState(() {
        _listing = RealEstateListingModel.fromJson(
          Map<String, dynamic>.from(listingRaw),
        );
        _similar = similarRows
            .map(RealEstateListingModel.fromJson)
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.realEstateLoadFailed,
        );
      });
    }
  }

  Future<void> _toggleSaved() async {
    final listing = _listing;
    final auth = ref.read(authControllerProvider);
    if (listing == null || !auth.isAuthed || _busy) return;
    setState(() => _busy = true);
    try {
      final nextSaved = !listing.isSaved;
      if (nextSaved) {
        await _api.saveListing(listing.id);
      } else {
        await _api.unsaveListing(listing.id);
      }
      if (!mounted) return;
      setState(() => _listing = listing.copyWith(isSaved: nextSaved));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextSaved
                ? context.l10n.realEstateSaved
                : context.l10n.realEstateUnsaved,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(error, fallback: context.l10n.realEstateSaveFailed),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareListing() async {
    final listing = _listing;
    if (listing == null) return;
    final subtitleParts = <String>[
      if ((listing.city ?? '').trim().isNotEmpty) listing.city!.trim(),
      if ((listing.block ?? '').trim().isNotEmpty) listing.block!.trim(),
      '${listing.areaSqm} ${context.l10n.realEstateAreaLabel}',
    ];
    await showSocialShareSheet(
      context: context,
      entityType: 'real_estate_listing',
      entityId: listing.id,
      previewTitle: listing.title,
      previewSubtitle: subtitleParts.join(' • '),
      externalShareText: context.l10n.realEstateShareText(listing.title),
      sharedSnapshot: <String, dynamic>{
        'title': listing.title,
        'subtitle': subtitleParts.join(' • '),
        'imageUrl': listing.media.isNotEmpty
            ? listing.media.first.imageUrl
            : null,
        'price': listing.price,
        'status': listing.status,
        'city': listing.city,
        'block': listing.block,
      }..removeWhere((_, value) => value == null),
    );
  }

  Future<void> _callOwner() async {
    final listing = _listing;
    if (listing == null || listing.phone.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: listing.phone.trim());
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.realEstateCallFailed)),
      );
    }
  }

  Future<void> _messageOwner() async {
    final listing = _listing;
    final auth = ref.read(authControllerProvider);
    if (listing == null || _busy || !auth.isAuthed || auth.user == null) return;
    if (auth.user!.id == listing.ownerId) return;
    setState(() => _busy = true);
    try {
      final raw = await _socialApi.createThread(
        listing.ownerId,
        kind: 'business',
        contextType: 'real_estate_listing',
        contextId: listing.id,
      );
      final thread = SocialChatThread.fromJson(
        Map<String, dynamic>.from(raw['thread'] as Map),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SocialChatThreadScreen(
            threadId: thread.id,
            peerName: (listing.ownerFullName ?? '').trim().isNotEmpty
                ? listing.ownerFullName!.trim()
                : (thread.peer.username?.trim().isNotEmpty == true
                      ? '@${thread.peer.username!}'
                      : thread.peer.fullName),
            peerPhone: thread.peerPhone,
            peerUserId: listing.ownerId,
            peerImageUrl: thread.peer.imageUrl,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: context.l10n.realEstateStartChatFailed,
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
    final listing = _listing;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.realEstateDetailsTitle),
        actions: [
          IconButton(
            onPressed: listing == null ? null : _shareListing,
            icon: const Icon(Icons.share_outlined),
            tooltip: l10n.commonShare,
          ),
          if (ref.watch(authControllerProvider).isAuthed)
            IconButton(
              onPressed: listing == null || _busy ? null : _toggleSaved,
              icon: Icon(
                listing?.isSaved == true
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              tooltip: listing?.isSaved == true
                  ? l10n.realEstateRemoveSavedListing
                  : l10n.realEstateSaveListing,
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
                  Center(child: Text(_error!)),
                ],
              )
            : listing == null
            ? ListView(
                children: [
                  const SizedBox(height: 140),
                  Center(child: Text(l10n.realEstateNoListings)),
                ],
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _ListingGallery(listing: listing),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          listing.title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formatIqd(listing.price),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoBadge(
                              label: purposeLabel(context, listing.purpose),
                            ),
                            _InfoBadge(
                              label: statusLabel(context, listing.status),
                            ),
                            _InfoBadge(
                              label:
                                  '${listing.areaSqm} ${context.l10n.realEstateAreaLabel}',
                            ),
                            _InfoBadge(
                              label: listing.furnished
                                  ? l10n.realEstateFurnished
                                  : l10n.realEstateUnfurnished,
                            ),
                            _InfoBadge(
                              label: paymentMethodLabel(
                                context,
                                listing.paymentMethod,
                              ),
                            ),
                            _InfoBadge(
                              label: settlementModeLabel(
                                context,
                                listing.bankSettlementMode,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _InfoSection(
                          title: l10n.realEstateLocation,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if ((listing.city ?? '').isNotEmpty)
                                _InfoBadge(label: listing.city!),
                              if ((listing.block ?? '').isNotEmpty)
                                _InfoBadge(
                                  label:
                                      '${l10n.realEstateBlock}: ${listing.block!}',
                                ),
                              if ((listing.buildingNumber ?? '').isNotEmpty)
                                _InfoBadge(
                                  label:
                                      '${l10n.realEstateBuildingNumber}: ${listing.buildingNumber!}',
                                ),
                              if ((listing.apartmentNumber ?? '').isNotEmpty)
                                _InfoBadge(
                                  label:
                                      '${l10n.realEstateApartmentNumber}: ${listing.apartmentNumber!}',
                                ),
                            ],
                          ),
                        ),
                        _InfoSection(
                          title: l10n.realEstateSpecsStep,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InfoBadge(
                                label:
                                    '${listing.areaSqm} ${l10n.realEstateArea}',
                              ),
                              if (listing.roomsCount != null)
                                _InfoBadge(
                                  label:
                                      '${listing.roomsCount} ${l10n.realEstateRooms}',
                                ),
                              if (listing.bathroomsCount != null)
                                _InfoBadge(
                                  label:
                                      '${listing.bathroomsCount} ${l10n.realEstateBathrooms}',
                                ),
                              if (listing.floorNumber != null)
                                _InfoBadge(
                                  label:
                                      '${l10n.realEstateFloor}: ${listing.floorNumber}',
                                ),
                            ],
                          ),
                        ),
                        if ((listing.description ?? '').trim().isNotEmpty)
                          _InfoSection(
                            title: l10n.realEstateDescription,
                            child: Text(
                              listing.description!,
                              style: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.copyWith(height: 1.5),
                            ),
                          ),
                        if (listing.furnished &&
                            (listing.furnishingDescription ?? '')
                                .trim()
                                .isNotEmpty)
                          _InfoSection(
                            title: l10n.realEstateFurnishingDescription,
                            child: Text(listing.furnishingDescription!),
                          ),
                        _InfoSection(
                          title: l10n.realEstateContact,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                listing.ownerFullName?.trim().isNotEmpty == true
                                    ? listing.ownerFullName!
                                    : l10n.realEstateListingOwnerUnknown,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(listing.phone),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _busy ? null : _messageOwner,
                                      icon: const Icon(
                                        Icons.chat_bubble_outline,
                                      ),
                                      label: Text(l10n.realEstateMessageOwner),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _callOwner,
                                      icon: const Icon(Icons.call_outlined),
                                      label: Text(l10n.realEstateCallOwner),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (_similar.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            l10n.realEstateSimilar,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 12),
                          ..._similar.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: RealEstateListingCard(
                                listing: item,
                                compact: true,
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          RealEstateListingDetailsScreen(
                                            listingId: item.id,
                                            initialListing: item,
                                          ),
                                    ),
                                  );
                                  if (mounted) {
                                    await _load();
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ListingGallery extends StatefulWidget {
  final RealEstateListingModel listing;

  const _ListingGallery({required this.listing});

  @override
  State<_ListingGallery> createState() => _ListingGalleryState();
}

class _ListingGalleryState extends State<_ListingGallery> {
  late final PageController _pageController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final images = listing.media;
    return AspectRatio(
      aspectRatio: 1.18,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (images.isEmpty)
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.apartment_rounded,
                    size: 46,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(context.l10n.realEstateNoImages),
                ],
              ),
            )
          else
            PageView.builder(
              controller: _pageController,
              itemCount: images.length,
              onPageChanged: (value) => setState(() => _page = value),
              itemBuilder: (context, index) {
                return CachedAppImage(
                  imageUrl: images[index].imageUrl,
                  cacheIdentity:
                      'real_estate_${listing.id}_media_${images[index].id}',
                  version: listing.updatedAt?.toIso8601String(),
                  fit: BoxFit.cover,
                );
              },
            ),
          if (images.length > 1)
            PositionedDirectional(
              bottom: 16,
              end: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.44),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_page + 1}/${images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _InfoSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String label;

  const _InfoBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
