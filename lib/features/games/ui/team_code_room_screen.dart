import 'dart:async';

import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../data/games_api.dart';
import '../state/team_code_room_controller.dart';
import '../state/team_code_voice_controller.dart';

class TeamCodeRoomScreen extends ConsumerStatefulWidget {
  final int roomId;

  const TeamCodeRoomScreen({super.key, required this.roomId});

  @override
  ConsumerState<TeamCodeRoomScreen> createState() => _TeamCodeRoomScreenState();
}

class _TeamCodeRoomScreenState extends ConsumerState<TeamCodeRoomScreen>
    with WidgetsBindingObserver {
  final _code = <int>[];
  final _messageController = TextEditingController();
  final TeamCodeVoiceController _voice = TeamCodeVoiceController();
  Timer? _clock;
  DateTime _now = DateTime.now();
  int? _timeoutRefreshRoundId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice.addListener(_voiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_voice.connect(ref.read(gamesApiProvider), widget.roomId));
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final state = ref.read(teamCodeRoomControllerProvider(widget.roomId));
      final snapshot = state.snapshot;
      if (snapshot != null) {
        final round = _map(snapshot['round']);
        final roundId = _int(round['id']);
        if (round['status'] == 'active' &&
            _remainingRoundSeconds(snapshot, now) <= 0 &&
            _timeoutRefreshRoundId != roundId) {
          _timeoutRefreshRoundId = roundId;
          unawaited(
            ref
                .read(teamCodeRoomControllerProvider(widget.roomId).notifier)
                .refresh(silent: true),
          );
        }
      }
      setState(() => _now = now);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice.removeListener(_voiceChanged);
    _voice.dispose();
    _clock?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_voice.retry());
    }
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _confirmLeave() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مغادرة الجولة؟'),
        content: const Text(
          'سيتم حفظ التقدم، لكن المغادرة المتعمدة تزيلك من الفريق الحالي.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('البقاء'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('مغادرة'),
          ),
        ],
      ),
    );
    if (result != true) return false;
    await _voice.disconnect();
    await ref.read(gamesApiProvider).leave(widget.roomId).catchError((_) {});
    return true;
  }

  Future<void> _submitCode(Map<String, dynamic> snapshot) async {
    final round = _map(snapshot['round']);
    final length = _int(round['codeLength']);
    if (_code.length != length) return;
    final value = _code.join();
    final mode = '${_map(snapshot['room'])['mode']}';
    final controller = ref.read(
      teamCodeRoomControllerProvider(widget.roomId).notifier,
    );
    if (mode == 'solo') {
      await controller.attempt(value);
    } else {
      await controller.proposeCode(value);
    }
    if (mounted) setState(_code.clear);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(teamCodeRoomControllerProvider(widget.roomId));
    final snapshot = state.snapshot;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (snapshot == null && context.mounted) {
          Navigator.of(context).pop();
        } else if (await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (snapshot == null && context.mounted) {
                Navigator.of(context).pop();
              } else if (await _confirmLeave() && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: const Text('شفرة الفريق'),
          actions: [
            IconButton(
              onPressed: () => ref
                  .read(teamCodeRoomControllerProvider(widget.roomId).notifier)
                  .refresh(),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'تحديث الحالة',
            ),
          ],
        ),
        body: state.loading && snapshot == null
            ? const Center(child: CircularProgressIndicator())
            : snapshot == null
            ? _RoomError(
                message: state.error,
                onRetry: () => ref
                    .read(
                      teamCodeRoomControllerProvider(widget.roomId).notifier,
                    )
                    .refresh(),
                onReturn: () => Navigator.of(context).pop(),
              )
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: _content(snapshot, state),
              ),
      ),
    );
  }

  Widget _content(Map<String, dynamic> snapshot, TeamCodeRoomState state) {
    final room = _map(snapshot['room']);
    final status = '${room['status']}';
    late final Widget content;
    if (status == 'lobby') {
      content = _LobbyView(
        key: const ValueKey('lobby'),
        snapshot: snapshot,
        acting: state.acting,
      );
    } else if (status == 'completed' ||
        status == 'failed' ||
        status == 'abandoned') {
      content = _ResultView(key: const ValueKey('result'), snapshot: snapshot);
    } else {
      content = _GameView(
        key: const ValueKey('game'),
        snapshot: snapshot,
        acting: state.acting,
        error: state.error,
        code: _code,
        now: _now,
        messageController: _messageController,
        onDigit: (digit) {
          final length = _int(_map(snapshot['round'])['codeLength']);
          if (_code.length >= length || _code.contains(digit)) return;
          setState(() => _code.add(digit));
        },
        onBackspace: () {
          if (_code.isNotEmpty) setState(() => _code.removeLast());
        },
        onClear: () => setState(_code.clear),
        onSubmit: () => _submitCode(snapshot),
      );
    }
    final voice = _map(snapshot['voice']);
    if (voice['enabled'] != true) return content;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _TeamCodeVoiceBar(
            controller: _voice,
            members: _listOfMaps(snapshot['members']),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(child: content),
      ],
    );
  }
}

