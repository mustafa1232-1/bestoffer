import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';

class SocialCommunityChatMonitorScreen extends ConsumerStatefulWidget {
  final String scopeType;
  final String scopeCode;
  final String? title;
  final String? subtitle;

  const SocialCommunityChatMonitorScreen({
    super.key,
    required this.scopeType,
    required this.scopeCode,
    this.title,
    this.subtitle,
  });

  @override
  ConsumerState<SocialCommunityChatMonitorScreen> createState() =>
      _SocialCommunityChatMonitorScreenState();
}

class _SocialCommunityChatMonitorScreenState
    extends ConsumerState<SocialCommunityChatMonitorScreen> {
  List<SocialCommunityChatMessage> _messages = const [];
  SocialChatMonitorThread? _chat;
  int? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  SocialApi get _api => ref.read(socialApiProvider);

  intl.DateFormat get _dateFormat =>
      intl.DateFormat('d/M hh:mm a', context.isEnglishLocale ? 'en' : 'ar');

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _load(initial: true));
  }

  Future<void> _load({bool initial = false, bool loadMore = false}) async {
    if (_loading && !loadMore) return;
    if (loadMore && (_loadingMore || _nextCursor == null)) return;
    if (mounted) {
      setState(() {
        if (loadMore) {
          _loadingMore = true;
        } else {
          _loading = true;
          _error = null;
        }
      });
    }
    try {
      final out = await _api.listAdminMonitoredCommunityMessages(
        scopeType: widget.scopeType,
        scopeCode: widget.scopeCode,
        limit: 60,
        beforeId: loadMore ? _nextCursor : null,
      );
      final chatRaw = out['chat'];
      final messagesRaw = List<dynamic>.from(
        out['messages'] as List? ?? const [],
      );
      final parsed = messagesRaw
          .map(
            (e) => SocialCommunityChatMessage.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _chat = chatRaw is Map
            ? SocialChatMonitorThread.fromJson(
                Map<String, dynamic>.from(chatRaw),
              )
            : _chat;
        _nextCursor = int.tryParse('${out['nextCursor'] ?? ''}');
        if (loadMore) {
          _messages = [...parsed, ..._messages];
        } else if (initial) {
          _messages = parsed;
        } else {
          final byId = <int, SocialCommunityChatMessage>{
            for (final message in _messages) message.id: message,
            for (final message in parsed) message.id: message,
          };
          final merged = byId.values.toList()
            ..sort((a, b) => a.id.compareTo(b.id));
          _messages = merged;
        }
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialCommunityChatMonitorLoadFailed,
        );
      });
    }
  }

  Widget _buildMessageTile(SocialCommunityChatMessage message) {
    final l10n = context.l10n;
    final senderName = message.isSystem
        ? l10n.socialCommunityChatMonitorSystemMessage
        : (message.sender.fullName.trim().isNotEmpty
              ? message.sender.fullName
              : l10n.commonUnknownUser);
    final subtitle = message.isDeleted
        ? l10n.socialCommunityChatMonitorDeletedMessage
        : (message.body.trim().isNotEmpty
              ? message.body.trim()
              : l10n.socialCommunityChatMonitorEmptyBody);
    final meta = <String>[
      if (message.createdAt != null)
        _dateFormat.format(message.createdAt!.toLocal()),
      if ((message.sender.phone ?? '').trim().isNotEmpty)
        message.sender.phone!.trim(),
    ].join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: context.isEnglishLocale
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: context.isEnglishLocale
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.end,
                  children: [
                    Text(
                      senderName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (message.isSystem)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l10n.socialCommunityChatMonitorSystemChip,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: message.isDeleted
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.onSurface,
              fontStyle: message.isDeleted
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title =
        widget.title ??
        _chat?.scopeTitle ??
        l10n.socialCommunityChatMonitorTitle;
    final subtitle = widget.subtitle ?? _chat?.scopeSubtitle;

    return Directionality(
      textDirection: context.appTextDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: context.isEnglishLocale
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Text(title),
              if ((subtitle ?? '').trim().isNotEmpty)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: l10n.commonRefresh,
              onPressed: _loading ? null : () => _load(initial: false),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => _load(initial: false),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? ListView(
                  padding: const EdgeInsets.only(top: 120),
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 42,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 10),
                    Text(_error!, textAlign: TextAlign.center),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer.withValues(alpha: 0.5),
                      ),
                      child: Column(
                        crossAxisAlignment: context.isEnglishLocale
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.end,
                        children: [
                          Text(
                            l10n.socialCommunityChatMonitorHeaderTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.socialCommunityChatMonitorHeaderSubtitle,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_messages.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 80),
                        child: Text(
                          l10n.socialCommunityChatMonitorEmpty,
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ..._messages.map(_buildMessageTile),
                    if (_nextCursor != null) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: _loadingMore
                              ? null
                              : () => _load(loadMore: true),
                          icon: _loadingMore
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more_rounded),
                          label: Text(l10n.socialCommunityChatMonitorLoadMore),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
