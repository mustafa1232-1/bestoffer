import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_core/local_media_file.dart';
import 'package:core_design_system/core_design_system.dart'
    show showMaslakiBottomSheet;

import '../../../core/auth/auth_guard.dart';
import '../../../core/i18n/locale_text.dart';
import '../../auth/state/auth_controller.dart';
import '../../orders/models/order_item_model.dart';
import '../../orders/models/order_model.dart';
import '../../orders/state/orders_controller.dart';
import '../../social/state/social_controller.dart';
import '../../social/models/social_story_document.dart';
import '../capabilities/social_capabilities_controller.dart';
import '../capabilities/story_scope_error.dart';
import '../pickers/social_media_picker_v3.dart';
import 'story_media_type_picker.dart';
import '../upload/dio_tus_transport.dart';
import '../upload/reel_map_normalizer.dart';
import '../upload/reel_upload_api_impl.dart';
import '../upload/tus_upload_client.dart';
import 'post_composer_v3.dart';
import 'reel_composer_state.dart';
import 'reel_composer_v3.dart';
import 'reel_video_edits.dart';
import 'story_composer_source.dart';
import 'story_composer_v3.dart';
import '../../social/state/social_story_draft_controller.dart';

const int kMaxReelDurationMs = reelMaximumDurationMs;
int _reelIdempotencyCounter = 0;

String createReelIdempotencyKey(PickedSocialMedia video) {
  final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  _reelIdempotencyCounter = (_reelIdempotencyCounter + 1) & 0x7fffffff;
  return 'reel-$timestamp-$_reelIdempotencyCounter-${video.sizeBytes ?? 0}-${video.name.hashCode}';
}

String? validatePickedReelVideo(PickedSocialMedia video) {
  if (!video.isVideo) {
    return 'اختر فيديو فقط لإنشاء الريل.';
  }
  final mime = (video.mimeType ?? '').trim().toLowerCase();
  final inferred = inferMediaTypeFromNameOrMime(
    name: video.name,
    mimeType: mime.isEmpty ? null : mime,
  );
  if (mime.isNotEmpty && !mime.startsWith('video/')) {
    return 'صيغة الملف المختار ليست فيديو.';
  }
  if (inferred != PickedMediaType.video) {
    return 'صيغة الفيديو غير مدعومة.';
  }
  final size = video.sizeBytes;
  if (size == null || size <= 0) {
    return 'تعذر قراءة حجم الفيديو. اختر فيديو آخر.';
  }
  final duration = video.durationMs;
  if (duration != null && duration > kMaxReelDurationMs) {
    return 'مدة الفيديو أطول من الحد المسموح.';
  }
  return null;
}

void _showReelPickerMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

