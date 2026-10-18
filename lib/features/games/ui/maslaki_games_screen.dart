import 'dart:async';
import 'dart:math' as math;

import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../data/games_api.dart';
import 'knowledge_game_screen.dart';
import 'mafia_room_screen.dart';
import 'team_code_room_screen.dart';

enum _GamesView { picker, teamCode, mafia }

class MaslakiGamesScreen extends ConsumerStatefulWidget {
  const MaslakiGamesScreen({super.key});

  @override
  ConsumerState<MaslakiGamesScreen> createState() => _MaslakiGamesScreenState();
}

class _MaslakiGamesScreenState extends ConsumerState<MaslakiGamesScreen> {
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _history = const [];
  List<Map<String, dynamic>> _mafiaHistory = const [];
  bool _loading = true;
  bool _acting = false;
  String? _error;
  _GamesView _view = _GamesView.picker;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _showFirstRunGuide() async {
    final store = ref.read(secureStoreProvider);
    final shown = await store.readBool('team_code_guide_seen') ?? false;
    if (!mounted || shown) return;
    await _showGuide();
    await store.writeBool('team_code_guide_seen', true);
  }

  void _selectGame(_GamesView view) {
    if (_view == view) return;
    setState(() => _view = view);
    if (view == _GamesView.teamCode) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_showFirstRunGuide()),
      );
    }
  }

  void _backToPicker() {
    if (_view == _GamesView.picker) return;
    setState(() => _view = _GamesView.picker);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(gamesApiProvider);
      final values = await Future.wait([
        api.status(),
        api.history(),
        api.mafiaHistory().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _status = values[0] as Map<String, dynamic>;
        _history = values[1] as List<Map<String, dynamic>>;
        _mafiaHistory = values[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _create(String mode) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      final snapshot = await ref.read(gamesApiProvider).createRoom(mode);
      if (!mounted) return;
      await _openRoom(_int(_map(snapshot['room'])['id']));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _join() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الانضمام إلى فريق'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            labelText: 'رمز الغرفة',
            hintText: 'A7K9Q2',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('انضمام'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return;
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      final snapshot = await ref.read(gamesApiProvider).joinRoom(code);
      if (!mounted) return;
      await _openRoom(_int(_map(snapshot['room'])['id']));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _openRoom(int roomId) async {
    if (roomId <= 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TeamCodeRoomScreen(roomId: roomId)),
    );
    await _load();
  }

  Future<void> _createMafia() async {
    if (_acting) return;
    final setup = await showMaslakiBottomSheet<_MafiaSetupResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _MafiaSetupSheet(),
    );
    if (setup == null) return;
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      final snapshot = await ref
          .read(gamesApiProvider)
          .createMafiaRoom(
            ruleset: setup.ruleset,
            pace: setup.pace,
            tableTheme: setup.tableTheme,
            maxPlayers: setup.maxPlayers,
            revealRolesOnDeath: setup.revealRolesOnDeath,
          );
      if (!mounted) return;
      await _openMafiaRoom(_int(_map(snapshot['room'])['id']));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _joinMafia() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الانضمام إلى ليلة مسلكي'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            labelText: 'رمز الغرفة',
            hintText: 'M7K9Q2',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('انضمام'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return;
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      final snapshot = await ref.read(gamesApiProvider).joinMafiaRoom(code);
      if (!mounted) return;
      await _openMafiaRoom(_int(_map(snapshot['room'])['id']));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _openMafiaRoom(int roomId) async {
    if (roomId <= 0) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MafiaRoomScreen(roomId: roomId)));
    await _load();
  }

  Future<void> _reactivateMafiaRoom(Map<String, dynamic> previous) async {
    final previousRuleset = '${previous['ruleset']}' == 'advanced'
        ? 'advanced'
        : 'standard';
    final ruleset = await showMaslakiBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إعادة تنشيط الغرفة',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text('ستبدأ قاعة انتظار جديدة برمز جديد وآمن.'),
              const SizedBox(height: 12),
              ListTile(
                key: const ValueKey('mafia-reactivate-same-rules'),
                onTap: () => Navigator.pop(context, previousRuleset),
                leading: const Icon(Icons.replay_circle_filled_rounded),
                title: const Text('بنفس القوانين'),
                subtitle: Text(_mafiaRulesetLabel(previousRuleset)),
                trailing: const Icon(Icons.chevron_left_rounded),
              ),
              ListTile(
                key: const ValueKey('mafia-reactivate-other-rules'),
                onTap: () => Navigator.pop(
                  context,
                  previousRuleset == 'advanced' ? 'standard' : 'advanced',
                ),
                leading: const Icon(Icons.tune_rounded),
                title: const Text('بقوانين مختلفة'),
                subtitle: Text(
                  _mafiaRulesetLabel(
                    previousRuleset == 'advanced' ? 'standard' : 'advanced',
                  ),
                ),
                trailing: const Icon(Icons.chevron_left_rounded),
              ),
            ],
          ),
        ),
      ),
    );
    if (ruleset == null || !mounted) return;
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      final snapshot = await ref
          .read(gamesApiProvider)
          .reactivateMafiaRoom(
            _int(previous['roomId']),
            ruleset: ruleset,
            pace: '${previous['pace']}' == 'quick' ? 'quick' : 'classic',
            tableTheme:
                const {'royal', 'cinema'}.contains(previous['tableTheme'])
                ? '${previous['tableTheme']}'
                : 'emerald',
            maxPlayers: _int(previous['maxPlayers']) > 0
                ? _int(previous['maxPlayers'])
                : 14,
            revealRolesOnDeath: previous['revealRolesOnDeath'] != false,
          );
      if (!mounted) return;
      await _openMafiaRoom(_int(_map(snapshot['room'])['id']));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _showGuide() => showMaslakiBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _GameGuideSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final statusKnown = _status != null;
    final game = _map(_status?['game']);
    final campaign = _map(_status?['campaign']);
    final enabled = statusKnown && game['enabled'] == true;
    final activeRoom = _map(game['activeRoom']);
    final activeMafia = _mafiaHistory.firstWhere((item) {
      final status = '${item['status']}';
      return status != 'completed' && status != 'cancelled';
    }, orElse: () => const <String, dynamic>{});
    final title = switch (_view) {
      _GamesView.picker => 'ألعاب مسلكي',
      _GamesView.teamCode => 'شفرة الفريق',
      _GamesView.mafia => 'ليلة مسلكي',
    };
    return PopScope(
      canPop: _view == _GamesView.picker,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToPicker();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _view == _GamesView.picker
              ? null
              : IconButton(
                  key: const ValueKey('games-back-to-picker'),
                  onPressed: _backToPicker,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  tooltip: 'كل الألعاب',
                ),
          title: Text(title),
          actions: [
            if (_view == _GamesView.teamCode)
              IconButton(
                onPressed: _showGuide,
                icon: const Icon(Icons.help_outline_rounded),
                tooltip: 'طريقة اللعب',
              ),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: switch (_view) {
            _GamesView.picker => _buildPicker(
              activeTeamRoom: activeRoom.isNotEmpty,
              activeMafiaRoom: activeMafia.isNotEmpty,
            ),
            _GamesView.mafia => _buildMafia(
              activeMafia: activeMafia,
              rooms: _mafiaHistory,
            ),
            _GamesView.teamCode => _buildTeamCode(
              statusKnown: statusKnown,
              enabled: enabled,
              activeRoom: activeRoom,
              campaign: campaign,
            ),
          },
        ),
      ),
    );
  }

  Widget _refreshable(List<Widget> children) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: children,
    ),
  );

  Widget _buildPicker({
    required bool activeTeamRoom,
    required bool activeMafiaRoom,
  }) => _refreshable([
    if (_loading) const LinearProgressIndicator(minHeight: 2),
    const SizedBox(height: 8),
    Text(
      'اختر لعبتك',
      style: Theme.of(
        context,
      ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
    ),
    const SizedBox(height: 4),
    Text(
      'كل لعبة لها غرفها وقواعدها وسجلها الخاص.',
      style: TextStyle(
        color: context.maslakiTokens.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    ),
    const SizedBox(height: 16),
    _GameChoiceCard(
      key: const ValueKey('game-choice-team-code'),
      title: 'شفرة الفريق',
      description: 'افتح ثلاث خزائن بحل الأدلة منفردًا أو مع فريقك.',
      details: '1 إلى 4 لاعبين • ألغاز وتعاون',
      icon: Icons.lock_open_rounded,
      color: const Color(0xFF286046),
      activeLabel: activeTeamRoom ? 'لديك جولة جارية' : null,
      artwork: const _VaultIllustration(size: 82),
      onTap: () => _selectGame(_GamesView.teamCode),
    ),
    const SizedBox(height: 12),
    _GameChoiceCard(
      key: const ValueKey('game-choice-mafia'),
      title: 'ليلة مسلكي',
      description: 'أدوار سرية، نقاش وتصويت وصوت حي داخل الغرفة.',
      details: '7 إلى 14 لاعبًا • مافيا جماعية',
      icon: Icons.dark_mode_rounded,
      color: const Color(0xFF172F29),
      activeLabel: activeMafiaRoom ? 'لديك غرفة جارية' : null,
      artwork: const _MafiaChoiceArtwork(),
      onTap: () => _selectGame(_GamesView.mafia),
    ),
    const SizedBox(height: 12),
    _GameChoiceCard(
      key: const ValueKey('game-choice-knowledge-map'),
      title: 'خريطة المعرفة',
      description:
          'أسئلة سريعة، مناطق تُفتح بالإجابة، ومنافسة بين فرق الأصدقاء.',
      details: 'من 1 ضد 1 إلى 4 ضد 4 • تحديات وبطولات',
      icon: Icons.explore_rounded,
      color: const Color(0xFF174C3A),
      artwork: const _VaultIllustration(size: 82),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const KnowledgeGameScreen())),
    ),
    if (_error != null) ...[
      const SizedBox(height: 14),
      _ErrorStrip(message: _error!, onRetry: _load),
    ],
  ]);

  Widget _buildMafia({
    required Map<String, dynamic> activeMafia,
    required List<Map<String, dynamic>> rooms,
  }) => _refreshable([
    if (_loading) const LinearProgressIndicator(minHeight: 2),
    _MafiaShowcase(
      busy: _acting,
      onCreate: _createMafia,
      onJoin: _joinMafia,
      onContinue: activeMafia.isEmpty
          ? null
          : () => _openMafiaRoom(_int(activeMafia['roomId'])),
    ),
    const SizedBox(height: 14),
    const _InfoStrip(
      text:
          'أنشئ غرفة وشارك رمزها مع أصدقائك، أو انضم مباشرة برمز غرفة موجودة.',
    ),
    const SizedBox(height: 20),
    Text(
      'غرفي',
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
    ),
    const SizedBox(height: 4),
    Text(
      'تابع غرفتك الحالية أو أعد تنشيط جولة سابقة.',
      style: TextStyle(
        color: context.maslakiTokens.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    ),
    const SizedBox(height: 10),
    if (rooms.isEmpty)
      const _InfoStrip(text: 'الغرف التي تنشئها أو تنضم إليها ستظهر هنا.')
    else
      ...rooms.map(
        (room) => Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: _MafiaRoomHistoryCard(
            room: room,
            busy: _acting,
            onOpen: ['completed', 'cancelled'].contains('${room['status']}')
                ? null
                : () => _openMafiaRoom(_int(room['roomId'])),
            onReactivate:
                room['isHost'] == true &&
                    ['completed', 'cancelled'].contains('${room['status']}')
                ? () => _reactivateMafiaRoom(room)
                : null,
          ),
        ),
      ),
    if (_error != null) ...[
      const SizedBox(height: 14),
      _ErrorStrip(message: _error!, onRetry: _load),
    ],
  ]);

  Widget _buildTeamCode({
    required bool statusKnown,
    required bool enabled,
    required Map<String, dynamic> activeRoom,
    required Map<String, dynamic> campaign,
  }) {
    final tokens = context.maslakiTokens;
    return _refreshable([
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Container(
        constraints: const BoxConstraints(minHeight: 220),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: tokens.cardPrimary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: tokens.secondaryAccent.withValues(alpha: .55),
          ),
        ),
        child: Column(
          children: [
            const _VaultIllustration(size: 96),
            const SizedBox(height: 14),
            Text(
              'شفرة الفريق',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'ثلاث خزائن، أدلة موزعة، وقرار واحد يجمع الفريق.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (campaign['isMock'] == true) ...[
              const SizedBox(height: 12),
              _Badge(
                label: 'مكافآت تجريبية غير قابلة للاستخدام',
                color: tokens.warning,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (_error != null) _ErrorStrip(message: _error!, onRetry: _load),
      if (_error == null && statusKnown && !enabled)
        const _InfoStrip(
          text: 'اللعبة متوقفة مؤقتًا من الإدارة. سيبقى سجلك محفوظًا.',
        ),
      if (activeRoom.isNotEmpty) ...[
        FilledButton.icon(
          onPressed: () => _openRoom(_int(activeRoom['id'])),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('متابعة الجولة الحالية'),
        ),
        const SizedBox(height: 10),
      ],
      Row(
        children: [
          Expanded(
            child: _ModeButton(
              icon: Icons.person_rounded,
              title: 'فردي',
              subtitle: 'كل الملفات عندك',
              onTap: enabled && !_acting ? () => _create('solo') : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ModeButton(
              icon: Icons.group_rounded,
              title: 'إنشاء فريق',
              subtitle: 'من 2 إلى 4',
              onTap: enabled && !_acting ? () => _create('cooperative') : null,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: enabled && !_acting ? _join : null,
        icon: const Icon(Icons.key_rounded),
        label: const Text('الانضمام برمز غرفة'),
      ),
      const SizedBox(height: 22),
      Text(
        'سجل شفرة الفريق',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 8),
      if (_history.isEmpty)
        const _InfoStrip(text: 'أول جولة لك ستظهر هنا.')
      else
        ..._history.map(
          (item) => _HistoryTile(
            item: item,
            onOpen: () => _openRoom(_int(item['roomId'])),
            onClaim: () async {
              await ref
                  .read(gamesApiProvider)
                  .claimReward(_int(item['sessionId']));
              await _load();
            },
          ),
        ),
    ]);
  }
}

class _GameChoiceCard extends StatelessWidget {
  final String title;
  final String description;
  final String details;
  final IconData icon;
  final Color color;
  final String? activeLabel;
  final Widget artwork;
  final VoidCallback onTap;

  const _GameChoiceCard({
    required this.title,
    required this.description,
    required this.details,
    required this.icon,
    required this.color,
    required this.artwork,
    required this.onTap,
    this.activeLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Material(
      color: tokens.cardPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: .45), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 176),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 88, child: Center(child: artwork)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: color, size: 22),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        description,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        details,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (activeLabel != null) ...[
                        const SizedBox(height: 9),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_circle_fill_rounded,
                              size: 17,
                              color: tokens.success,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                activeLabel!,
                                style: TextStyle(
                                  color: tokens.success,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_left_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MafiaChoiceArtwork extends StatelessWidget {
  const _MafiaChoiceArtwork();

  @override
  Widget build(BuildContext context) => Container(
    width: 82,
    height: 82,
    decoration: BoxDecoration(
      color: const Color(0xFF172F29),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFC6A552)),
    ),
    child: const Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 10,
          right: 12,
          child: Icon(
            Icons.nightlight_round,
            color: Color(0xFFF0CE78),
            size: 30,
          ),
        ),
        Positioned(
          bottom: 12,
          child: Icon(Icons.groups_rounded, color: Colors.white, size: 38),
        ),
      ],
    ),
  );
}

class _MafiaRoomHistoryCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final bool busy;
  final VoidCallback? onOpen;
  final VoidCallback? onReactivate;

  const _MafiaRoomHistoryCard({
    required this.room,
    required this.busy,
    this.onOpen,
    this.onReactivate,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final status = '${room['status']}';
    final active = !['completed', 'cancelled'].contains(status);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: tokens.cardPrimary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active
              ? tokens.success.withValues(alpha: .55)
              : tokens.secondaryAccent.withValues(alpha: .35),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: active
                ? tokens.success.withValues(alpha: .12)
                : tokens.secondaryAccent.withValues(alpha: .14),
            child: Icon(
              active ? Icons.play_arrow_rounded : Icons.history_rounded,
              color: active ? tokens.success : tokens.secondaryAccent,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الغرفة ${room['inviteCode'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_mafiaStatusLabel(status)} • ${_mafiaRulesetLabel('${room['ruleset']}')}',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onOpen != null)
            IconButton.filledTonal(
              tooltip: 'فتح الغرفة',
              onPressed: busy ? null : onOpen,
              icon: const Icon(Icons.login_rounded),
            )
          else if (onReactivate != null)
            TextButton.icon(
              key: ValueKey('mafia-reactivate-${room['roomId']}'),
              onPressed: busy ? null : onReactivate,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('تنشيط'),
            ),
        ],
      ),
    );
  }
}

class _GameGuideSheet extends StatelessWidget {
  const _GameGuideSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'كيف تفتحون الخزنة؟',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          const _GuideStep(
            number: '1',
            text: 'اقرأ دليلك وشاركه بالكلام مع فريقك.',
          ),
          const _GuideStep(number: '2', text: 'الأرقام لا تتكرر داخل الشفرة.'),
          const _GuideStep(
            number: '3',
            text: 'اقترحوا رمزًا وصوّتوا عليه بالإجماع.',
          ),
          const _GuideStep(number: '4', text: 'لكل خزنة 5 محاولات و3 تلميحات.'),
          const SizedBox(height: 12),
          const _TutorialExample(),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('فهمت، لنبدأ'),
          ),
        ],
      ),
    ),
  );
}