class _TeamCodeVoiceBar extends StatelessWidget {
  const _TeamCodeVoiceBar({required this.controller, required this.members});

  final TeamCodeVoiceController controller;
  final List<Map<String, dynamic>> members;

  @override
  Widget build(BuildContext context) {
    final connected = controller.state == TeamCodeVoiceState.connected;
    final waiting =
        controller.state == TeamCodeVoiceState.connecting ||
        controller.state == TeamCodeVoiceState.reconnecting ||
        controller.state == TeamCodeVoiceState.requestingPermission;
    final speakers = members
        .where(
          (member) =>
              controller.activeSpeakerUserIds.contains(_int(member['userId'])),
        )
        .map((member) => '${member['name'] ?? ''}'.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final statusText = speakers.isNotEmpty
        ? 'يتحدث الآن: ${speakers.join('، ')}'
        : connected
        ? 'الصوت متصل'
        : waiting
        ? 'جارٍ ربط الصوت...'
        : controller.state == TeamCodeVoiceState.disabled
        ? 'الصوت غير متاح'
        : 'تعذر اتصال الصوت';
    final color = connected
        ? context.maslakiTokens.success
        : context.maslakiTokens.secondaryAccent;

    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 7, 6, 7),
      decoration: BoxDecoration(
        color: context.maslakiTokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .65)),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: connected ? .18 : .1),
            ),
            child: Icon(
              speakers.isNotEmpty
                  ? Icons.graphic_eq_rounded
                  : Icons.spatial_audio_off_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  controller.microphoneEnabled ? 'مايكك مفتوح' : 'مايكك مغلق',
                  style: TextStyle(
                    color: context.maslakiTokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (controller.needsAudioStart)
            IconButton(
              onPressed: controller.startAudio,
              tooltip: 'تشغيل الصوت',
              icon: const Icon(Icons.play_circle_outline_rounded),
            ),
          if (controller.state == TeamCodeVoiceState.error)
            IconButton(
              onPressed: controller.retry,
              tooltip: 'إعادة اتصال الصوت',
              icon: const Icon(Icons.refresh_rounded),
            ),
          IconButton(
            onPressed: connected ? controller.toggleSpeaker : null,
            tooltip: controller.speakerEnabled ? 'كتم السماعة' : 'فتح السماعة',
            icon: Icon(
              controller.speakerEnabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
            ),
          ),
          IconButton.filledTonal(
            onPressed: connected ? controller.toggleMicrophone : null,
            tooltip: controller.microphoneRequested
                ? 'غلق المايك'
                : 'فتح المايك',
            icon: Icon(
              controller.microphoneRequested
                  ? Icons.mic_rounded
                  : Icons.mic_off_rounded,
              color:
                  controller.microphoneRequested &&
                      controller.canPublish &&
                      connected
                  ? context.maslakiTokens.success
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _LobbyView extends ConsumerWidget {
  final Map<String, dynamic> snapshot;
  final bool acting;
  const _LobbyView({super.key, required this.snapshot, required this.acting});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = _map(snapshot['room']);
    final me = _map(snapshot['me']);
    final members = _listOfMaps(snapshot['members']);
    final userId = _int(me['userId']);
    final host = _int(room['hostUserId']) == userId;
    final myMember = members.cast<Map<String, dynamic>?>().firstWhere(
      (item) => _int(item?['userId']) == userId,
      orElse: () => null,
    );
    final ready = myMember?['isReady'] == true;
    final allReady =
        members.length >= 2 && members.every((item) => item['isReady'] == true);
    final code = '${room['inviteCode'] ?? ''}';
    final controller = ref.read(
      teamCodeRoomControllerProvider(_int(room['id'])).notifier,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
      children: [
        Text(
          'ردهة الفريق',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'يبدأ المضيف عندما يصبح الجميع جاهزين.',
          style: TextStyle(color: context.maslakiTokens.textSecondary),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.maslakiTokens.surfaceSecondary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: context.maslakiTokens.secondaryAccent.withValues(
                alpha: .55,
              ),
            ),
          ),
          child: Column(
            children: [
              const Text(
                'رمز الدعوة',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              SelectableText(
                code,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ رمز الغرفة')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: 'نسخ الرمز',
                  ),
                  IconButton(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                        text:
                            'انضم إلى شفرة الفريق في مسلكي. رمز الغرفة: $code',
                      ),
                    ),
                    icon: const Icon(Icons.share_rounded),
                    tooltip: 'مشاركة الدعوة',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'اللاعبون ${members.length}/4',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        ...members.map(
          (member) =>
              _MemberTile(member: member, hostUserId: _int(room['hostUserId'])),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: acting ? null : () => controller.setReady(!ready),
          icon: Icon(
            ready
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
          ),
          label: Text(ready ? 'أنا جاهز' : 'تحديد أنني جاهز'),
        ),
        if (host) ...[
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: !acting && allReady ? controller.launch : null,
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('بدء الجولة'),
          ),
        ],
      ],
    );
  }
}

class _GameView extends ConsumerWidget {
  final Map<String, dynamic> snapshot;
  final bool acting;
  final String? error;
  final List<int> code;
  final DateTime now;
  final TextEditingController messageController;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  const _GameView({
    super.key,
    required this.snapshot,
    required this.acting,
    required this.error,
    required this.code,
    required this.now,
    required this.messageController,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = _map(snapshot['room']);
    final round = _map(snapshot['round']);
    final session = _map(snapshot['session']);
    final members = _listOfMaps(snapshot['members']);
    final clues = _listOfMaps(round['clues']);
    final hints = _listOfMaps(round['revealedHints']);
    final proposal = _map(snapshot['proposal']);
    final messages = _listOfMaps(snapshot['messages']);
    final me = _map(snapshot['me']);
    final mode = '${room['mode']}';
    final length = _int(round['codeLength']);
    final remainingSeconds = _remainingRoundSeconds(snapshot, now);
    final timeLimitSeconds = _int(round['timeLimitSeconds']);
    final urgent = remainingSeconds <= 30;
    final controller = ref.read(
      teamCodeRoomControllerProvider(_int(room['id'])).notifier,
    );
    final connected = members
        .where((member) => member['isConnected'] == true)
        .length;
    final canContinueSolo = mode == 'cooperative' && connected == 1;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'الخزنة ${_int(round['index'])} من 3',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            _Metric(
              icon: urgent ? Icons.timer_rounded : Icons.timer_outlined,
              label: _clockText(remainingSeconds),
              color: urgent ? context.maslakiTokens.danger : null,
            ),
            const SizedBox(width: 6),
            _Metric(
              icon: Icons.stars_rounded,
              label: '${_int(session['score'])}',
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: timeLimitSeconds <= 0
                ? 0
                : (remainingSeconds / timeLimitSeconds).clamp(0.0, 1.0),
            color: urgent
                ? context.maslakiTokens.danger
                : context.maslakiTokens.primaryAccent,
            backgroundColor: context.maslakiTokens.surfaceSecondary,
          ),
        ),
        const SizedBox(height: 10),
        if (error != null) _Notice(text: error!, danger: true),
        if (members.any((member) => member['isConnected'] != true))
          const _Notice(
            text: 'ننتظر عودة أحد أعضاء الفريق. التصويت متوقف لحماية دوره.',
          ),
        if (canContinueSolo)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              onPressed: acting ? null : controller.continueSolo,
              icon: const Icon(Icons.person_rounded),
              label: const Text('المتابعة منفردًا بكل الأدلة'),
            ),
          ),
        _VaultPanel(
          title: _localized(round['title']),
          length: length,
          code: code,
          attempts: _int(round['attemptsRemaining']),
          hints: _int(round['hintsRemaining']),
        ),
        const SizedBox(height: 12),
        _NumberPad(
          onDigit: onDigit,
          onBackspace: onBackspace,
          onClear: onClear,
          disabled: acting,
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: !acting && code.length == length ? onSubmit : null,
          icon: Icon(
            mode == 'solo'
                ? Icons.lock_open_rounded
                : Icons.how_to_vote_rounded,
          ),
          label: Text(mode == 'solo' ? 'تجربة الرمز' : 'اقتراح الرمز للتصويت'),
        ),
        const SizedBox(height: 18),
        _SectionTitle(
          icon: Icons.description_outlined,
          title: mode == 'solo' ? 'ملفات الأدلة' : 'أدلتي',
        ),
        ...clues.map(
          (clue) => _ClueTile(
            index: _int(clue['index']) + 1,
            text: _localized(clue['text']),
          ),
        ),
        if (hints.isNotEmpty) ...[
          const SizedBox(height: 8),
          const _SectionTitle(
            icon: Icons.lightbulb_outline_rounded,
            title: 'التلميحات المكشوفة',
          ),
          ...hints.map(
            (hint) => _ClueTile(
              index: _int(hint['index']) + 1,
              text: _localized(hint['text']),
              hint: true,
            ),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: acting || _int(round['hintsRemaining']) <= 0
              ? null
              : mode == 'solo'
              ? controller.hint
              : controller.proposeHint,
          icon: const Icon(Icons.lightbulb_outline_rounded),
          label: Text(mode == 'solo' ? 'كشف تلميح' : 'طلب تلميح بالتصويت'),
        ),
        if (proposal.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ProposalPanel(
            snapshot: snapshot,
            proposal: proposal,
            acting: acting,
          ),
        ],
        const SizedBox(height: 18),
        const _SectionTitle(icon: Icons.groups_rounded, title: 'الفريق'),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: members.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, index) => _PlayerChip(member: members[index]),
          ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text(
            'محادثة الفريق',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          leading: const Icon(Icons.chat_bubble_outline_rounded),
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              alignment: Alignment.center,
              child: messages.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('ابدأوا بتبادل الأدلة.'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (_, index) => _MessageLine(
                        message: messages[index],
                        meUserId: _int(me['userId']),
                      ),
                    ),
            ),
            Wrap(
              spacing: 6,
              children:
                  ['عندي دليل', 'راجعوا الترتيب', 'شنو رأيكم؟', 'نحتاج تلميح']
                      .map(
                        (text) => ActionChip(
                          label: Text(text),
                          onPressed: () => controller.sendMessage(text),
                        ),
                      )
                      .toList(),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    maxLength: 300,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'اكتب لفريقك...',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(controller),
                  ),
                ),
                IconButton(
                  onPressed: () => _send(controller),
                  icon: const Icon(Icons.send_rounded),
                  tooltip: 'إرسال',
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _send(TeamCodeRoomController controller) async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;
    messageController.clear();
    await controller.sendMessage(text);
  }
}

class _ProposalPanel extends ConsumerWidget {
  final Map<String, dynamic> snapshot;
  final Map<String, dynamic> proposal;
  final bool acting;
  const _ProposalPanel({
    required this.snapshot,
    required this.proposal,
    required this.acting,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = _map(snapshot['room']);
    final me = _map(snapshot['me']);
    final votes = _listOfMaps(proposal['votes']);
    final alreadyVoted = votes.any(
      (vote) => _int(vote['membershipId']) == _int(me['membershipId']),
    );
    final isHint = proposal['kind'] == 'hint';
    final controller = ref.read(
      teamCodeRoomControllerProvider(_int(room['id'])).notifier,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.maslakiTokens.secondaryAccent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.maslakiTokens.secondaryAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'تصويت جارٍ',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            isHint
                ? '${proposal['proposerName']} يقترح كشف تلميح.'
                : '${proposal['proposerName']} يقترح الرمز ${proposal['proposedCode']}.',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '${votes.where((vote) => vote['vote'] == 'approve').length} موافقة من ${_listOfMaps(snapshot['members']).where((member) => member['isConnected'] == true).length}',
          ),
          if (!alreadyVoted) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: acting
                        ? null
                        : () => controller.vote(_int(proposal['id']), true),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('موافقة'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: acting
                        ? null
                        : () => controller.vote(_int(proposal['id']), false),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('رفض'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultView extends ConsumerWidget {
  final Map<String, dynamic> snapshot;
  const _ResultView({super.key, required this.snapshot});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = _map(snapshot['room']);
    final session = _map(snapshot['session']);
    final results = _listOfMaps(snapshot['results']);
    final completed = room['status'] == 'completed';
    final timedOut = _map(snapshot['round'])['failureReason'] == 'timeout';
    final me = _map(snapshot['me']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Icon(
          completed ? Icons.verified_rounded : Icons.lock_clock_rounded,
          size: 76,
          color: completed
              ? context.maslakiTokens.success
              : context.maslakiTokens.warning,
        ),
        const SizedBox(height: 8),
        Text(
          completed
              ? 'فُتحت الخزائن الثلاث'
              : timedOut
              ? 'انتهى وقت الخزنة'
              : 'انتهت الجولة',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          '${_int(session['score'])} نقطة',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.maslakiTokens.secondaryAccent,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 18),
        ...results.map(
          (result) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.maslakiTokens.cardPrimary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.maslakiTokens.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'الخزنة ${result['index']} • ${_localized(result['title'])}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  'الحل: ${result['solutionCode']}',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: context.maslakiTokens.primaryAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(_localized(result['explanation'])),
              ],
            ),
          ),
        ),
        if (completed && me['rewardEligible'] == true)
          const _Notice(
            text:
                'أنت مؤهل لمكافأة الاختبار. ستظهر في سجل الجولات بعبارة غير قابلة للاستخدام.',
          ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.sports_esports_rounded),
          label: const Text('العودة إلى ألعاب مسلكي'),
        ),
      ],
    );
  }
}

