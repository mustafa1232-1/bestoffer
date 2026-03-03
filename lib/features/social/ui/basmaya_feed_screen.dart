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

class BasmayaFeedScreen extends ConsumerStatefulWidget {
  final int? initialThreadId;
  final int? initialPostId;

  const BasmayaFeedScreen({
    super.key,
    this.initialThreadId,
    this.initialPostId,
  });

  @override
  ConsumerState<BasmayaFeedScreen> createState() => _BasmayaFeedScreenState();
}

class _BasmayaFeedScreenState extends ConsumerState<BasmayaFeedScreen> {
  final ScrollController _scrollController = ScrollController();
  final intl.DateFormat _timeFmt = intl.DateFormat('d/M hh:mm a', 'ar');
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(_bootstrap);
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
      await ref
          .read(socialControllerProvider.notifier)
          .loadPosts(refresh: true);
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

  Future<void> _sharePost(SocialPost post) async {
    final text = [
      'شديصير بسماية',
      if (post.caption.trim().isNotEmpty) post.caption.trim(),
      if ((post.mediaUrl ?? '').trim().isNotEmpty) post.mediaUrl!.trim(),
    ].join('\n');
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _callAuthor(SocialAuthor author) async {
    final phone = (author.phone ?? '').trim();
    if (phone.isEmpty) return;
    await launchUrl(Uri.parse('tel:$phone'));
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

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
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
          await Future.wait([
            ref
                .read(socialControllerProvider.notifier)
                .loadPosts(refresh: true),
            ref.read(socialControllerProvider.notifier).loadThreads(),
          ]);
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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              post.mediaUrl!,
                              width: double.infinity,
                              height: 210,
                              fit: BoxFit.cover,
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
                              label: 'اتصال',
                              icon: Icons.call_outlined,
                              onTap: () => _callAuthor(post.author),
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
