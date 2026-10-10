import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/games_api.dart';
import '../state/team_code_voice_controller.dart';
import '../state/knowledge_match_controller.dart';
import 'knowledge_match_board.dart';
import 'knowledge_series_picker.dart';
import 'knowledge_tournament_bracket.dart';

class KnowledgeGameScreen extends ConsumerStatefulWidget {
  const KnowledgeGameScreen({super.key});

  @override
  ConsumerState<KnowledgeGameScreen> createState() =>
      _KnowledgeGameScreenState();
}

class _KnowledgeGameScreenState extends ConsumerState<KnowledgeGameScreen> {
  static const _forest = Color(0xFF174C3A);
  List<Map<String, dynamic>> _events = const [];
  bool _loading = true;
  bool _acting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final events = await ref.read(gamesApiProvider).knowledgeEvents();
      if (mounted) {
        setState(() {
          _events = events;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _createDuel() async {
    var bestOf = 3;
    final size = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'اختر حجم الفريقين',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  KnowledgeSeriesPicker(
                    value: bestOf,
                    onChanged: (value) => setSheetState(() => bestOf = value),
                  ),
                  for (var count = 1; count <= 4; count++)
                    ListTile(
                      leading: Icon(
                        count == 1 ? Icons.person : Icons.groups,
                        color: _forest,
                      ),
                      title: Text(
                        count == 1 ? 'فرد ضد فرد' : '$count ضد $count',
                      ),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.pop(context, count),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (size == null || !mounted) return;
    final visibility = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('من يمكنه الانضمام؟'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.public_rounded),
              title: const Text('غرفة عامة'),
              subtitle: const Text('تظهر للاعبين في قائمة الغرف'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: const Text('غرفة خاصة'),
              subtitle: const Text('لا تظهر؛ ينضم اللاعبون برمز الدعوة'),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (visibility == null || !mounted) return;
    await _run(() async {
      final result = await ref
          .read(gamesApiProvider)
          .createKnowledgeDuel(
            teamSize: size,
            isPrivate: visibility,
            bestOf: bestOf,
          );
      final code = '${result['joinCode'] ?? ''}';
      await _openWaitingRoom(
        eventId: _int(result['eventId']),
        joinCode: code,
        title: 'تحدي خريطة المعرفة',
        teamSize: size,
        isOwner: true,
        isPrivate: visibility,
      );
      await _load();
    });
  }

  Future<void> _register(Map<String, dynamic> event) async {
    var teamName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل فريق'),
        content: TextField(
          maxLength: 48,
          autofocus: true,
          onChanged: (value) => teamName = value,
          decoration: const InputDecoration(labelText: 'اسم الفريق'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, teamName.trim()),
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await _run(() async {
      final team = await ref
          .read(gamesApiProvider)
          .registerKnowledgeTeam(_int(event['id']), name: name);
      final code = '${team['joinCode'] ?? ''}';
      await _openWaitingRoom(
        eventId: _int(event['id']),
        joinCode: code,
        title: '${event['title'] ?? 'البطولة'}',
        teamSize: _int(event['teamSize']),
        tournament: true,
      );
    });
  }

  Future<void> _joinWithCode() async {
    var enteredCode = '';
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الانضمام إلى فريق'),
        content: TextField(
          autofocus: true,
          maxLength: 7,
          textCapitalization: TextCapitalization.characters,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          onChanged: (value) => enteredCode = value,
          decoration: const InputDecoration(labelText: 'رمز الغرفة أو الدعوة'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, enteredCode),
            child: const Text('انضمام'),
          ),
        ],
      ),
    );
    if (code == null || !mounted) return;
    await _run(() async {
      final api = ref.read(gamesApiProvider);
      final result = await api.lookupKnowledgeRoom(code);
      final eventId = _int(result['eventId']);
      final resolvedEventId = eventId > 0 ? eventId : _int(result['id']);
      if (resolvedEventId < 1) throw StateError('ROOM_NOT_FOUND');
      if (result['eventType'] == 'tournament') {
        final team = await api.joinKnowledgeTeam(code);
        await _openWaitingRoom(
          eventId: _int(team['eventId']),
          joinCode: '${team['joinCode'] ?? code}'.trim(),
          title: '${team['eventTitle'] ?? 'البطولة'}',
          teamSize: _int(team['teamSize']),
          tournament: true,
        );
        await _load();
        return;
      }
      await _openWaitingRoom(
        eventId: resolvedEventId,
        joinCode: code.trim().toUpperCase(),
        title: '${result['title'] ?? 'تحدي خريطة المعرفة'}',
        teamSize: _int(result['teamSize']),
        isPrivate: result['isPrivate'] == true,
      );
      await _load();
    });
  }

  Future<void> _openWaitingRoom({
    required int eventId,
    required String joinCode,
    required String title,
    required int teamSize,
    bool tournament = false,
    bool isOwner = false,
    bool isPrivate = false,
  }) async {
    if (eventId < 1) throw StateError('ROOM_NOT_FOUND');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KnowledgeWaitingRoomScreen(
          eventId: eventId,
          joinCode: joinCode,
          title: title,
          teamSize: teamSize,
          tournament: tournament,
          isOwner: isOwner,
          isPrivate: isPrivate,
        ),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      debugPrint('Knowledge waiting room navigation/poll error: $error');
      if (mounted) setState(() => _error = _knowledgeActionError(error));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _openEvent(Map<String, dynamic> event) async {
    if (event['type'] == 'duel') {
      await _openWaitingRoom(
        eventId: _int(event['id']),
        joinCode: '',
        title: '${event['title'] ?? 'تحدي خريطة المعرفة'}',
        teamSize: _int(event['teamSize']),
        isOwner: event['isMine'] == true,
        isPrivate: event['isPrivate'] == true,
      );
      await _load();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => KnowledgeEventScreen(event: event)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final publicRooms = _events.where(
      (event) =>
          event['type'] == 'duel' &&
          event['isMine'] != true &&
          event['isPrivate'] != true &&
          event['status'] == 'registration',
    );
    final myRooms = _events.where(
      (event) => event['type'] == 'duel' && event['isMine'] == true,
    );
    final tournaments = _events.where((event) => event['type'] == 'tournament');
    return Scaffold(
      appBar: AppBar(title: const Text('خريطة المعرفة')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            _KnowledgeHero(onCreate: _acting ? null : _createDuel),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _acting ? null : _joinWithCode,
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('دخول برمز'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _loading ? null : _load,
                  tooltip: 'تحديث',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (_acting || _loading)
              const LinearProgressIndicator(minHeight: 2),
            if (_error != null) _ErrorNotice(message: _error!, onRetry: _load),
            const SizedBox(height: 12),
            const Text(
              'الغرف العامة',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (!_loading && publicRooms.isEmpty)
              const _EmptyNotice(
                text:
                    'لا توجد غرف عامة متاحة الآن. أنشئ غرفة أو انضم برمز دعوة.',
              ),
            for (final event in publicRooms)
              _EventTile(
                event: event,
                onOpen: () => _openEvent(event),
                onRegister: () => _openEvent(event),
              ),
            const SizedBox(height: 14),
            const Text(
              'غرفي',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (!_loading && myRooms.isEmpty)
              const _EmptyNotice(text: 'الغرف التي تنشئها ستظهر هنا.'),
            for (final event in myRooms)
              _EventTile(
                event: event,
                onOpen: () => _openEvent(event),
                onRegister: event['status'] == 'closed'
                    ? () async {
                        await ref
                            .read(gamesApiProvider)
                            .reactivateKnowledgeRoom(_int(event['id']));
                        await _load();
                      }
                    : () => _openEvent(event),
              ),
            if (tournaments.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'البطولات',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final event in tournaments)
                _EventTile(
                  event: event,
                  onOpen: () => _openEvent(event),
                  onRegister: event['status'] == 'registration'
                      ? () => _register(event)
                      : null,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class KnowledgeWaitingRoomScreen extends ConsumerStatefulWidget {
  final int eventId;
  final String joinCode;
  final String title;
  final int teamSize;
  final bool tournament;
  final bool isOwner;
  final bool isPrivate;

  const KnowledgeWaitingRoomScreen({
    super.key,
    required this.eventId,
    required this.joinCode,
    required this.title,
    required this.teamSize,
    this.tournament = false,
    this.isOwner = false,
    this.isPrivate = false,
  });

  @override
  ConsumerState<KnowledgeWaitingRoomScreen> createState() =>
      _KnowledgeWaitingRoomScreenState();
}

class _KnowledgeWaitingRoomScreenState
    extends ConsumerState<KnowledgeWaitingRoomScreen> {
  Timer? _poll;
  Timer? _initialCheck;
  bool _checking = false;
  bool _openingMatch = false;
  bool _takingSeat = false;
  String? _error;
  Map<String, dynamic> _room = const {};

  @override
  void initState() {
    super.initState();
    _initialCheck = Timer(const Duration(milliseconds: 800), () {
      unawaited(_checkForMatch());
    });
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_checkForMatch());
    });
  }

  @override
  void dispose() {
    _initialCheck?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkForMatch() async {
    if (_checking || _openingMatch) return;
    _checking = true;
    try {
      if (!widget.tournament) {
        final room = await ref
            .read(gamesApiProvider)
            .knowledgeRoom(
              widget.eventId,
              code: widget.joinCode.isEmpty ? null : widget.joinCode,
            );
        if (mounted) setState(() => _room = room);
      }
      final matches = await ref
          .read(gamesApiProvider)
          .knowledgeMatches(widget.eventId);
      Map<String, dynamic>? playable;
      for (final match in matches) {
        final status = '${match['status']}';
        if (status == 'pending' || status == 'active') {
          playable = match;
          break;
        }
      }
      if (!mounted) return;
      setState(() => _error = null);
      if (playable == null) return;
      _openingMatch = true;
      _poll?.cancel();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => KnowledgeMatchScreen(matchId: _int(playable!['id'])),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = _knowledgeActionError(error));
    } finally {
      _checking = false;
    }
  }

  Future<void> _copyCode() async {
    if (widget.joinCode.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: widget.joinCode));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ رمز الفريق')));
  }

  Future<void> _takeSeat(String side) async {
    if (_takingSeat) return;
    setState(() => _takingSeat = true);
    try {
      final room = await ref
          .read(gamesApiProvider)
          .joinKnowledgeRoomSeat(
            widget.eventId,
            side: side,
            code: widget.joinCode.isEmpty ? null : widget.joinCode,
          );
      if (mounted) setState(() => _room = room);
    } catch (error) {
      if (mounted) setState(() => _error = _knowledgeActionError(error));
    } finally {
      if (mounted) setState(() => _takingSeat = false);
    }
  }

  Future<void> _leaveSeat() async {
    if (_takingSeat) return;
    setState(() => _takingSeat = true);
    try {
      await ref.read(gamesApiProvider).leaveKnowledgeSeat(widget.eventId);
      await _checkForMatch();
    } catch (error) {
      if (mounted) setState(() => _error = _knowledgeActionError(error));
    } finally {
      if (mounted) setState(() => _takingSeat = false);
    }
  }

  Future<void> _closeRoom() async {
    try {
      await ref.read(gamesApiProvider).closeKnowledgeRoom(widget.eventId);
      if (mounted) setState(() => _room = {..._room, 'status': 'closed'});
    } catch (error) {
      if (mounted) setState(() => _error = _knowledgeActionError(error));
    }
  }

  Future<void> _reactivateRoom() async {
    try {
      await ref.read(gamesApiProvider).reactivateKnowledgeRoom(widget.eventId);
      final room = await ref
          .read(gamesApiProvider)
          .knowledgeRoom(
            widget.eventId,
            code: widget.joinCode.isEmpty ? null : widget.joinCode,
          );
      if (mounted) setState(() => _room = room);
    } catch (error) {
      if (mounted) setState(() => _error = _knowledgeActionError(error));
    }
  }

  Widget _teamSeats(String side, String title) {
    final teams = (_room['teams'] as List? ?? const [])
        .whereType<Map>()
        .map((team) => Map<String, dynamic>.from(team))
        .toList();
    Map<String, dynamic>? team;
    for (final candidate in teams) {
      if (candidate['side'] == side) {
        team = candidate;
        break;
      }
    }
    final players = (team?['players'] as List? ?? const [])
        .whereType<Map>()
        .map((player) => Map<String, dynamic>.from(player))
        .toList();
    final occupied = players.length;
    final canJoin =
        _room['status'] == 'registration' &&
        _room['isMember'] != true &&
        occupied < widget.teamSize;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$title  ($occupied/${widget.teamSize})',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            for (var index = 0; index < widget.teamSize; index++)
              ListTile(
                dense: true,
                leading: Icon(
                  index < players.length
                      ? Icons.person
                      : Icons.person_add_alt_1_outlined,
                ),
                title: Text(
                  index < players.length
                      ? '${players[index]['name'] ?? 'لاعب'}'
                      : 'مقعد شاغر',
                ),
                trailing: index >= players.length && canJoin
                    ? TextButton(
                        onPressed: _takingSeat ? null : () => _takeSeat(side),
                        child: const Text('اجلس'),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.explore_rounded,
                  size: 66,
                  color: Color(0xFFC18B2F),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.tournament ? 'فريقك جاهز' : 'غرفتك جاهزة للتحدي',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.tournament
                      ? 'أرسل الرمز لأعضاء فريقك. تبدأ المباراة بعد اكتمال الفرق وبدء البطولة من الإدارة.'
                      : 'اختر مقعدًا شاغرًا؛ تبدأ المباراة تلقائيًا عند اكتمال الفريقين. إذا بقي مقعد فردي، ادعُ لاعبًا آخر.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 22),
                if (widget.joinCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF174C3A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFC18B2F),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          widget.isPrivate ? 'رمز دعوة الغرفة' : 'رمز الغرفة',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          widget.joinCode,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _copyCode,
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('نسخ الرمز ومشاركته'),
                        ),
                      ],
                    ),
                  ),
                if (!widget.tournament && _room.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _teamSeats('a', 'الفريق الأول'),
                  _teamSeats('b', 'الفريق الثاني'),
                  if (_room['isMember'] == true &&
                      _room['status'] == 'registration')
                    TextButton.icon(
                      onPressed: _takingSeat ? null : _leaveSeat,
                      icon: const Icon(Icons.logout),
                      label: const Text('مغادرة المقعد'),
                    ),
                  Text(
                    '${_room['occupiedSeats'] ?? 0} / ${_room['totalSeats'] ?? widget.teamSize * 2} لاعبين',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (_room['status'] == 'closed' && widget.isOwner)
                    FilledButton.icon(
                      onPressed: _reactivateRoom,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة تنشيط الغرفة'),
                    )
                  else if (_room['status'] == 'registration' && widget.isOwner)
                    OutlinedButton.icon(
                      onPressed: _closeRoom,
                      icon: const Icon(Icons.visibility_off_outlined),
                      label: const Text('إغلاق الغرفة'),
                    ),
                  if (_room['status'] == 'registration' &&
                      _int(_room['occupiedSeats']) > 0 &&
                      _int(_room['occupiedSeats']) <
                          _int(_room['totalSeats']) &&
                      _int(_room['occupiedSeats']).isOdd)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'عدد اللاعبين فردي؛ ادعُ لاعبًا آخر ليكتمل العدد وتبدأ المباراة.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_room['status'] == 'registration' &&
                      _int(_room['occupiedSeats']) > 0 &&
                      _int(_room['occupiedSeats']) <
                          _int(_room['totalSeats']) &&
                      _int(_room['occupiedSeats']).isEven)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'الغرفة تنتظر اكتمال الفريقين؛ شارك الرمز وادعُ لاعبين للمقاعد المتبقية.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'نبحث عن المباراة ونفتحها تلقائيًا',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                if (widget.teamSize > 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    'حجم الفريق ${widget.teamSize} لاعبين. استخدموا الرمز نفسه لإكمال فريقكم ثم دعوة الفريق المنافس.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _checking ? null : _checkForMatch,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('تحقق الآن'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class KnowledgeEventScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> event;
  const KnowledgeEventScreen({super.key, required this.event});

  @override
  ConsumerState<KnowledgeEventScreen> createState() =>
      _KnowledgeEventScreenState();
}

class _KnowledgeEventScreenState extends ConsumerState<KnowledgeEventScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic> _bracket = const {};
  bool _loading = true, _refreshing = false, _matchOpen = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _schedule();
  }

  void _schedule() {
    _poll?.cancel();
    if (_matchOpen) return;
    _poll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_load()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_matchOpen) {
      unawaited(_load());
      _schedule();
    } else {
      _poll?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final result = await ref
          .read(gamesApiProvider)
          .knowledgeBracket(_int(widget.event['id']));
      if (mounted) {
        setState(() {
          _bracket = result;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = knowledgeErrorText(error));
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openMatch(Map<String, dynamic> match) async {
    if (_matchOpen || match['canPlay'] != true || _int(match['id']) <= 0) {
      return;
    }
    _matchOpen = true;
    _poll?.cancel();
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => KnowledgeMatchScreen(
            matchId: _int(match['id']),
            returnToTournament: true,
          ),
        ),
      );
    } finally {
      _matchOpen = false;
    }
    if (!mounted) return;
    await _load();
    _schedule();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7F5),
        foregroundColor: knowledgeInk,
        surfaceTintColor: Colors.transparent,
        title: Text('${widget.event['title'] ?? 'البطولة'}'),
        actions: [
          IconButton(
            tooltip: 'تحديث البطولة',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  ListTile(
                    leading: const Icon(Icons.wifi_off),
                    title: Text(_error!),
                    trailing: IconButton(
                      tooltip: 'إعادة المحاولة',
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                if (_bracket.isNotEmpty)
                  KnowledgeTournamentBracket(
                    data: _bracket,
                    onOpenMatch: _openMatch,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class KnowledgeMatchScreen extends ConsumerStatefulWidget {
  final int matchId;
  final bool returnToTournament;
  const KnowledgeMatchScreen({
    super.key,
    required this.matchId,
    this.returnToTournament = false,
  });

  @override
  ConsumerState<KnowledgeMatchScreen> createState() =>
      _KnowledgeMatchScreenState();
}

class _KnowledgeMatchScreenState extends ConsumerState<KnowledgeMatchScreen>
    with WidgetsBindingObserver {
  static const _forest = Color(0xFF174C3A);
  late final KnowledgeMatchController _controller;
  bool _sendingChat = false;
  bool _rematching = false;
  bool _reducedMotion = false, _effects = true, _haptics = false;
  int? _confirmedRound;
  String _chatChannel = 'team';
  String? _voiceChannel;
  final TextEditingController _chatInput = TextEditingController();
  final TeamCodeVoiceController _voice = TeamCodeVoiceController();
  Map<String, dynamic> get _snapshot => _controller.snapshot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice.addListener(_voiceChanged);
    _controller = KnowledgeMatchController(
      api: ref.read(gamesApiProvider),
      matchId: widget.matchId,
      realtime: ref.read(knowledgeRealtimeProvider),
    )..addListener(_controllerChanged);
    unawaited(_controller.start());
    unawaited(_readSettings());
  }

  Future<void> _readSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _reducedMotion = prefs.getBool('knowledge.motion.off') ?? false;
          _effects = prefs.getBool('knowledge.effects') ?? true;
          _haptics = prefs.getBool('knowledge.haptics') ?? false;
        });
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.setActive(state == AppLifecycleState.resumed);
  }

  void _controllerChanged() {
    if (!mounted) return;
    final chat = _map(_snapshot['chat']);
    if (chat['publicEnabled'] != true && _chatChannel == 'public') {
      _chatChannel = 'team';
    }
    if ((_snapshot['phase'] == 'finished' ||
            (chat['publicEnabled'] != true && _voiceChannel == 'public')) &&
        _voice.isConnected) {
      _voiceChannel = null;
      unawaited(_voice.disconnect());
    }
    if (_controller.submission == KnowledgeSubmission.confirmed &&
        _confirmedRound != _controller.roundId) {
      _confirmedRound = _controller.roundId;
      if (_effects) unawaited(SystemSound.play(SystemSoundType.click));
      if (_haptics) unawaited(HapticFeedback.lightImpact());
    }
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_controllerChanged);
    _controller.dispose();
    _chatInput.dispose();
    _voice.removeListener(_voiceChanged);
    _voice.dispose();
    super.dispose();
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _settings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: _forest,
              brightness: Brightness.light,
            ),
          ),
          child: StatefulBuilder(
            builder: (context, update) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('تقليل الحركة'),
                    value: _reducedMotion,
                    onChanged: (v) {
                      update(() => _reducedMotion = v);
                      setState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('المؤثرات الصوتية'),
                    value: _effects,
                    onChanged: (v) {
                      update(() => _effects = v);
                      setState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('الاهتزاز'),
                    value: _haptics,
                    onChanged: (v) {
                      update(() => _haptics = v);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('knowledge.motion.off', _reducedMotion);
      await prefs.setBool('knowledge.effects', _effects);
      await prefs.setBool('knowledge.haptics', _haptics);
    } catch (_) {}
  }

  Future<void> _rematch() async {
    if (_rematching) return;
    final match = _map(_snapshot['match']);
    if (match['eventType'] == 'tournament') {
      if (widget.returnToTournament) {
        Navigator.of(context).pop();
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => KnowledgeEventScreen(
            event: {'id': match['eventId'], 'title': match['eventTitle']},
          ),
        ),
      );
      return;
    }
    _rematching = true;
    try {
      final next = await ref
          .read(gamesApiProvider)
          .createKnowledgeDuel(
            teamSize: _int(_map(_snapshot['match'])['teamSize']),
            bestOf: _int(_map(match['series'])['bestOf']) == 0
                ? 3
                : _int(_map(match['series'])['bestOf']),
          );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => KnowledgeWaitingRoomScreen(
            eventId: _int(next['eventId']),
            joinCode: '${next['joinCode']}',
            teamSize: _int(_map(_snapshot['match'])['teamSize']),
            title: 'تحدي خريطة المعرفة',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(knowledgeErrorText(error))));
      }
    } finally {
      _rematching = false;
    }
  }

  Future<void> _toggleKnowledgeVoice(String channel) async {
    if (_voice.isConnected && _voiceChannel == channel) {
      await _voice.disconnect();
      if (mounted) setState(() => _voiceChannel = null);
      return;
    }
    final api = ref.read(gamesApiProvider);
    await _voice.connect(
      api,
      widget.matchId,
      force: true,
      startMuted: true,
      accessProvider: () => api.knowledgeVoiceToken(widget.matchId, channel),
    );
    if (mounted) setState(() => _voiceChannel = channel);
  }

  Future<void> _sendKnowledgeMessage() async {
    final body = _chatInput.text.trim();
    if (body.isEmpty || _sendingChat) return;
    setState(() => _sendingChat = true);
    try {
      await ref
          .read(gamesApiProvider)
          .sendKnowledgeMessage(
            widget.matchId,
            channel: _chatChannel,
            body: body,
          );
      _chatInput.clear();
      await _load(quiet: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(knowledgeErrorText(error))));
      }
    } finally {
      if (mounted) setState(() => _sendingChat = false);
    }
  }

  Future<void> _sendKnowledgeReaction(String kind) async {
    try {
      await ref
          .read(gamesApiProvider)
          .reactKnowledgeMatch(widget.matchId, kind);
      await _load(quiet: true);
    } catch (_) {}
  }

  Future<void> _setPublicChatConsent(bool value) async {
    try {
      await ref
          .read(gamesApiProvider)
          .setKnowledgePublicChatConsent(widget.matchId, value);
      await _load(quiet: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(knowledgeErrorText(error))));
      }
    }
  }

  Widget _buildSocialPanel(Map<String, dynamic> chat, {required bool active}) {
    final publicEnabled = chat['publicEnabled'] == true;
    final consent = _map(chat['consent']);
    final ownTeam = _map(consent['ownTeam']);
    final otherTeam = _map(consent['opponentTeam']);
    final messages = (chat['messages'] as List? ?? const [])
        .map(_map)
        .where((message) => message['channel'] == _chatChannel)
        .toList();
    final reactions = (chat['reactions'] as List? ?? const [])
        .map(_map)
        .toList();
    final channel = _voiceChannel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تواصل الفريقين',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'team',
                  label: Text('فريقي'),
                  icon: Icon(Icons.shield_outlined),
                ),
                ButtonSegment(
                  value: 'public',
                  label: Text('عام'),
                  icon: Icon(Icons.groups_outlined),
                ),
              ],
              selected: {_chatChannel},
              onSelectionChanged: (values) {
                final next = values.first;
                if (next != 'public' || publicEnabled) {
                  setState(() => _chatChannel = next);
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: consent['enabled'] == true,
              onChanged: active ? _setPublicChatConsent : null,
              title: const Text('أوافق على فتح الدردشة العامة'),
              subtitle: Text(
                'موافقة فريقك ${ownTeam['optedIn'] ?? 0}/${ownTeam['required'] ?? 0} · الفريق الآخر ${otherTeam['optedIn'] ?? 0}/${otherTeam['required'] ?? 0}',
              ),
            ),
            if (publicEnabled)
              const ListTile(
                dense: true,
                leading: Icon(Icons.public, color: Color(0xFF174C3A)),
                title: Text('الدردشة العامة مفتوحة بموافقة الفريقين'),
              ),
            if (messages.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F4EE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - index - 1];
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${message['name'] ?? 'لاعب'}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('${message['body'] ?? ''}'),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatInput,
                    enabled: active,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: 'اكتب رسالة لفريقك',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendKnowledgeMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed:
                      !active ||
                          _sendingChat ||
                          (_chatChannel == 'public' && !publicEnabled)
                      ? null
                      : _sendKnowledgeMessage,
                  tooltip: 'إرسال',
                  icon: _sendingChat
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
            Wrap(
              spacing: 4,
              children: [
                for (final item in const {
                  'happy': '😀',
                  'angry': '😠',
                  'laugh': '😂',
                  'surprised': '😮',
                  'applause': '👏',
                }.entries)
                  IconButton(
                    tooltip: item.key,
                    onPressed: active
                        ? () => _sendKnowledgeReaction(item.key)
                        : null,
                    icon: Text(item.value),
                  ),
                IconButton(
                  tooltip: 'اطلب فتح الدردشة العامة',
                  onPressed: active
                      ? () => _sendKnowledgeReaction('request_public_chat')
                      : null,
                  icon: const Icon(Icons.campaign_outlined),
                ),
              ],
            ),
            if (reactions.isNotEmpty)
              Wrap(
                spacing: 6,
                children: reactions
                    .map(
                      (reaction) => Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${reaction['name'] ?? 'لاعب'} · ${reaction['kind']}',
                        ),
                      ),
                    )
                    .toList(),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: active
                      ? () => _toggleKnowledgeVoice('team')
                      : null,
                  icon: Icon(
                    channel == 'team' && _voice.isConnected
                        ? Icons.call_end_rounded
                        : Icons.headset_mic_outlined,
                  ),
                  label: Text(
                    channel == 'team' && _voice.isConnected
                        ? 'إنهاء صوت الفريق'
                        : 'صوت الفريق',
                  ),
                ),
                if (publicEnabled)
                  OutlinedButton.icon(
                    onPressed: active
                        ? () => _toggleKnowledgeVoice('public')
                        : null,
                    icon: Icon(
                      channel == 'public' && _voice.isConnected
                          ? Icons.call_end_rounded
                          : Icons.graphic_eq_rounded,
                    ),
                    label: Text(
                      channel == 'public' && _voice.isConnected
                          ? 'إنهاء الصوت العام'
                          : 'الصوت العام',
                    ),
                  ),
                if (_voice.isConnected)
                  IconButton(
                    tooltip: _voice.microphoneEnabled
                        ? 'كتم الميكروفون'
                        : 'تشغيل الميكروفون',
                    onPressed: _voice.toggleMicrophone,
                    icon: Icon(
                      _voice.microphoneEnabled
                          ? Icons.mic_rounded
                          : Icons.mic_off_rounded,
                    ),
                  ),
              ],
            ),
            if (_voice.needsAudioStart)
              TextButton.icon(
                onPressed: _voice.startAudio,
                icon: const Icon(Icons.volume_up_rounded),
                label: const Text('تشغيل الصوت'),
              ),
            if (_voice.error != null && _voice.error!.isNotEmpty)
              Text(
                'تعذر الاتصال الصوتي: ${_voice.error}',
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _load({bool quiet = false}) => _controller.refresh();

  @override
  Widget build(BuildContext context) => KnowledgeArena(
    controller: _controller,
    reducedMotion: _reducedMotion,
    onSettings: _settings,
    onRematch: _rematch,
    social: ExpansionTile(
      key: const PageStorageKey('knowledge-chat'),
      maintainState: true,
      leading: Icon(
        _voice.isConnected ? Icons.headset_mic : Icons.forum_outlined,
        color: _forest,
      ),
      title: const Text(
        'دردشة الفريق والصوت',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      children: [
        _buildSocialPanel(
          _map(_snapshot['chat']),
          active: _map(_snapshot['match'])['status'] == 'active',
        ),
      ],
    ),
  );
}

class _KnowledgeHero extends StatelessWidget {
  final VoidCallback? onCreate;
  const _KnowledgeHero({required this.onCreate});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF174C3A),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFC18B2F), width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.explore_rounded, color: Color(0xFFE7C982), size: 34),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'افتح خريطة المعرفة',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'أجب بسرعة، وسّع نفوذ فريقك، ونافس على لقب مسلكي.',
          style: TextStyle(color: Color(0xFFE6EEE9), height: 1.45),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onCreate,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFD5A64A),
            foregroundColor: const Color(0xFF172F29),
          ),
          icon: const Icon(Icons.sports_esports_rounded),
          label: const Text('إنشاء غرفة'),
        ),
      ],
    ),
  );
}