class _VaultPanel extends StatelessWidget {
  final String title;
  final int length;
  final List<int> code;
  final int attempts;
  final int hints;
  const _VaultPanel({
    required this.title,
    required this.length,
    required this.code,
    required this.attempts,
    required this.hints,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.maslakiTokens.cardPrimary,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: context.maslakiTokens.secondaryAccent.withValues(alpha: .55),
      ),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              color: context.maslakiTokens.secondaryAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '$attempts محاولات • $hints تلميحات',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 48,
                height: 58,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index < code.length
                      ? context.maslakiTokens.primaryAccent
                      : context.maslakiTokens.surfaceSecondary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: context.maslakiTokens.borderSubtle,
                    width: 1.4,
                  ),
                ),
                child: Text(
                  index < code.length ? '${code[index]}' : '—',
                  style: TextStyle(
                    color: index < code.length
                        ? Colors.white
                        : context.maslakiTokens.textMuted,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'لا تتكرر الأرقام داخل الرمز',
          style: TextStyle(
            color: context.maslakiTokens.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _NumberPad extends StatelessWidget {
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final bool disabled;
  const _NumberPad({
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.disabled,
  });
  @override
  Widget build(BuildContext context) {
    final items = <Object>[1, 2, 3, 4, 5, 6, 7, 8, 9, 'clear', 0, 'back'];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.15,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: items.length,
      itemBuilder: (_, index) {
        final item = items[index];
        if (item == 'clear') {
          return IconButton.filledTonal(
            onPressed: disabled ? null : onClear,
            icon: const Icon(Icons.clear_all_rounded),
            tooltip: 'مسح',
          );
        }
        if (item == 'back') {
          return IconButton.filledTonal(
            onPressed: disabled ? null : onBackspace,
            icon: const Icon(Icons.backspace_outlined),
            tooltip: 'حذف',
          );
        }
        return FilledButton.tonal(
          onPressed: disabled ? null : () => onDigit(item as int),
          child: Text(
            '$item',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
        );
      },
    );
  }
}

class _MemberTile extends StatelessWidget {
  final Map<String, dynamic> member;
  final int hostUserId;
  const _MemberTile({required this.member, required this.hostUserId});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(child: Text(_initial('${member['name']}'))),
    title: Text(
      '${member['name']}',
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    subtitle: Text(member['isConnected'] == true ? 'متصل' : 'يعيد الاتصال...'),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_int(member['userId']) == hostUserId)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.workspace_premium_rounded, size: 20),
          ),
        Icon(
          member['isReady'] == true
              ? Icons.check_circle_rounded
              : Icons.hourglass_empty_rounded,
          color: member['isReady'] == true
              ? context.maslakiTokens.success
              : context.maslakiTokens.textMuted,
        ),
      ],
    ),
  );
}

