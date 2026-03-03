import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_chat_thread_screen.dart';
import 'social_chat_threads_screen.dart';
import 'social_profile_screen.dart';

class BasmayaFeedScreen extends ConsumerStatefulWidget {
  final int? initialThreadId;
  final int? initialPostId;
  final int? initialStoryId;

  const BasmayaFeedScreen({
    super.key,
    this.initialThreadId,
    this.initialPostId,
    this.initialStoryId,
  });

  @override
  ConsumerState<BasmayaFeedScreen> createState() => _BasmayaFeedScreenState();
}

class _BasmayaFeedScreenState extends ConsumerState<BasmayaFeedScreen> {
  final ScrollController _scrollController = ScrollController();
  final intl.DateFormat _timeFmt = intl.DateFormat('d/M hh:mm a', 'ar');
  Timer? _feedRefreshTimer;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(_bootstrap);
    _feedRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      ref.read(socialControllerProvider.notifier).refreshFeedTick();
    });
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    final notifier = ref.read(socialControllerProvider.notifier);
    await notifier.bootstrap();
    if (!mounted) return;
    if (widget.initialThreadId != null && widget.initialThreadId! > 0) {
      await _openThreadById(widget.initialThreadId!);
      return;
    }
    if (widget.initialStoryId != null && widget.initialStoryId! > 0) {
      await _openStoryById(widget.initialStoryId!);
      return;
    }
    if (widget.initialPostId != null && widget.initialPostId! > 0) {
      await notifier.ensurePostVisible(widget.initialPostId!);
      if (!mounted) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 260;
    if (_scrollController.position.pixels < threshold) return;
    ref.read(socialControllerProvider.notifier).loadMorePosts();
  }

  Future<void> _openThreadById(int id) async {
    SocialChatThread? thread;
    for (final item in ref.read(socialControllerProvider).threads) {
      if (item.id == id) {
        thread = item;
        break;
      }
    }
    if (thread == null) {
      await ref.read(socialControllerProvider.notifier).loadThreads();
      if (!mounted) return;
      for (final item in ref.read(socialControllerProvider).threads) {
        if (item.id == id) {
          thread = item;
          break;
        }
      }
    }
    if (thread == null || !mounted) return;
    final resolvedThread = thread;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialChatThreadScreen(
          threadId: resolvedThread.id,
          peerName: resolvedThread.peer.fullName,
          peerPhone: resolvedThread.peerPhone,
        ),
      ),
    );
  }

  Future<void> _openThreads() async {
    await ref.read(socialControllerProvider.notifier).loadThreads();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SocialChatThreadsScreen()),
    );
  }

  Future<void> _openCreatePost() async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CreatePostSheet(),
    );
    if (posted == true) {
      await _refreshAll();
    }
  }

  Future<void> _openCreateStory() async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CreateStorySheet(),
    );
    if (posted == true) {
      await _refreshAll();
    }
  }

  Future<void> _openComments(SocialPost post) async {
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CommentsSheet(post: post),
    );
    if (count == null) return;
    ref
        .read(socialControllerProvider.notifier)
        .patchCommentsCount(postId: post.id, commentsCount: count);
  }

  Future<void> _openStoryGroup(
    SocialStoryGroup group, {
    int? initialStoryId,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StoryViewerSheet(
        group: group,
        initialStoryId: initialStoryId,
        onStoryViewed: (storyId) => ref
            .read(socialControllerProvider.notifier)
            .markStoryViewed(storyId),
      ),
    );
  }

  Future<void> _openStoryById(int storyId) async {
    SocialStoryGroup? storyGroup;
    for (final group in ref.read(socialControllerProvider).stories) {
      if (group.stories.any((story) => story.id == storyId)) {
        storyGroup = group;
        break;
      }
    }
    if (storyGroup == null) {
      await ref.read(socialControllerProvider.notifier).loadStories();
      if (!mounted) return;
      for (final group in ref.read(socialControllerProvider).stories) {
        if (group.stories.any((story) => story.id == storyId)) {
          storyGroup = group;
          break;
        }
      }
    }
    if (storyGroup == null || !mounted) return;
    await _openStoryGroup(storyGroup, initialStoryId: storyId);
  }

  Future<void> _sharePost(SocialPost post) async {
    final text = [
      'شديصير بسماية',
      if (post.caption.trim().isNotEmpty) post.caption.trim(),
      if ((post.mediaUrl ?? '').trim().isNotEmpty) post.mediaUrl!.trim(),
    ].join('\n');
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _messageAuthor(SocialAuthor author) async {
    final me = ref.read(authControllerProvider).user?.id;
    if (me != null && me == author.id) return;
    final thread = await ref
        .read(socialControllerProvider.notifier)
        .createThreadWithUser(author.id);
    if (thread == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialChatThreadScreen(
          threadId: thread.id,
          peerName: thread.peer.fullName,
          peerPhone: thread.peerPhone,
        ),
      ),
    );
  }

  Future<void> _openAuthorProfile(SocialAuthor author) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialProfileScreen(
          userId: author.id,
          initialName: author.fullName,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _feedRefreshTimer?.cancel();
    _feedRefreshTimer = null;
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      ref.read(socialControllerProvider.notifier).loadStories(),
      ref.read(socialControllerProvider.notifier).loadPosts(refresh: true),
      ref.read(socialControllerProvider.notifier).loadThreads(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialControllerProvider);
    ref.listen<String?>(socialControllerProvider.select((s) => s.error), (
      prev,
      next,
    ) {
      if (next == null || next == prev || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next, textDirection: TextDirection.rtl)),
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('شديصير بسماية'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'المحادثات',
            onPressed: _openThreads,
            icon: const Icon(Icons.chat_bubble_outline_rounded),
          ),
          IconButton(
            tooltip: 'منشور جديد',
            onPressed: _openCreatePost,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreatePost,
        icon: const Icon(Icons.post_add_rounded),
        label: const Text('إضافة منشور'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _refreshAll();
        },
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF1B4F8A), Color(0xFF153C66)],
                ),
              ),
              child: const Text(
                'آخر أخبار وحياة بسماية: صور، ريلز، وتجارب حقيقية للمطاعم والمتاجر.',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _StoriesStrip(
              loading: state.loadingStories,
              stories: state.stories,
              onCreateStory: _openCreateStory,
              onOpenStoryGroup: (group) => _openStoryGroup(group),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                children: _filters
                    .map((f) {
                      final selected = state.activeKind == f.kind;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          selected: selected,
                          onSelected: (_) => ref
                              .read(socialControllerProvider.notifier)
                              .setActiveKind(f.kind),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(f.label),
                              const SizedBox(width: 6),
                              Icon(f.icon, size: 16),
                            ],
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 10),
            if (state.loadingPosts && state.posts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.posts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(
                  child: Text(
                    'لا يوجد محتوى بعد. ابدأ أول منشور الآن.',
                    textDirection: TextDirection.rtl,
                  ),
                ),
              )
            else
              ...state.posts.map((post) {
                final isImage =
                    (post.mediaKind == 'image' || post.postKind == 'image') &&
                    (post.mediaUrl ?? '').trim().isNotEmpty;
                final isVideo =
                    (post.mediaKind == 'video' || post.postKind == 'video') &&
                    (post.mediaUrl ?? '').trim().isNotEmpty;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            CircleAvatar(
                              backgroundImage:
                                  (post.author.imageUrl ?? '').trim().isNotEmpty
                                  ? NetworkImage(post.author.imageUrl!)
                                  : null,
                              child: (post.author.imageUrl ?? '').trim().isEmpty
                                  ? const Icon(Icons.person_outline)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: InkWell(
                                onTap: () => _openAuthorProfile(post.author),
                                borderRadius: BorderRadius.circular(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      post.author.fullName,
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      post.createdAt == null
                                          ? _kindLabel(post.postKind)
                                          : '${_kindLabel(post.postKind)} • ${_timeFmt.format(post.createdAt!.toLocal())}',
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (post.caption.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            post.caption,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (post.postKind == 'merchant_review') ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'تقييم متجر: ${post.merchantName ?? 'غير معروف'}',
                                  textDirection: TextDirection.rtl,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: List.generate(
                                    5,
                                    (i) => Icon(
                                      i < (post.reviewRating ?? 0)
                                          ? Icons.star_rounded
                                          : Icons.star_border_rounded,
                                      color: Colors.amber,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (isImage) ...[
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              if (post.isLiked) return;
                              ref
                                  .read(socialControllerProvider.notifier)
                                  .toggleLike(post);
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                post.mediaUrl!,
                                width: double.infinity,
                                height: 210,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _MediaLoadFailed(
                                      message: 'تعذر تحميل الصورة',
                                    ),
                              ),
                            ),
                          ),
                        ],
                        if (isVideo) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final uri = Uri.tryParse(post.mediaUrl!);
                              if (uri == null) return;
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            icon: const Icon(Icons.play_circle_fill_rounded),
                            label: const Text('تشغيل الريل'),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ChipAction(
                              label: 'مشاركة',
                              icon: Icons.ios_share_rounded,
                              onTap: () => _sharePost(post),
                            ),
                            _ChipAction(
                              label: 'مراسلة',
                              icon: Icons.chat_bubble_outline_rounded,
                              onTap: () => _messageAuthor(post.author),
                            ),
                            _ChipAction(
                              label: 'تعليقات ${post.commentsCount}',
                              icon: Icons.mode_comment_outlined,
                              onTap: () => _openComments(post),
                            ),
                            _ChipAction(
                              label: 'إعجاب ${post.likesCount}',
                              icon: post.isLiked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              onTap: () => ref
                                  .read(socialControllerProvider.notifier)
                                  .toggleLike(post),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            if (state.loadingMorePosts)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _CreatePostSheet extends ConsumerStatefulWidget {
  const _CreatePostSheet();

  @override
  ConsumerState<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends ConsumerState<_CreatePostSheet> {
  late final SocialApi _api;
  final TextEditingController _captionCtrl = TextEditingController();
  final TextEditingController _merchantSearchCtrl = TextEditingController();
  Timer? _searchTimer;
  String _postKind = 'text';
  LocalMediaFile? _media;
  bool _publishing = false;
  bool _loadingMerchants = false;
  List<SocialMerchantOption> _merchantOptions = const [];
  SocialMerchantOption? _selectedMerchant;
  int _reviewRating = 5;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = ref.read(socialApiProvider);
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
      final out = await _api.listMerchants(search: query.trim(), limit: 220);
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
    final file = await pickPostMediaFromDevice();
    if (file == null) return;
    setState(() {
      _media = file;
      _postKind = file.isVideo ? 'video' : 'image';
    });
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final caption = _captionCtrl.text.trim();
    if (_postKind == 'text' && caption.isEmpty) {
      setState(() => _error = 'اكتب نص المنشور أولاً.');
      return;
    }
    if ((_postKind == 'image' || _postKind == 'video') && _media == null) {
      setState(() => _error = 'اختر صورة أو فيديو أولاً.');
      return;
    }
    if (_postKind == 'merchant_review' && _selectedMerchant == null) {
      setState(() => _error = 'اختر المتجر الذي تريد تقييمه.');
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
              const Text(
                'منشور جديد',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ModeChip(
                    selected: _postKind == 'merchant_review',
                    label: 'ريفيو متجر',
                    icon: Icons.rate_review_outlined,
                    onTap: () => _setPostKind('merchant_review'),
                  ),
                  _ModeChip(
                    selected: _postKind == 'video',
                    label: 'ريلز',
                    icon: Icons.ondemand_video_rounded,
                    onTap: () => _setPostKind('video'),
                  ),
                  _ModeChip(
                    selected: _postKind == 'image',
                    label: 'صورة',
                    icon: Icons.image_outlined,
                    onTap: () => _setPostKind('image'),
                  ),
                  _ModeChip(
                    selected: _postKind == 'text',
                    label: 'نصي',
                    icon: Icons.text_fields_rounded,
                    onTap: () => _setPostKind('text'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _captionCtrl,
                textDirection: TextDirection.rtl,
                minLines: 3,
                maxLines: 7,
                decoration: InputDecoration(
                  labelText: _postKind == 'merchant_review'
                      ? 'اكتب رأيك بالتجربة...'
                      : 'شنو تحب تشارك اليوم؟',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              if (_postKind == 'image' || _postKind == 'video') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_media != null) Expanded(child: Text(_media!.name)),
                    OutlinedButton.icon(
                      onPressed: _pickMedia,
                      icon: const Icon(Icons.attach_file_rounded),
                      label: Text(
                        _media == null ? 'اختيار ملف' : 'تبديل الملف',
                      ),
                    ),
                  ],
                ),
              ],
              if (_postKind == 'merchant_review') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _merchantSearchCtrl,
                  textDirection: TextDirection.rtl,
                  decoration: InputDecoration(
                    labelText: 'ابحث عن مطعم أو متجر',
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
                SizedBox(
                  height: 170,
                  child: ListView.builder(
                    itemCount: _merchantOptions.length,
                    itemBuilder: (context, index) {
                      final merchant = _merchantOptions[index];
                      final selected = _selectedMerchant?.id == merchant.id;
                      return ListTile(
                        dense: true,
                        onTap: () =>
                            setState(() => _selectedMerchant = merchant),
                        title: Text(
                          merchant.name,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          merchant.type == 'restaurant' ? 'مطعم' : 'متجر',
                          textDirection: TextDirection.rtl,
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
                  textDirection: TextDirection.rtl,
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
                  label: const Text('نشر الآن'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeChip({
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

class _StoriesStrip extends StatelessWidget {
  final bool loading;
  final List<SocialStoryGroup> stories;
  final VoidCallback onCreateStory;
  final ValueChanged<SocialStoryGroup> onOpenStoryGroup;

  const _StoriesStrip({
    required this.loading,
    required this.stories,
    required this.onCreateStory,
    required this.onOpenStoryGroup,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        children: [
          _StoryCircleAdd(onTap: onCreateStory),
          const SizedBox(width: 8),
          if (loading && stories.isEmpty)
            const SizedBox(
              width: 68,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (stories.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 36),
              child: Text(
                'لا توجد ستوري حالياً',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          else
            ...stories.map(
              (group) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _StoryCircle(
                  group: group,
                  onTap: () => onOpenStoryGroup(group),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StoryCircleAdd extends StatelessWidget {
  final VoidCallback onTap;
  const _StoryCircleAdd({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF4CC9F0), width: 2),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'إضافة ستوري',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryCircle extends StatelessWidget {
  final SocialStoryGroup group;
  final VoidCallback onTap;

  const _StoryCircle({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasImage = (group.author.imageUrl ?? '').trim().isNotEmpty;
    final ringColor = group.hasUnviewed
        ? const Color(0xFF22D3EE)
        : Colors.white.withValues(alpha: 0.38);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ringColor, width: 2),
              ),
              child: CircleAvatar(
                backgroundImage: hasImage
                    ? NetworkImage(group.author.imageUrl!)
                    : null,
                child: hasImage
                    ? null
                    : const Icon(Icons.person_outline_rounded, size: 24),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              group.author.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateStorySheet extends ConsumerStatefulWidget {
  const _CreateStorySheet();

  @override
  ConsumerState<_CreateStorySheet> createState() => _CreateStorySheetState();
}

class _CreateStorySheetState extends ConsumerState<_CreateStorySheet> {
  final TextEditingController _captionCtrl = TextEditingController();
  static const List<Color> _storyBgPalette = <Color>[
    Color(0xFF1E3A8A),
    Color(0xFF0F766E),
    Color(0xFF7C2D12),
    Color(0xFF5B21B6),
    Color(0xFF0F172A),
    Color(0xFF14532D),
  ];
  static const List<Color> _storyTextPalette = <Color>[
    Colors.white,
    Color(0xFFFFF7ED),
    Color(0xFFE0F2FE),
    Color(0xFFFFF3C4),
    Color(0xFFF8FAFC),
    Color(0xFF111827),
  ];

  LocalMediaFile? _media;
  int _backgroundIndex = 0;
  int _textColorIndex = 0;
  String _fontFamily = 'system';
  String _fontWeight = 'bold';
  String _textAlign = 'center';
  double _fontScale = 1.2;
  bool _publishing = false;
  String? _error;

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final file = await pickPostMediaFromDevice();
    if (file == null || !mounted) return;
    setState(() => _media = file);
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final caption = _captionCtrl.text.trim();
    if (caption.isEmpty && _media == null) {
      setState(() => _error = 'أضف نصاً أو وسائط قبل النشر.');
      return;
    }
    setState(() {
      _publishing = true;
      _error = null;
    });

    await ref
        .read(socialControllerProvider.notifier)
        .createStory(
          caption: caption,
          mediaFile: _media,
          storyStyle: _currentStoryStyle(),
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
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(bottom: keyboard),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'ستوري جديدة',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  minHeight: 200,
                  maxHeight: 260,
                ),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _storyBgPalette[_backgroundIndex],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: TextField(
                    controller: _captionCtrl,
                    minLines: 2,
                    maxLines: 6,
                    textDirection: TextDirection.rtl,
                    textAlign: _toTextAlign(_textAlign),
                    style: _storyTextStyle(_storyTextPalette[_textColorIndex]),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'اكتب ستوريك هنا...',
                      hintStyle: _storyTextStyle(
                        _storyTextPalette[_textColorIndex].withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _StoryStyleSection(
                title: 'الخلفية',
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: List<Widget>.generate(_storyBgPalette.length, (
                    index,
                  ) {
                    final selected = _backgroundIndex == index;
                    return _ColorChip(
                      color: _storyBgPalette[index],
                      selected: selected,
                      onTap: () => setState(() => _backgroundIndex = index),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 8),
              _StoryStyleSection(
                title: 'لون الخط',
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: List<Widget>.generate(
                    _storyTextPalette.length,
                    (index) => _ColorChip(
                      color: _storyTextPalette[index],
                      selected: _textColorIndex == index,
                      onTap: () => setState(() => _textColorIndex = index),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _StoryStyleSection(
                title: 'نوع الخط',
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ModeChip(
                      selected: _fontFamily == 'system',
                      label: 'عصري',
                      icon: Icons.text_fields_rounded,
                      onTap: () => setState(() => _fontFamily = 'system'),
                    ),
                    _ModeChip(
                      selected: _fontFamily == 'serif',
                      label: 'كلاسيكي',
                      icon: Icons.format_shapes_rounded,
                      onTap: () => setState(() => _fontFamily = 'serif'),
                    ),
                    _ModeChip(
                      selected: _fontFamily == 'monospace',
                      label: 'مونو',
                      icon: Icons.code_rounded,
                      onTap: () => setState(() => _fontFamily = 'monospace'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _StoryStyleSection(
                title: 'سماكة الخط',
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ModeChip(
                      selected: _fontWeight == 'normal',
                      label: 'عادي',
                      icon: Icons.format_bold_rounded,
                      onTap: () => setState(() => _fontWeight = 'normal'),
                    ),
                    _ModeChip(
                      selected: _fontWeight == 'bold',
                      label: 'عريض',
                      icon: Icons.format_bold_rounded,
                      onTap: () => setState(() => _fontWeight = 'bold'),
                    ),
                    _ModeChip(
                      selected: _fontWeight == 'heavy',
                      label: 'ثقيل',
                      icon: Icons.format_bold_rounded,
                      onTap: () => setState(() => _fontWeight = 'heavy'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _StoryStyleSection(
                title: 'المحاذاة',
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ModeChip(
                      selected: _textAlign == 'right',
                      label: 'يمين',
                      icon: Icons.format_align_right_rounded,
                      onTap: () => setState(() => _textAlign = 'right'),
                    ),
                    _ModeChip(
                      selected: _textAlign == 'center',
                      label: 'وسط',
                      icon: Icons.format_align_center_rounded,
                      onTap: () => setState(() => _textAlign = 'center'),
                    ),
                    _ModeChip(
                      selected: _textAlign == 'left',
                      label: 'يسار',
                      icon: Icons.format_align_left_rounded,
                      onTap: () => setState(() => _textAlign = 'left'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _StoryStyleSection(
                title: 'حجم الخط',
                child: Slider(
                  value: _fontScale,
                  min: 0.8,
                  max: 2.2,
                  divisions: 14,
                  label: _fontScale.toStringAsFixed(1),
                  onChanged: (value) => setState(() => _fontScale = value),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (_media != null) Expanded(child: Text(_media!.name)),
                  OutlinedButton.icon(
                    onPressed: _pickMedia,
                    icon: const Icon(Icons.photo_camera_back_rounded),
                    label: Text(
                      _media == null ? 'اختيار وسائط' : 'تبديل الوسائط',
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Text(
                  _error!,
                  textDirection: TextDirection.rtl,
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
                      : const Icon(Icons.auto_awesome_rounded),
                  label: const Text('نشر الستوري'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _currentStoryStyle() => <String, dynamic>{
    'backgroundColor': _toHex(_storyBgPalette[_backgroundIndex]),
    'textColor': _toHex(_storyTextPalette[_textColorIndex]),
    'fontFamily': _fontFamily,
    'fontWeight': _fontWeight,
    'textAlign': _textAlign,
    'fontScale': _fontScale,
  };

  TextAlign _toTextAlign(String value) {
    switch (value) {
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.center;
    }
  }

  TextStyle _storyTextStyle(Color color) {
    FontWeight weight;
    switch (_fontWeight) {
      case 'normal':
        weight = FontWeight.w500;
        break;
      case 'heavy':
        weight = FontWeight.w900;
        break;
      default:
        weight = FontWeight.w700;
        break;
    }

    String? family;
    if (_fontFamily == 'serif') {
      family = 'serif';
    } else if (_fontFamily == 'monospace') {
      family = 'monospace';
    }

    return TextStyle(
      color: color,
      fontWeight: weight,
      fontFamily: family,
      fontSize: 18 * _fontScale,
      height: 1.35,
    );
  }
}

class _StoryViewerSheet extends StatefulWidget {
  final SocialStoryGroup group;
  final int? initialStoryId;
  final ValueChanged<int> onStoryViewed;

  const _StoryViewerSheet({
    required this.group,
    this.initialStoryId,
    required this.onStoryViewed,
  });

  @override
  State<_StoryViewerSheet> createState() => _StoryViewerSheetState();
}

class _StoryViewerSheetState extends State<_StoryViewerSheet>
    with TickerProviderStateMixin {
  static const Duration _storyDuration = Duration(seconds: 30);
  late final PageController _pageController;
  late final AnimationController _progress;
  late int _currentIndex;
  final Set<int> _viewedIds = <int>{};

  @override
  void initState() {
    super.initState();
    _currentIndex = 0;
    if (widget.initialStoryId != null && widget.initialStoryId! > 0) {
      final index = widget.group.stories.indexWhere(
        (story) => story.id == widget.initialStoryId,
      );
      if (index >= 0) {
        _currentIndex = index;
      }
    }
    _pageController = PageController(initialPage: _currentIndex);
    _progress = AnimationController(vsync: this, duration: _storyDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _goNext();
        }
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markCurrentViewed();
      _restartProgress();
    });
  }

  void _restartProgress() {
    if (!mounted) return;
    _progress
      ..stop()
      ..value = 0
      ..forward();
  }

  void _markCurrentViewed() {
    if (_currentIndex < 0 || _currentIndex >= widget.group.stories.length) {
      return;
    }
    final story = widget.group.stories[_currentIndex];
    if (_viewedIds.contains(story.id)) return;
    _viewedIds.add(story.id);
    widget.onStoryViewed(story.id);
  }

  Future<void> _goNext() async {
    final stories = widget.group.stories;
    _progress.stop();
    if (_currentIndex >= stories.length - 1) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goPrevious() async {
    if (_currentIndex <= 0) return;
    _progress.stop();
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  String _timeAgo(DateTime? date) {
    if (date == null) return 'الآن';
    final diff = DateTime.now().difference(date.toLocal());
    if (diff.inSeconds < 60) return 'منذ ثوانٍ';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  @override
  void dispose() {
    _progress.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stories = widget.group.stories;
    final height = MediaQuery.of(context).size.height * 0.84;
    if (stories.isEmpty) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          child: AnimatedBuilder(
            animation: _progress,
            builder: (context, _) {
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: stories.length,
                      onPageChanged: (index) {
                        setState(() => _currentIndex = index);
                        _markCurrentViewed();
                        _restartProgress();
                      },
                      itemBuilder: (context, index) {
                        final story = stories[index];
                        final isImage =
                            (story.mediaKind == 'image') &&
                            (story.mediaUrl ?? '').trim().isNotEmpty;
                        final isVideo =
                            (story.mediaKind == 'video') &&
                            (story.mediaUrl ?? '').trim().isNotEmpty;

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPressStart: (_) => _progress.stop(),
                              onLongPressEnd: (_) {
                                if (!_progress.isAnimating) {
                                  _progress.forward();
                                }
                              },
                              onTapUp: (details) {
                                final width = constraints.maxWidth;
                                final dx = details.localPosition.dx;
                                if (dx <= width * 0.35) {
                                  _goNext();
                                  return;
                                }
                                if (dx >= width * 0.65) {
                                  _goPrevious();
                                }
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (isImage)
                                    Image.network(
                                      story.mediaUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              _MediaLoadFailed(
                                                message:
                                                    'تعذر تحميل صورة الستوري',
                                              ),
                                    )
                                  else
                                    _StoryTextCanvas(story: story),
                                  if (isVideo)
                                    Center(
                                      child: FilledButton.icon(
                                        onPressed: () async {
                                          final uri = Uri.tryParse(
                                            story.mediaUrl!,
                                          );
                                          if (uri == null) return;
                                          await launchUrl(
                                            uri,
                                            mode:
                                                LaunchMode.externalApplication,
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                        ),
                                        label: const Text('تشغيل الفيديو'),
                                      ),
                                    ),
                                  if (isImage || isVideo)
                                    Positioned(
                                      right: 12,
                                      left: 12,
                                      bottom: 14,
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.38,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          story.caption.trim().isEmpty
                                              ? '—'
                                              : story.caption.trim(),
                                          textDirection: TextDirection.rtl,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 10,
                      child: Column(
                        children: [
                          Row(
                            children: List.generate(stories.length, (index) {
                              final value = index < _currentIndex
                                  ? 1.0
                                  : index == _currentIndex
                                  ? _progress.value
                                  : 0.0;
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      minHeight: 3,
                                      value: value,
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.25,
                                      ),
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            textDirection: TextDirection.rtl,
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundImage:
                                    (widget.group.author.imageUrl ?? '')
                                        .trim()
                                        .isNotEmpty
                                    ? NetworkImage(
                                        widget.group.author.imageUrl!,
                                      )
                                    : null,
                                child:
                                    (widget.group.author.imageUrl ?? '')
                                        .trim()
                                        .isEmpty
                                    ? const Icon(
                                        Icons.person_outline_rounded,
                                        size: 18,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'نشر بواسطة ${widget.group.author.fullName}',
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      _timeAgo(
                                        stories[_currentIndex].createdAt,
                                      ),
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CommentsSheet extends ConsumerStatefulWidget {
  final SocialPost post;
  const _CommentsSheet({required this.post});

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  late final SocialApi _api;
  final TextEditingController _ctrl = TextEditingController();
  List<SocialComment> _comments = const [];
  int _count = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = ref.read(socialApiProvider);
    _count = widget.post.commentsCount;
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final out = await _api.listComments(widget.post.id, limit: 60);
      final raw = List<dynamic>.from(out['comments'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        _comments = raw
            .map(
              (e) =>
                  SocialComment.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty) return;
    try {
      final out = await _api.addComment(widget.post.id, body);
      final raw = out['comment'];
      if (raw is! Map || !mounted) return;
      final comment = SocialComment.fromJson(Map<String, dynamic>.from(raw));
      setState(() {
        _comments = [comment, ..._comments];
        _count = _count + 1;
      });
      _ctrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: 'تعذر إرسال التعليق.'),
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            ListTile(
              title: Text(
                'تعليقات ($_count)',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.end,
              ),
              leading: IconButton(
                onPressed: () => Navigator.of(context).pop(_count),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      children: _comments
                          .map(
                            (c) => Card(
                              child: ListTile(
                                title: Text(
                                  c.author.fullName,
                                  textDirection: TextDirection.rtl,
                                ),
                                subtitle: Text(
                                  c.body,
                                  textDirection: TextDirection.rtl,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textDirection: TextDirection.rtl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'اكتب تعليقك...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _send,
                    child: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryStyleSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _StoryStyleSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _ColorChip extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.35),
            width: selected ? 2.4 : 1.2,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x6622D3EE),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

class _MediaLoadFailed extends StatelessWidget {
  final String message;

  const _MediaLoadFailed({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      color: const Color(0xFF102A4A),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              size: 28,
              color: Colors.white70,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryTextCanvas extends StatelessWidget {
  final SocialStory story;

  const _StoryTextCanvas({required this.story});

  @override
  Widget build(BuildContext context) {
    final style = story.style;
    final bg = _hexToColor(style.backgroundColor, const Color(0xFF1E3A8A));
    final fg = _hexToColor(style.textColor, Colors.white);
    final align = _textAlignFromString(style.textAlign);
    final weight = _fontWeightFromString(style.fontWeight);
    final family = _fontFamilyFromString(style.fontFamily);
    final scale = style.fontScale.clamp(0.8, 2.4);
    final text = story.caption.trim();

    return Container(
      color: bg,
      padding: const EdgeInsets.all(18),
      alignment: Alignment.center,
      child: Text(
        text.isEmpty ? '—' : text,
        textAlign: align,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          color: fg,
          fontWeight: weight,
          fontFamily: family,
          fontSize: 18 * scale,
          height: 1.38,
        ),
      ),
    );
  }
}

TextAlign _textAlignFromString(String value) {
  switch (value.trim().toLowerCase()) {
    case 'left':
      return TextAlign.left;
    case 'right':
      return TextAlign.right;
    default:
      return TextAlign.center;
  }
}

FontWeight _fontWeightFromString(String value) {
  switch (value.trim().toLowerCase()) {
    case 'normal':
      return FontWeight.w500;
    case 'heavy':
      return FontWeight.w900;
    default:
      return FontWeight.w700;
  }
}

String? _fontFamilyFromString(String value) {
  switch (value.trim().toLowerCase()) {
    case 'serif':
      return 'serif';
    case 'monospace':
      return 'monospace';
    default:
      return null;
  }
}

Color _hexToColor(String value, Color fallback) {
  final hex = value.replaceAll('#', '').trim();
  if (hex.length == 6) {
    final parsed = int.tryParse('FF$hex', radix: 16);
    if (parsed != null) return Color(parsed);
  }
  if (hex.length == 8) {
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) return Color(parsed);
  }
  return fallback;
}

String _toHex(Color color) {
  final value = color.toARGB32();
  final hex = value.toRadixString(16).padLeft(8, '0').toUpperCase();
  return '#$hex';
}

class _FeedFilter {
  final String label;
  final String? kind;
  final IconData icon;
  const _FeedFilter(this.label, this.kind, this.icon);
}

class _ChipAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ChipAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(width: 6),
            Icon(icon, size: 17),
          ],
        ),
      ),
    );
  }
}

const _filters = <_FeedFilter>[
  _FeedFilter('الكل', null, Icons.grid_view_rounded),
  _FeedFilter('صور', 'image', Icons.image_outlined),
  _FeedFilter('ريلز', 'video', Icons.ondemand_video_rounded),
  _FeedFilter('ريفيوات', 'merchant_review', Icons.rate_review_outlined),
  _FeedFilter('نصوص', 'text', Icons.text_fields_rounded),
];

String _kindLabel(String kind) {
  switch (kind) {
    case 'image':
      return 'صورة';
    case 'video':
      return 'ريلز';
    case 'merchant_review':
      return 'ريفيو';
    default:
      return 'منشور';
  }
}
