import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../models/social_models.dart';
import '../../state/social_controller.dart';
import 'social_identity_view.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialMentionComposerController {
  SocialMentionComposerController({String text = ''})
    : textController = TextEditingController(text: text),
      _lastText = text;

  final TextEditingController textController;
  final List<_MentionAnnotation> _mentions = <_MentionAnnotation>[];
  String _lastText;

  String get plainText => textController.text;

  void dispose() {
    textController.dispose();
  }

  void clear() {
    _mentions.clear();
    _lastText = '';
    textController.clear();
  }

  void handleExternalTextChange() {
    final nextText = textController.text;
    if (nextText == _lastText) return;
    final previousText = _lastText;
    final prefixLength = _sharedPrefixLength(previousText, nextText);
    final suffixLength = _sharedSuffixLength(
      previousText,
      nextText,
      prefixLength,
    );
    final oldEditEnd = previousText.length - suffixLength;
    final delta = nextText.length - previousText.length;

    final updated = <_MentionAnnotation>[];
    for (final mention in _mentions) {
      if (mention.end <= prefixLength) {
        updated.add(mention);
        continue;
      }
      if (mention.start >= oldEditEnd) {
        updated.add(
          mention.copyWith(
            start: mention.start + delta,
            end: mention.end + delta,
          ),
        );
      }
    }

    _mentions
      ..clear()
      ..addAll(
        updated.where((mention) {
          if (mention.start < 0 || mention.end > nextText.length) return false;
          final slice = nextText.substring(mention.start, mention.end);
          return slice == '@${mention.displayLabel}';
        }),
      );
    _lastText = nextText;
  }

  void insertMention({
    required int start,
    required int end,
    required SocialAuthor author,
  }) {
    final label = (author.username ?? '').trim().isNotEmpty
        ? author.username!.trim()
        : author.fullName.trim();
    final replacement = '@$label ';
    _replaceRange(start: start, end: end, replacement: replacement);
    _mentions.add(
      _MentionAnnotation(
        start: start,
        end: start + replacement.trimRight().length,
        userId: author.id,
        displayLabel: label,
      ),
    );
    _mentions.sort((a, b) => a.start.compareTo(b.start));
  }

  void insertHashtag({
    required int start,
    required int end,
    required String tag,
  }) {
    final normalized = tag.trim().replaceAll(RegExp(r'^#+'), '');
    if (normalized.isEmpty) return;
    _replaceRange(start: start, end: end, replacement: '#$normalized ');
  }

  String buildMarkedText() {
    var output = textController.text;
    final annotations = [..._mentions]
      ..sort((a, b) => b.start.compareTo(a.start));
    for (final mention in annotations) {
      if (mention.start < 0 || mention.end > output.length) continue;
      final slice = output.substring(mention.start, mention.end);
      if (slice != '@${mention.displayLabel}') continue;
      output = output.replaceRange(
        mention.start,
        mention.end,
        '@[${mention.displayLabel}](${mention.userId})',
      );
    }
    return output;
  }

  void _replaceRange({
    required int start,
    required int end,
    required String replacement,
  }) {
    final oldText = textController.text;
    final nextText = oldText.replaceRange(start, end, replacement);
    final delta = replacement.length - (end - start);
    final shifted = <_MentionAnnotation>[];
    for (final mention in _mentions) {
      final overlaps = mention.start < end && mention.end > start;
      if (overlaps) continue;
      if (mention.start >= end) {
        shifted.add(
          mention.copyWith(
            start: mention.start + delta,
            end: mention.end + delta,
          ),
        );
      } else {
        shifted.add(mention);
      }
    }
    _mentions
      ..clear()
      ..addAll(shifted);
    textController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    _lastText = nextText;
  }

  int _sharedPrefixLength(String a, String b) {
    var index = 0;
    while (index < a.length && index < b.length && a[index] == b[index]) {
      index += 1;
    }
    return index;
  }

  int _sharedSuffixLength(String a, String b, int prefixLength) {
    var index = 0;
    while (a.length - 1 - index >= prefixLength &&
        b.length - 1 - index >= prefixLength &&
        a[a.length - 1 - index] == b[b.length - 1 - index]) {
      index += 1;
    }
    return index;
  }
}

class SocialMentionComposerField extends ConsumerStatefulWidget {
  final SocialMentionComposerController controller;
  final String hintText;
  final int minLines;
  final int maxLines;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  const SocialMentionComposerField({
    super.key,
    required this.controller,
    required this.hintText,
    this.minLines = 1,
    this.maxLines = 4,
    this.enabled = true,
    this.textInputAction = TextInputAction.newline,
    this.onSubmitted,
  });

  @override
  ConsumerState<SocialMentionComposerField> createState() =>
      _SocialMentionComposerFieldState();
}

