import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../state/knowledge_match_controller.dart';
import 'knowledge_landmark_art.dart';

const knowledgeInk = Color(0xFF173D35);
const knowledgeTeal = Color(0xFF14604E);
const knowledgeCoral = Color(0xFFAC3444);
const knowledgeGold = Color(0xFFE6B852);

class KnowledgeArena extends StatelessWidget {
  const KnowledgeArena({
    super.key,
    required this.controller,
    required this.social,
    required this.reducedMotion,
    required this.onSettings,
    required this.onRematch,
  });
  final KnowledgeMatchController controller;
  final Widget social;
  final bool reducedMotion;
  final VoidCallback onSettings;
  final VoidCallback onRematch;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final snapshot = c.snapshot;
    final match = knowledgeMap(snapshot['match']);
    final question = knowledgeMap(snapshot['question']);
    final teams = knowledgeMap(match['teams']);
    final series = knowledgeMap(match['series']);
    final bestOf = knowledgeInt(series['bestOf']);
    final result = knowledgeMap(snapshot['result']);
    final phase = snapshot['phase'];
    final motion = reducedMotion || MediaQuery.disableAnimationsOf(context);
    final ownResult = (result['outcomes'] as List? ?? [])
        .map(knowledgeMap)
        .where((r) => r['teamId'] == knowledgeMap(teams[match['mySide']])['id'])
        .firstOrNull;
    final confirmed = c.submission == KnowledgeSubmission.confirmed;
    final checking = c.submission == KnowledgeSubmission.reconciling;
    final sending = c.submission == KnowledgeSubmission.submitting;
    final status = sending
        ? 'جارٍ تسجيل إجابتك'
        : checking
        ? 'نتحقق من حفظ إجابتك'
        : confirmed
        ? 'تم تسجيل إجابتك'
        : phase == 'resolving'
        ? 'انتهى الوقت، ننتظر النتيجة'
        : c.selectedDistrict == null
        ? 'اختر منطقة وإجابة'
        : 'اعتماد الإجابة';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: Theme.of(context).copyWith(
          scaffoldBackgroundColor: const Color(0xFFF5F8F8),
          colorScheme:
              ColorScheme.fromSeed(
                seedColor: knowledgeInk,
                brightness: Brightness.light,
              ).copyWith(
                surface: Colors.white,
                onSurface: const Color(0xFF162D35),
                primary: knowledgeInk,
              ),
          textTheme: Theme.of(context).textTheme.apply(
            bodyColor: const Color(0xFF162D35),
            displayColor: const Color(0xFF162D35),
          ),
          cardTheme: const CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        child: Container(
          color: const Color(0xFFEDF3F4),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.white,
                foregroundColor: knowledgeInk,
                surfaceTintColor: Colors.transparent,
                titleSpacing: 0,
                title: Row(
                  children: [
                    Image.asset(
                      'assets/branding/maslaki_official_logo.png',
                      height: 32,
                      width: 32,
                      cacheWidth: 96,
                      semanticLabel: 'مسلكي',
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'خريطة المعرفة',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'إعدادات الحركة والصوت',
                    onPressed: onSettings,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
              body: SafeArea(
                top: false,
                child: Column(
                  children: [
                    KnowledgeCompetitionHeader(
                      controller: c,
                      reducedMotion: motion,
                    ),
                    if (c.offline)
                      Material(
                        color: const Color(0xFFFFEACA),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.wifi_off,
                            color: Color(0xFF774300),
                          ),
                          title: Text(
                            c.message ?? 'الاتصال متقطع. اختيارك محفوظ.',
                            style: const TextStyle(color: Color(0xFF593600)),
                          ),
                          trailing: IconButton(
                            tooltip: 'إعادة الاتصال',
                            onPressed: c.refresh,
                            icon: const Icon(Icons.refresh),
                          ),
                        ),
                      ),
                    Expanded(
                      child: c.loading && snapshot.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : ListView(
                              key: const ValueKey('knowledge-content'),
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                16,
                              ),
                              children: [
                                if (phase == 'finished') ...[
                                  _MatchResult(
                                    match: match,
                                    result: result,
                                    motion: motion,
                                  ),
                                  FilledButton.icon(
                                    onPressed: onRematch,
                                    icon: const Icon(Icons.replay),
                                    label: Text(
                                      match['eventType'] == 'tournament'
                                          ? 'مخطط البطولة والمواجهة التالية'
                                          : 'إعادة اللعب في غرفة جديدة',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('العودة إلى الغرف'),
                                  ),
                                ] else if (phase == 'countdown')
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 32,
                                    ),
                                    alignment: Alignment.center,
                                    child: Column(
                                      children: [
                                        const Icon(
                                          Icons.hourglass_top_rounded,
                                          size: 40,
                                          color: knowledgeInk,
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'استعد لفريقك',
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        KnowledgeClock(
                                          controller: c,
                                          large: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                if (bestOf > 1 &&
                                    result['gameCompleted'] == true)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      'حُسمت الجولة ${result['gameNumber']} · ${series['winsA']} مقابل ${series['winsB']}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: knowledgeInk,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                if (question.isNotEmpty &&
                                    phase != 'countdown' &&
                                    phase != 'finished') ...[
                                  Row(
                                    children: [
                                      Text(
                                        '${question['categoryLabel'] ?? 'المعرفة'}',
                                        style: const TextStyle(
                                          color: knowledgeInk,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (knowledgeInt(
                                            match['questionNumber'],
                                          ) >=
                                          5)
                                        const Text('سؤال فاصل'),
                                    ],
                                  ),
                                  KnowledgeQuestionReward(question: question),
                                  const SizedBox(height: 8),
                                  AnimatedSwitcher(
                                    duration: motion
                                        ? Duration.zero
                                        : const Duration(milliseconds: 200),
                                    child: Align(
                                      key: ValueKey(question['id']),
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        '${question['text'] ?? ''}',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...List.generate(
                                    (question['options'] as List? ?? []).length,
                                    (i) {
                                      final chosen = c.selectedAnswer == i;
                                      final correct =
                                          result['correctAnswerIndex'] == i;
                                      final wrong =
                                          result.isNotEmpty &&
                                          chosen &&
                                          !correct;
                                      final color = correct
                                          ? const Color(0xFFE2F3E9)
                                          : wrong
                                          ? const Color(0xFFFFE6E6)
                                          : chosen
                                          ? const Color(0xFFDDF1F2)
                                          : Colors.white;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Semantics(
                                          selected: chosen,
                                          button: true,
                                          enabled: c.canSelect,
                                          child: AnimatedContainer(
                                            duration: motion
                                                ? Duration.zero
                                                : const Duration(
                                                    milliseconds: 140,
                                                  ),
                                            decoration: BoxDecoration(
                                              color: color,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: correct
                                                    ? knowledgeInk
                                                    : wrong
                                                    ? knowledgeCoral
                                                    : chosen
                                                    ? knowledgeTeal
                                                    : const Color(0xFFCBD9DE),
                                                width: chosen || correct
                                                    ? 2
                                                    : 1,
                                              ),
                                            ),
                                            child: Material(
                                              type: MaterialType.transparency,
                                              child: InkWell(
                                                key: ValueKey(
                                                  'knowledge-answer-$i',
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                onTap: c.canSelect
                                                    ? () => c.selectAnswer(i)
                                                    : null,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 11,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        correct
                                                            ? Icons.check_circle
                                                            : wrong
                                                            ? Icons.cancel
                                                            : chosen
                                                            ? Icons
                                                                  .radio_button_checked
                                                            : Icons
                                                                  .radio_button_off,
                                                        color: wrong
                                                            ? knowledgeCoral
                                                            : chosen || correct
                                                            ? knowledgeInk
                                                            : const Color(
                                                                0xFF61747D,
                                                              ),
                                                        size: 22,
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Text(
                                                          '${(question['options'] as List)[i]}',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 15,
                                                                height: 1.4,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                                if (result.isNotEmpty && phase != 'finished')
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ownResult?['correct'] == true
                                              ? 'إجابة فريقك صحيحة! +${ownResult?['points'] ?? 0}'
                                              : 'فرصة جديدة في السؤال القادم',
                                          style: const TextStyle(
                                            color: knowledgeInk,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '${result['explanation'] ?? ''}',
                                          style: const TextStyle(height: 1.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (phase == 'waiting')
                                  const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'نجهّز بداية مشتركة للفريقين...',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                if (match.isNotEmpty)
                                  KnowledgeMapSection(
                                    match: match,
                                    selected: c.selectedDistrict,
                                    onSelect: c.canSelect
                                        ? c.selectDistrict
                                        : null,
                                    reducedMotion: motion,
                                  ),
                                if (c.message != null && !c.offline)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      c.message!,
                                      style: const TextStyle(
                                        color: Color(0xFF8C3535),
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                const Divider(),
                                social,
                              ],
                            ),
                    ),
                    if (phase != 'finished' && phase != 'countdown')
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (confirmed)
                              Text(
                                'أجاب ${knowledgeMap(snapshot['lastAnswer'])['submitted'] ?? 0} من ${knowledgeMap(snapshot['lastAnswer'])['total'] ?? 0} في فريقك',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF536970),
                                ),
                              ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                key: const ValueKey('knowledge-submit'),
                                onPressed: checking
                                    ? c.reconcile
                                    : c.canSubmit
                                    ? c.submit
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: knowledgeInk,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: confirmed
                                      ? const Color(0xFFDCEFE7)
                                      : const Color(0xFFE5EDEE),
                                  disabledForegroundColor: knowledgeInk,
                                  minimumSize: const Size(0, 50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: AnimatedSwitcher(
                                  duration: motion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 150),
                                  child: sending
                                      ? const SizedBox(
                                          key: ValueKey('sending'),
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          confirmed
                                              ? Icons.check_circle
                                              : checking
                                              ? Icons.sync
                                              : Icons.bolt,
                                          key: ValueKey(status),
                                        ),
                                ),
                                label: Text(
                                  checking ? 'التحقق من الإجابة' : status,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class KnowledgeCompetitionHeader extends StatelessWidget {
  const KnowledgeCompetitionHeader({
    super.key,
    required this.controller,
    required this.reducedMotion,
  });
  final KnowledgeMatchController controller;
  final bool reducedMotion;
  @override
  Widget build(BuildContext context) {
    final match = knowledgeMap(controller.snapshot['match']);
    final teams = knowledgeMap(match['teams']);
    final series = knowledgeMap(match['series']);
    final bestOf = knowledgeInt(series['bestOf']);
    final question = knowledgeInt(match['questionNumber']);
    final finished = controller.snapshot['phase'] == 'finished';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(13) > 18 ? 142 : 114,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: KnowledgeScore(
                        team: knowledgeMap(teams['a']),
                        color: knowledgeTeal,
                        symbol: Icons.shield_rounded,
                        reducedMotion: reducedMotion,
                        own: match['mySide'] == 'a',
                        wins: bestOf > 1 ? knowledgeInt(series['winsA']) : null,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: KnowledgeScore(
                        team: knowledgeMap(teams['b']),
                        color: knowledgeCoral,
                        symbol: Icons.flag_rounded,
                        reducedMotion: reducedMotion,
                        own: match['mySide'] == 'b',
                        wins: bestOf > 1 ? knowledgeInt(series['winsB']) : null,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: knowledgeGold,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFFF0B9),
                      width: 3,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'VS',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: knowledgeInk,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 56,
            child: Row(
              children: [
                const Icon(Icons.route_rounded, size: 18, color: knowledgeInk),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    question >= 5 ? 'سؤال فاصل' : 'السؤال ${question + 1} من 5',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 5; i++) ...[
                        if (i > 0)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: i <= question || finished
                                  ? knowledgeGold
                                  : const Color(0xFFCFDEDA),
                            ),
                          ),
                        AnimatedContainer(
                          duration: reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 250),
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i <= question || finished
                                ? knowledgeGold
                                : const Color(0xFFE1EAE7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (finished)
                  const Icon(Icons.sports_score_rounded, color: knowledgeInk)
                else
                  KnowledgeClock(controller: controller),
              ],
            ),
          ),
          if (bestOf > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'الجولة ${series['game']} من $bestOf · الحسم بـ ${series['winsRequired']} انتصارات',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class KnowledgeScore extends StatelessWidget {
  const KnowledgeScore({
    super.key,
    required this.team,
    required this.color,
    required this.symbol,
    required this.reducedMotion,
    required this.own,
    this.wins,
  });
  final Map<String, dynamic> team;
  final Color color;
  final IconData symbol;
  final bool reducedMotion, own;
  final int? wins;
  @override
  Widget build(BuildContext context) => Container(
    height: double.infinity,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: knowledgeGold, width: 1.5),
    ),
    padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(symbol, color: const Color(0xFFFFE6A4), size: 20),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '${team['name'] ?? 'فريق'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                end: (wins ?? knowledgeInt(team['score'])).toDouble(),
              ),
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 350),
              builder: (_, value, _) => FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${value.round()}',
                  style: const TextStyle(
                    color: Color(0xFFFFE6A4),
                    fontSize: 34,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
        Text(
          wins == null
              ? (own ? 'فريقك' : 'المنافس')
              : 'انتصارات · نقاط الجولة ${team['score'] ?? 0}',
          style: const TextStyle(
            fontSize: 10,
            height: 1.1,
            color: Color(0xFFF2F8F4),
          ),
        ),
      ],
    ),
  );
}

class KnowledgeQuestionReward extends StatelessWidget {
  const KnowledgeQuestionReward({super.key, required this.question});
  final Map<String, dynamic> question;
  @override
  Widget build(BuildContext context) {
    final rules = knowledgeMap(question['scoring']);
    if (rules.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          Text(
            '${knowledgeInt(rules['basePoints'])} نقطة للإجابة الصحيحة',
            style: const TextStyle(
              fontSize: 12,
              color: knowledgeInk,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'السرعة: حتى +${knowledgeInt(rules['maxSpeedBonus'])}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF765219)),
          ),
        ],
      ),
    );
  }
}

class KnowledgeClock extends StatefulWidget {
  const KnowledgeClock({
    super.key,
    required this.controller,
    this.large = false,
  });
  final KnowledgeMatchController controller;
  final bool large;
  @override
  State<KnowledgeClock> createState() => _KnowledgeClockState();
}

class _KnowledgeClockState extends State<KnowledgeClock> {
  Timer? _tick;
  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  @override
  void didUpdateWidget(KnowledgeClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleTick();
  }

  void _scheduleTick() {
    _tick?.cancel();
    if (![
      'countdown',
      'question_open',
    ].contains(widget.controller.snapshot['phase'])) {
      return;
    }
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final countdown = c.snapshot['phase'] == 'countdown';
    final end = DateTime.tryParse(
      '${knowledgeMap(c.snapshot['round'])[countdown ? 'startsAt' : 'deadlineAt']}',
    );
    final seconds = end == null
        ? 0
        : math.max(
            0,
            (end.difference(c.serverNow).inMilliseconds / 1000).ceil(),
          );
    final visible = [
      'question_open',
      'countdown',
    ].contains(c.snapshot['phase']);
    final starts = DateTime.tryParse(
      '${knowledgeMap(c.snapshot['round'])['startsAt']}',
    );
    final totalMs = countdown
        ? 3000
        : end != null && starts != null
        ? end.difference(starts).inMilliseconds
        : 1;
    final fraction = end == null || !visible
        ? 0.0
        : (end.difference(c.serverNow).inMilliseconds / math.max(1, totalMs))
              .clamp(0.0, 1.0);
    final color = visible && seconds <= 5 && !countdown
        ? knowledgeCoral
        : knowledgeInk;
    return Semantics(
      label: countdown
          ? 'بداية السؤال بعد $seconds ثانية'
          : 'الوقت المتبقي $seconds ثانية',
      child: SizedBox(
        width: widget.large ? 80 : 54,
        height: widget.large ? 80 : 50,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: CircularProgressIndicator(
                  value: fraction,
                  strokeWidth: 3,
                  color: color,
                  backgroundColor: const Color(0xFFD8E5DF),
                ),
              ),
            ),
            Text(
              visible ? '$seconds' : '—',
              style: TextStyle(
                fontSize: widget.large ? 36 : 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class KnowledgeMapSection extends StatelessWidget {
  const KnowledgeMapSection({
    super.key,
    required this.match,
    this.selected,
    this.onSelect,
    required this.reducedMotion,
  });
  final Map<String, dynamic> match;
  final String? selected;
  final ValueChanged<String>? onSelect;
  final bool reducedMotion;
  @override
  Widget build(BuildContext context) {
    final territories = knowledgeMap(match['territories']);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.map_outlined, color: knowledgeInk, size: 23),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'خريطة السيطرة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              if (selected != null && selected != 'none')
                const Icon(
                  Icons.location_on,
                  color: Color(0xFF9A6612),
                  size: 21,
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'الاحتلال: +1 منطقة · دون نقاط إضافية',
            style: TextStyle(fontSize: 12, color: Color(0xFF4C625C)),
          ),
          const SizedBox(height: 12),
          RepaintBoundary(
            child: KnowledgeTerritoryMap(
              match: match,
              selected: selected,
              onSelect: onSelect,
              reducedMotion: reducedMotion,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 6,
            children: [
              _TerritoryCount(
                color: knowledgeTeal,
                icon: Icons.shield_rounded,
                count: (territories['a'] as List? ?? []).length,
                name:
                    '${knowledgeMap(knowledgeMap(match['teams'])['a'])['name'] ?? 'الفريق أ'}',
              ),
              _TerritoryCount(
                color: knowledgeCoral,
                icon: Icons.flag_rounded,
                count: (territories['b'] as List? ?? []).length,
                name:
                    '${knowledgeMap(knowledgeMap(match['teams'])['b'])['name'] ?? 'الفريق ب'}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TerritoryCount extends StatelessWidget {
  const _TerritoryCount({
    required this.color,
    required this.icon,
    required this.name,
    required this.count,
  });
  final Color color;
  final IconData icon;
  final String name;
  final int count;
  String get countLabel => switch (count) {
    0 => 'دون مناطق',
    1 => 'منطقة واحدة',
    2 => 'منطقتان',
    >= 3 && <= 10 => '$count مناطق',
    _ => '$count منطقة',
  };
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          '$name: $countLabel',
          maxLines: 2,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

// The art layout is decorative; only server-provided neighbors draw roads or
// permit a conquest. Tile bounds never move when a landmark celebrates.
class KnowledgeTerritoryMap extends StatelessWidget {
  const KnowledgeTerritoryMap({
    super.key,
    required this.match,
    this.selected,
    this.onSelect,
    this.reducedMotion = false,
  });
  final Map<String, dynamic> match;
  final String? selected;
  final ValueChanged<String>? onSelect;
  final bool reducedMotion;
  static const positions = {
    'souk': Offset(2, 0),
    'river': Offset(1, 0),
    'garden': Offset(0, 0),
    'old-city': Offset(2, 1),
    'bridge': Offset(1, 1),
    'library': Offset(0, 1),
    'market': Offset(2, 2),
    'crafts': Offset(1, 2),
    'science': Offset(0, 2),
    'sports': Offset(1.55, 3),
    'arts': Offset(.45, 3),
  };
  static const artIndices = {
    'souk': 0,
    'river': 1,
    'garden': 2,
    'old-city': 3,
    'bridge': 4,
    'library': 5,
    'market': 6,
    'crafts': 7,
    'science': 8,
    'sports': 9,
    'arts': 10,
  };
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final districts = (match['districts'] as List? ?? [])
          .map(knowledgeMap)
          .toList();
      final available = (match['availableDistricts'] as List? ?? [])
          .map(knowledgeMap)
          .map((d) => d['id'])
          .toSet();
      final owned = knowledgeMap(match['territories']);
      final a = (owned['a'] as List? ?? []).toSet(),
          b = (owned['b'] as List? ?? []).toSet();
      final stepX = constraints.maxWidth / 3;
      final stepY =
          132.0 +
          math.max(0, MediaQuery.textScalerOf(context).scale(12) - 12) * 4;
      final width = stepX - 10, height = stepY - 14;
      final centers = positions.map(
        (id, p) => MapEntry(
          id,
          Offset(stepX * p.dx + stepX / 2, stepY * p.dy + height / 2),
        ),
      );
      return SizedBox(
        height: stepY * 4,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _KnowledgeRoads(districts, centers)),
            ),
            for (final district in districts)
              if (positions.containsKey(district['id']))
                Positioned(
                  left: centers[district['id']]!.dx - width / 2,
                  top: centers[district['id']]!.dy - height / 2,
                  width: width,
                  height: height,
                  child: RepaintBoundary(
                    child: _TerritoryTile(
                      id: '${district['id']}',
                      name: '${district['nameAr']}',
                      artIndex: artIndices[district['id']]!,
                      owner: a.contains(district['id'])
                          ? 'a'
                          : b.contains(district['id'])
                          ? 'b'
                          : null,
                      chosen: selected == district['id'],
                      available: available.contains(district['id']),
                      onTap:
                          onSelect != null && available.contains(district['id'])
                          ? () => onSelect!('${district['id']}')
                          : null,
                      reducedMotion: reducedMotion,
                    ),
                  ),
                ),
          ],
        ),
      );
    },
  );
}

class _TerritoryTile extends StatefulWidget {
  const _TerritoryTile({
    required this.id,
    required this.name,
    required this.artIndex,
    required this.owner,
    required this.chosen,
    required this.available,
    required this.onTap,
    required this.reducedMotion,
  });
  final String id, name;
  final int artIndex;
  final String? owner;
  final bool chosen, available, reducedMotion;
  final VoidCallback? onTap;
  @override
  State<_TerritoryTile> createState() => _TerritoryTileState();
}

class _TerritoryTileState extends State<_TerritoryTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _celebrate = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  @override
  void didUpdateWidget(_TerritoryTile old) {
    super.didUpdateWidget(old);
    if (widget.reducedMotion) {
      _celebrate.stop();
      _celebrate.value = 0;
    } else if (widget.owner != old.owner || (widget.chosen && !old.chosen)) {
      _celebrate.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _celebrate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final occupied = widget.owner != null;
    final color = widget.owner == 'a'
        ? knowledgeTeal
        : widget.owner == 'b'
        ? knowledgeCoral
        : widget.chosen
        ? const Color(0xFFFFF8E5)
        : const Color(0xFFEDF4F0);
    final ink = occupied ? Colors.white : knowledgeInk;
    final ownership = widget.owner == 'a'
        ? 'الفريق أ'
        : widget.owner == 'b'
        ? 'الفريق ب'
        : 'محايدة';
    final label =
        '${widget.name}، $ownership${widget.chosen ? '، الهدف المختار' : ''}';
    final detail = occupied
        ? 'منطقة محتلة'
        : widget.available
        ? '+1 منطقة'
        : 'غير متصلة';
    return Semantics(
      button: true,
      selected: widget.chosen,
      enabled: widget.onTap != null,
      label: '$label، $detail',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: Tooltip(
        message: '$label، $detail',
        child: ClipPath(
          clipper: const _TerritoryClip(),
          child: AnimatedContainer(
            duration: widget.reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 280),
            color: color,
            child: CustomPaint(
              foregroundPainter: _TerritoryBorder(
                widget.chosen
                    ? knowledgeGold
                    : occupied
                    ? const Color(0xFFD9B35B)
                    : widget.available
                    ? const Color(0xFF8EAFA0)
                    : const Color(0xFFC6D5D1),
                widget.chosen ? 3 : 1.5,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: ValueKey('district-${widget.id}'),
                  onTap: widget.onTap,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(5, 4, 5, 5),
                        child: Column(
                          children: [
                            Expanded(
                              child: AnimatedBuilder(
                                animation: _celebrate,
                                child: KnowledgeLandmarkArt(
                                  index: widget.artIndex,
                                ),
                                builder: (context, child) {
                                  final lift = math.sin(
                                    _celebrate.value * math.pi,
                                  );
                                  return Transform.translate(
                                    offset: Offset(0, -3 * lift),
                                    child: Transform.scale(
                                      scale: 1 + .065 * lift,
                                      child: child,
                                    ),
                                  );
                                },
                              ),
                            ),
                            Text(
                              widget.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                color: ink,
                                fontSize: 12,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              detail,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                color: occupied
                                    ? const Color(0xFFFFE6A4)
                                    : const Color(0xFF486557),
                                fontSize: 10,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 5,
                        right: 5,
                        child: AnimatedSwitcher(
                          duration: widget.reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: Container(
                            key: ValueKey('${widget.owner}:${widget.chosen}'),
                            width: 23,
                            height: 23,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                              border: Border.all(
                                color: occupied
                                    ? const Color(0xFFFFE6A4)
                                    : knowledgeInk,
                              ),
                            ),
                            child: Icon(
                              widget.owner == 'a'
                                  ? Icons.shield_rounded
                                  : widget.owner == 'b'
                                  ? Icons.flag_rounded
                                  : widget.chosen
                                  ? Icons.place
                                  : widget.available
                                  ? Icons.add
                                  : Icons.lock_outline,
                              size: 14,
                              color: occupied
                                  ? const Color(0xFFFFE6A4)
                                  : knowledgeInk,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Path _territoryPath(Size s) => Path()
  ..moveTo(14, 0)
  ..lineTo(s.width - 18, 0)
  ..quadraticBezierTo(s.width, 0, s.width, 18)
  ..lineTo(s.width - 3, s.height - 15)
  ..quadraticBezierTo(s.width - 3, s.height, s.width - 19, s.height)
  ..lineTo(17, s.height)
  ..quadraticBezierTo(0, s.height, 1, s.height - 17)
  ..lineTo(3, 17)
  ..quadraticBezierTo(4, 0, 14, 0)
  ..close();

class _TerritoryClip extends CustomClipper<Path> {
  const _TerritoryClip();
  @override
  Path getClip(Size size) => _territoryPath(size);
  @override
  bool shouldReclip(_TerritoryClip old) => false;
}

class _TerritoryBorder extends CustomPainter {
  _TerritoryBorder(this.color, this.width);
  final Color color;
  final double width;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    _territoryPath(size),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width,
  );
  @override
  bool shouldRepaint(_TerritoryBorder old) =>
      color != old.color || width != old.width;
}

class _KnowledgeRoads extends CustomPainter {
  _KnowledgeRoads(this.districts, this.centers);
  final List<Map<String, dynamic>> districts;
  final Map<String, Offset> centers;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8AA69A)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final d in districts) {
      for (final neighbor in (d['neighbors'] as List? ?? [])) {
        final a = centers[d['id']], b = centers[neighbor];
        if (a == null ||
            b == null ||
            '${d['id']}'.compareTo('$neighbor') >= 0) {
          continue;
        }
        final delta = b - a, length = delta.distance;
        for (double start = 0; start < length; start += 10) {
          canvas.drawLine(
            a + delta * (start / length),
            a + delta * (math.min(start + 4, length) / length),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_KnowledgeRoads old) =>
      old.centers['souk'] != centers['souk'] ||
      old.centers['sports'] != centers['sports'] ||
      !identical(old.districts, districts);
}

class _MatchResult extends StatelessWidget {
  const _MatchResult({
    required this.match,
    required this.result,
    required this.motion,
  });
  final Map<String, dynamic> match, result;
  final bool motion;
  @override
  Widget build(BuildContext context) {
    final teams = knowledgeMap(match['teams']);
    final a = knowledgeMap(teams['a']), b = knowledgeMap(teams['b']);
    final winner = match['winnerTeamId'] == a['id'] ? a : b;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .9, end: 1),
      duration: motion ? Duration.zero : const Duration(milliseconds: 600),
      builder: (_, value, child) => Transform.scale(scale: value, child: child),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            const SizedBox(
              width: 110,
              height: 92,
              child: KnowledgeLandmarkArt(index: 11),
            ),
            const SizedBox(height: 10),
            Text(
              'الفوز لفريق ${winner['name'] ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: knowledgeInk,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${a['score']} : ${b['score']}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
