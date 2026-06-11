import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_chat_thread_screen.dart';
import 'social_community_chat_monitor_screen.dart';

class SocialChatQualityMonitorScreen extends ConsumerStatefulWidget {
  const SocialChatQualityMonitorScreen({super.key});

  @override
  ConsumerState<SocialChatQualityMonitorScreen> createState() =>
      _SocialChatQualityMonitorScreenState();
}

class _SocialChatQualityMonitorScreenState
    extends ConsumerState<SocialChatQualityMonitorScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<SocialChatMonitorThread> _threads = const [];
  bool _loading = true;
  String _query = '';
  String _kind = 'all';
  String? _error;

  SocialApi get _api => ref.read(socialApiProvider);

  intl.DateFormat get _dateFormat =>
      intl.DateFormat('d/M hh:mm a', context.isEnglishLocale ? 'en' : 'ar');

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    Future.microtask(_loadThreads);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchController.text.trim();
    if (next == _query) return;
    _query = next;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _loadThreads);
  }

  Future<void> _loadThreads() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final out = await _api.listAdminMonitoredThreads(
        search: _query,
        limit: 80,
        kind: _kind,
      );
      final raw = List<dynamic>.from(out['threads'] as List? ?? const []);
      final parsed = raw
          .map(
            (e) => SocialChatMonitorThread.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _threads = parsed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialChatQualityMonitorLoadFailed,
        );
      });
    }
  }

  Future<void> _openThread(SocialChatMonitorThread thread) async {
    if (thread.isCommunity) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SocialCommunityChatMonitorScreen(
            scopeType: thread.scopeType ?? '',
            scopeCode: thread.scopeCode ?? '',
            title: thread.scopeTitle ?? thread.participantLabel,
            subtitle: thread.scopeSubtitle,
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialChatThreadScreen(
          threadId: thread.threadId ?? thread.id,
          peerName: thread.participantLabel,
          readOnly: true,
          monitorMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    if (!auth.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.socialChatQualityMonitorTitle)),
        body: Center(
          child: Text(
            l10n.socialChatQualityMonitorSuperAdminOnly,
            textDirection: context.appTextDirection,
          ),
        ),
      );
    }

    return Directionality(
      textDirection: context.appTextDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.socialChatQualityMonitorTitle),
          actions: [
            IconButton(
              tooltip: l10n.commonRefresh,
              onPressed: _loading ? null : _loadThreads,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.socialChatQualityMonitorSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.commonClear,
                          onPressed: () {
                            _searchController.clear();
                            _loadThreads();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(
                    value: 'all',
                    icon: const Icon(Icons.forum_outlined),
                    label: Text(l10n.commonAll),
                  ),
                  ButtonSegment<String>(
                    value: 'direct',
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: Text(l10n.socialChatQualityMonitorDirect),
                  ),
                  ButtonSegment<String>(
                    value: 'community',
                    icon: const Icon(Icons.groups_2_outlined),
                    label: Text(l10n.socialBasmayaCommunity),
                  ),
                ],
                selected: <String>{_kind},
                onSelectionChanged: (next) {
                  final selected = next.isEmpty ? 'all' : next.first;
                  if (selected == _kind) return;
                  setState(() => _kind = selected);
                  _loadThreads();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.socialChatQualityMonitorSummary,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadThreads,
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
                    : _threads.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.only(top: 120),
                        children: [
                          const Icon(Icons.forum_outlined, size: 52),
                          const SizedBox(height: 10),
                          Text(
                            l10n.socialChatQualityMonitorEmpty,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                        itemCount: _threads.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final thread = _threads[index];
                          final preview =
                              thread.lastMessage?.previewText ??
                              l10n.socialChatQualityMonitorNoMessageYet;
                          final details = thread.isCommunity
                              ? (thread.scopeSubtitle ??
                                    l10n.socialChatQualityMonitorCommunityDetails)
                              : thread.participants
                                    .map(
                                      (item) =>
                                          '${item.fullName} (${item.phone ?? '-'})',
                                    )
                                    .join(' - ');

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openThread(thread),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.7),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: context.isEnglishLocale
                                        ? CrossAxisAlignment.start
                                        : CrossAxisAlignment.end,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              thread.isCommunity
                                                  ? (thread.scopeTitle ??
                                                        thread.participantLabel)
                                                  : thread.participantLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.12),
                                            ),
                                            child: Text(
                                              thread.isCommunity
                                                  ? l10n.socialBasmayaCommunity
                                                  : l10n.socialChatQualityMonitorDirect,
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        details,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        preview,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            thread.lastMessageAt == null
                                                ? l10n.socialChatQualityMonitorNoActivity
                                                : _dateFormat.format(
                                                    thread.lastMessageAt!
                                                        .toLocal(),
                                                  ),
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const Spacer(),
                                          const Icon(
                                            Icons.visibility_outlined,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
