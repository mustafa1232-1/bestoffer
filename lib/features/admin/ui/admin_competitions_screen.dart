import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/parsers.dart';
import '../state/admin_controller.dart';

class AdminCompetitionsScreen extends ConsumerStatefulWidget {
  const AdminCompetitionsScreen({super.key});

  @override
  ConsumerState<AdminCompetitionsScreen> createState() =>
      _AdminCompetitionsScreenState();
}

class _AdminCompetitionsScreenState
    extends ConsumerState<AdminCompetitionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _refreshToken = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    Future.microtask(() async {
      await ref.read(adminControllerProvider.notifier).refreshPlatformKpisV2();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return tryParseLocalizedInt(value) ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return tryParseLocalizedDouble(value) ?? 0;
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<void> _refreshAll() async {
    await ref.read(adminControllerProvider.notifier).refreshPlatformKpisV2();
    if (!mounted) return;
    setState(() => _refreshToken += 1);
  }

  Future<void> _openCompetitionDetails(int competitionId) async {
    final l10n = context.l10n;
    final details = await ref
        .read(adminControllerProvider.notifier)
        .fetchCompetitionDetailsV2(competitionId);
    if (!mounted || details == null) return;

    final competition = Map<String, dynamic>.from(
      (details['competition'] as Map?) ?? const {},
    );
    final tiers = _mapList(competition['tiers']);
    final leaderboard = _mapList(details['leaderboard']);
    final winners = _mapList(details['winners']);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${competition['title'] ?? l10n.adminCompetitionsCompetitionFallback}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if ('${competition['description'] ?? ''}'.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${competition['description']}'),
              ),
            const SizedBox(height: 12),
            Text(
              l10n.adminCompetitionsTiers,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...tiers.map(
              (tier) => ListTile(
                dense: true,
                title: Text('${tier['title'] ?? ''}'),
                subtitle: Text(
                  l10n.adminCompetitionsTierMinimumOrders(
                    '${_asInt(tier['requiredCompletedOrders'] ?? tier['required_completed_orders'])}',
                  ),
                ),
                trailing: Text(
                  formatIqd(
                    _asDouble(tier['rewardAmount'] ?? tier['reward_amount']),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.adminCompetitionsLeaderboard,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (leaderboard.isEmpty)
              Text(l10n.adminCompetitionsNoParticipants)
            else
              ...leaderboard.take(50).toList().asMap().entries.map((entry) {
                final row = entry.value;
                return ListTile(
                  dense: true,
                  leading: Text('#${entry.key + 1}'),
                  title: Text(
                    '${row['full_name'] ?? l10n.adminCompetitionsCourierFallback}',
                  ),
                  subtitle: Text(
                    l10n.adminCompetitionsCounted(
                      '${_asInt(row['current_value'])}',
                    ),
                  ),
                  trailing: Text('${row['current_rank_title'] ?? '-'}'),
                );
              }),
            const SizedBox(height: 12),
            Text(
              l10n.adminCompetitionsWinners,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (winners.isEmpty)
              Text(l10n.adminCompetitionsNoWinners)
            else
              ...winners.map(
                (row) => ListTile(
                  dense: true,
                  title: Text(
                    '${row['full_name'] ?? l10n.adminCompetitionsCourierFallback}',
                  ),
                  subtitle: Text(
                    l10n.adminCompetitionsWinnerSummary(
                      '${row['final_rank_title'] ?? '-'}',
                      '${_asInt(row['final_completed_orders'])}',
                    ),
                  ),
                  trailing: Text(formatIqd(_asDouble(row['reward_amount']))),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    final platform = Map<String, dynamic>.from(
      (state.platformKpisV2['platform'] as Map?) ?? const {},
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminCompetitionsTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.adminCompetitionsTabActive),
            Tab(text: l10n.adminCompetitionsTabHistory),
            Tab(text: l10n.adminCompetitionsTabCreate),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _KpiChip(
                  label: l10n.adminCompetitionsKpiTotal,
                  value: '${_asInt(platform['totalCompetitions'])}',
                ),
                _KpiChip(
                  label: l10n.adminCompetitionsKpiActive,
                  value: '${_asInt(platform['activeCompetitions'])}',
                ),
                _KpiChip(
                  label: l10n.adminCompetitionsKpiEnded,
                  value: '${_asInt(platform['endedCompetitions'])}',
                ),
                _KpiChip(
                  label: l10n.adminCompetitionsKpiRewards,
                  value: formatIqd(_asDouble(platform['competitionRewards'])),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _AdminCompetitionListTab(
                  status: 'active',
                  refreshToken: _refreshToken,
                  onOpenDetails: _openCompetitionDetails,
                  onUpdated: _refreshAll,
                ),
                _AdminCompetitionListTab(
                  status: 'ended',
                  refreshToken: _refreshToken,
                  onOpenDetails: _openCompetitionDetails,
                  onUpdated: _refreshAll,
                ),
                _AdminCompetitionCreateTab(onCreated: _refreshAll),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminCompetitionListTab extends ConsumerStatefulWidget {
  const _AdminCompetitionListTab({
    required this.status,
    required this.refreshToken,
    required this.onOpenDetails,
    required this.onUpdated,
  });

  final String status;
  final int refreshToken;
  final Future<void> Function(int competitionId) onOpenDetails;
  final Future<void> Function() onUpdated;

  @override
  ConsumerState<_AdminCompetitionListTab> createState() =>
      _AdminCompetitionListTabState();
}

class _AdminCompetitionListTabState
    extends ConsumerState<_AdminCompetitionListTab> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return tryParseLocalizedInt(value) ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return tryParseLocalizedDouble(value) ?? 0;
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ref
          .read(adminApiProvider)
          .competitionsV2(status: widget.status);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = _mapList(data['competitions']);
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapDioError(
          e,
          fallback: context.l10n.adminCompetitionsServerUnavailable,
          appendRequestId: true,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.adminCompetitionsLoadFailed;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant _AdminCompetitionListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status ||
        oldWidget.refreshToken != widget.refreshToken) {
      Future.microtask(_load);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _InlineError(text: _error!, onRetry: _load),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Center(
                child: Text(l10n.adminCompetitionsListEmpty),
              ),
            )
          else
            ..._items.map((competition) {
              final competitionId = _asInt(competition['id']);
              final tiers = _mapList(competition['tiers']);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${competition['title'] ?? l10n.adminCompetitionsCompetitionFallback}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (widget.status == 'active')
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: state.saving
                                      ? null
                                      : () async {
                                          final updated =
                                              await showModalBottomSheet<bool>(
                                                context: context,
                                                isScrollControlled: true,
                                                builder: (_) =>
                                                    _AdminCompetitionEditSheet(
                                                      competition: competition,
                                                    ),
                                              );
                                          if (!mounted || updated != true) {
                                            return;
                                        }
                                          await _load();
                                          await widget.onUpdated();
                                        },
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: l10n.adminCompetitionsEditTooltip,
                                ),
                                IconButton(
                                  onPressed: state.saving
                                      ? null
                                      : () async {
                                          final ok = await ref
                                              .read(
                                                adminControllerProvider
                                                    .notifier,
                                              )
                                              .endCompetitionV2(competitionId);
                                          if (!mounted) return;
                                          if (ok) {
                                            await _load();
                                            await widget.onUpdated();
                                          }
                                        },
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  tooltip: l10n.adminCompetitionsEndNowTooltip,
                                ),
                              ],
                            ),
                        ],
                      ),
                      if ('${competition['description'] ?? ''}'
                          .trim()
                          .isNotEmpty)
                        Text('${competition['description']}'),
                      const SizedBox(height: 6),
                      Text(
                        l10n.adminCompetitionsParticipantsSummary(
                          '${_asInt(competition['participants_count'])}',
                          '${_asInt(competition['winners_count'])}',
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (tiers.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: tiers
                              .map((tier) {
                                final title = '${tier['title'] ?? ''}'.trim();
                                final required = _asInt(
                                  tier['requiredCompletedOrders'] ??
                                      tier['required_completed_orders'],
                                );
                                final reward = _asDouble(
                                  tier['rewardAmount'] ?? tier['reward_amount'],
                                );
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: Colors.white.withValues(alpha: 0.06),
                                  ),
                                  child: Text(
                                    '$title • $required • ${formatIqd(reward)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () => widget.onOpenDetails(competitionId),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: Text(l10n.adminCompetitionsOpenDetails),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _AdminCompetitionCreateTab extends ConsumerStatefulWidget {
  const _AdminCompetitionCreateTab({required this.onCreated});

  final Future<void> Function() onCreated;

  @override
  ConsumerState<_AdminCompetitionCreateTab> createState() =>
      _AdminCompetitionCreateTabState();
}

class _AdminCompetitionCreateTabState
    extends ConsumerState<_AdminCompetitionCreateTab> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _startAt;
  DateTime? _endAt;
  final List<_TierDraft> _tiers = [];
  bool _seededDefaultTiers = false;

  List<_TierDraft> _buildDefaultTiers() {
    final l10n = context.l10n;
    return [
      _TierDraft(
        title: l10n.adminCompetitionsFirstPlace,
        required: '20',
        reward: '20000',
      ),
      _TierDraft(
        title: l10n.adminCompetitionsSecondPlace,
        required: '15',
        reward: '15000',
      ),
      _TierDraft(
        title: l10n.adminCompetitionsThirdPlace,
        required: '10',
        reward: '10000',
      ),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seededDefaultTiers) return;
    _seededDefaultTiers = true;
    _tiers.addAll(_buildDefaultTiers());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    for (final tier in _tiers) {
      tier.dispose();
    }
    super.dispose();
  }

  String _formatDateTime(DateTime value) {
    final date = MaterialLocalizations.of(context).formatShortDate(value);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: true,
    );
    return '$date  $time';
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final current = isStart
        ? (_startAt ?? now)
        : (_endAt ??
              (_startAt != null
                  ? _startAt!.add(const Duration(hours: 1))
                  : now.add(const Duration(hours: 1))));
    final minDate = !isStart && _startAt != null
        ? DateTime(_startAt!.year, _startAt!.month, _startAt!.day)
        : DateTime(now.year - 1);
    final maxDate = DateTime(now.year + 5);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: minDate,
      lastDate: maxDate,
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (pickedTime == null || !mounted) return;

    final picked = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      if (isStart) {
        _startAt = picked;
        if (_endAt != null && _endAt!.isBefore(_startAt!)) {
          _endAt = _startAt!.add(const Duration(hours: 1));
        }
      } else {
        _endAt = picked;
      }
    });
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.adminCompetitionsTitleRequired),
        ),
      );
      return;
    }

    if (_startAt != null && _endAt != null && !_endAt!.isAfter(_startAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.adminCompetitionsEndAfterStart),
        ),
      );
      return;
    }

    final tiers = <Map<String, dynamic>>[];
    for (final tier in _tiers) {
      final required = tryParseLocalizedInt(tier.requiredController.text.trim());
      final reward = tryParseLocalizedDouble(tier.rewardController.text.trim());
      if (required == null || required <= 0 || reward == null || reward < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.adminCompetitionsCheckTiersRewards),
          ),
        );
        return;
      }
      tiers.add({
        'title': tier.titleController.text.trim().isEmpty
            ? l10n.adminCompetitionsGenericTier
            : tier.titleController.text.trim(),
        'requiredCompletedOrders': required,
        'rewardAmount': reward,
      });
    }

    final ok = await ref
        .read(adminControllerProvider.notifier)
        .createCompetitionV2({
          'title': title,
          'description': _descriptionController.text.trim(),
          'competitionType': 'completed_orders',
          'rewardType': 'cash',
          'isActive': true,
          'startAt': _startAt?.toUtc().toIso8601String(),
          'endAt': _endAt?.toUtc().toIso8601String(),
          'tiers': tiers,
        });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? l10n.adminCompetitionsCreated
              : l10n.adminCompetitionsCreateFailed,
        ),
      ),
    );

    if (ok) {
      _titleController.clear();
      _descriptionController.clear();
      setState(() {
        _startAt = null;
        _endAt = null;
      });
      await widget.onCreated();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: l10n.adminCompetitionsFieldTitle,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: l10n.adminCompetitionsDescription,
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.adminCompetitionsStartDateTime),
          subtitle: Text(
            _startAt == null
                ? l10n.adminCompetitionsStartImmediate
                : _formatDateTime(_startAt!),
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                onPressed: () => _pickDateTime(isStart: true),
                icon: const Icon(Icons.schedule_rounded),
                tooltip: l10n.adminCompetitionsPickDateTime,
              ),
              if (_startAt != null)
                IconButton(
                  onPressed: () => setState(() => _startAt = null),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: l10n.commonClear,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.adminCompetitionsEndDateTime),
          subtitle: Text(
            _endAt == null
                ? l10n.adminCompetitionsEndServerDefault
                : _formatDateTime(_endAt!),
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                onPressed: () => _pickDateTime(isStart: false),
                icon: const Icon(Icons.schedule_rounded),
                tooltip: l10n.adminCompetitionsPickDateTime,
              ),
              if (_endAt != null)
                IconButton(
                  onPressed: () => setState(() => _endAt = null),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: l10n.commonClear,
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.adminCompetitionsTiers,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ..._tiers.asMap().entries.map((entry) {
          final i = entry.key;
          final tier = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  TextField(
                    controller: tier.titleController,
                    decoration: InputDecoration(
                      labelText: l10n.adminCompetitionsTierTitle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tier.requiredController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.adminCompetitionsRequiredOrders,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: tier.rewardController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: l10n.adminCompetitionsRewardIqd,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_tiers.length > 1)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: IconButton(
                        onPressed: () {
                          setState(() {
                            final removed = _tiers.removeAt(i);
                            removed.dispose();
                          });
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _tiers.add(
                  _TierDraft(
                    title: l10n.adminCompetitionsGenericTier,
                    required: '5',
                    reward: '5000',
                  ),
                );
              });
            },
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.adminCompetitionsAddTier),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: state.saving ? null : _submit,
          icon: const Icon(Icons.check_rounded),
          label: Text(l10n.adminCompetitionsCreateCompetition),
        ),
      ],
    );
  }
}

