import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_guard.dart';
import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../merchants/utils/catalog_taxonomy.dart';
import '../creator/creator_adapters.dart';
import '../creator/creator_models.dart';
import '../creator/social_camera_creator_screen.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_post_composer_screen.dart';
import 'widgets/social_mention_composer_field.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

Future<bool?> showSocialCreatePostSheet(BuildContext context) async {
  if (!await requireAuthBeforeAction(
    context,
    featureArabic: 'إنشاء منشور أو ريل',
    featureEnglish: 'creating a post or reel',
  )) {
    return null;
  }
  if (!context.mounted) return null;
  final selection = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _CreatePostModePickerSheet(),
  );
  if (selection == null || !context.mounted) return null;
  if (selection == 'merchant_review') {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const SocialCreatePostSheet(reviewOnly: true),
    );
  }
  return showSocialPostComposerScreen(context, initialKind: selection);
}

class SocialCreatePostSheet extends ConsumerStatefulWidget {
  final bool reviewOnly;

  const SocialCreatePostSheet({super.key, this.reviewOnly = false});

  @override
  ConsumerState<SocialCreatePostSheet> createState() =>
      _SocialCreatePostSheetState();
}

class _SocialCreatePostSheetState extends ConsumerState<SocialCreatePostSheet> {
  final SocialMentionComposerController _captionCtrl =
      SocialMentionComposerController();
  final TextEditingController _merchantSearchCtrl = TextEditingController();
  Timer? _searchTimer;

