import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/appbar_quick_actions.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_chat_thread_screen.dart';
import 'social_profile_screen.dart';
import 'widgets/social_identity_view.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialUserSearchScreen extends ConsumerStatefulWidget {
  const SocialUserSearchScreen({super.key});

  @override
  ConsumerState<SocialUserSearchScreen> createState() =>
      _SocialUserSearchScreenState();
}

class _SocialUserSearchScreenState
    extends ConsumerState<SocialUserSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loading = false;
  String? _error;
  String _activeQuery = '';
  int _activeTab = 0;
  List<SocialUserSearchResult> _results = const [];
  final Set<int> _busyUserIds = <int>{};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onQueryChanged);
    Future<void>.microtask(() => _loadResults(force: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), _loadResults);
  }

  Future<void> _loadResults({bool force = false}) async {
    final query = _searchCtrl.text.trim();
    if (!force && query == _activeQuery) return;

    setState(() {
      _activeQuery = query;
      _loading = true;
      _error = null;
    });

    try {
      final out = await ref
          .read(socialApiProvider)
          .searchUsers(search: query, limit: 80);
      final raw = List<dynamic>.from(out['users'] as List? ?? const []);
      final next = raw
          .map(
            (row) => SocialUserSearchResult.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _results = next;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialUserSearchLoadFailed,
        );
      });
    }
  }

  String _relationLabel(SocialRelation relation) {
    final l10n = context.l10n;
    if (relation.isBlockedByMe) {
      return l10n.socialUserSearchRelationBlockedByMe;
    }
    if (relation.isBlockedByOther) {
      return l10n.socialUserSearchRelationBlockedByOther;
    }
    if (relation.isAccepted) return l10n.socialUserSearchRelationAccepted;
    if (relation.isPendingOutgoing) {
      return l10n.socialUserSearchRelationPendingOutgoing;
    }
    if (relation.isPendingIncoming) {
      return l10n.socialUserSearchRelationPendingIncoming;
    }
    return l10n.socialUserSearchRelationOpenProfile;
  }

  String _followButtonLabel(SocialRelation relation) {
    final l10n = context.l10n;
    if (relation.isBlocked) return l10n.socialUserSearchActionBlocked;
    if (relation.isAccepted) return l10n.socialUserSearchActionFollowing;
    if (relation.isPendingOutgoing) {
      return l10n.socialUserSearchActionCancelRequest;
    }
    if (relation.isPendingIncoming) {
      return l10n.socialUserSearchActionAcceptFollow;
    }
    return l10n.socialUserSearchActionFollow;
  }

  String _friendButtonLabel(SocialRelation relation) {
    final l10n = context.l10n;
    if (relation.isBlocked) return l10n.socialUserSearchActionBlocked;
    if (relation.isAccepted) return l10n.socialUserSearchActionFriend;
    if (relation.isPendingOutgoing) {
      return l10n.socialUserSearchActionCancelRequest;
    }
    if (relation.isPendingIncoming) {
      return l10n.socialUserSearchActionAcceptFriend;
    }
    return l10n.socialUserSearchActionAddFriend;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textDirection: context.appTextDirection),
        ),
      );
  }

  void _patchRelationForUser(int userId, SocialRelation relation) {
    setState(() {
      _results = _results
          .map((item) {
            if (item.user.id != userId) return item;
            return SocialUserSearchResult(user: item.user, relation: relation);
          })
          .toList(growable: false);
    });
  }

  Future<void> _onRelationActionPressed(
    SocialUserSearchResult item, {
    required bool friendMode,
  }) async {
    final l10n = context.l10n;
    final user = item.user;
    final relation = item.relation;
    if (_busyUserIds.contains(user.id)) return;

    if (relation.isBlockedByOther) {
      _snack(l10n.socialUserSearchBlockedByOtherActionUnavailable);
      return;
    }
    if (relation.isBlockedByMe) {
      _snack(l10n.socialUserSearchUnblockFirst);
      return;
    }
    if (relation.isAccepted) return;

    setState(() => _busyUserIds.add(user.id));
    try {
      final api = ref.read(socialApiProvider);
      late final Map<String, dynamic> out;
      late final String successMessage;

      if (relation.isPendingIncoming) {
        out = await api.acceptRelationRequest(user.id);
        successMessage = friendMode
            ? l10n.socialUserSearchFriendRequestAccepted
            : l10n.socialUserSearchFollowRequestAccepted;
        await ref.read(socialControllerProvider.notifier).loadThreads();
      } else if (relation.isPendingOutgoing) {
        out = await api.cancelRelationRequest(user.id);
        successMessage = l10n.socialUserSearchRequestCancelled;
      } else {
        out = await api.sendRelationRequest(user.id);
        successMessage = friendMode
            ? l10n.socialUserSearchFriendRequestSent
            : l10n.socialUserSearchFollowRequestSent;
      }

      final rawRelation = out['relation'];
      if (rawRelation is Map) {
        _patchRelationForUser(
          user.id,
          SocialRelation.fromJson(Map<String, dynamic>.from(rawRelation)),
        );
      } else {
        await _loadResults(force: true);
      }
      _snack(successMessage);
    } catch (e) {
      _snack(mapAnyError(e, fallback: l10n.socialUserSearchActionFailed));
    } finally {
      if (mounted) {
        setState(() => _busyUserIds.remove(user.id));
      }
    }
  }

  Future<void> _openChatWithUser(SocialAuthor user) async {
    final l10n = context.l10n;
    final thread = await ref
        .read(socialControllerProvider.notifier)
        .createThreadWithUser(user.id);
    if (thread == null || !mounted) {
      _snack(l10n.socialUserSearchOpenChatFailed);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialChatThreadScreen(
          threadId: thread.id,
          peerName: socialPrimaryIdentityLabel(user),
          peerPhone: thread.peerPhone,
          peerUserId: user.id,
          peerImageUrl: (thread.peer.imageUrl ?? '').trim().isNotEmpty
              ? thread.peer.imageUrl
              : user.imageUrl,
          readOnly:
              thread.state.requestStatus.trim().toLowerCase() == 'pending' ||
              thread.state.inboxBucket.trim().toLowerCase() == 'requests',
        ),
      ),
    );
  }

  Future<void> _openProfile(SocialAuthor user) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SocialProfileScreen(userId: user.id, initialName: user.fullName),
      ),
    );
    if (!mounted) return;
    await _loadResults(force: true);
  }

  List<SocialUserSearchResult> _visibleResults() {
    if (_activeTab == 1) {
      return _results
          .where((item) => item.relation.isPendingIncoming)
          .toList(growable: false);
    }
    return _results;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _searchCtrl.text.trim();
    final incomingCount = _results
        .where((item) => item.relation.isPendingIncoming)
        .length;
    final visibleResults = _visibleResults();

    return Directionality(
      textDirection: context.appTextDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.socialUserSearchTitle),
          actions: const [
            AppBarQuickActions(compact: true, includeProfile: false),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: TextField(
                  controller: _searchCtrl,
                  textDirection: context.appTextDirection,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: l10n.socialUserSearchFieldLabel,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              _loadResults(force: true);
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Align(
                  alignment: context.isEnglishLocale
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        selected: _activeTab == 0,
                        onSelected: (selected) {
                          if (selected) setState(() => _activeTab = 0);
                        },
                        label: Text(l10n.commonAll),
                      ),
                      ChoiceChip(
                        selected: _activeTab == 1,
                        onSelected: (selected) {
                          if (selected) setState(() => _activeTab = 1);
                        },
                        label: Text(
                          l10n.socialUserSearchIncomingRequests(incomingCount),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: _error != null
                    ? _SearchState(
                        icon: Icons.error_outline_rounded,
                        title: _error!,
                        actionLabel: l10n.commonRetry,
                        onAction: () => _loadResults(force: true),
                      )
                    : visibleResults.isEmpty
                    ? _SearchState(
                        icon: Icons.person_search_rounded,
                        title: _activeTab == 1
                            ? l10n.socialUserSearchNoIncomingRequests
                            : query.isEmpty
                            ? l10n.socialUserSearchPrompt
                            : l10n.socialUserSearchNoResults,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
                        itemCount: visibleResults.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final item = visibleResults[index];
                          final user = item.user;
                          final relation = item.relation;
                          final busy = _busyUserIds.contains(user.id);
                          final phone = (user.phone ?? '').trim();
                          final relationLabel = _relationLabel(relation);

                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                10,
                                10,
                                10,
                                10,
                              ),
                              child: Column(
                                crossAxisAlignment: context.isEnglishLocale
                                    ? CrossAxisAlignment.start
                                    : CrossAxisAlignment.end,
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    onTap: () => _openProfile(user),
                                    leading: CircleAvatar(
                                      backgroundImage:
                                          (user.imageUrl ?? '')
                                              .trim()
                                              .isNotEmpty
                                          ? AppCachedImageProvider(
                                              user.imageUrl!.trim(),
                                            )
                                          : null,
                                      child:
                                          (user.imageUrl ?? '')
                                              .trim()
                                              .isNotEmpty
                                          ? null
                                          : const Icon(
                                              Icons.person_outline_rounded,
                                            ),
                                    ),
                                    title: Text(
                                      user.fullName,
                                      textDirection: context.appTextDirection,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      phone.isEmpty
                                          ? relationLabel
                                          : '$relationLabel • $phone',
                                      textDirection: context.appTextDirection,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: const Icon(
                                      Icons.open_in_new_rounded,
                                    ),
                                  ),
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (relation.isAccepted)
                                        FilledButton.tonalIcon(
                                          onPressed: busy
                                              ? null
                                              : () => _openChatWithUser(user),
                                          icon: const Icon(
                                            Icons.chat_bubble_outline_rounded,
                                          ),
                                          label: Text(
                                            l10n.socialUserSearchMessageAction,
                                          ),
                                        ),
                                      FilledButton.tonalIcon(
                                        onPressed: (busy || relation.isAccepted)
                                            ? null
                                            : () => _onRelationActionPressed(
                                                item,
                                                friendMode: false,
                                              ),
                                        icon: const Icon(
                                          Icons.person_add_alt_1_rounded,
                                        ),
                                        label: Text(
                                          _followButtonLabel(relation),
                                        ),
                                      ),
                                      FilledButton.icon(
                                        onPressed: (busy || relation.isAccepted)
                                            ? null
                                            : () => _onRelationActionPressed(
                                                item,
                                                friendMode: true,
                                              ),
                                        icon: busy
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.group_add_rounded,
                                              ),
                                        label: Text(
                                          _friendButtonLabel(relation),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SearchState({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              textDirection: context.appTextDirection,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