class _EventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback onOpen;
  final VoidCallback? onRegister;
  const _EventTile({
    required this.event,
    required this.onOpen,
    this.onRegister,
  });
  @override
  Widget build(BuildContext context) {
    final prize = _map(event['prize']);
    final tournament = event['type'] == 'tournament';
    final duel = event['type'] == 'duel';
    final roomSubtitle = duel
        ? '${event['occupiedSeats'] ?? 0}/${event['totalSeats'] ?? 2} مقعد • ${event['isPrivate'] == true ? 'خاصة' : 'عامة'} • ${event['status'] == 'closed' ? 'مغلقة' : 'مفتوحة'}'
        : '${event['teamSize']} ضد ${event['teamSize']} • ${event['registeredTeams']}/${event['maxTeams']} فريق • ${event['status'] == 'active'
              ? 'جارية'
              : event['status'] == 'completed'
              ? 'مكتملة'
              : 'التسجيل مفتوح'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            ListTile(
              onTap: onOpen,
              leading: Icon(
                tournament
                    ? Icons.emoji_events_outlined
                    : Icons.flash_on_rounded,
                color: const Color(0xFFC18B2F),
              ),
              title: Text(
                '${event['title'] ?? 'تحدي المعرفة'}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                '$roomSubtitle${_int(event['bestOf']) > 1 ? '\nالأفضل من ${event['bestOf']} جولات' : ''}',
              ),
              trailing: const Icon(Icons.chevron_left_rounded),
            ),
            if (prize.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.redeem_rounded,
                      size: 17,
                      color: Color(0xFF9B6B1E),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${prize['title']}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (prize['mock'] == true)
                      const Text(
                        'بإشراف الإدارة',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
              ),
            if (onRegister != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: onRegister,
                  icon: const Icon(Icons.group_add_outlined),
                  label: Text(
                    duel
                        ? event['status'] == 'closed'
                              ? 'إعادة التنشيط'
                              : 'فتح الغرفة'
                        : 'سجّل فريقاً',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  final String text;
  const _EmptyNotice({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F2E9),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(text, textAlign: TextAlign.center),
  );
}

class _ErrorNotice extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorNotice({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.error_outline, color: Colors.red),
    title: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh)),
  );
}