class _MafiaShowcase extends StatefulWidget {
  final bool busy;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback? onContinue;

  const _MafiaShowcase({
    required this.busy,
    required this.onCreate,
    required this.onJoin,
    this.onContinue,
  });

  @override
  State<_MafiaShowcase> createState() => _MafiaShowcaseState();
}

class _MafiaShowcaseState extends State<_MafiaShowcase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 238),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFF16372C),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFC6A552)),
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) =>
                CustomPaint(painter: _MafiaSkyPainter(_pulse.value)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.dark_mode_rounded,
                    color: Color(0xFFF0CE78),
                    size: 42,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ليلة مسلكي',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'من 7 إلى 14 لاعباً مع صوت حي',
                          style: TextStyle(
                            color: Color(0xFFD8E4DE),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'مدينة تنام، أدوار سرية تستيقظ، وكل كلمة قد تكشف الحقيقة.',
                style: TextStyle(
                  color: Colors.white,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              if (widget.onContinue != null) ...[
                FilledButton.icon(
                  onPressed: widget.busy ? null : widget.onContinue,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('متابعة ليلة مسلكي'),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFC39A37),
                        foregroundColor: const Color(0xFF10251E),
                      ),
                      onPressed: widget.busy ? null : widget.onCreate,
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text('إنشاء غرفة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFE8D9A7)),
                      ),
                      onPressed: widget.busy ? null : widget.onJoin,
                      icon: const Icon(Icons.key_rounded),
                      label: const Text('رمز غرفة'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }
}

class _MafiaSkyPainter extends CustomPainter {
  final double pulse;
  const _MafiaSkyPainter(this.pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final haze = Paint()
      ..color = Color.lerp(
        const Color(0x001E5A45),
        const Color(0x552B7256),
        pulse,
      )!;
    canvas.drawCircle(Offset(size.width * .12, 35), 70 + pulse * 8, haze);
    final buildings = Paint()..color = const Color(0xFF0D241C);
    final windows = Paint()..color = const Color(0xFFB99743);
    for (var i = 0; i < 10; i++) {
      final width = size.width / 10;
      final height = 24.0 + (i % 4) * 8;
      canvas.drawRect(
        Rect.fromLTWH(i * width, size.height - height, width - 2, height),
        buildings,
      );
      if ((i + (pulse > .5 ? 1 : 0)).isEven) {
        canvas.drawRect(
          Rect.fromLTWH(i * width + 7, size.height - height + 8, 4, 5),
          windows,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MafiaSkyPainter oldDelegate) =>
      oldDelegate.pulse != pulse;
}

class _TutorialExample extends StatefulWidget {
  const _TutorialExample();

  @override
  State<_TutorialExample> createState() => _TutorialExampleState();
}

class _TutorialExampleState extends State<_TutorialExample> {
  final List<int> _digits = [];
  bool? _correct;

  void _digit(int value) {
    if (_digits.length >= 3 || _digits.contains(value)) return;
    setState(() {
      _digits.add(value);
      _correct = null;
    });
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.maslakiTokens.cardPrimary,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.maslakiTokens.borderSubtle),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'لغز تعليمي بلا مكافأة',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        const Text('الأرقام هي 2 و4 و7. الرقم 7 في الوسط، والرقم 2 قبل 4.'),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            3,
            (index) => Container(
              width: 46,
              height: 46,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: context.maslakiTokens.primaryAccent),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                index < _digits.length ? '${_digits[index]}' : 'ـ',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [2, 4, 7]
              .map(
                (digit) => IconButton.filledTonal(
                  tooltip: 'إضافة $digit',
                  onPressed: _digits.contains(digit)
                      ? null
                      : () => _digit(digit),
                  icon: Text('$digit'),
                ),
              )
              .toList(),
        ),
        Row(
          children: [
            IconButton(
              tooltip: 'مسح',
              onPressed: _digits.isEmpty
                  ? null
                  : () => setState(() {
                      _digits.clear();
                      _correct = null;
                    }),
              icon: const Icon(Icons.clear_all_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _digits.length == 3
                    ? () => setState(() => _correct = _digits.join() == '274')
                    : null,
                child: const Text('تحقق'),
              ),
            ),
          ],
        ),
        if (_correct != null) ...[
          const SizedBox(height: 8),
          Text(
            _correct == true
                ? 'صحيح. هكذا تُجمع الأدلة لفتح الخزنة.'
                : 'راجع موضع 7 وترتيب 2 قبل 4.',
            style: TextStyle(
              color: _correct == true
                  ? context.maslakiTokens.success
                  : context.maslakiTokens.warning,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    ),
  );
}

class _GuideStep extends StatelessWidget {
  final String number;
  final String text;
  const _GuideStep({required this.number, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        CircleAvatar(radius: 15, child: Text(number)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _ModeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: context.maslakiTokens.cardPrimary,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: context.maslakiTokens.borderSubtle),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 116,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 34, color: context.maslakiTokens.primaryAccent),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onOpen;
  final Future<void> Function() onClaim;
  const _HistoryTile({
    required this.item,
    required this.onOpen,
    required this.onClaim,
  });
  @override
  Widget build(BuildContext context) {
    final eligible =
        item['rewardEligible'] == true && item['rewardClaimed'] != true;
    final canOpen = item['canOpen'] != false;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: canOpen ? onOpen : null,
        leading: Icon(
          item['status'] == 'completed'
              ? Icons.lock_open_rounded
              : Icons.lock_outline_rounded,
        ),
        title: Text(
          '${item['mode'] == 'solo' ? 'فردي' : 'فريق'} • ${_statusLabel('${item['status']}')}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          canOpen
              ? 'النتيجة ${_int(item['score'])} نقطة'
              : 'غادرت هذه الجولة • النتيجة ${_int(item['score'])} نقطة',
        ),
        trailing: eligible
            ? TextButton(onPressed: onClaim, child: const Text('استلام'))
            : Icon(
                canOpen
                    ? Icons.chevron_left_rounded
                    : Icons.lock_outline_rounded,
              ),
      ),
    );
  }
}

class _MafiaSetupResult {
  final String ruleset;
  final String pace;
  final String tableTheme;
  final int maxPlayers;
  final bool revealRolesOnDeath;

  const _MafiaSetupResult({
    required this.ruleset,
    required this.pace,
    required this.tableTheme,
    required this.maxPlayers,
    required this.revealRolesOnDeath,
  });
}

class _MafiaSetupSheet extends StatefulWidget {
  const _MafiaSetupSheet();

  @override
  State<_MafiaSetupSheet> createState() => _MafiaSetupSheetState();
}

class _MafiaSetupSheetState extends State<_MafiaSetupSheet> {
  String _ruleset = 'standard';
  String _pace = 'quick';
  String _tableTheme = 'emerald';
  double _maxPlayers = 14;
  bool _revealRolesOnDeath = true;

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'جهّز ليلتك',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'اختر إيقاع الجولة وقوانينها قبل دعوة اللاعبين.',
              style: TextStyle(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            const _SetupLabel(icon: Icons.tune_rounded, text: 'نظام الأدوار'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'standard',
                  icon: Icon(Icons.shield_outlined),
                  label: Text('قياسي'),
                ),
                ButtonSegment(
                  value: 'advanced',
                  icon: Icon(Icons.psychology_alt_outlined),
                  label: Text('متقدم'),
                ),
              ],
              selected: {_ruleset},
              onSelectionChanged: (value) =>
                  setState(() => _ruleset = value.first),
            ),
            const SizedBox(height: 16),
            const _SetupLabel(icon: Icons.speed_rounded, text: 'إيقاع الجولة'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'classic',
                  icon: Icon(Icons.hourglass_bottom_rounded),
                  label: Text('كلاسيكي'),
                ),
                ButtonSegment(
                  value: 'quick',
                  icon: Icon(Icons.bolt_rounded),
                  label: Text('سريع'),
                ),
              ],
              selected: {_pace},
              onSelectionChanged: (value) =>
                  setState(() => _pace = value.first),
            ),
            const SizedBox(height: 16),
            const _SetupLabel(
              icon: Icons.palette_outlined,
              text: 'هوية المجلس',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final option in const [
                  ('emerald', 'زمردي', Color(0xFF286046)),
                  ('royal', 'ملكي', Color(0xFF7B5A22)),
                  ('cinema', 'سينمائي', Color(0xFF853C45)),
                ]) ...[
                  Expanded(
                    child: _ThemeChoice(
                      value: option.$1,
                      label: option.$2,
                      color: option.$3,
                      selected: _tableTheme == option.$1,
                      onTap: () => setState(() => _tableTheme = option.$1),
                    ),
                  ),
                  if (option.$1 != 'cinema') const SizedBox(width: 7),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.groups_rounded, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'عدد المقاعد',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${_maxPlayers.round()} لاعباً',
                  style: TextStyle(
                    color: tokens.primaryAccent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            Slider(
              value: _maxPlayers,
              min: 7,
              max: 14,
              divisions: 7,
              label: '${_maxPlayers.round()}',
              onChanged: (value) => setState(() => _maxPlayers = value),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'كشف دور المستبعد',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text('يعرف المجلس دور اللاعب بعد خروجه.'),
              secondary: const Icon(Icons.visibility_rounded),
              value: _revealRolesOnDeath,
              onChanged: (value) => setState(() => _revealRolesOnDeath = value),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('mafia-create-confirm'),
              onPressed: () => Navigator.pop(
                context,
                _MafiaSetupResult(
                  ruleset: _ruleset,
                  pace: _pace,
                  tableTheme: _tableTheme,
                  maxPlayers: _maxPlayers.round(),
                  revealRolesOnDeath: _revealRolesOnDeath,
                ),
              ),
              icon: const Icon(Icons.nightlight_round),
              label: const Text('إنشاء الغرفة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeChoice({
    required this.value,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? color.withValues(alpha: .13) : Colors.transparent,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      key: ValueKey('mafia-theme-$value'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 74,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : const Color(0xFFD4D2C8)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SetupLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SetupLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
    ],
  );
}

class _VaultIllustration extends StatelessWidget {
  final double size;
  const _VaultIllustration({required this.size});
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _VaultPainter(
        context.maslakiTokens.primaryAccent,
        context.maslakiTokens.secondaryAccent,
      ),
    ),
  );
}

class _VaultPainter extends CustomPainter {
  final Color body;
  final Color accent;
  const _VaultPainter(this.body, this.accent);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .065
      ..strokeCap = StrokeCap.round;
    paint.color = body;
    final rect = RRect.fromRectAndRadius(
      Offset(size.width * .08, size.height * .08) &
          Size(size.width * .84, size.height * .84),
      Radius.circular(size.width * .12),
    );
    canvas.drawRRect(rect, paint);
    paint.color = accent;
    canvas.drawCircle(
      Offset(size.width * .52, size.height * .5),
      size.width * .2,
      paint,
    );
    for (var i = 0; i < 4; i++) {
      final angle = i * 1.5708;
      canvas.drawLine(
        Offset(size.width * .52, size.height * .5),
        Offset(
          size.width * .52 + size.width * .29 * math.sin(angle),
          size.height * .5 + size.height * .29 * math.cos(angle),
        ),
        paint,
      );
    }
    paint.color = body;
    canvas.drawLine(
      Offset(size.width * .18, size.height * .25),
      Offset(size.width * .18, size.height * .75),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _VaultPainter oldDelegate) =>
      oldDelegate.body != body || oldDelegate.accent != accent;
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .45)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w800),
    ),
  );
}