class _SocialMentionComposerFieldState
    extends ConsumerState<SocialMentionComposerField> {
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  _ComposerToken? _token;
  bool _loading = false;
  String? _error;
  List<SocialAuthor> _mentionSuggestions = const <SocialAuthor>[];
  List<String> _hashtagSuggestions = const <String>[];

  @override
  void initState() {
    super.initState();
    widget.controller.textController.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.textController.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus && mounted) {
      setState(() {
        _token = null;
        _loading = false;
        _error = null;
        _mentionSuggestions = const <SocialAuthor>[];
        _hashtagSuggestions = const <String>[];
      });
    } else {
      _handleTextChanged();
    }
  }

  void _handleTextChanged() {
    widget.controller.handleExternalTextChange();
    final token = _readToken();
    if (token == null) {
      _debounce?.cancel();
      if (!mounted) return;
      setState(() {
        _token = null;
        _loading = false;
        _error = null;
        _mentionSuggestions = const <SocialAuthor>[];
        _hashtagSuggestions = const <String>[];
      });
      return;
    }
    setState(() => _token = token);
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 180),
      () => _loadSuggestions(token),
    );
  }

  _ComposerToken? _readToken() {
    if (!_focusNode.hasFocus) return null;
    final selection = widget.controller.textController.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final text = widget.controller.textController.text;
    final cursor = selection.baseOffset;
    if (cursor < 0 || cursor > text.length) return null;
    var start = cursor;
    while (start > 0) {
      final previous = text[start - 1];
      if (RegExp(r'\s').hasMatch(previous)) break;
      start -= 1;
    }
    final token = text.substring(start, cursor);
    if (token.isEmpty) return null;
    final marker = token[0];
    if (marker != '@' && marker != '#') return null;
    final query = token.substring(1);
    if (query.contains('@') || query.contains('#')) return null;
    return _ComposerToken(
      marker: marker,
      query: query,
      start: start,
      end: cursor,
    );
  }

  Future<void> _loadSuggestions(_ComposerToken token) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (token.marker == '@') {
        final out = await ref
            .read(socialApiProvider)
            .listMentionSuggestions(search: token.query, limit: 8);
        final raw = List<dynamic>.from(
          out['users'] as List? ?? const <dynamic>[],
        );
        if (!mounted) return;
        setState(() {
          _mentionSuggestions = raw
              .map(
                (row) => SocialAuthor.fromJson(
                  Map<String, dynamic>.from(row as Map),
                ),
              )
              .toList(growable: false);
          _hashtagSuggestions = const <String>[];
          _loading = false;
        });
        return;
      }
      final out = await ref
          .read(socialApiProvider)
          .listHashtagSuggestions(search: token.query, limit: 8);
      final raw = List<dynamic>.from(
        out['hashtags'] as List? ?? const <dynamic>[],
      );
      if (!mounted) return;
      setState(() {
        _hashtagSuggestions = raw
            .map((row) => '${(row as Map)['tag'] ?? ''}'.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        _mentionSuggestions = const <SocialAuthor>[];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _mentionSuggestions = const <SocialAuthor>[];
        _hashtagSuggestions = const <String>[];
        _error = mapAnyError(
          error,
          fallback: context.l10n.socialStoryMentionLoadFailed,
        );
      });
    }
  }

  void _selectMention(SocialAuthor author) {
    final token = _token;
    if (token == null) return;
    widget.controller.insertMention(
      start: token.start,
      end: token.end,
      author: author,
    );
    _handleTextChanged();
  }

  void _selectHashtag(String tag) {
    final token = _token;
    if (token == null) return;
    widget.controller.insertHashtag(
      start: token.start,
      end: token.end,
      tag: tag,
    );
    _handleTextChanged();
  }

  @override
  Widget build(BuildContext context) {
    final showSuggestions =
        _token != null &&
        (_loading ||
            _error != null ||
            _mentionSuggestions.isNotEmpty ||
            _hashtagSuggestions.isNotEmpty);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSuggestions)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : (_error ?? '').trim().isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : _token?.marker == '@'
                ? ListView.separated(
                    shrinkWrap: true,
                    itemCount: _mentionSuggestions.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final author = _mentionSuggestions[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              (author.imageUrl ?? '').trim().isNotEmpty
                              ? AppCachedImageProvider(author.imageUrl!)
                              : null,
                          child: (author.imageUrl ?? '').trim().isEmpty
                              ? const Icon(Icons.person_outline)
                              : null,
                        ),
                        title: SocialIdentityView(
                          author: author,
                          primaryStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                          ),
                          secondaryStyle: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () => _selectMention(author),
                      );
                    },
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _hashtagSuggestions.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tag = _hashtagSuggestions[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.tag_rounded),
                        ),
                        title: Text(
                          '#$tag',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        onTap: () => _selectHashtag(tag),
                      );
                    },
                  ),
          ),
        TextField(
          controller: widget.controller.textController,
          focusNode: _focusNode,
          enabled: widget.enabled,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            hintText: widget.hintText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }
}

class _MentionAnnotation {
  final int start;
  final int end;
  final int userId;
  final String displayLabel;

  const _MentionAnnotation({
    required this.start,
    required this.end,
    required this.userId,
    required this.displayLabel,
  });

  _MentionAnnotation copyWith({
    int? start,
    int? end,
    int? userId,
    String? displayLabel,
  }) {
    return _MentionAnnotation(
      start: start ?? this.start,
      end: end ?? this.end,
      userId: userId ?? this.userId,
      displayLabel: displayLabel ?? this.displayLabel,
    );
  }
}

class _ComposerToken {
  final String marker;
  final String query;
  final int start;
  final int end;

  const _ComposerToken({
    required this.marker,
    required this.query,
    required this.start,
    required this.end,
  });
}