String _knowledgeActionError(Object error) {
  final value = '${knowledgeErrorCode(error)} $error'.toUpperCase();
  if (value.contains('TEAM_FULL')) return 'الفريق مكتمل ولا توجد خانة شاغرة.';
  if (value.contains('TEAM_NOT_JOINABLE')) {
    return 'الرمز غير صحيح أو انتهى التسجيل.';
  }
  if (value.contains('EVENT_CLOSED')) return 'التسجيل في هذه البطولة مغلق.';
  if (value.contains('ROOM_NOT_FOUND')) {
    return 'تعذر العثور على الغرفة المرتبطة بهذا الرمز.';
  }
  if (value.contains('ROOM_SEAT_UNAVAILABLE')) {
    return 'هذا المقعد لم يعد متاحًا. حدّث الغرفة واختر مقعدًا آخر.';
  }
  if (value.contains('ROOM_ALREADY_SEATED')) {
    return 'أنت جالس بالفعل في مقعد من هذه الغرفة.';
  }
  if (value.contains('ROOM_NOT_JOINABLE')) {
    return 'الغرفة مغلقة أو بدأت المباراة بالفعل.';
  }
  if (value.contains('ROOM_ALREADY_STARTED')) {
    return 'بدأت المباراة؛ لا يمكن تغيير المقعد أثناء اللعب.';
  }
  if (value.contains('ROOM_NOT_CLOSABLE')) {
    return 'لا يمكن إغلاق الغرفة بعد بدء المباراة.';
  }
  if (value.contains('ROOM_NOT_REACTIVATABLE')) {
    return 'تعذر إعادة تنشيط الغرفة؛ حدّث قائمة الغرف وحاول مرة أخرى.';
  }
  if (value.contains('TOURNAMENT_NEEDS_TWO_FULL_TEAMS')) {
    return 'تبدأ البطولة بعد اكتمال فريقين على الأقل.';
  }
  if (value.contains('RESOURCE_ALREADY_EXISTS')) {
    return 'أنت مسجل في هذا الحدث بالفعل؛ أعد فتح فريقك من الرمز نفسه.';
  }
  return knowledgeErrorText(error);
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
int _int(dynamic value) => int.tryParse('$value') ?? 0;