class _AdminCompetitionEditSheet extends ConsumerStatefulWidget {
  const _AdminCompetitionEditSheet({required this.competition});

  final Map<String, dynamic> competition;

  @override
  ConsumerState<_AdminCompetitionEditSheet> createState() =>
      _AdminCompetitionEditSheetState();
}

class _AdminCompetitionEditSheetState
    extends ConsumerState<_AdminCompetitionEditSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _startAt;
  DateTime? _endAt;
  final List<_TierDraft> _tiers = [];
  late final List<Map<String, dynamic>> _initialTiers;
  late final int _fallbackTargetValue;
  late final double _fallbackRewardAmount;
  bool _seededInitialTiers = false;

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return tryParseLocalizedInt(value) ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return tryParseLocalizedDouble(value) ?? 0;
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    final raw = '$value'.trim();
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    final competition = widget.competition;
    _titleController.text = '${competition['title'] ?? ''}'.trim();
    _descriptionController.text = '${competition['description'] ?? ''}'.trim();
    _startAt = _parseDate(competition['start_at'] ?? competition['startAt']);
    _endAt = _parseDate(competition['end_at'] ?? competition['endAt']);
    _initialTiers = _mapList(competition['tiers']);
    _fallbackTargetValue = _asInt(competition['target_value']);
    _fallbackRewardAmount = _asDouble(competition['reward_amount']);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seededInitialTiers) return;
    _seededInitialTiers = true;
    final l10n = context.l10n;
    if (_initialTiers.isNotEmpty) {
      for (final tier in _initialTiers) {
        final title = '${tier['title'] ?? ''}'.trim();
        _tiers.add(
          _TierDraft(
            title: title.isEmpty ? l10n.adminCompetitionsGenericTier : title,
            required:
                '${_asInt(tier['requiredCompletedOrders'] ?? tier['required_completed_orders'])}',
            reward:
                '${_asDouble(tier['rewardAmount'] ?? tier['reward_amount'])}',
          ),
        );
      }
      return;
    }
    _tiers.add(
      _TierDraft(
        title: l10n.adminCompetitionsFirstPlace,
        required: '$_fallbackTargetValue',
        reward: '$_fallbackRewardAmount',
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    for (final tier in _tiers) {
      tier.dispose();
    }
    super.dispose();
  }

  String _formatDateTime(DateTime value) {
    final date = MaterialLocalizations.of(context).formatShortDate(value);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: true,
    );
    return '$date  $time';
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final current = isStart
        ? (_startAt ?? now)
        : (_endAt ??
              (_startAt != null
                  ? _startAt!.add(const Duration(hours: 1))
                  : now.add(const Duration(hours: 1))));
    final minDate = !isStart && _startAt != null
        ? DateTime(_startAt!.year, _startAt!.month, _startAt!.day)
        : DateTime(now.year - 1);
    final maxDate = DateTime(now.year + 5);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: minDate,
      lastDate: maxDate,
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (pickedTime == null || !mounted) return;

    final picked = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      if (isStart) {
        _startAt = picked;
        if (_endAt != null && _endAt!.isBefore(_startAt!)) {
          _endAt = _startAt!.add(const Duration(hours: 1));
        }
      } else {
        _endAt = picked;
      }
    });
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final competitionId = _asInt(widget.competition['id']);
    if (competitionId <= 0) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.adminCompetitionsTitleRequired),
        ),
      );
      return;
    }

    if (_startAt != null && _endAt != null && !_endAt!.isAfter(_startAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.adminCompetitionsEndAfterStart),
        ),
      );
      return;
    }

    final tiers = <Map<String, dynamic>>[];
    for (final tier in _tiers) {
      final required = tryParseLocalizedInt(tier.requiredController.text.trim());
      final reward = tryParseLocalizedDouble(tier.rewardController.text.trim());
      if (required == null || required <= 0 || reward == null || reward < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.adminCompetitionsCheckTiersRewards),
          ),
        );
        return;
      }
      tiers.add({
        'title': tier.titleController.text.trim().isEmpty
            ? l10n.adminCompetitionsGenericTier
            : tier.titleController.text.trim(),
        'requiredCompletedOrders': required,
        'rewardAmount': reward,
      });
    }
    tiers.sort(
      (a, b) => (b['requiredCompletedOrders'] as int).compareTo(
        a['requiredCompletedOrders'] as int,
      ),
    );
    for (var i = 1; i < tiers.length; i += 1) {
      final current = tiers[i]['requiredCompletedOrders'] as int;
      final previous = tiers[i - 1]['requiredCompletedOrders'] as int;
      if (current >= previous) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.adminCompetitionsTierOrderInvalid),
          ),
        );
        return;
      }
    }

    final ok = await ref
        .read(adminControllerProvider.notifier)
        .patchCompetitionV2(competitionId, {
          'title': title,
          'description': _descriptionController.text.trim(),
          'startAt': _startAt?.toUtc().toIso8601String(),
          'endAt': _endAt?.toUtc().toIso8601String(),
          'isActive': true,
          'status': 'active',
          'tiers': tiers,
        });
    if (!mounted) return;

    if (!ok) {
      final error = ref.read(adminControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error?.trim().isNotEmpty == true
                ? error!
                : l10n.adminCompetitionsUpdateFailed,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.adminCompetitionsEditActiveTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(l10n.adminCompetitionsEditActiveHint),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: l10n.adminCompetitionsFieldTitle,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: l10n.adminCompetitionsDescription,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.adminCompetitionsStartDateTime),
                subtitle: Text(
                  _startAt == null
                      ? l10n.adminCompetitionsDateKeepCurrent
                      : _formatDateTime(_startAt!),
                ),
                trailing: IconButton(
                  onPressed: () => _pickDateTime(isStart: true),
                  icon: const Icon(Icons.schedule_rounded),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.adminCompetitionsEndDateTime),
                subtitle: Text(
                  _endAt == null
                      ? l10n.adminCompetitionsDateKeepCurrent
                      : _formatDateTime(_endAt!),
                ),
                trailing: IconButton(
                  onPressed: () => _pickDateTime(isStart: false),
                  icon: const Icon(Icons.schedule_rounded),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.adminCompetitionsTiers,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ..._tiers.asMap().entries.map((entry) {
                final i = entry.key;
                final tier = entry.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        TextField(
                          controller: tier.titleController,
                          decoration: InputDecoration(
                            labelText: l10n.adminCompetitionsTierTitle,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: tier.requiredController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: l10n.adminCompetitionsRequiredOrders,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: tier.rewardController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: l10n.adminCompetitionsRewardIqd,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_tiers.length > 1)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: IconButton(
                              onPressed: () {
                                setState(() {
                                  final removed = _tiers.removeAt(i);
                                  removed.dispose();
                                });
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _tiers.add(
                      _TierDraft(
                        title: l10n.adminCompetitionsGenericTier,
                        required: '5',
                        reward: '5000',
                      ),
                    );
                  });
                },
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.adminCompetitionsAddTier),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text(l10n.commonCancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: state.saving ? null : _submit,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(l10n.adminCompetitionsSaveChanges),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TierDraft {
  _TierDraft({
    required String title,
    required String required,
    required String reward,
  }) : titleController = TextEditingController(text: title),
       requiredController = TextEditingController(text: required),
       rewardController = TextEditingController(text: reward);

  final TextEditingController titleController;
  final TextEditingController requiredController;
  final TextEditingController rewardController;

  void dispose() {
    titleController.dispose();
    requiredController.dispose();
    rewardController.dispose();
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.07),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.text, required this.onRetry});

  final String text;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}
