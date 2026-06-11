import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';
import 'admin_social_users_screen.dart';

class AdminSocialRestrictionsScreen extends ConsumerStatefulWidget {
  final int? initialUserId;

  const AdminSocialRestrictionsScreen({super.key, this.initialUserId});

  @override
  ConsumerState<AdminSocialRestrictionsScreen> createState() =>
      _AdminSocialRestrictionsScreenState();
}

class _AdminSocialRestrictionsScreenState
    extends ConsumerState<AdminSocialRestrictionsScreen> {
  final _userIdCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _loading = false;
  bool _busy = false;
  String? _error;
  String _capabilityKey = 'post_create';
  int _durationDays = 7;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    if (widget.initialUserId != null && widget.initialUserId! > 0) {
      _userIdCtrl.text = '${widget.initialUserId}';
      Future.microtask(_load);
    }
  }

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  int? get _userId => int.tryParse(_userIdCtrl.text.trim());

  Map<String, dynamic> _unwrapPayload(Map<String, dynamic> raw) {
    final data = raw['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return raw;
  }

  String _capabilityLabel(String value) {
    switch (value) {
      case 'story_create':
        return context.l10n.adminSocialRestrictionsStoryPublishing;
      case 'reel_create':
        return context.l10n.adminSocialRestrictionsReelsPublishing;
      case 'comment_create':
        return context.l10n.commonComments;
      case 'community_post_create':
        return context.l10n.adminSocialRestrictionsCommunityPosting;
      default:
        return context.l10n.adminSocialRestrictionsRegularPosting;
    }
  }

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null || userId <= 0) {
      setState(() {
        _items = const [];
        _error = context.l10n.adminSocialRestrictionsInvalidUserId;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(adminApiProvider)
          .socialRestrictionsForUser(userId);
      final payload = _unwrapPayload(out);
      if (!mounted) return;
      setState(() {
        _items = List<dynamic>.from(payload['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.adminSocialRestrictionsLoadFailed,
        );
      });
    }
  }

  Future<void> _createRestriction() async {
    final userId = _userId;
    if (userId == null || userId <= 0 || _busy) return;
    setState(() => _busy = true);
    try {
      final endsAt = _durationDays <= 0
          ? null
          : DateTime.now().toUtc().add(Duration(days: _durationDays));
      await ref
          .read(adminApiProvider)
          .createSocialRestriction(
            userId: userId,
            capabilityKey: _capabilityKey,
            reason: _reasonCtrl.text.trim(),
            endsAt: endsAt,
          );
      if (!mounted) return;
      _reasonCtrl.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.adminSocialRestrictionsCreated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.adminSocialRestrictionsCreateFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeRestriction(int restrictionId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminApiProvider).revokeSocialRestriction(restrictionId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.adminSocialRestrictionsRevoked)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.adminSocialRestrictionsRevokeFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickUser() async {
    final pickedUserId = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => const AdminSocialUsersScreen(selectionMode: true),
      ),
    );
    if (!mounted || pickedUserId == null || pickedUserId <= 0) return;
    _userIdCtrl.text = '$pickedUserId';
    await _load();
  }

  Widget _durationChip(int days) {
    final label = days <= 0
        ? context.l10n.commonOpenEnded
        : days == 1
        ? context.l10n.commonDurationOneDay
        : days == 7
        ? context.l10n.commonDurationSevenDays
        : days == 30
        ? context.l10n.commonDurationThirtyDays
        : '$days';
    return ChoiceChip(
      label: Text(label),
      selected: _durationDays == days,
      onSelected: (_) => setState(() => _durationDays = days),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.adminDashboardSocialRestrictions),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      context.l10n.adminSocialRestrictionsManageByUser,
                      textDirection: Directionality.of(context),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _userIdCtrl,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: context.l10n.commonUserId,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _loading ? null : _load,
                          icon: const Icon(Icons.search_rounded),
                          label: Text(context.l10n.commonLoad),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _pickUser,
                          icon: const Icon(Icons.person_search_rounded),
                          label: const Text('اختيار مستخدم'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _capabilityKey,
                      decoration: InputDecoration(
                        labelText: context.l10n.commonCapability,
                      ),
                      items:
                          const [
                                'post_create',
                                'story_create',
                                'reel_create',
                                'comment_create',
                                'community_post_create',
                              ]
                              .map(
                                (value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(_capabilityLabel(value)),
                                ),
                              )
                              .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _capabilityKey = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _reasonCtrl,
                      minLines: 2,
                      maxLines: 4,
                      textDirection: Directionality.of(context),
                      decoration: InputDecoration(
                        labelText:
                            context.l10n.adminSocialRestrictionsReasonLabel,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _durationChip(1),
                        _durationChip(7),
                        _durationChip(30),
                        _durationChip(0),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _createRestriction,
                        icon: const Icon(Icons.shield_outlined),
                        label: Text(context.l10n.adminSocialRestrictionsCreate),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textDirection: Directionality.of(context),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(
                  child: Text(
                    context.l10n.adminSocialRestrictionsEmpty,
                    textDirection: Directionality.of(context),
                  ),
                ),
              )
            else
              ..._items.map((item) {
                final isActive = item['isActive'] == true;
                final restrictionId = int.tryParse('${item['id'] ?? ''}') ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            textDirection: Directionality.of(context),
                            children: [
                              Expanded(
                                child: Text(
                                  _capabilityLabel(
                                    '${item['capabilityKey'] ?? ''}',
                                  ),
                                  textDirection: Directionality.of(context),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color:
                                      (isActive
                                              ? const Color(0xFFDC2626)
                                              : const Color(0xFF64748B))
                                          .withValues(alpha: 0.14),
                                ),
                                child: Text(
                                  isActive
                                      ? context.l10n.commonActive
                                      : context.l10n.commonInactive,
                                  style: TextStyle(
                                    color: isActive
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF64748B),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${context.l10n.commonUser}: ${item['userFullName'] ?? ''}  (#${item['userId'] ?? ''})',
                            textDirection: Directionality.of(context),
                          ),
                          if ('${item['userPhone'] ?? ''}'.trim().isNotEmpty)
                            Text(
                              '${context.l10n.commonPhone}: ${item['userPhone']}',
                              textDirection: Directionality.of(context),
                            ),
                          if ('${item['reason'] ?? ''}'.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '${context.l10n.commonReason}: ${item['reason']}',
                                textDirection: Directionality.of(context),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${context.l10n.commonStarts}: ${item['startsAt'] ?? '-'}',
                              textDirection: Directionality.of(context),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${context.l10n.commonEnds}: ${item['endsAt'] ?? context.l10n.commonOpenEnded}',
                              textDirection: Directionality.of(context),
                            ),
                          ),
                          if (isActive)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _revokeRestriction(restrictionId),
                                  icon: const Icon(Icons.remove_circle_outline),
                                  label: Text(
                                    context
                                        .l10n
                                        .adminSocialRestrictionsRevokeAction,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