class _PlayerChip extends StatelessWidget {
  final Map<String, dynamic> member;
  const _PlayerChip({required this.member});
  @override
  Widget build(BuildContext context) => Container(
    width: 112,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: context.maslakiTokens.surfaceSecondary,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.maslakiTokens.borderSubtle),
    ),
    child: Row(
      children: [
        CircleAvatar(radius: 18, child: Text(_initial('${member['name']}'))),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${member['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                member['isConnected'] == true ? 'متصل' : 'غائب',
                style: TextStyle(
                  fontSize: 11,
                  color: member['isConnected'] == true
                      ? context.maslakiTokens.success
                      : context.maslakiTokens.warning,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MessageLine extends StatelessWidget {
  final Map<String, dynamic> message;
  final int meUserId;
  const _MessageLine({required this.message, required this.meUserId});
  @override
  Widget build(BuildContext context) {
    final mine = _int(message['userId']) == meUserId;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: mine
              ? context.maslakiTokens.primaryAccent.withValues(alpha: .12)
              : context.maslakiTokens.surfaceSecondary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${message['senderName']}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
            Text('${message['body']}'),
          ],
        ),
      ),
    );
  }
}

class _ClueTile extends StatelessWidget {
  final int index;
  final String text;
  final bool hint;
  const _ClueTile({required this.index, required this.text, this.hint = false});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 7),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: hint
          ? context.maslakiTokens.secondaryAccent.withValues(alpha: .09)
          : context.maslakiTokens.surfaceSecondary,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.maslakiTokens.borderSubtle),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: hint
              ? context.maslakiTokens.secondaryAccent
              : context.maslakiTokens.primaryAccent,
          foregroundColor: Colors.white,
          child: Text(
            '$index',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 9),
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

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 21),
        const SizedBox(width: 7),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _Metric({required this.icon, required this.label, this.color});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 250),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color:
          color?.withValues(alpha: .12) ??
          context.maslakiTokens.surfaceSecondary,
      borderRadius: BorderRadius.circular(8),
      border: color == null ? null : Border.all(color: color!),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w900, color: color),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  final String text;
  final bool danger;
  const _Notice({required this.text, this.danger = false});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color:
          (danger
                  ? context.maslakiTokens.danger
                  : context.maslakiTokens.warning)
              .withValues(alpha: .1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class _RoomError extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onReturn;
  const _RoomError({
    required this.message,
    required this.onRetry,
    required this.onReturn,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48),
          const SizedBox(height: 12),
          const Text(
            'لا يمكن فتح هذه الجولة',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            message ?? 'تحقق من الاتصال ثم حاول مجددًا.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
          TextButton.icon(
            onPressed: onReturn,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('العودة إلى ألعاب مسلكي'),
          ),
        ],
      ),
    ),
  );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> _listOfMaps(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : const [];
int _int(dynamic value) => int.tryParse('$value') ?? 0;
String _localized(dynamic value) {
  final map = _map(value);
  return '${map['ar'] ?? map['en'] ?? ''}';
}

String _initial(String value) {
  final safe = value.trim();
  return safe.isEmpty ? 'م' : safe.characters.first;
}

int _remainingRoundSeconds(Map<String, dynamic> snapshot, DateTime now) {
  final round = _map(snapshot['round']);
  final initial = _int(round['remainingSeconds']);
  final receivedAtMs = _int(snapshot['_clientReceivedAtMs']);
  if (initial <= 0 || receivedAtMs <= 0) return initial;
  final elapsed = (now.millisecondsSinceEpoch - receivedAtMs) ~/ 1000;
  final remaining = initial - (elapsed < 0 ? 0 : elapsed);
  return remaining < 0 ? 0 : remaining;
}

String _clockText(int totalSeconds) {
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
