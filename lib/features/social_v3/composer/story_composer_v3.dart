import 'dart:ui';

import 'package:flutter/material.dart';

import '../media/social_media_presentation.dart';
import '../media/social_safe_image.dart';
import 'story_composer_source.dart';

/// Full-screen Story Composer (§7).
///
/// The composed media fills the 9:16 canvas. For a shared reel the reel IS the
/// base media (cover for vertical, blurred-poster background + contained media
/// for horizontal) — never a width-278 attachment card, never padding/border,
/// never a manually-resizable layer. The source is locked by default.
class StoryComposerV3 extends StatefulWidget {
  const StoryComposerV3({
    super.key,
    required this.source,
    this.scope = StoryComposerScope.global,
    this.onPublish,
    this.onSaveDraft,
  });

  final StoryComposerSource source;

  /// Preselected audience scope (§2). May be locked for building/community.
  final StoryComposerScope scope;

  /// Publishes with the composed caption + authoritative scope. Returns true on
  /// success (composer then closes). The backend re-validates the scope.
  final Future<bool> Function(String caption, StoryComposerScope scope)?
      onPublish;
  final void Function(String caption)? onSaveDraft;

  static Route<void> route(
    StoryComposerSource source, {
    StoryComposerScope scope = StoryComposerScope.global,
    Future<bool> Function(String caption, StoryComposerScope scope)? onPublish,
  }) {
    return MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) =>
          StoryComposerV3(source: source, scope: scope, onPublish: onPublish),
    );
  }

  @override
  State<StoryComposerV3> createState() => _StoryComposerV3State();
}

class _StoryComposerV3State extends State<StoryComposerV3> {
  final TextEditingController _caption = TextEditingController();
  late final StoryComposerScope _scope = widget.scope;
  bool _editingText = false;
  bool _publishing = false;

  /// True when a non-global scope cannot be published because the backend does
  /// not yet enforce story scope. Exposed for tests.
  bool get isScopedPublishBlocked =>
      _scope.scope != StoryAudienceScope.global && !kStoryAudienceScopeSupported;

  Future<void> _publish() async {
    if (_publishing) return;
    // SAFETY GUARD (§1): never silently publish a scoped story globally. If a
    // non-global scope is requested but the backend does not yet persist/enforce
    // story scope, refuse publication and preserve the draft.
    if (isScopedPublishBlocked) {
      widget.onSaveDraft?.call(_caption.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'نشر القصص المخصصة للبناية غير متاح حالياً. تم حفظ المسودة.',
            ),
          ),
        );
      }
      return;
    }
    setState(() {
      _publishing = true;
    });
    final ok = await (widget.onPublish?.call(_caption.text.trim(), _scope) ??
        Future.value(true));
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _publishing = false);
    }
  }

  String get _scopeLabel {
    if (_scope.label != null && _scope.label!.trim().isNotEmpty) {
      return _scope.label!.trim();
    }
    switch (_scope.scope) {
      case StoryAudienceScope.global:
        return 'الجميع';
      case StoryAudienceScope.closeFriends:
        return 'الأصدقاء المقربون';
      case StoryAudienceScope.followers:
        return 'المتابعون';
      case StoryAudienceScope.building:
        return 'المبنى';
      case StoryAudienceScope.block:
        return 'البلوك';
      case StoryAudienceScope.compound:
        return 'المجمع';
      case StoryAudienceScope.area:
        return 'المنطقة';
      case StoryAudienceScope.friends:
        return 'الأصدقاء';
      case StoryAudienceScope.custom:
        return 'مخصص';
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  SocialMediaPresentation? get _presentation {
    final reel = widget.source.sharedReel;
    if (reel != null) return reel.toPresentation();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _CanvasBase(source: widget.source, presentation: _presentation),

          // Composed caption overlay.
          if (_caption.text.trim().isNotEmpty && !_editingText)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _caption.text.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
                  ),
                ),
              ),
            ),

          if (_editingText)
            Container(
              color: const Color(0x99000000),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: TextField(
                controller: _caption,
                autofocus: true,
                maxLines: null,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22),
                decoration: const InputDecoration(
                  hintText: 'أضف نصًا…',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => setState(() => _editingText = false),
              ),
            ),

          // Top bar: close + tools.
          Positioned(
            top: padding.top + 8,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _RoundButton(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                Row(
                  children: [
                    _RoundButton(
                      icon: Icons.text_fields_rounded,
                      onTap: () => setState(() => _editingText = !_editingText),
                    ),
                    const SizedBox(width: 8),
                    _RoundButton(
                      icon: Icons.emoji_emotions_outlined,
                      onTap: () {},
                    ),
                    const SizedBox(width: 8),
                    _RoundButton(icon: Icons.brush_rounded, onTap: () {}),
                  ],
                ),
              ],
            ),
          ),

          // Bottom bar: audience + save draft + publish.
          Positioned(
            left: 12,
            right: 12,
            bottom: padding.bottom + 14,
            child: Row(
              children: [
                // Story scope is set by the entry point (generic = global,
                // community = a locked block/compound/building scope). The
                // backend only accepts global/block/compound/building for
                // stories, so there is no free-form audience toggle here.
                _ScopeChip(
                  label: _scopeLabel,
                  official: _scope.isOfficial,
                  locked: _scope.locked,
                  onTap: null,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => widget.onSaveDraft?.call(_caption.text.trim()),
                  child: const Text(
                    'مسودة',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                _PublishButton(onTap: _publishing ? null : _publish),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The base canvas: shared reel / local media filling 9:16.
class _CanvasBase extends StatelessWidget {
  const _CanvasBase({required this.source, required this.presentation});

  final StoryComposerSource source;
  final SocialMediaPresentation? presentation;

  @override
  Widget build(BuildContext context) {
    final p = presentation;
    if (p == null) {
      // Local/text source: neutral canvas (local media preview is wired by the
      // connector; here we show a dark canvas so layout stays deterministic).
      return const ColoredBox(color: Color(0xFF0D1B2A));
    }
    if (!p.isVertical && p.hasPoster) {
      // Horizontal reel: blurred poster fill + centered contained media.
      return Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: SocialSafeImage(imageUrl: p.posterImageUrl, fit: BoxFit.cover),
          ),
          Center(
            child: AspectRatio(
              aspectRatio: p.aspectRatio ?? (16 / 9),
              child: SocialSafeImage(
                imageUrl: p.posterImageUrl,
                fit: BoxFit.contain,
                showVideoGlyph: true,
              ),
            ),
          ),
        ],
      );
    }
    // Vertical reel (default): fill the canvas, cover.
    return SocialSafeImage(
      imageUrl: p.posterImageUrl,
      fit: BoxFit.cover,
      showVideoGlyph: true,
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Color(0x55000000),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.official,
    required this.locked,
    this.onTap,
  });

  final String label;
  final bool official;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: official ? const Color(0xFFE7B24B) : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              official
                  ? Icons.verified_rounded
                  : (locked ? Icons.lock_outline : Icons.public),
              color: official ? const Color(0xFFE7B24B) : Colors.white,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _PublishButton extends StatelessWidget {
  const _PublishButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE7B24B),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Text(
          'نشر',
          style: TextStyle(color: Color(0xFF0D1B2A), fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
