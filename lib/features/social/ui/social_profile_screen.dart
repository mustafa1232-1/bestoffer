import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

import '../models/social_models.dart';
import '../state/social_controller.dart';

class SocialProfileScreen extends ConsumerStatefulWidget {
  final int userId;
  final String? initialName;

  const SocialProfileScreen({
    super.key,
    required this.userId,
    this.initialName,
  });

  @override
  ConsumerState<SocialProfileScreen> createState() =>
      _SocialProfileScreenState();
}

class _SocialProfileScreenState extends ConsumerState<SocialProfileScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = <_ProfileTab>[
    _ProfileTab('المنشورات', null, Icons.article_outlined),
    _ProfileTab('الصور', 'image', Icons.image_outlined),
    _ProfileTab('الريلز', 'video', Icons.ondemand_video_rounded),
    _ProfileTab('التقييمات', 'merchant_review', Icons.rate_review_outlined),
  ];

  final ScrollController _scrollController = ScrollController();
  final intl.DateFormat _dateFmt = intl.DateFormat('d/M/y', 'ar');

  late final TabController _tabController;
  bool _loadingProfile = true;
  String? _error;
  SocialUserProfile? _profile;

  final Map<String, List<SocialPost>> _postsByKey = {};
  final Map<String, int?> _nextCursorByKey = {};
  final Set<String> _loadingKeys = {};
  final Set<String> _loadingMoreKeys = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadProfile(),
      _loadPostsForTab(_tabs.first, refresh: true),
    ]);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final tab = _tabs[_tabController.index];
    final key = _tabKey(tab.kind);
    if ((_postsByKey[key] ?? const []).isEmpty && !_loadingKeys.contains(key)) {
      _loadPostsForTab(tab, refresh: true);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final tab = _tabs[_tabController.index];
    final key = _tabKey(tab.kind);
    if (_loadingKeys.contains(key) || _loadingMoreKeys.contains(key)) return;
    final cursor = _nextCursorByKey[key];
    if (cursor == null) return;
    final threshold = _scrollController.position.maxScrollExtent - 220;
    if (_scrollController.position.pixels < threshold) return;
    _loadPostsForTab(tab, refresh: false);
  }

  String _tabKey(String? kind) => kind ?? 'all';

  Future<void> _loadProfile() async {
    setState(() {
      _loadingProfile = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(socialApiProvider)
          .getUserProfile(widget.userId);
      final raw = out['profile'];
      if (raw is! Map) {
        if (!mounted) return;
        setState(() {
          _loadingProfile = false;
          _error = 'تعذر تحميل بيانات الحساب.';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _profile = SocialUserProfile.fromJson(Map<String, dynamic>.from(raw));
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _error = 'تعذر تحميل الحساب الآن.';
      });
    }
  }

  Future<void> _loadPostsForTab(
    _ProfileTab tab, {
    required bool refresh,
  }) async {
    final key = _tabKey(tab.kind);
    if (refresh) {
      _loadingKeys.add(key);
    } else {
      _loadingMoreKeys.add(key);
    }
    if (mounted) setState(() {});

    try {
      final out = await ref
          .read(socialApiProvider)
          .listUserPosts(
            userId: widget.userId,
            beforeId: refresh ? null : _nextCursorByKey[key],
            kind: tab.kind,
            limit: 20,
          );
      final rawPosts = List<dynamic>.from(out['posts'] as List? ?? const []);
      final posts = rawPosts
          .map((e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);

      if (!mounted) return;
      final merged = refresh
          ? posts
          : [...(_postsByKey[key] ?? const []), ...posts];
      setState(() {
        _postsByKey[key] = merged;
        _nextCursorByKey[key] = int.tryParse('${out['nextCursor']}');
        _loadingKeys.remove(key);
        _loadingMoreKeys.remove(key);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingKeys.remove(key);
        _loadingMoreKeys.remove(key);
        _error = 'تعذر تحميل منشورات هذا الحساب.';
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = _tabs[_tabController.index];
    final key = _tabKey(activeTab.kind);
    final posts = _postsByKey[key] ?? const <SocialPost>[];
    final isLoading = _loadingKeys.contains(key);
    final isLoadingMore = _loadingMoreKeys.contains(key);

    return Scaffold(
      appBar: AppBar(
        title: Text(_profile?.fullName ?? widget.initialName ?? 'الملف الشخصي'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs
              .map(
                (tab) => Tab(text: tab.label, icon: Icon(tab.icon, size: 18)),
              )
              .toList(growable: false),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            _loadProfile(),
            _loadPostsForTab(activeTab, refresh: true),
          ]);
        },
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
          children: [
            _ProfileHeader(
              profile: _profile,
              loading: _loadingProfile,
              dateFmt: _dateFmt,
            ),
            const SizedBox(height: 10),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (isLoading && posts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (posts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(
                  child: Text(
                    'لا يوجد محتوى في هذا القسم.',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              )
            else
              ...posts.map((post) => _ProfilePostCard(post: post)),
            if (isLoadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final SocialUserProfile? profile;
  final bool loading;
  final intl.DateFormat dateFmt;

  const _ProfileHeader({
    required this.profile,
    required this.loading,
    required this.dateFmt,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && profile == null) {
      return const SizedBox(
        height: 130,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final p = profile;
    if (p == null) return const SizedBox.shrink();

    String joined = '—';
    if (p.joinedAt != null) {
      joined = dateFmt.format(p.joinedAt!.toLocal());
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: (p.imageUrl ?? '').trim().isNotEmpty
                    ? NetworkImage(p.imageUrl!)
                    : null,
                child: (p.imageUrl ?? '').trim().isEmpty
                    ? const Icon(Icons.person_outline_rounded)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      p.fullName,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'انضم في $joined',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              _ProfileStatChip(label: 'المنشورات', value: p.stats.totalPosts),
              _ProfileStatChip(label: 'الصور', value: p.stats.imagePosts),
              _ProfileStatChip(label: 'الريلز', value: p.stats.videoPosts),
              _ProfileStatChip(label: 'التقييمات', value: p.stats.reviewPosts),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileStatChip extends StatelessWidget {
  final String label;
  final int value;
  const _ProfileStatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Text(
        '$label: $value',
        textDirection: TextDirection.rtl,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ProfilePostCard extends StatelessWidget {
  final SocialPost post;
  const _ProfilePostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final isImage =
        (post.mediaKind == 'image' || post.postKind == 'image') &&
        (post.mediaUrl ?? '').trim().isNotEmpty;
    final isVideo =
        (post.mediaKind == 'video' || post.postKind == 'video') &&
        (post.mediaUrl ?? '').trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (post.caption.trim().isNotEmpty)
              Text(
                post.caption,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            if (post.postKind == 'merchant_review') ...[
              const SizedBox(height: 8),
              Text(
                'تقييم: ${post.merchantName ?? 'متجر'}',
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
            if (isImage) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  post.mediaUrl!,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            if (isVideo) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(post.mediaUrl!);
                  if (uri == null) return;
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.play_circle_fill_rounded),
                label: const Text('تشغيل الريل'),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'إعجاب ${post.likesCount} • تعليق ${post.commentsCount}',
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTab {
  final String label;
  final String? kind;
  final IconData icon;
  const _ProfileTab(this.label, this.kind, this.icon);
}
