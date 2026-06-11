import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../state/admin_controller.dart';
import 'admin_social_restrictions_screen.dart';

class AdminSocialReportsScreen extends ConsumerStatefulWidget {
  const AdminSocialReportsScreen({super.key});

  @override
  ConsumerState<AdminSocialReportsScreen> createState() =>
      _AdminSocialReportsScreenState();
}

class _AdminSocialReportsScreenState
    extends ConsumerState<AdminSocialReportsScreen> {
  bool _loading = true;
  bool _busy = false;
  String _status = 'all';
  String? _error;
  List<Map<String, dynamic>> _postItems = const [];
  List<Map<String, dynamic>> _storyItems = const [];
  List<Map<String, dynamic>> _userItems = const [];

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
      final api = ref.read(adminApiProvider);
      final results = await Future.wait<dynamic>([
        api.socialPostReports(status: _status, limit: 120),
        api.socialStoryReports(status: _status, limit: 120),
        api.socialUserReports(limit: 120),
      ]);
      if (!mounted) return;

      setState(() {
        _postItems = _extractItems(results[0]);
        _storyItems = _extractItems(results[1]);
        _userItems = _extractItems(results[2]);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.adminSocialReportsLoadFailed,
        );
      });
    }
  }

  List<Map<String, dynamic>> _extractItems(dynamic value) {
    final map = value is Map<String, dynamic> ? value : <String, dynamic>{};
    final data = map['data'];
    final payload = data is Map ? Map<String, dynamic>.from(data) : map;
    return List<dynamic>.from(payload['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<String?> _askForNote({
    required String title,
    required String hint,
    String? initial,
  }) async {
    final direction = Directionality.of(context);
    final ctrl = TextEditingController(text: initial ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          title,
          textDirection: direction,
          textAlign: TextAlign.start,
        ),
        content: TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 5,
          textDirection: direction,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.commonConfirm),
          ),
        ],
      ),
    );
    final value = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return null;
    return value;
  }

  Future<void> _actOnPost({
    required int postId,
    required String action,
    String? note,
  }) async {
    final l10n = context.l10n;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminApiProvider)
          .reviewSocialPostReport(postId: postId, action: action, note: note);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminSocialReportsPostActionApplied)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: l10n.adminSocialReportsPostActionFailed),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveEditedPost(int postId) async {
    final l10n = context.l10n;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminApiProvider).approveEditedSocialPost(postId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminSocialReportsEditedPostApproved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: l10n.adminSocialReportsEditedPostApproveFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _actOnStory({
    required int storyId,
    required String action,
    String? note,
  }) async {
    final l10n = context.l10n;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminApiProvider)
          .reviewSocialStoryReport(
            storyId: storyId,
            action: action,
            note: note,
          );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminSocialReportsStoryActionApplied)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: l10n.adminSocialReportsStoryActionFailed),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveEditedStory(int storyId) async {
    final l10n = context.l10n;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminApiProvider).approveEditedSocialStory(storyId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminSocialReportsEditedStoryApproved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: l10n.adminSocialReportsEditedStoryApproveFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRestrictionsForUser(int userId) async {
    if (userId <= 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminSocialRestrictionsScreen(initialUserId: userId),
      ),
    );
  }

  Widget _buildStatusFilters() {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          Text(
            l10n.adminSocialReportsFilterLabel,
            textDirection: context.appTextDirection,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          ChoiceChip(
            label: Text(l10n.commonOpen),
            selected: _status == 'open',
            onSelected: (_) async {
              setState(() => _status = 'open');
              await _load();
            },
          ),
          ChoiceChip(
            label: Text(l10n.adminSocialReportsPendingEdit),
            selected: _status == 'pending_edit',
            onSelected: (_) async {
              setState(() => _status = 'pending_edit');
              await _load();
            },
          ),
          ChoiceChip(
            label: Text(l10n.commonAll),
            selected: _status == 'all',
            onSelected: (_) async {
              setState(() => _status = 'all');
              await _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReportsSummaryChip({
    required String moderationStatus,
    required int reportsCount,
  }) {
    final l10n = context.l10n;
    final pending = moderationStatus == 'pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: pending
            ? Colors.amber.withValues(alpha: 0.2)
            : Colors.red.withValues(alpha: 0.16),
      ),
      child: Text(
        pending
            ? l10n.adminSocialReportsPendingEdit
            : l10n.adminSocialReportsReportsCount(reportsCount),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildReportList(List<Map<String, dynamic>> reports) {
    final l10n = context.l10n;
    if (reports.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(height: 10),
        Text(
          l10n.adminSocialReportsRecentReports,
          textDirection: context.appTextDirection,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        for (final report in reports.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Builder(
              builder: (context) {
                final source = '${report['source'] ?? 'user'}'
                    .trim()
                    .toLowerCase();
                final sourceLabel = source == 'system'
                    ? l10n.adminSocialReportsSourceSystem
                    : l10n.adminSocialReportsSourceUser;
                final reason = '${report['reason'] ?? ''}'.trim();
                final details = '${report['details'] ?? ''}'.trim();
                final reporter =
                    '${report['reporterFullName'] ?? report['reporter_full_name'] ?? ''}'
                        .trim();
                final suffix = reporter.isEmpty ? '' : ' - $reporter';
                return Text(
                  '• [$sourceLabel] $reason${details.isEmpty ? '' : ' - $details'}$suffix',
                  textDirection: context.appTextDirection,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildModerationActions({
    required bool canModerate,
    required bool isPendingEdit,
    required VoidCallback onKeep,
    required Future<void> Function() onRequestEdit,
    required Future<void> Function() onDelete,
    required VoidCallback onApproveEdit,
  }) {
    final l10n = context.l10n;
    if (!canModerate) {
      return Text(
        l10n.adminSocialReportsReadOnly,
        textDirection: context.appTextDirection,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (isPendingEdit)
          FilledButton.icon(
            onPressed: _busy ? null : onApproveEdit,
            icon: const Icon(Icons.verified_outlined),
            label: Text(l10n.adminSocialReportsApproveEdit),
          ),
        if (!isPendingEdit)
          OutlinedButton.icon(
            onPressed: _busy ? null : onKeep,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(l10n.adminSocialReportsKeep),
          ),
        if (!isPendingEdit)
          OutlinedButton.icon(
            onPressed: _busy ? null : onRequestEdit,
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(l10n.adminSocialReportsRequestEdit),
          ),
        if (!isPendingEdit)
          FilledButton.icon(
            onPressed: _busy ? null : onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB42318),
            ),
            label: Text(l10n.adminSocialReportsDeleteWithPenalty),
          ),
      ],
    );
  }

  Widget _buildPostReportCard(
    Map<String, dynamic> item, {
    required bool canModerate,
  }) {
    final l10n = context.l10n;
    final postId = int.tryParse('${item['postId'] ?? ''}') ?? 0;
    final caption = '${item['caption'] ?? ''}'.trim();
    final author = '${item['authorFullName'] ?? l10n.commonUnknown}'.trim();
    final moderationStatus = '${item['moderationStatus'] ?? 'approved'}'
        .trim()
        .toLowerCase();
    final reportsCount = int.tryParse('${item['reportsCount'] ?? ''}') ?? 0;
    final reports = List<dynamic>.from(item['reports'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    final isPendingEdit = moderationStatus == 'pending';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              textDirection: context.appTextDirection,
              children: [
                Expanded(
                  child: Text(
                    author,
                    textDirection: context.appTextDirection,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                _buildReportsSummaryChip(
                  moderationStatus: moderationStatus,
                  reportsCount: reportsCount,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              caption.isEmpty ? l10n.adminSocialReportsNoText : caption,
              textDirection: context.appTextDirection,
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
            ),
            _buildReportList(reports),
            const SizedBox(height: 8),
            _buildModerationActions(
              canModerate: canModerate,
              isPendingEdit: isPendingEdit,
              onKeep: () => _actOnPost(postId: postId, action: 'keep'),
              onRequestEdit: () async {
                final note = await _askForNote(
                  title: l10n.adminSocialReportsRequestPostEditTitle,
                  hint: l10n.adminSocialReportsRequestPostEditHint,
                  initial: l10n.adminSocialReportsRequestEditDefaultNote,
                );
                if (note == null) return;
                await _actOnPost(
                  postId: postId,
                  action: 'request_edit',
                  note: note,
                );
              },
              onDelete: () async {
                final note = await _askForNote(
                  title: l10n.adminSocialReportsDeletePostTitle,
                  hint: l10n.adminSocialReportsDeletePostHint,
                );
                if (!mounted) return;
                await _actOnPost(postId: postId, action: 'delete', note: note);
              },
              onApproveEdit: () => _approveEditedPost(postId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryReportCard(
    Map<String, dynamic> item, {
    required bool canModerate,
  }) {
    final l10n = context.l10n;
    final storyId = int.tryParse('${item['storyId'] ?? ''}') ?? 0;
    final caption = '${item['caption'] ?? ''}'.trim();
    final author = '${item['authorFullName'] ?? l10n.commonUnknown}'.trim();
    final moderationStatus = '${item['moderationStatus'] ?? 'approved'}'
        .trim()
        .toLowerCase();
    final reportsCount = int.tryParse('${item['reportsCount'] ?? ''}') ?? 0;
    final mediaUrl = '${item['mediaUrl'] ?? ''}'.trim();
    final mediaKind = '${item['mediaKind'] ?? ''}'.trim().toLowerCase();
    final reports = List<dynamic>.from(item['reports'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    final isPendingEdit = moderationStatus == 'pending';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              textDirection: context.appTextDirection,
              children: [
                Expanded(
                  child: Text(
                    author,
                    textDirection: context.appTextDirection,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                _buildReportsSummaryChip(
                  moderationStatus: moderationStatus,
                  reportsCount: reportsCount,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (caption.isNotEmpty)
              Text(
                caption,
                textDirection: context.appTextDirection,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            if (mediaUrl.isNotEmpty) ...[
              if (caption.isNotEmpty) const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  mediaKind == 'video'
                      ? l10n.adminSocialReportsStoryVideoAttachment
                      : l10n.adminSocialReportsStoryImageAttachment,
                  textDirection: context.appTextDirection,
                  textAlign: TextAlign.start,
                ),
              ),
            ],
            _buildReportList(reports),
            const SizedBox(height: 8),
            _buildModerationActions(
              canModerate: canModerate,
              isPendingEdit: isPendingEdit,
              onKeep: () => _actOnStory(storyId: storyId, action: 'keep'),
              onRequestEdit: () async {
                final note = await _askForNote(
                  title: l10n.adminSocialReportsRequestStoryEditTitle,
                  hint: l10n.adminSocialReportsRequestStoryEditHint,
                  initial: l10n.adminSocialReportsRequestEditDefaultNote,
                );
                if (note == null) return;
                await _actOnStory(
                  storyId: storyId,
                  action: 'request_edit',
                  note: note,
                );
              },
              onDelete: () async {
                final note = await _askForNote(
                  title: l10n.adminSocialReportsDeleteStoryTitle,
                  hint: l10n.adminSocialReportsDeleteStoryHint,
                );
                if (!mounted) return;
                await _actOnStory(
                  storyId: storyId,
                  action: 'delete',
                  note: note,
                );
              },
              onApproveEdit: () => _approveEditedStory(storyId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserReportCard(
    Map<String, dynamic> item, {
    required bool canModerate,
  }) {
    final l10n = context.l10n;
    final reportedUserId = int.tryParse('${item['reportedUserId'] ?? ''}') ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${item['reportedUserFullName'] ?? ''}',
              textDirection: context.appTextDirection,
              textAlign: TextAlign.start,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '${l10n.adminSocialReportsReporterLabel} ${item['reporterFullName'] ?? ''}\n${l10n.commonReason}: ${item['reason'] ?? ''}',
              textDirection: context.appTextDirection,
              textAlign: TextAlign.start,
            ),
            if (canModerate && reportedUserId > 0) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _openRestrictionsForUser(reportedUserId),
                  icon: const Icon(Icons.gpp_bad_outlined),
                  label: Text(l10n.adminSocialReportsManageRestrictions),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String text) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Text(
            text,
            textDirection: context.appTextDirection,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final canModerate = auth.isSuperAdmin || auth.isAdmin;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.adminSocialReportsTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.adminSocialReportsPostsTab),
              Tab(text: l10n.adminSocialReportsStoriesTab),
              Tab(text: l10n.adminSocialReportsUsersTab),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Text(
                  _error!,
                  textDirection: context.appTextDirection,
                  textAlign: TextAlign.center,
                ),
              )
            : Column(
                children: [
                  _buildStatusFilters(),
                  Expanded(
                    child: TabBarView(
                      children: [
                        RefreshIndicator(
                          onRefresh: _load,
                          child: _postItems.isEmpty
                              ? _buildEmptyState(
                                  l10n.adminSocialReportsNoPostReports,
                                )
                              : ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    20,
                                  ),
                                  itemCount: _postItems.length,
                                  itemBuilder: (context, index) =>
                                      _buildPostReportCard(
                                        _postItems[index],
                                        canModerate: canModerate,
                                      ),
                                ),
                        ),
                        RefreshIndicator(
                          onRefresh: _load,
                          child: _storyItems.isEmpty
                              ? _buildEmptyState(
                                  l10n.adminSocialReportsNoStoryReports,
                                )
                              : ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    20,
                                  ),
                                  itemCount: _storyItems.length,
                                  itemBuilder: (context, index) =>
                                      _buildStoryReportCard(
                                        _storyItems[index],
                                        canModerate: canModerate,
                                      ),
                                ),
                        ),
                        RefreshIndicator(
                          onRefresh: _load,
                          child: _userItems.isEmpty
                              ? _buildEmptyState(
                                  l10n.adminSocialReportsNoUserReports,
                                )
                              : ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    20,
                                  ),
                                  itemCount: _userItems.length,
                                  itemBuilder: (context, index) =>
                                      _buildUserReportCard(
                                        _userItems[index],
                                        canModerate: canModerate,
                                      ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
