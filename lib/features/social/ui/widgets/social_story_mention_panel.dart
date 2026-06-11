import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../models/social_models.dart';
import '../../state/social_controller.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialStoryMentionPanel extends ConsumerStatefulWidget {
  final void Function(int userId, String displayLabel)? onMentionSelected;

  const SocialStoryMentionPanel({super.key, this.onMentionSelected});

  @override
  ConsumerState<SocialStoryMentionPanel> createState() =>
      _SocialStoryMentionPanelState();
}

class _SocialStoryMentionPanelState
    extends ConsumerState<SocialStoryMentionPanel> {
  final TextEditingController _controller = TextEditingController(text: '@');
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<SocialAuthor> _users = const <SocialAuthor>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _focusNode.requestFocus());
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (!query.startsWith('@')) {
      setState(() {
        _users = const <SocialAuthor>[];
        _error = null;
        _loading = false;
      });
      return;
    }
    final term = query.substring(1).trim();
    if (term.isEmpty) {
      setState(() {
        _users = const <SocialAuthor>[];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(socialApiProvider)
          .listMentionSuggestions(search: term);
      final raw = List<dynamic>.from(out['users'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        _users = raw
            .map(
              (row) =>
                  SocialAuthor.fromJson(Map<String, dynamic>.from(row as Map)),
            )
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _users = const <SocialAuthor>[];
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.socialStoryMentionLoadFailed,
        );
      });
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _search(value));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: l10n.socialStoryMentionHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if ((_error ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else if (_users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.socialStoryMentionEmpty,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _users.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final user = _users[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: (user.imageUrl ?? '').trim().isNotEmpty
                          ? AppCachedImageProvider(user.imageUrl!)
                          : null,
                      child: (user.imageUrl ?? '').trim().isEmpty
                          ? const Icon(Icons.person_outline)
                          : null,
                    ),
                    title: Text(user.fullName),
                    subtitle: Text(
                      (user.username ?? '').trim().isNotEmpty
                          ? '@${user.username}'
                          : user.role,
                    ),
                    onTap: () => widget.onMentionSelected?.call(
                      user.id,
                      (user.username ?? '').trim().isNotEmpty
                          ? user.username!.trim()
                          : user.fullName,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
