import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_story_quick_viewer.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialStoryArchiveScreen extends ConsumerStatefulWidget {
  const SocialStoryArchiveScreen({super.key});

  @override
  ConsumerState<SocialStoryArchiveScreen> createState() =>
      _SocialStoryArchiveScreenState();
}

class _SocialStoryArchiveScreenState
    extends ConsumerState<SocialStoryArchiveScreen> {
  bool _loading = true;
  String? _error;
  List<SocialStory> _stories = const <SocialStory>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await ref.read(socialApiProvider).listMyStoryArchive();
      final raw = List<dynamic>.from(out['stories'] as List? ?? const []);
      setState(() {
        _stories = raw
            .map(
              (item) =>
                  SocialStory.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.socialStoryArchiveTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _stories.isEmpty
          ? Center(child: Text(l10n.socialStoryArchiveEmpty))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.68,
              ),
              itemCount: _stories.length,
              itemBuilder: (context, index) {
                final story = _stories[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final group = SocialStoryGroup(
                      userId: story.userId,
                      author: SocialAuthor(
                        id: 0,
                        fullName: l10n.socialStoryArchiveMe,
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
                      onStoryArchiveChanged: _load,
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: story.mediaUrl != null
                        ? CachedAppImage(
                            imageUrl: story.mediaUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (context, error, stackTrace) =>
                                _TextCard(story: story),
                          )
                        : _TextCard(story: story),
                  ),
                );
              },
            ),
    );
  }
}

class _TextCard extends StatelessWidget {
  final SocialStory story;

  const _TextCard({required this.story});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.indigo,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            story.caption.trim().isEmpty
                ? l10n.socialStoryArchiveFallbackTitle
                : story.caption.trim(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
