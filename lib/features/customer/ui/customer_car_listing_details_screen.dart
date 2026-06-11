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
import '../data/cars_api.dart';
import '../models/car_listing_model.dart';
import 'widgets/customer_car_listing_card.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class CustomerCarListingDetailsScreen extends ConsumerStatefulWidget {
  final int listingId;
  final CarListingModel? initialListing;

  const CustomerCarListingDetailsScreen({
    super.key,
    required this.listingId,
    this.initialListing,
  });

  @override
  ConsumerState<CustomerCarListingDetailsScreen> createState() =>
      _CustomerCarListingDetailsScreenState();
}

class _CustomerCarListingDetailsScreenState
    extends ConsumerState<CustomerCarListingDetailsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  CarListingModel? _listing;
  List<CarListingModel> _similar = const [];

  CarsApi get _api => ref.read(carsApiProvider);
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
      final raw = await _api.getListing(widget.listingId);
      final listing = CarListingModel.fromJson(Map<String, dynamic>.from(raw));
      final similar = await _loadSimilar(listing);
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _similar = similar;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(error, fallback: context.l10n.carsLoadFailed);
      });
    }
  }

  Future<List<CarListingModel>> _loadSimilar(CarListingModel listing) async {
    try {
      final rows = await _api.listMarketplaceListings(
        CarListingQuery(
          brand: listing.brand,
          bodyType: listing.bodyType,
          sort: 'recent',
        ),
        limit: 8,
      );
      final models = rows
          .map(CarListingModel.fromJson)
          .where((item) => item.id != listing.id)
          .take(6)
          .toList(growable: false);
      if (models.isNotEmpty) return models;
      final fallbackRows = await _api.listMarketplaceListings(
        CarListingQuery(brand: listing.brand, sort: 'recent'),
        limit: 8,
      );
      return fallbackRows
          .map(CarListingModel.fromJson)
          .where((item) => item.id != listing.id)
          .take(6)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _shareListing() async {
    final listing = _listing;
    if (listing == null) return;
    final subtitleParts = <String>[
      '${listing.brand} ${listing.model}'.trim(),
      '${listing.modelYear}',
      if ((listing.city ?? '').trim().isNotEmpty) listing.city!.trim(),
    ];
    await showSocialShareSheet(
      context: context,
      entityType: 'car_listing',
      entityId: listing.id,
      previewTitle: listing.title,
      previewSubtitle: subtitleParts.join(' • '),
      externalShareText: context.l10n.carsShareText(listing.title),
      sharedSnapshot: <String, dynamic>{
        'title': listing.title,
        'subtitle': subtitleParts.join(' • '),
        'imageUrl': listing.media.isNotEmpty
            ? listing.media.first.imageUrl
            : null,
        'price': listing.price,
        'status': listing.status,
        'city': listing.city,
      }..removeWhere((_, value) => value == null),
    );
  }

  Future<void> _callSeller() async {
    final listing = _listing;
    if (listing == null || listing.phone.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: listing.phone.trim());
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.carsCallFailed)));
    }
  }

  Future<void> _messageSeller() async {
    final listing = _listing;
    final auth = ref.read(authControllerProvider);
    if (listing == null || _busy || !auth.isAuthed || auth.user == null) return;
    if (auth.user!.id == listing.ownerId) return;
    setState(() => _busy = true);
    try {
      final raw = await _socialApi.createThread(
        listing.ownerId,
        kind: 'business',
        contextType: 'car_listing',
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
            peerName: thread.peer.username?.trim().isNotEmpty == true
                ? '@${thread.peer.username!}'
                : thread.peer.fullName,
            peerPhone: thread.peerPhone,
            peerUserId: thread.peer.id,
            peerImageUrl: thread.peer.imageUrl,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(error, fallback: context.l10n.carsStartChatFailed),
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
    final auth = ref.watch(authControllerProvider);
    final canMessage =
        auth.isAuthed && auth.user != null && auth.user!.id != listing?.ownerId;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.carsDetailsTitle),
        actions: [
          IconButton(
            onPressed: listing == null ? null : _shareListing,
            icon: const Icon(Icons.share_outlined),
            tooltip: l10n.commonShare,
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
                  Center(child: Text(l10n.carsNoListings)),
                ],
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _CarGallery(listing: listing),
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
                              label: carConditionLabel(
                                context,
                                listing.condition,
                              ),
                            ),
                            _InfoBadge(
                              label: carListingStatusLabel(
                                context,
                                listing.status,
                              ),
                            ),
                            _InfoBadge(
                              label: carBodyTypeLabel(
                                context,
                                listing.bodyType,
                              ),
                            ),
                            _InfoBadge(
                              label: carTransmissionLabel(
                                context,
                                listing.transmission,
                              ),
                            ),
                            _InfoBadge(
                              label: carFuelTypeLabel(
                                context,
                                listing.fuelType,
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
                              _InfoBadge(
                                label:
                                    '${l10n.carsModelYear}: ${listing.modelYear}',
                              ),
                              if (listing.mileageKm != null)
                                _InfoBadge(
                                  label:
                                      '${l10n.carsMileage}: ${listing.mileageKm} km',
                                ),
                              if ((listing.color ?? '').isNotEmpty)
                                _InfoBadge(
                                  label: '${l10n.carsColor}: ${listing.color!}',
                                ),
                            ],
                          ),
                        ),
                        _InfoSection(
                          title: l10n.carsDetailsTitle,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InfoBadge(
                                label: '${l10n.carsBrand}: ${listing.brand}',
                              ),
                              _InfoBadge(
                                label: '${l10n.carsModel}: ${listing.model}',
                              ),
                              _InfoBadge(
                                label:
                                    '${l10n.carsTransmission}: ${carTransmissionLabel(context, listing.transmission)}',
                              ),
                              _InfoBadge(
                                label:
                                    '${l10n.carsFuelType}: ${carFuelTypeLabel(context, listing.fuelType)}',
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
                              ).textTheme.bodyLarge?.copyWith(height: 1.55),
                            ),
                          ),
                        _InfoSection(
                          title: l10n.realEstateContact,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                listing.ownerFullName?.trim().isNotEmpty == true
                                    ? listing.ownerFullName!
                                    : l10n.carsSellerUnknown,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                listing.phone,
                                textDirection: TextDirection.ltr,
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _busy ? null : _callSeller,
                                      icon: const Icon(Icons.call_outlined),
                                      label: Text(l10n.carsCallSeller),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.tonalIcon(
                                      onPressed: canMessage && !_busy
                                          ? _messageSeller
                                          : null,
                                      icon: const Icon(
                                        Icons.chat_bubble_outline_rounded,
                                      ),
                                      label: Text(l10n.commonMessage),
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
                            l10n.carsSimilarListings,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 12),
                          ..._similar.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: CustomerCarListingCard(
                                listing: item,
                                compact: true,
                                onTap: () {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          CustomerCarListingDetailsScreen(
                                            listingId: item.id,
                                            initialListing: item,
                                          ),
                                    ),
                                  );
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

class _CarGallery extends StatefulWidget {
  final CarListingModel listing;

  const _CarGallery({required this.listing});

  @override
  State<_CarGallery> createState() => _CarGalleryState();
}

class _CarGalleryState extends State<_CarGallery> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.listing.media;
    if (media.isEmpty) {
      return Container(
        height: 260,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.directions_car_filled_rounded,
          size: 56,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.72),
        ),
      );
    }

    return SizedBox(
      height: 280,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: media.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) => CachedAppImage(
              imageUrl: media[index].imageUrl,
              cacheIdentity:
                  'car_listing_${widget.listing.id}_media_${media[index].id}',
              version: widget.listing.updatedAt?.toIso8601String(),
              fit: BoxFit.cover,
            ),
          ),
          PositionedDirectional(
            bottom: 14,
            start: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.44),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  '${_index + 1} / ${media.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
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
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