class _InfoStrip extends StatelessWidget {
  final String text;
  const _InfoStrip({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.maslakiTokens.surfaceSecondary,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.maslakiTokens.borderSubtle),
    ),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}

class _ErrorStrip extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorStrip({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.maslakiTokens.danger.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(Icons.error_outline_rounded, color: context.maslakiTokens.danger),
        const SizedBox(width: 8),
        const Expanded(child: Text('تعذر تحميل بيانات اللعبة. حاول مجددًا.')),
        IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)),
      ],
    ),
  );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
int _int(dynamic value) => int.tryParse('$value') ?? 0;

String _mafiaRulesetLabel(String ruleset) =>
    ruleset == 'advanced' ? 'قوانين متقدمة' : 'قوانين أساسية';

String _mafiaStatusLabel(String status) => switch (status) {
  'lobby' => 'بانتظار اللاعبين',
  'completed' => 'مكتملة',
  'cancelled' => 'مغلقة',
  'role_reveal' => 'كشف الأدوار',
  'night' => 'مرحلة الليل',
  _ => 'جولة نشطة',
};
String _statusLabel(String value) => switch (value) {
  'completed' => 'مكتملة',
  'failed' => 'انتهت المحاولات',
  'active' => 'جارية',
  'paused' => 'متوقفة مؤقتًا',
  _ => value,
};
