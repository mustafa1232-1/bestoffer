import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_profile_posts_screen.dart';
import 'social_story_quick_viewer.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

enum _ArchiveTab { posts, reels, stories }

class SocialProfileArchiveScreen extends ConsumerStatefulWidget {
  const SocialProfileArchiveScreen({super.key});

  @override
  ConsumerState<SocialProfileArchiveScreen> createState() =>
      _SocialProfileArchiveScreenState();
}

class _SocialProfileArchiveScreenState
    extends ConsumerState<SocialProfileArchiveScreen> {
  _ArchiveTab _tab = _ArchiveTab.posts;
  bool _loadingStories = true;
  String? _storiesError;
  List<SocialStory> _stories = const <SocialStory>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadStories);
  }

  Future<void> _loadStories() async {
    setState(() {
      _loadingStories = true;
      _storiesError = null;
    });
    try {
      final out = await ref
          .read(socialApiProvider)
          .listMyStoryArchive(limit: 120);
      final rows = List<dynamic>.from(out['stories'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        _stories = rows
            .map(
              (item) =>
                  SocialStory.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(growable: false);
        _loadingStories = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _storiesError = mapAnyError(
          e,
          fallback: Localizations.localeOf(context).languageCode == 'en'
              ? 'Unable to load archived stories.'
              : 'تعذر تحميل القصص المؤرشفة.',
        );
        _loadingStories = false;
      });
    }
  }

  Future<void> _restoreStory(SocialStory story) async {
    await ref.read(socialApiProvider).restoreStory(story.id);
    if (!mounted) return;
    setState(() {
      _stories = _stories
          .where((item) => item.id != story.id)
          .toList(growable: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.socialProfileArchiveStoryRestored)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.socialProfileArchiveTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ArchiveChip(
                selected: _tab == _ArchiveTab.posts,
                label: l10n.socialProfileArchivePosts,
                onTap: () => setState(() => _tab = _ArchiveTab.posts),
              ),
              _ArchiveChip(
                selected: _tab == _ArchiveTab.reels,
                label: l10n.socialProfileArchiveReels,
                onTap: () => setState(() => _tab = _ArchiveTab.reels),
              ),
              _ArchiveChip(
                selected: _tab == _ArchiveTab.stories,
                label: l10n.socialProfileArchiveStories,
                onTap: () => setState(() => _tab = _ArchiveTab.stories),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_tab == _ArchiveTab.posts)
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: SocialProfilePostsScreen(
                userId: 0,
                title: l10n.socialProfileArchiveTitle,
                mode: SocialProfilePostCollectionMode.archivedPosts,
                allowRestore: true,
                showScaffold: false,
              ),
            )
          else if (_tab == _ArchiveTab.reels)
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: SocialProfilePostsScreen(
                userId: 0,
                title: l10n.socialProfileArchiveReelsTitle,
                mode: SocialProfilePostCollectionMode.archivedPosts,
                kind: 'reel',
                gridLayout: true,
                allowRestore: true,
                showScaffold: false,
              ),
            )
          else if (_loadingStories)
            const Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_storiesError != null)
            Padding(
              padding: const EdgeInsets.only(top: 120),
              child: Center(child: Text(_storiesError!)),
            )
          else if (_stories.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 120),
              child: Center(child: Text(l10n.socialProfileArchiveEmptyStories)),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _stories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.68,
              ),
              itemBuilder: (context, index) {
                final story = _stories[index];
                final mediaUrl = (story.mediaUrl ?? '').trim();
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final group = SocialStoryGroup(
                      userId: story.userId,
                      author: SocialAuthor(
                        id: story.userId,
                        fullName: l10n.socialProfileArchiveMe,
                        imageUrl: null,
                        phone: null,
                        role: 'user',
                      ),
                      latestAt: story.createdAt,
                      hasUnviewed: false,
                      stories: _stories,
                    );
                    await showSocialStoryQuickViewer(
                      context: context,
                      group: group,
                      initialStoryId: story.id,
                      api: ref.read(socialApiProvider),
                      onStoryArchiveChanged: _loadStories,
                    );
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            image: mediaUrl.isEmpty
                                ? null
                                : DecorationImage(
                                    image: AppCachedImageProvider(mediaUrl),
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          child: mediaUrl.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      story.caption.trim().isEmpty
                                          ? l10n.socialProfileArchiveStoryFallback
                                          : story.caption.trim(),
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.black45,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _restoreStory(story),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.unarchive_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ArchiveChip extends StatelessWidget {
  const _ArchiveChip({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onTap(),
    );
  }
}
