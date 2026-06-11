import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_story_quick_viewer.dart';

class SocialStoryViewerScreen extends ConsumerStatefulWidget {
  const SocialStoryViewerScreen({super.key, required this.storyId});

  final int storyId;

  @override
  ConsumerState<SocialStoryViewerScreen> createState() =>
      _SocialStoryViewerScreenState();
}

class _SocialStoryViewerScreenState
    extends ConsumerState<SocialStoryViewerScreen> {
  bool _loading = true;
  String? _error;
  bool _opened = false;
  SocialStoryGroup? _group;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(socialApiProvider)
          .listStories(limitUsers: 60, maxPerUser: 12);
      final rawGroups = List<dynamic>.from(out['stories'] as List? ?? const []);
      SocialStoryGroup? targetGroup;
      for (final item in rawGroups) {
        final group = SocialStoryGroup.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
        if (group.stories.any((story) => story.id == widget.storyId)) {
          targetGroup = group;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _group = targetGroup;
        _loading = false;
        if (targetGroup == null) {
          _error = context.l10n.socialStoryViewerUnavailable;
        }
      });
      _openIfReady();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.socialStoryViewerLoadFailed,
        );
      });
    }
  }

  void _openIfReady() {
    if (_opened || _group == null || !mounted) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _group == null) return;
      await showSocialStoryQuickViewer(
        context: context,
        group: _group!,
        initialStoryId: widget.storyId,
        api: ref.read(socialApiProvider),
      );
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  Widget build(BuildContext context) {
    _openIfReady();
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.socialStoryViewerTitle)),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: Text(context.l10n.commonRetry),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
