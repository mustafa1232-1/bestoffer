import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../auth/state/auth_controller.dart';
import '../../models/social_models.dart';
import '../../state/social_controller.dart';
import 'social_identity_view.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialGroupThreadSheet extends ConsumerStatefulWidget {
  final SocialChatThread initialThread;
  final ValueChanged<SocialChatThread>? onThreadUpdated;
  final VoidCallback? onLeftGroup;

  const SocialGroupThreadSheet({
    super.key,
    required this.initialThread,
    this.onThreadUpdated,
    this.onLeftGroup,
  });

  @override
  ConsumerState<SocialGroupThreadSheet> createState() =>
      _SocialGroupThreadSheetState();
}

class _SocialGroupThreadSheetState
    extends ConsumerState<SocialGroupThreadSheet> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  late SocialChatThread _thread;
  List<SocialThreadMember> _members = const <SocialThreadMember>[];

  @override
  void initState() {
    super.initState();
    _thread = widget.initialThread;
    Future<void>.microtask(_load);
  }

  bool get _canManage => _thread.group?.canManage == true;
  int? get _currentUserId => ref.read(authControllerProvider).user?.id;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(socialApiProvider)
          .getGroupThreadDetails(_thread.id);
      final thread = SocialChatThread.fromJson(
        Map<String, dynamic>.from(out['thread'] as Map? ?? const {}),
      );
      final members = List<dynamic>.from(out['members'] as List? ?? const [])
          .map(
            (entry) => SocialThreadMember.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _thread = thread;
        _members = members;
        _loading = false;
      });
      widget.onThreadUpdated?.call(thread);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.socialChatThreadGroupLoadFailed,
        );
      });
    }
  }

  Future<void> _renameGroup() async {
    final controller = TextEditingController(text: _thread.displayTitle);
    final l10n = context.l10n;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.socialChatThreadGroupRename),
        content: TextField(
          controller: controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: l10n.socialChatThreadGroupRenameHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.socialChatThreadGroupRenameSave),
          ),
        ],
      ),
    );
    if (!mounted || title == null) return;
    if (title.trim().isEmpty) {
      setState(() => _error = l10n.socialChatThreadsCreateGroupNameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(socialApiProvider)
          .updateGroupThread(_thread.id, title: title);
      final thread = SocialChatThread.fromJson(
        Map<String, dynamic>.from(out['thread'] as Map? ?? const {}),
      );
      if (!mounted) return;
      setState(() {
        _thread = thread;
        _busy = false;
      });
      widget.onThreadUpdated?.call(thread);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = mapAnyError(
          error,
          fallback: l10n.socialChatThreadsCreateGroupFailed,
        );
      });
    }
  }

  Future<void> _addMembers() async {
    final existingIds = _members.map((entry) => entry.userId).toSet();
    final selectedUserIds = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddGroupMembersSheet(existingUserIds: existingIds),
    );
    if (!mounted || selectedUserIds == null || selectedUserIds.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(socialApiProvider)
          .addGroupThreadMembers(_thread.id, memberIds: selectedUserIds);
      final thread = SocialChatThread.fromJson(
        Map<String, dynamic>.from(out['thread'] as Map? ?? const {}),
      );
      final members = List<dynamic>.from(out['members'] as List? ?? const [])
          .map(
            (entry) => SocialThreadMember.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _thread = thread;
        _members = members;
        _busy = false;
      });
      widget.onThreadUpdated?.call(thread);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.socialChatThreadGroupAddMembersFailed,
        );
      });
    }
  }

  Future<void> _removeMember(SocialThreadMember member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.socialChatThreadGroupRemoveMember),
        content: Text(
          context.l10n.socialChatThreadGroupRemoveMemberConfirm(
            member.user.fullName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonRemove),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(socialApiProvider)
          .removeGroupThreadMember(_thread.id, memberUserId: member.userId);
      final threadRaw = out['thread'];
      final members = List<dynamic>.from(out['members'] as List? ?? const [])
          .map(
            (entry) => SocialThreadMember.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        if (threadRaw is Map) {
          _thread = SocialChatThread.fromJson(
            Map<String, dynamic>.from(threadRaw),
          );
          widget.onThreadUpdated?.call(_thread);
        }
        _members = members;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.socialChatThreadGroupRemoveMemberFailed,
        );
      });
    }
  }

  Future<void> _leaveGroup() async {
    final l10n = context.l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.socialChatThreadGroupLeave),
        content: Text(l10n.socialChatThreadGroupLeaveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.socialChatThreadGroupLeave),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(socialApiProvider).leaveGroupThread(_thread.id);
      if (!mounted) return;
      widget.onLeftGroup?.call();
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = mapAnyError(
          error,
          fallback: l10n.socialChatThreadGroupLeaveFailed,
        );
      });
    }
  }

  String _presenceLabel(SocialThreadMember member) {
    final presence = member.presence;
    if (presence.canSeeOnlineStatus && presence.isOnline) {
      return context.l10n.socialChatThreadOnlineNow;
    }
    if (presence.canSeeLastSeen && presence.lastSeenAt != null) {
      return context.l10n.socialChatThreadLastSeen(
        MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay.fromDateTime(member.presence.lastSeenAt!.toLocal()),
          alwaysUse24HourFormat: false,
        ),
      );
    }
    return switch (member.memberRole) {
      'owner' => context.l10n.socialChatThreadGroupRoleOwner,
      'admin' => context.l10n.socialChatThreadGroupRoleAdmin,
      _ => context.l10n.socialChatThreadGroupRoleMember,
    };
  }

  bool _canRemoveMember(SocialThreadMember member) {
    if (!_canManage) return false;
    if (member.userId == _currentUserId) return false;
    if (member.isOwner) return false;
    if (_thread.group?.memberRole == 'admin' && member.canManage) return false;
    return true;
  }

  bool _canManageMemberRole(SocialThreadMember member) {
    return (_thread.group?.memberRole ?? '') == 'owner' &&
        member.userId != _currentUserId &&
        !member.isOwner;
  }

  Future<void> _updateMemberRole(
    SocialThreadMember member, {
    required String memberRole,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(socialApiProvider)
          .updateGroupThreadMemberRole(
            _thread.id,
            memberUserId: member.userId,
            memberRole: memberRole,
          );
      final threadRaw = out['thread'];
      final members = List<dynamic>.from(out['members'] as List? ?? const [])
          .map(
            (entry) => SocialThreadMember.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        if (threadRaw is Map) {
          _thread = SocialChatThread.fromJson(
            Map<String, dynamic>.from(threadRaw),
          );
          widget.onThreadUpdated?.call(_thread);
        }
        _members = members;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      final fallback = memberRole == 'admin'
          ? context.l10n.socialChatThreadGroupPromoteAdminFailed
          : context.l10n.socialChatThreadGroupDemoteAdminFailed;
      setState(() {
        _busy = false;
        _error = mapAnyError(error, fallback: fallback);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.socialChatThreadGroupManage,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                _thread.displayTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                l10n.socialChatThreadsGroupMembersCount(_members.length),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if ((_error ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_canManage)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _renameGroup,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(l10n.socialChatThreadGroupRename),
                    ),
                  if (_canManage)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _addMembers,
                      icon: const Icon(Icons.person_add_alt_rounded),
                      label: Text(l10n.socialChatThreadGroupAddMembers),
                    ),
                  if ((_thread.group?.memberRole ?? '') != 'owner')
                    TextButton.icon(
                      onPressed: _busy ? null : _leaveGroup,
                      icon: const Icon(Icons.exit_to_app_rounded),
                      label: Text(l10n.socialChatThreadGroupLeave),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _members.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final member = _members[index];
                        return Material(
                          color: Colors.transparent,
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            tileColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            leading: CircleAvatar(
                              backgroundImage:
                                  (member.user.imageUrl ?? '').trim().isNotEmpty
                                  ? AppCachedImageProvider(
                                      member.user.imageUrl!,
                                    )
                                  : null,
                              child: (member.user.imageUrl ?? '').trim().isEmpty
                                  ? const Icon(Icons.person_outline)
                                  : null,
                            ),
                            title: SocialIdentityView(author: member.user),
                            subtitle: Text(
                              _presenceLabel(member),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing:
                                _canManageMemberRole(member) ||
                                    _canRemoveMember(member)
                                ? PopupMenuButton<String>(
                                    enabled: !_busy,
                                    onSelected: (value) {
                                      switch (value) {
                                        case 'promote_admin':
                                          unawaited(
                                            _updateMemberRole(
                                              member,
                                              memberRole: 'admin',
                                            ),
                                          );
                                          break;
                                        case 'demote_admin':
                                          unawaited(
                                            _updateMemberRole(
                                              member,
                                              memberRole: 'member',
                                            ),
                                          );
                                          break;
                                        case 'remove':
                                          unawaited(_removeMember(member));
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      if (_canManageMemberRole(member) &&
                                          member.memberRole != 'admin')
                                        PopupMenuItem<String>(
                                          value: 'promote_admin',
                                          child: Text(
                                            l10n.socialChatThreadGroupPromoteAdmin,
                                          ),
                                        ),
                                      if (_canManageMemberRole(member) &&
                                          member.memberRole == 'admin')
                                        PopupMenuItem<String>(
                                          value: 'demote_admin',
                                          child: Text(
                                            l10n.socialChatThreadGroupDemoteAdmin,
                                          ),
                                        ),
                                      if (_canRemoveMember(member))
                                        PopupMenuItem<String>(
                                          value: 'remove',
                                          child: Text(
                                            l10n.socialChatThreadGroupRemoveMember,
                                          ),
                                        ),
                                    ],
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddGroupMembersSheet extends ConsumerStatefulWidget {
  final Set<int> existingUserIds;

  const _AddGroupMembersSheet({required this.existingUserIds});

  @override
  ConsumerState<_AddGroupMembersSheet> createState() =>
      _AddGroupMembersSheetState();
}

class _AddGroupMembersSheetState extends ConsumerState<_AddGroupMembersSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  List<SocialUserSearchResult> _results = const <SocialUserSearchResult>[];
  final Set<int> _selectedUserIds = <int>{};

  int? get _currentUserId => ref.read(authControllerProvider).user?.id;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadUsers);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({String search = ''}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(socialApiProvider)
          .searchUsers(search: search, limit: search.trim().isEmpty ? 28 : 50);
      final users = List<dynamic>.from(out['users'] ?? const <dynamic>[])
          .map(
            (entry) => SocialUserSearchResult.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .where(
            (entry) =>
                entry.user.id != _currentUserId &&
                !widget.existingUserIds.contains(entry.user.id),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _results = users;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.socialChatThreadGroupLoadFailed,
        );
      });
    }
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 280),
      () => _loadUsers(search: value.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.76,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                l10n.socialChatThreadGroupAddMembers,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: _scheduleSearch,
                decoration: InputDecoration(
                  hintText: l10n.socialChatThreadsCreateGroupSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.commonClear,
                          onPressed: () {
                            _searchController.clear();
                            _loadUsers();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                l10n.socialChatThreadsCreateGroupSelectedCount(
                  _selectedUserIds.length,
                ),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if ((_error ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          l10n.socialChatThreadsCreateGroupNoUsers,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _results.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        final selected = _selectedUserIds.contains(
                          result.user.id,
                        );
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (_) {
                            setState(() {
                              if (selected) {
                                _selectedUserIds.remove(result.user.id);
                              } else {
                                _selectedUserIds.add(result.user.id);
                              }
                            });
                          },
                          title: SocialIdentityView(author: result.user),
                          subtitle: Text(
                            result.user.phone ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondary: CircleAvatar(
                            backgroundImage:
                                (result.user.imageUrl ?? '').trim().isNotEmpty
                                ? AppCachedImageProvider(result.user.imageUrl!)
                                : null,
                            child: (result.user.imageUrl ?? '').trim().isEmpty
                                ? const Icon(Icons.person_outline)
                                : null,
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: _selectedUserIds.isEmpty
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pop(_selectedUserIds.toList(growable: false)),
                icon: const Icon(Icons.person_add_alt_rounded),
                label: Text(l10n.socialChatThreadGroupAddMembers),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
