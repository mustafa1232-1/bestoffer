import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/i18n/app_localizations_context.dart';
import 'creator_temp_media_service.dart';

/// A background option for the text card — solid (one colour) or gradient (two),
/// plus the default text colour that reads well on it.
class _TextBackground {
  final List<Color> colors;
  final Color textColor;
  const _TextBackground(this.colors, this.textColor);

  bool get isGradient => colors.length > 1;
}

const List<_TextBackground> _kTextBackgrounds = <_TextBackground>[
  _TextBackground([Color(0xFF1E3A8A), Color(0xFF0F766E)], Colors.white),
  _TextBackground([Color(0xFF0D1B2A)], Color(0xFFD4AF37)),
  _TextBackground([Color(0xFFC9A870), Color(0xFF1A2640)], Colors.white),
  _TextBackground([Color(0xFFF5EEE4)], Color(0xFF1A2640)),
  _TextBackground([Color(0xFFD4AF37), Color(0xFF8A6D1F)], Color(0xFF0D1B2A)),
  _TextBackground([Color(0xFF111C2B)], Colors.white),
];

const List<Color> _kTextColors = <Color>[
  Colors.white,
  Color(0xFFD4AF37),
  Color(0xFF1A2640),
  Color(0xFFF5EEE4),
  Colors.black,
];

const List<double> _kTextSizes = <double>[26, 34, 44];

/// Opens the full-screen Maslaki text-story composer. Returns the rendered card
/// as a PNG [File], or null if the user backs out.
Future<File?> showStoryTextComposer(BuildContext context) {
  return Navigator.of(context).push<File>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const StoryTextComposerScreen(),
    ),
  );
}

class StoryTextComposerScreen extends StatefulWidget {
  const StoryTextComposerScreen({super.key});

  @override
  State<StoryTextComposerScreen> createState() =>
      _StoryTextComposerScreenState();
}

class _StoryTextComposerScreenState extends State<StoryTextComposerScreen> {
  final GlobalKey _cardKey = GlobalKey();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final CreatorTempMediaService _tempMediaService =
      const CreatorTempMediaService();

  int _bgIndex = 0;
  int _sizeIndex = 1;
  Color? _textColorOverride;
  TextAlign _align = TextAlign.center;
  bool _exporting = false;

  _TextBackground get _bg => _kTextBackgrounds[_bgIndex];
  Color get _textColor => _textColorOverride ?? _bg.textColor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _cycleBackground() {
    setState(() {
      _bgIndex = (_bgIndex + 1) % _kTextBackgrounds.length;
      _textColorOverride = null; // reset to the new background's best default
    });
  }

  void _cycleTextColor() {
    final current = _textColorOverride ?? _bg.textColor;
    final idx = _kTextColors.indexOf(current);
    setState(() {
      _textColorOverride = _kTextColors[(idx + 1) % _kTextColors.length];
    });
  }

  void _cycleSize() {
    setState(() => _sizeIndex = (_sizeIndex + 1) % _kTextSizes.length);
  }

  void _cycleAlign() {
    setState(() {
      _align = switch (_align) {
        TextAlign.center => TextAlign.start,
        TextAlign.start => TextAlign.end,
        _ => TextAlign.center,
      };
    });
  }

  IconData get _alignIcon => switch (_align) {
        TextAlign.center => Icons.format_align_center_rounded,
        TextAlign.start => Icons.format_align_right_rounded,
        _ => Icons.format_align_left_rounded,
      };

  Future<void> _capture() async {
    if (_exporting) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (_controller.text.trim().isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.socialCreatorTextEmpty)),
      );
      return;
    }
    setState(() => _exporting = true);
    // Drop the keyboard and caret so they are not baked into the image.
    _focus.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    try {
      final boundary = _cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        setState(() => _exporting = false);
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        setState(() => _exporting = false);
        return;
      }
      final path = await _tempMediaService.newFilePath(
        prefix: 'story_text',
        extension: 'png',
      );
      final file = File(path)
        ..writeAsBytesSync(byteData.buffer.asUint8List(), flush: true);
      if (!mounted) return;
      Navigator.of(context).pop(file);
    } catch (_) {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The card that gets rendered to an image.
          RepaintBoundary(
            key: _cardKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _bg.isGradient ? null : _bg.colors.first,
                gradient: _bg.isGradient
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _bg.colors,
                      )
                    : null,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    textAlign: _align,
                    maxLines: null,
                    cursorColor: _textColor,
                    keyboardType: TextInputType.multiline,
                    style: TextStyle(
                      color: _textColor,
                      fontSize: _kTextSizes[_sizeIndex],
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: l10n.socialCreatorTextHint,
                      hintStyle: TextStyle(
                        color: _textColor.withValues(alpha: 0.45),
                        fontSize: _kTextSizes[_sizeIndex],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Top scrim + close.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                    color: _textColor,
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                  ),
                ],
              ),
            ),
          ),
          // Left-side writing tools.
          PositionedDirectional(
            top: 0,
            bottom: 0,
            start: 8,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TextToolButton(
                    icon: Icons.palette_outlined,
                    label: l10n.socialCreatorTextBackground,
                    swatch: _bg.colors.first,
                    onTap: _cycleBackground,
                  ),
                  const SizedBox(height: 14),
                  _TextToolButton(
                    icon: Icons.format_color_text_rounded,
                    label: l10n.socialCreatorTextColor,
                    swatch: _textColor,
                    onTap: _cycleTextColor,
                  ),
                  const SizedBox(height: 14),
                  _TextToolButton(
                    icon: Icons.format_size_rounded,
                    label: l10n.socialCreatorTextSize,
                    onTap: _cycleSize,
                  ),
                  const SizedBox(height: 14),
                  _TextToolButton(
                    icon: _alignIcon,
                    label: l10n.socialCreatorTextAlign,
                    onTap: _cycleAlign,
                  ),
                ],
              ),
            ),
          ),
          // Bottom-center capture/confirm button.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: GestureDetector(
                  onTap: _exporting ? null : _capture,
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFFE6C98A), width: 4),
                      color: Colors.black.withValues(alpha: 0.25),
                    ),
                    child: Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFD4AF37),
                        ),
                        child: _exporting
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF0D1B2A),
                                  ),
                                ),
                              )
                            : const Icon(Icons.check_rounded,
                                color: Color(0xFF0D1B2A), size: 30),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? swatch;
  final VoidCallback onTap;

  const _TextToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.swatch,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            shape: BoxShape.circle,
            border: Border.all(
              color: swatch != null ? Colors.white70 : Colors.white24,
              width: 1.2,
            ),
          ),
          child: swatch != null
              ? Center(
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54),
                    ),
                  ),
                )
              : Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