/// Builds a **production** [ReelComposerController] — real HTTP API + real tus
/// transport, no fakes. Reads providers from [context] via the enclosing
/// [ProviderScope], so any BuildContext (including a modal sheet) can call it.
ReelComposerController buildProductionReelComposerController(
  BuildContext context, {
  required String videoPath,
  required String idempotencyKey,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final dio = container.read(dioClientProvider).dio;
  return ReelComposerController(
    api: ReelUploadApiImpl(dio),
    idempotencyKey: idempotencyKey,
    tusFactory:
        ({
          required uploadUrl,
          required totalBytes,
          required assetId,
          required video,
        }) {
          return TusUploadClient(
            transport: DioTusTransport(filePath: video.path),
            uploadUrl: uploadUrl,
            totalBytes: totalBytes,
            assetId: assetId,
          );
        },
  );
}

/// Live "Create Reel" (§1): native **video-only** gallery → V3 editor.
Future<void> openReelComposerV3(
  BuildContext context, {
  SocialMediaPickerV3? picker,
  void Function(int reelId)? onPublished,
}) async {
  if (!await requireAuthBeforeAction(
    context,
    featureArabic: 'إنشاء ريل',
    featureEnglish: 'creating a reel',
  )) {
    return;
  }
  final p = picker ?? SocialMediaPickerV3();
  final PickedSocialMedia? video;
  try {
    video = await p.pickReelVideo();
  } on SocialPickerException {
    if (!context.mounted) return;
    _showReelPickerMessage(
      context,
      'تعذر فتح معرض الفيديو. تحقق من صلاحية الصور والفيديو وحاول مجدداً.',
    );
    return;
  } catch (_) {
    if (!context.mounted) return;
    _showReelPickerMessage(
      context,
      'تعذر فتح معرض الفيديو. تحقق من صلاحية الصور والفيديو وحاول مجدداً.',
    );
    return;
  }
  final selectedVideo = video;
  if (selectedVideo == null || !context.mounted) return;
  final validationError = validatePickedReelVideo(selectedVideo);
  if (validationError != null) {
    _showReelPickerMessage(context, validationError);
    return;
  }
  final controller = buildProductionReelComposerController(
    context,
    videoPath: selectedVideo.path,
    idempotencyKey: createReelIdempotencyKey(selectedVideo),
  );
  try {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReelComposerV3(
          video: selectedVideo,
          controller: controller,
          onPublished: onPublished,
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

/// Live "Create Story": native gallery → V3 story composer, publishing via the
/// existing `createStory` controller with the (backend-validated) scope.
Future<void> openStoryComposerV3FromGallery(
  BuildContext context, {
  SocialMediaPickerV3? picker,
  StoryComposerScope scope = StoryComposerScope.global,
  bool audienceScopeSupported = false,
}) async {
  final p = picker ?? SocialMediaPickerV3();
  final type = await pickStoryMediaType(context);
  if (type == null || !context.mounted) return;
  final media = type == PickedMediaType.video
      ? await p.pickStoryVideo()
      : await p.pickStoryImage();
  if (media == null || !context.mounted) return;
  final local = LocalStoryMedia(
    path: media.path,
    isVideo: media.isVideo,
    width: media.width,
    height: media.height,
    name: media.name,
    mimeType: media.mimeType,
  );
  final source = media.isVideo
      ? StoryComposerSource.localVideo(local)
      : StoryComposerSource.localImage(local);
  final container = ProviderScope.containerOf(context, listen: false);
  await Navigator.of(context).push(
    StoryComposerV3.route(
      source,
      scope: scope,
      audienceScopeSupported: audienceScopeSupported,
      onPublish: (caption, publishScope) =>
          _publishStoryDraft(container, caption: caption, scope: publishScope),
    ),
  );
}

/// Live scoped-community story (§2/§3): consults the authoritative backend
/// capability first. When scoped stories are not yet supported, it informs the
/// user and opens a **global** story instead — never implying restricted
/// visibility, and never sending a scoped request the backend would reject.
Future<void> openStoryComposerV3Scoped(
  BuildContext context, {
  required String scopeType,
  required String scopeCode,
  String? label,
  bool official = false,
  SocialMediaPickerV3? picker,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  await container.read(socialCapabilitiesProvider.notifier).ensureFresh();
  final caps = container.read(socialCapabilitiesProvider);

  if (!caps.storyAudienceScope.supportsType(scopeType)) {
    if (!context.mounted) return;
    // Explicit confirmation (§3) — never silently redirect a scoped intent into
    // a global publish. Default action is Cancel.
    final createGlobal = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('القصص المخصصة غير متاحة حالياً'),
        content: const Text(
          'ميزة نشر قصة خاصة بسكان البناية ستتوفر قريباً. لن يتم نشر قصتك بشكل '
          'عام دون موافقتك.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('إنشاء قصة عامة'),
          ),
        ],
      ),
    );
    if (createGlobal != true || !context.mounted) return; // default: Cancel
    await openStoryComposerV3FromGallery(context, picker: picker);
    return;
  }

  if (!context.mounted) return;
  await openStoryComposerV3FromGallery(
    context,
    picker: picker,
    audienceScopeSupported: true,
    scope: StoryComposerScope(
      scope: StoryAudienceScopeX.fromWire(scopeType),
      scopeCode: scopeCode,
      label: label,
      isOfficial: official,
      locked: true,
    ),
  );
}

Future<bool> _publishStoryDraft(
  ProviderContainer container, {
  required String caption,
  required StoryComposerScope scope,
}) async {
  final draft = container.read(socialStoryDraftControllerProvider).draft;
  final mediaFile = draft.buildLocalMediaFile();
  final storyStyle = normalizeReelMap(
    draft.toStoryStyleJson(),
    'INVALID_REEL_STORY_STYLE',
  );
  final publishCaption = caption.trim().isNotEmpty
      ? caption.trim()
      : draft.caption.trim();

  if (scope.scope == StoryAudienceScope.global) {
    await container
        .read(socialControllerProvider.notifier)
        .createStory(
          caption: publishCaption,
          mediaFile: mediaFile,
          storyStyle: storyStyle,
        );
    final err = container.read(socialControllerProvider).error;
    final ok = err == null || err.trim().isEmpty;
    if (ok) {
      await container
          .read(socialStoryDraftControllerProvider.notifier)
          .clearPersistedDraft();
    }
    return ok;
  }

  // Non-global (capability-gated). Call the API directly so we can handle the
  // backend 409 STORY_AUDIENCE_SCOPE_NOT_AVAILABLE. This is the real production
  // call site for markStoryScopeUnsupported().
  try {
    await container
        .read(socialApiProvider)
        .createStory(
          caption: publishCaption,
          mediaFile: mediaFile,
          storyStyle: storyStyle,
          audienceScopeType: scope.scope.wireType,
          audienceScopeCode: scope.scopeCode,
        );
    await container.read(socialControllerProvider.notifier).loadStories();
    await container
        .read(socialStoryDraftControllerProvider.notifier)
        .clearPersistedDraft();
    return true;
  } catch (error) {
    if (isStoryScopeUnavailableError(error)) {
      // Draft preserved (composer stays open); capability drops to fail-closed;
      // do NOT retry as global.
      container
          .read(socialCapabilitiesProvider.notifier)
          .markStoryScopeUnsupported();
    }
    return false;
  }
}

/// Live "Create text Story": V3 story composer in text mode.
Future<void> openStoryComposerV3Text(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final notifier = container.read(socialStoryDraftControllerProvider.notifier);
  SocialStoryDraft? restored;
  try {
    restored = await notifier.restoreLastDraft();
  } catch (_) {
    restored = null;
  }
  final source = restored == null
      ? StoryComposerSource.text('')
      : StoryComposerSource.restoredDraft(restored);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    StoryComposerV3.route(
      source,
      onPublish: (caption, scope) =>
          _publishStoryDraft(container, caption: caption, scope: scope),
    ),
  );
}

/// Live "Add Reel to Story" (§5): reel is the full-canvas base media.
Future<void> openStoryComposerV3WithReel(
  BuildContext context, {
  required SharedReelSource reel,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return Navigator.of(context).push(
    StoryComposerV3.route(
      StoryComposerSource.sharedReel(reel),
      onPublish: (caption, scope) =>
          _publishStoryDraft(container, caption: caption, scope: scope),
    ),
  );
}

/// Live merchant review (§3): opens the V3 post composer in review mode with
/// the merchant preselected. Publishes via `createPost(postKind:merchant_review)`
/// — the backend validates the merchant, rating, and verified-purchase state.
Future<bool?> openPostComposerV3Review(
  BuildContext context, {
  required MerchantReviewDraft review,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => PostComposerV3(
        initialMedia: const [],
        mode: PostComposerMode.merchantReview,
        review: review,
        onPublish: (result) async {
          await container
              .read(socialControllerProvider.notifier)
              .createPost(
                caption: result.caption,
                postKind: 'merchant_review',
                merchantId: result.review?.merchantId,
                reviewRating: result.rating,
                orderId: result.review?.orderId,
                productId: result.review?.productId,
                linkTargetType: result.review?.productId == null
                    ? null
                    : 'product',
                linkMerchantId: result.review?.merchantId,
                linkProductId: result.review?.productId,
              );
          final err = container.read(socialControllerProvider).error;
          return err == null || err.trim().isEmpty;
        },
      ),
    ),
  );
}

/// Opens a real store picker, then starts the V3 merchant-review composer.
Future<bool?> openPostComposerV3MerchantReview(BuildContext context) async {
  if (!await requireAuthBeforeAction(
    context,
    featureArabic: 'نشر مراجعة متجر موثقة',
    featureEnglish: 'creating a store review',
  )) {
    return null;
  }
  if (!context.mounted) return null;

  final review = await _pickCompletedOrderForReview(context);
  if (review == null || !context.mounted) return null;
  return openPostComposerV3Review(context, review: review);
}

Future<MerchantReviewDraft?> _pickCompletedOrderForReview(
  BuildContext context,
) {
  return showMaslakiBottomSheet<MerchantReviewDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.82,
      child: _MerchantReviewPickerSheet(),
    ),
  );
}