  String _postKind = 'text';
  LocalMediaFile? _media;
  Map<String, dynamic>? _reelStyle;
  bool _publishing = false;
  bool _loadingMerchants = false;
  List<SocialMerchantOption> _merchantOptions = const [];
  SocialMerchantOption? _selectedMerchant;
  int _reviewRating = 5;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.reviewOnly) {
      _postKind = 'merchant_review';
      unawaited(_loadMerchants(_merchantSearchCtrl.text));
    }
    _merchantSearchCtrl.addListener(_onMerchantSearchChanged);
  }

  void _onMerchantSearchChanged() {
    if (_postKind != 'merchant_review') return;
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 320), () {
      _loadMerchants(_merchantSearchCtrl.text);
    });
  }

  Future<void> _loadMerchants(String query) async {
    setState(() => _loadingMerchants = true);
    try {
      final out = await ref
          .read(socialApiProvider)
          .listMerchants(search: query.trim(), limit: 220);
      final raw = List<dynamic>.from(out['merchants'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        _merchantOptions = raw
            .map(
              (e) => SocialMerchantOption.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(growable: false);
        _loadingMerchants = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMerchants = false);
    }
  }

  void _setPostKind(String kind) {
    setState(() => _postKind = kind);
    if (kind == 'merchant_review') {
      _loadMerchants(_merchantSearchCtrl.text);
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _captionCtrl.dispose();
    _merchantSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'نشر صورة أو فيديو',
      featureEnglish: 'publishing a photo or video',
    )) {
      return;
    }
    final file = await pickGalleryMediaFromDevice();
    if (!mounted) return;
    if (file == null) return;
    setState(() {
      _media = file;
      _postKind = file.isVideo ? 'reel' : 'image';
      if (!file.isVideo) {
        _reelStyle = null;
      }
    });
  }

  Future<void> _captureReel() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'إنشاء ريل',
      featureEnglish: 'creating a reel',
    )) {
      return;
    }
    if (!mounted) return;
    final creatorDraft = await showSocialCameraCreator(
      context,
      mode: SocialCreatorMode.reel,
    );
    if (!mounted || creatorDraft == null) return;
    setState(() {
      _media = buildReelMediaFromCreator(creatorDraft);
      _reelStyle = buildReelStyleFromCreator(creatorDraft);
      _postKind = 'reel';
    });
  }

  Future<void> _publish() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'نشر محتوى اجتماعي',
      featureEnglish: 'publishing social content',
    )) {
      return;
    }
    if (!mounted) return;
    final l10n = context.l10n;
    if (_publishing) return;
    final caption = _captionCtrl.buildMarkedText().trim();

    if (_postKind == 'text' && caption.isEmpty) {
      setState(() {
        _error = l10n.socialCreatePostErrorTextRequired;
      });
      return;
    }
    if ((_postKind == 'image' || _postKind == 'reel') && _media == null) {
      setState(() {
        _error = l10n.socialCreatePostErrorMediaRequired;
      });
      return;
    }
    if (_postKind == 'merchant_review' && _selectedMerchant == null) {
      setState(() {
        _error = l10n.socialCreatePostErrorMerchantRequired;
      });
      return;
    }
    if (_postKind == 'merchant_review' &&
        _selectedMerchant?.canReview != true) {
      setState(() {
        _error =
            _selectedMerchant?.eligibilityReason ??
            l10n.socialCreatePostReviewEligibilityFallback;
      });
      return;
    }

    setState(() {
      _publishing = true;
      _error = null;
    });
    await ref
        .read(socialControllerProvider.notifier)
        .createPost(
          caption: caption,
          postKind: _postKind,
          merchantId: _selectedMerchant?.id,
          reviewRating: _postKind == 'merchant_review' ? _reviewRating : null,
          mediaFile: _media,
          reelStyle: _postKind == 'reel' ? _reelStyle : null,
        );
    if (!mounted) return;
    final err = ref.read(socialControllerProvider).error;
    if (err != null && err.trim().isNotEmpty) {
      setState(() {
        _publishing = false;
        _error = err;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.only(bottom: keyboard),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                l10n.socialCreatePostTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              if (!widget.reviewOnly) ...[
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PostModeChip(
                      selected: _postKind == 'merchant_review',
                      label: l10n.socialCreatePostModeStoreReview,
                      icon: Icons.rate_review_outlined,
                      onTap: () => _setPostKind('merchant_review'),
                    ),
                    _PostModeChip(
                      selected: _postKind == 'reel',
                      label: l10n.socialCreatePostModeReel,
                      icon: Icons.ondemand_video_rounded,
                      onTap: () => _setPostKind('reel'),
                    ),
                    _PostModeChip(
                      selected: _postKind == 'image',
                      label: l10n.socialCreatePostModePhoto,
                      icon: Icons.image_outlined,
                      onTap: () => _setPostKind('image'),
                    ),
                    _PostModeChip(
                      selected: _postKind == 'text',
                      label: l10n.socialCreatePostModeText,
                      icon: Icons.text_fields_rounded,
                      onTap: () => _setPostKind('text'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              SocialMentionComposerField(
                controller: _captionCtrl,
                minLines: 3,
                maxLines: 7,
                hintText: _postKind == 'merchant_review'
                    ? l10n.socialCreatePostReviewHint
                    : l10n.socialCreatePostShareHint,
              ),
              if (_postKind == 'image' || _postKind == 'reel') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_media != null) Expanded(child: Text(_media!.name)),
                    OutlinedButton.icon(
                      onPressed: _pickMedia,
                      icon: const Icon(Icons.attach_file_rounded),
                      label: Text(
                        _media == null
                            ? l10n.socialCreatePostChooseFile
                            : l10n.socialCreatePostReplaceFile,
                      ),
                    ),
                    if (_postKind == 'reel') ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _captureReel,
                        icon: const Icon(Icons.videocam_rounded),
                        label: Text(l10n.socialCreatorUseCamera),
                      ),
                    ],
                  ],
                ),
              ],
              if (_postKind == 'merchant_review') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _merchantSearchCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.socialCreatePostMerchantSearchLabel,
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                if (_loadingMerchants)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                const SizedBox(height: 8),
                Container(
                  height: 186,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: _merchantOptions.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              _loadingMerchants
                                  ? l10n.socialCreatePostLoadingMerchants
                                  : l10n.socialCreatePostNoMatchingMerchants,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _merchantOptions.length,
                          itemBuilder: (context, index) {
                            final merchant = _merchantOptions[index];
                            final selected =
                                _selectedMerchant?.id == merchant.id;
                            return ListTile(
                              dense: true,
                              enabled: merchant.canReview,
                              onTap: merchant.canReview
                                  ? () => setState(
                                      () => _selectedMerchant = merchant,
                                    )
                                  : null,
                              leading: (merchant.imageUrl ?? '').trim().isEmpty
                                  ? const CircleAvatar(
                                      radius: 16,
                                      child: Icon(
                                        Icons.storefront_rounded,
                                        size: 16,
                                      ),
                                    )
                                  : CircleAvatar(
                                      radius: 16,
                                      backgroundImage: AppCachedImageProvider(
                                        merchant.imageUrl!,
                                      ),
                                    ),
                              title: Text(
                                merchant.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  merchantScopeTag(
                                    merchantType: merchant.type,
                                    activityType: merchant.activityType,
                                  ),
                                  if ((merchant.eligibilityLabel ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    merchant.eligibilityLabel!.trim(),
                                ].join(' • '),
                              ),
                              trailing: selected
                                  ? const Icon(Icons.check_circle_rounded)
                                  : null,
                            );
                          },
                        ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: List.generate(
                    5,
                    (index) => IconButton(
                      onPressed: () =>
                          setState(() => _reviewRating = index + 1),
                      icon: Icon(
                        index < _reviewRating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _publishing ? null : _publish,
                  icon: _publishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.publish_rounded),
                  label: Text(l10n.socialCreatePostSubmitNow),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreatePostModePickerSheet extends StatelessWidget {
  const _CreatePostModePickerSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CreatePostModeTile(
              icon: Icons.text_fields_rounded,
              title: l10n.socialCreatePostModeText,
              subtitle: l10n.socialCreatePostShareHint,
              value: 'text',
            ),
            _CreatePostModeTile(
              icon: Icons.collections_outlined,
              title: l10n.socialCreatePostModePhoto,
              subtitle: 'Open full-screen editor for photos',
              value: 'image',
            ),
            const _CreatePostModeTile(
              icon: Icons.movie_creation_outlined,
              title: 'Video',
              subtitle: 'Open full-screen editor for videos',
              value: 'video',
            ),
            _CreatePostModeTile(
              icon: Icons.ondemand_video_rounded,
              title: l10n.socialCreatePostModeReel,
              subtitle: l10n.socialCreatorUseCamera,
              value: 'reel',
            ),
            _CreatePostModeTile(
              icon: Icons.rate_review_outlined,
              title: l10n.socialCreatePostModeStoreReview,
              subtitle: l10n.socialCreatePostReviewHint,
              value: 'merchant_review',
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatePostModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;

  const _CreatePostModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

class _PostModeChip extends StatelessWidget {
  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PostModeChip({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text(label), const SizedBox(width: 6), Icon(icon, size: 16)],
      ),
    );
  }
}
