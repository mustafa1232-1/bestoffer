import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_guard.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_profile_screen.dart';
import 'widgets/social_identity_view.dart';
import 'widgets/social_mention_composer_field.dart';
import 'widgets/social_mention_hashtag_text.dart';
import 'widgets/social_post_card_v2.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

Future<int?> showSocialPostCommentsSheet(
  BuildContext context, {
  required SocialPost post,
  String? title,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SocialPostCommentsSheet(post: post, title: title),
  );
}

class SocialPostDetailsScreen extends ConsumerStatefulWidget {
  final int? postId;
  final SocialPost? initialPost;

  const SocialPostDetailsScreen({super.key, this.postId, this.initialPost})
    : assert(postId != null || initialPost != null);

  @override
  ConsumerState<SocialPostDetailsScreen> createState() =>
      _SocialPostDetailsScreenState();
}

class _SocialPostDetailsScreenState
    extends ConsumerState<SocialPostDetailsScreen> {
  SocialPost? _post;
  bool _loading = true;
  String? _error;

  SocialApi get _api => ref.read(socialApiProvider);
  int? get _currentUserId => ref.read(authControllerProvider).user?.id;

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (widget.initialPost != null) {
      setState(() => _loading = false);
      return;
    }
    final postId = widget.postId;
    if (postId == null || postId <= 0) {
      setState(() {
        _loading = false;
        _error = context.l10n.socialPostDetailsInvalidContent;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await _api.getPostById(postId);
      final raw = Map<String, dynamic>.from(out['post'] as Map? ?? const {});
      if (!mounted) return;
      setState(() {
        _post = SocialPost.fromJson(raw);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.socialPostDetailsLoadFailed,
        );
      });
    }
  }

  Future<void> _toggleLike() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'الإعجاب بالمنشور',
      featureEnglish: 'liking a post',
    )) {
      return;
    }
    if (!mounted) return;
    final post = _post;
    if (post == null) return;
    final out = await _api.toggleLike(post.id);
    if (!mounted) return;
    setState(() {
      _post = post.copyWith(
        likesCount:
            int.tryParse('${out['likesCount'] ?? out['likes_count']}') ??
            post.likesCount,
        isLiked: out['liked'] == true || out['isLiked'] == true,
      );
    });
  }

  Future<void> _toggleSave() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'حفظ المنشور',
      featureEnglish: 'saving a post',
    )) {
      return;
    }
    if (!mounted) return;
    final post = _post;
    if (post == null) return;
    final entityType = post.postKind == 'merchant_review'
        ? 'review'
        : post.postKind == 'reel'
        ? 'reel'
        : 'post';
    final out = await _api.toggleSaved(
      entityType: entityType,
      entityId: post.id,
    );
    if (!mounted) return;
    final isSaved = out['saved'] == true;
    setState(() {
      _post = post.copyWith(
        isSaved: isSaved,
        savesCount:
            int.tryParse('${out['savesCount'] ?? out['saves_count']}') ??
            post.savesCount,
      );
    });
  }

  Future<void> _openComments() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'التعليق على المنشور',
      featureEnglish: 'commenting on a post',
    )) {
      return;
    }
    if (!mounted) return;
    final post = _post;
    if (post == null) return;
    final nextCount = await showSocialPostCommentsSheet(
      context,
      post: post,
      title: context.l10n.socialPostDetailsPostComments,
    );
    if (!mounted || nextCount == null) return;
    setState(() {
      _post = post.copyWith(commentsCount: nextCount);
    });
  }

  void _openMerchant() {
    final post = _post;
    if (post == null) return;
    final merchantId = post.contentLink?.merchantId ?? post.merchantId;
    if (merchantId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MerchantProductsScreen(
          merchant: MerchantModel(
            id: merchantId,
            name: post.merchantName ?? context.l10n.commonMerchant,
            type: post.merchantType ?? 'market',
            imageUrl: post.merchantImageUrl,
            isOpen: true,
            hasDiscountOffer: false,
            hasFreeDeliveryOffer: false,
          ),
        ),
      ),
    );
  }

  bool get _isMine => _post != null && _post!.userId == _currentUserId;

  Future<void> _toggleArchive(bool archived) async {
    final post = _post;
    if (post == null || !_isMine) return;
    try {
      if (archived) {
        await _api.archivePost(post.id);
      } else {
        await _api.restorePost(post.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            archived
                ? context.l10n.socialProfileContentArchived
                : context.l10n.socialProfileContentRestored,
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: archived
                  ? context.l10n.socialProfileContentArchiveFailed
                  : context.l10n.socialProfileContentRestoreFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _deletePost() async {
    final post = _post;
    if (post == null || !_isMine) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.commonDelete),
        content: Text(context.l10n.socialProfileDeletePostConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deletePost(post.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.socialProfileDeletePostSuccess)),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: context.l10n.socialProfileDeletePostFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openProfile(SocialAuthor author) async {
    // Opening another member's profile requires an account — gate before nav.
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'عرض الملف الشخصي',
      featureEnglish: 'viewing a profile',
    )) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialProfileScreen(
          userId: author.id,
          initialName: author.fullName,
        ),
      ),
    );
  }

  Future<void> _reportPost() async {
    final post = _post;
    if (post == null || _isMine) return;
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'الإبلاغ عن المنشور',
      featureEnglish: 'reporting a post',
    )) {
      return;
    }
    if (!mounted) return;
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final reasons = <({String key, String label})>[
      (key: 'spam', label: isEnglish ? 'Spam or misleading' : 'مزعج أو مضلل'),
      (
        key: 'abuse',
        label: isEnglish ? 'Abuse or harassment' : 'إساءة أو مضايقة',
      ),
      (key: 'violence', label: isEnglish ? 'Violence or danger' : 'عنف أو خطر'),
      (key: 'other', label: isEnglish ? 'Other' : 'سبب آخر'),
    ];
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: reasons
              .map(
                (reason) => ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(reason.label),
                  onTap: () => Navigator.of(context).pop(reason.key),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await _api.reportPost(postId: post.id, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.socialProfileReportSubmitted)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: context.l10n.socialProfileReportSubmitFailed,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final post = _post;
    return Directionality(
      textDirection: context.appTextDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.socialPostDetailsTitle),
          actions: [
            if (post != null)
              PopupMenuButton<String>(
                onSelected: (value) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    Future<void>.delayed(const Duration(milliseconds: 220), () {
                      if (!mounted) return;
                      switch (value) {
                        case 'archive':
                          _toggleArchive(true);
                          break;
                        case 'delete':
                          _deletePost();
                          break;
                        case 'report':
                          _reportPost();
                          break;
                      }
                    });
                  });
                },
                itemBuilder: (_) => [
                  if (_isMine)
                    PopupMenuItem<String>(
                      value: 'archive',
                      child: Text(l10n.commonArchive),
                    ),
                  if (_isMine)
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(l10n.commonDelete),
                    ),
                  if (!_isMine)
                    PopupMenuItem<String>(
                      value: 'report',
                      child: Text(l10n.commonReport),
                    ),
                ],
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : post == null
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _error ?? l10n.socialPostDetailsLoadFailed,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    SocialPostCardV2(
                      post: post,
                      onOpenProfile: () => _openProfile(post.author),
                      onOpenMerchantLink: _openMerchant,
                      onToggleLike: _toggleLike,
                      onToggleSave: _toggleSave,
                      onOpenComments: _openComments,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class SocialPostCommentsSheet extends ConsumerStatefulWidget {
  final SocialPost post;
  final String? title;

  const SocialPostCommentsSheet({super.key, required this.post, this.title});

  @override
  ConsumerState<SocialPostCommentsSheet> createState() =>
      _SocialPostCommentsSheetState();
}

class _SocialPostCommentsSheetState
    extends ConsumerState<SocialPostCommentsSheet> {
  final SocialMentionComposerController _composerController =
      SocialMentionComposerController();
  List<SocialComment> _comments = const <SocialComment>[];
  bool _loading = true;
  bool _submitting = false;
  int _count = 0;
  int? _replyToCommentId;
  SocialComment? _replyToComment;

  SocialApi get _api => ref.read(socialApiProvider);
  int? get _currentUserId => ref.read(authControllerProvider).user?.id;

  @override
  void initState() {
    super.initState();
    _count = widget.post.commentsCount;
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final out = await _api.listComments(widget.post.id, limit: 80);
      final raw = List<dynamic>.from(out['comments'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        _comments = raw
            .map(
              (row) =>
                  SocialComment.fromJson(Map<String, dynamic>.from(row as Map)),
            )
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: context.l10n.socialPostDetailsCommentsLoadFailed,
            ),
          ),
        ),
      );
    }
  }

  bool _canEditComment(SocialComment comment) {
    final me = _currentUserId;
    return me != null && comment.userId == me && !comment.isDeleted;
  }

  bool _canDeleteComment(SocialComment comment) {
    final me = _currentUserId;
    if (me == null) return false;
    return comment.userId == me || widget.post.userId == me;
  }

  void _replaceComment(SocialComment next) {
    setState(() {
      _comments = _comments
          .map((comment) => comment.id == next.id ? next : comment)
          .toList(growable: false);
    });
  }

  Future<void> _send() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'إرسال تعليق',
      featureEnglish: 'sending a comment',
    )) {
      return;
    }
    if (!mounted) return;
    final body = _composerController.buildMarkedText().trim();
    if (_submitting || body.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final out = _replyToCommentId == null
          ? await _api.addComment(widget.post.id, body)
          : await _api.addCommentReply(
              postId: widget.post.id,
              parentCommentId: _replyToCommentId!,
              body: body,
            );
      final raw = out['comment'];
      if (raw is! Map || !mounted) return;
      final comment = SocialComment.fromJson(Map<String, dynamic>.from(raw));
      final nextCount = int.tryParse(
        '${out['commentsCount'] ?? out['comments_count']}',
      );
      setState(() {
        _comments = <SocialComment>[comment, ..._comments];
        _count = nextCount ?? (_count + 1);
        _replyToComment = null;
        _replyToCommentId = null;
      });
      _composerController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: context.l10n.socialPostDetailsCommentSendFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _toggleLikeComment(SocialComment comment) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'الإعجاب بالتعليق',
      featureEnglish: 'liking a comment',
    )) {
      return;
    }
    if (!mounted) return;
    try {
      final out = await _api.toggleCommentLike(
        postId: widget.post.id,
        commentId: comment.id,
      );
      final raw = out['comment'];
      if (raw is! Map || !mounted) return;
      _replaceComment(SocialComment.fromJson(Map<String, dynamic>.from(raw)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: context.l10n.socialPostDetailsLikeUpdateFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _editComment(SocialComment comment) async {
    if (!_canEditComment(comment)) return;
    final l10n = context.l10n;
    final controller = TextEditingController(text: comment.body);
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.socialPostDetailsEditCommentTitle),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: l10n.socialPostDetailsEditCommentHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    final body = controller.text.trim();
    controller.dispose();
    if (approved != true || body.isEmpty) return;
    try {
      final out = await _api.updateComment(
        postId: widget.post.id,
        commentId: comment.id,
        body: body,
      );
      final raw = out['comment'];
      if (raw is! Map || !mounted) return;
      _replaceComment(SocialComment.fromJson(Map<String, dynamic>.from(raw)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: context.l10n.socialPostDetailsEditCommentFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _deleteComment(SocialComment comment) async {
    if (!_canDeleteComment(comment)) return;
    final l10n = context.l10n;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.socialPostDetailsDeleteCommentTitle),
        content: Text(l10n.socialPostDetailsDeleteCommentMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      final out = await _api.deleteComment(
        postId: widget.post.id,
        commentId: comment.id,
      );
      final raw = out['comment'];
      if (raw is! Map || !mounted) return;
      final nextCount = int.tryParse(
        '${out['commentsCount'] ?? out['comments_count']}',
      );
      setState(() {
        _count = nextCount ?? _count;
      });
      _replaceComment(SocialComment.fromJson(Map<String, dynamic>.from(raw)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: context.l10n.socialPostDetailsDeleteCommentFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _showCommentActions(SocialComment comment) async {
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (!comment.isDeleted)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(l10n.commonReply),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() {
                    _replyToCommentId = comment.id;
                    _replyToComment = comment;
                  });
                },
              ),
            if (!comment.isDeleted)
              ListTile(
                leading: Icon(
                  comment.isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
                title: Text(
                  comment.isLiked
                      ? l10n.socialPostDetailsActionRemoveLike
                      : l10n.socialPostDetailsActionLike,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _toggleLikeComment(comment);
                },
              ),
            if (_canEditComment(comment))
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.commonEdit),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _editComment(comment);
                },
              ),
            if (_canDeleteComment(comment))
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(l10n.commonDelete),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _deleteComment(comment);
                },
              ),
          ],
        ),
      ),
    );
  }

  List<SocialComment> _childrenOf(int parentId) {
    return _comments
        .where((comment) => comment.parentCommentId == parentId)
        .toList(growable: false);
  }

  Future<void> _openProfile(SocialAuthor author) async {
    // Opening another member's profile requires an account — gate before nav.
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'عرض الملف الشخصي',
      featureEnglish: 'viewing a profile',
    )) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialProfileScreen(
          userId: author.id,
          initialName: author.fullName,
        ),
      ),
    );
  }

  Widget _buildCommentTile(SocialComment comment, {int depth = 0}) {
    final l10n = context.l10n;
    final replies = _childrenOf(comment.id);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: depth * 18.0, top: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onLongPress: () => _showCommentActions(comment),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _openProfile(comment.author),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundImage:
                            (comment.author.imageUrl ?? '').trim().isNotEmpty
                            ? AppCachedImageProvider(comment.author.imageUrl!)
                            : null,
                        child: (comment.author.imageUrl ?? '').trim().isEmpty
                            ? const Icon(Icons.person_outline, size: 18)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _openProfile(comment.author),
                            child: SocialIdentityView(
                              author: comment.author,
                              showRoleFallback: false,
                              primaryStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                              secondaryStyle: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SocialMentionHashtagText(
                            text: comment.body,
                            style: TextStyle(
                              color: scheme.onSurface,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (!comment.isDeleted)
                      InkWell(
                        onTap: () {
                          setState(() {
                            _replyToCommentId = comment.id;
                            _replyToComment = comment;
                          });
                        },
                        child: Text(
                          l10n.commonReply,
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    if (!comment.isDeleted)
                      InkWell(
                        onTap: () => _toggleLikeComment(comment),
                        child: Text(
                          comment.isLiked
                              ? l10n.socialPostDetailsActionLikedCount(
                                  comment.likesCount,
                                )
                              : l10n.socialPostDetailsActionLikeCount(
                                  comment.likesCount,
                                ),
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    if (comment.editedAt != null)
                      Text(
                        l10n.socialPostDetailsEdited,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (_canEditComment(comment))
                      InkWell(
                        onTap: () => _editComment(comment),
                        child: Text(
                          l10n.commonEdit,
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    if (_canDeleteComment(comment))
                      InkWell(
                        onTap: () => _deleteComment(comment),
                        child: Text(
                          l10n.commonDelete,
                          style: TextStyle(
                            color: scheme.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                if (replies.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final reply in replies)
                    _buildCommentTile(reply, depth: depth + 1),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _composerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rootComments = _comments
        .where((comment) => comment.parentCommentId == null)
        .toList(growable: false);
    return Directionality(
      textDirection: context.appTextDirection,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.82,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title ?? l10n.commonComments,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '$_count',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: rootComments.isEmpty
                            ? [
                                const SizedBox(height: 120),
                                Center(
                                  child: Text(l10n.socialPostDetailsNoComments),
                                ),
                              ]
                            : rootComments
                                  .map((comment) => _buildCommentTile(comment))
                                  .toList(growable: false),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    if (_replyToComment != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.socialPostDetailsReplyingTo(
                                  socialPrimaryIdentityLabel(
                                    _replyToComment!.author,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _replyToComment = null;
                                  _replyToCommentId = null;
                                });
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: SocialMentionComposerField(
                            controller: _composerController,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            hintText: l10n.socialPostDetailsComposerHint,
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _submitting ? null : _send,
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