class _MerchantReviewPickerSheet extends ConsumerStatefulWidget {
  const _MerchantReviewPickerSheet();

  @override
  ConsumerState<_MerchantReviewPickerSheet> createState() =>
      _MerchantReviewPickerSheetState();
}

class _MerchantReviewPickerSheetState
    extends ConsumerState<_MerchantReviewPickerSheet> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<_ReviewableOrder> _orders = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadOrders);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = _search.text.trim().toLowerCase();
      final raw = await ref.read(ordersApiProvider).listMyOrders(limit: 120);
      final orders = raw
          .whereType<Map>()
          .map((item) => OrderModel.fromJson(Map<String, dynamic>.from(item)))
          .where(_isReviewableOrder)
          .where((order) {
            if (query.isEmpty) return true;
            return order.merchantName.toLowerCase().contains(query) ||
                order.items.any(
                  (item) => item.productName.toLowerCase().contains(query),
                ) ||
                order.id.toString().contains(query);
          })
          .map(_ReviewableOrder.fromOrder)
          .where((entry) => entry.merchantId > 0)
          .take(80)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.lt(
          ar: 'تعذر تحميل طلباتك السابقة. حاول مرة أخرى.',
          en: 'Could not load your past orders. Please try again.',
        );
      });
    }
  }

  bool _isReviewableOrder(OrderModel order) {
    final status = order.status.trim().toLowerCase();
    return order.merchantId > 0 &&
        const {'delivered', 'completed'}.contains(status);
  }

  Future<void> _selectOrder(_ReviewableOrder order) async {
    if (order.products.isEmpty) {
      _finishSelection(order);
      return;
    }
    final choice = await showMaslakiBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            ListTile(
              leading: const Icon(Icons.storefront_rounded),
              title: Text(
                context.lt(ar: 'مراجعة المتجر فقط', en: 'Review store only'),
              ),
              subtitle: Text(
                context.lt(
                  ar: 'بدون ربط المراجعة بمنتج محدد.',
                  en: 'Do not attach a specific product.',
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop('store'),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                context.lt(
                  ar: 'أو اختر منتجًا من نفس الطلب',
                  en: 'Or choose a product from this order',
                ),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final product in order.products)
              ListTile(
                leading: const Icon(Icons.inventory_2_rounded),
                title: Text(product.name),
                subtitle: Text(
                  context.lt(
                    ar: 'الكمية: ${product.quantity}',
                    en: 'Quantity: ${product.quantity}',
                  ),
                ),
                onTap: () => Navigator.of(sheetContext).pop(product),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == null) return;
    final product = choice is _ReviewableProduct ? choice : null;
    _finishSelection(order, product: product);
  }

  void _finishSelection(_ReviewableOrder order, {_ReviewableProduct? product}) {
    Navigator.of(context).pop(
      MerchantReviewDraft(
        merchantId: order.merchantId,
        merchantName: order.merchantName,
        orderId: order.orderId,
        productId: product?.productId,
        productName: product?.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: context.appTextDirection,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 0, 18, 16 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.lt(
                ar: 'اختر طلبًا مكتملًا للمراجعة',
                en: 'Choose a completed order',
              ),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              context.lt(
                ar: 'تستطيع مراجعة متجر طلبت منه سابقًا فقط. اختيار منتج من نفس الطلب اختياري.',
                en: 'You can review stores you ordered from. Choosing a product from that order is optional.',
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loadOrders(),
              decoration: InputDecoration(
                hintText: context.lt(
                  ar: 'ابحث باسم المتجر...',
                  en: 'Search store, product, or order...',
                ),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: context.lt(ar: 'بحث', en: 'Search'),
                  onPressed: _loading ? null : _loadOrders,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) ...[
              const SizedBox(height: 10),
              _ReviewPickerMessage(
                icon: Icons.wifi_off_rounded,
                message: _error!,
                actionLabel: context.lt(ar: 'إعادة المحاولة', en: 'Retry'),
                onAction: _loadOrders,
              ),
            ],
            const SizedBox(height: 8),
            Expanded(child: _buildOrderList(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderList(BuildContext context) {
    if (_loading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_orders.isEmpty && _error == null) {
      return _ReviewPickerMessage(
        icon: Icons.storefront_rounded,
        message: context.lt(
          ar: 'لا توجد طلبات مكتملة مؤهلة للمراجعة.',
          en: 'No completed orders are eligible for review yet.',
        ),
        actionLabel: context.lt(ar: 'عرض كل الطلبات', en: 'Show all orders'),
        onAction: () {
          _search.clear();
          _loadOrders();
        },
      );
    }
    return ListView.separated(
      itemCount: _orders.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final order = _orders[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          leading: const _ReviewOrderAvatar(),
          title: Text(
            order.merchantName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            _orderReviewSubtitle(context, order),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _selectOrder(order),
        );
      },
    );
  }
}

class _ReviewOrderAvatar extends StatelessWidget {
  const _ReviewOrderAvatar();
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 52,
        height: 52,
        child: ColoredBox(
          color: colors.primaryContainer,
          child: Icon(
            Icons.receipt_long_rounded,
            color: colors.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _ReviewPickerMessage extends StatelessWidget {
  const _ReviewPickerMessage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.primary, size: 34),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

String _orderReviewSubtitle(BuildContext context, _ReviewableOrder order) {
  final parts = <String>[];
  parts.add(
    context.lt(ar: 'طلب #${order.orderId}', en: 'Order #${order.orderId}'),
  );
  if (order.products.isNotEmpty) {
    parts.add(
      context.lt(
        ar: '${order.products.length} منتج قابل للربط',
        en: '${order.products.length} products available',
      ),
    );
  }
  return parts.join(' - ');
}

class _ReviewableOrder {
  const _ReviewableOrder({
    required this.orderId,
    required this.merchantId,
    required this.merchantName,
    required this.products,
  });

  final int orderId;
  final int merchantId;
  final String merchantName;
  final List<_ReviewableProduct> products;

  factory _ReviewableOrder.fromOrder(OrderModel order) {
    final seen = <int>{};
    final products = <_ReviewableProduct>[];
    for (final item in order.items) {
      final productId = item.productId;
      if (productId == null || productId <= 0 || seen.contains(productId)) {
        continue;
      }
      seen.add(productId);
      products.add(_ReviewableProduct.fromItem(item));
    }
    return _ReviewableOrder(
      orderId: order.id,
      merchantId: order.merchantId,
      merchantName: order.merchantName,
      products: products,
    );
  }
}

class _ReviewableProduct {
  const _ReviewableProduct({
    required this.productId,
    required this.name,
    required this.quantity,
  });

  final int productId;
  final String name;
  final int quantity;

  factory _ReviewableProduct.fromItem(OrderItemModel item) {
    return _ReviewableProduct(
      productId: item.productId!,
      name: item.productName,
      quantity: item.quantity,
    );
  }
}

/// Live "Create Post" (§2): native multi-select gallery → V3 post composer.
/// Publishing goes through the existing `createPost` controller (native picker
/// paths only — never FilePicker).
Future<bool?> openPostComposerV3(
  BuildContext context, {
  SocialMediaPickerV3? picker,
}) async {
  final p = picker ?? SocialMediaPickerV3();
  final media = await p.pickMultiplePostMedia();
  if (!context.mounted) return null;
  final container = ProviderScope.containerOf(context, listen: false);
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => PostComposerV3(
        initialMedia: media,
        onAddMore: p.pickMultiplePostMedia,
        onPublish: (result) async {
          final files = result.media
              .map(
                (m) => LocalMediaFile(
                  name: m.name,
                  path: m.path,
                  bytes: null,
                  mimeType: m.mimeType,
                ),
              )
              .toList();
          await container
              .read(socialControllerProvider.notifier)
              .createPost(
                caption: result.caption,
                postKind: result.postKind,
                mediaFiles: files.isEmpty ? null : files,
                audienceScopeType: result.audience == 'public'
                    ? 'global'
                    : 'followers',
              );
          final err = container.read(socialControllerProvider).error;
          return err == null || err.trim().isEmpty;
        },
      ),
    ),
  );
}
