import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../auth/state/auth_controller.dart';
import '../../social/models/social_models.dart';
import '../../social/state/social_controller.dart';
import '../../social/ui/social_chat_thread_screen.dart';
import '../data/services_api.dart';
import '../models/service_models.dart';
import 'service_offering_details_screen.dart';

class ServiceProviderProfileScreen extends ConsumerStatefulWidget {
  final int providerId;

  const ServiceProviderProfileScreen({super.key, required this.providerId});

  @override
  ConsumerState<ServiceProviderProfileScreen> createState() =>
      _ServiceProviderProfileScreenState();
}

class _ServiceProviderProfileScreenState
    extends ConsumerState<ServiceProviderProfileScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  ServiceProviderProfileModel? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref
          .read(servicesApiProvider)
          .getPublicProvider(widget.providerId);
      if (!mounted) return;
      setState(() {
        _profile = ServiceProviderProfileModel.fromJson(raw);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _callProvider() async {
    final profile = _profile;
    final phone = (profile?.whatsappPhone ?? profile?.phone ?? '').trim();
    if (phone.isEmpty) return;
    final ok = await launchUrl(
      Uri(scheme: 'tel', path: phone),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر بدء الاتصال حاليًا.')));
    }
  }

  Future<void> _messageProvider() async {
    final profile = _profile;
    final auth = ref.read(authControllerProvider);
    if (profile == null || _busy || !auth.isAuthed || auth.user == null) return;
    if (auth.user!.id == profile.userId) return;
    setState(() => _busy = true);
    try {
      final raw = await ref
          .read(socialApiProvider)
          .createThread(
            profile.userId,
            kind: 'business',
            contextType: 'service_provider',
            contextId: profile.id,
          );
      final thread = SocialChatThread.fromJson(
        Map<String, dynamic>.from(raw['thread'] as Map),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SocialChatThreadScreen(
            threadId: thread.id,
            peerName: profile.businessName.trim().isNotEmpty
                ? profile.businessName.trim()
                : (thread.peer.username?.trim().isNotEmpty == true
                      ? '@${thread.peer.username!}'
                      : thread.peer.fullName),
            peerPhone: thread.peerPhone,
            peerUserId: profile.userId,
            peerImageUrl: (profile.logoUrl ?? '').trim().isNotEmpty
                ? profile.logoUrl
                : thread.peer.imageUrl,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(error, fallback: 'تعذر فتح المحادثة مع مقدم الخدمة.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicesSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.services, displayName: 'الخدمات');
    if (servicesSection.isBlocked) {
      return SectionUnavailableScreen(entry: servicesSection);
    }
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('مقدم الخدمة')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'تعذر تحميل الصفحة\n${_error ?? ''}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _load,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final profile = _profile!;
    final auth = ref.watch(authControllerProvider);
    final canMessage =
        auth.isAuthed && auth.user != null && auth.user!.id != profile.userId;
    final hasPhone = (profile.whatsappPhone ?? profile.phone ?? '')
        .trim()
        .isNotEmpty;
    final location = [
      profile.city,
      profile.area,
    ].whereType<String>().where((e) => e.trim().isNotEmpty).join(' - ');

    return Scaffold(
      appBar: AppBar(title: const Text('صفحة مقدم الخدمة')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              height: 180,
              color: Colors.black12,
              child: (profile.coverImageUrl ?? '').trim().isEmpty
                  ? const Icon(Icons.image_outlined, size: 46)
                  : Image.network(
                      profile.coverImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined, size: 46),
                    ),
            ),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: Colors.white,
                      backgroundImage: (profile.logoUrl ?? '').trim().isNotEmpty
                          ? NetworkImage(profile.logoUrl!)
                          : null,
                      child: (profile.logoUrl ?? '').trim().isEmpty
                          ? const Icon(Icons.business_center_rounded, size: 32)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.businessName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if ((profile.mainCategoryName ?? '')
                              .trim()
                              .isNotEmpty)
                            Text(
                              profile.mainCategoryName!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((profile.bio ?? '').trim().isNotEmpty) Text(profile.bio!),
                  const SizedBox(height: 10),
                  if (canMessage || hasPhone)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (canMessage)
                          FilledButton.icon(
                            onPressed: _busy ? null : _messageProvider,
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: const Text('مراسلة مقدم الخدمة'),
                          ),
                        if (hasPhone)
                          OutlinedButton.icon(
                            onPressed: _callProvider,
                            icon: const Icon(Icons.call_outlined),
                            label: const Text('اتصال'),
                          ),
                      ],
                    ),
                  if (canMessage || hasPhone) const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metaChip(
                        context,
                        Icons.star_rounded,
                        '${profile.ratingAvg.toStringAsFixed(1)} (${profile.ratingCount})',
                      ),
                      _metaChip(
                        context,
                        Icons.task_alt_rounded,
                        '${profile.completedOrdersCount} خدمة منجزة',
                      ),
                      if (location.isNotEmpty)
                        _metaChip(
                          context,
                          Icons.location_on_outlined,
                          location,
                        ),
                      if (profile.hasEmergencyService)
                        _metaChip(
                          context,
                          Icons.emergency_rounded,
                          'خدمة طوارئ',
                        ),
                      if (profile.servesAtHome)
                        _metaChip(context, Icons.home_outlined, 'خدمة منزلية'),
                      if ((profile.averageResponseMinutes ?? 0) > 0)
                        _metaChip(
                          context,
                          Icons.timer_outlined,
                          'رد خلال ${profile.averageResponseMinutes} دقيقة',
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (profile.activePromotions.isNotEmpty) ...[
                    const Text(
                      'العروض',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...profile.activePromotions.map(
                      (promo) => Card(
                        color: Colors.orange.withValues(alpha: 0.12),
                        child: ListTile(
                          leading: const Icon(Icons.local_offer_rounded),
                          title: Text(promo.title),
                          subtitle: Text(promo.description ?? ''),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const Text(
                    'الخدمات',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  if (profile.offerings.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('لا توجد خدمات منشورة حاليًا.'),
                      ),
                    ),
                  ...profile.offerings.map(
                    (offering) => Card(
                      child: ListTile(
                        title: Text(offering.name),
                        subtitle: Text(
                          offering.displayPriceText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ServiceOfferingDetailsScreen(
                                offeringId: offering.id,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'أعمالي',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  if (profile.portfolio.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('لا توجد أعمال مضافة بعد.'),
                      ),
                    ),
                  if (profile.portfolio.isNotEmpty)
                    SizedBox(
                      height: 122,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: profile.portfolio.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final item = profile.portfolio[index];
                          final url = '${item['mediaUrl'] ?? ''}'.trim();
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 160,
                              color: Colors.black12,
                              child: url.isEmpty
                                  ? const Icon(
                                      Icons.image_not_supported_outlined,
                                    )
                                  : Image.network(
                                      url,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.broken_image_outlined,
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'التقييمات',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  if (profile.reviews.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('لا توجد تقييمات بعد.'),
                      ),
                    ),
                  ...profile.reviews
                      .take(8)
                      .map(
                        (review) => Card(
                          child: ListTile(
                            title: Text(review.customerFullName ?? 'عميل'),
                            subtitle: Text(review.comment ?? ''),
                            trailing: Text('${review.rating} ★'),
                          ),
                        ),
                      ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.black.withValues(alpha: 0.05),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
