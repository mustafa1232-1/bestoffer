import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../state/knowledge_match_controller.dart';
import 'knowledge_landmark_art.dart';
import 'knowledge_match_board.dart';

String knowledgeRoundTitle(int number, int total) => switch (total - number) {
  0 => 'النهائي',
  1 => 'نصف النهائي',
  2 => 'ربع النهائي',
  _ => 'دور ${1 << (total - number + 1)}',
};

class KnowledgeTournamentBracket extends StatefulWidget {
  const KnowledgeTournamentBracket({
    super.key,
    required this.data,
    required this.onOpenMatch,
  });
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onOpenMatch;
  @override
  State<KnowledgeTournamentBracket> createState() =>
      _KnowledgeTournamentBracketState();
}

class _KnowledgeTournamentBracketState
    extends State<KnowledgeTournamentBracket> {
  final _transform = TransformationController();
  Size? _viewport, _canvas;
  int _selectedRound = 1;
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _fit(Size viewport, Size canvas) {
    final scale =
        math.min(
          viewport.width / canvas.width,
          viewport.height / canvas.height,
        ) *
        .96;
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, (viewport.width - canvas.width * scale) / 2)
      ..setEntry(1, 3, (viewport.height - canvas.height * scale) / 2);
  }

  void _zoom(double factor) {
    final viewport = _viewport;
    if (viewport == null) return;
    final matrix = _transform.value.clone();
    final old = matrix.getMaxScaleOnAxis();
    final next = (old * factor).clamp(.08, 2.5);
    final ratio = next / old;
    matrix.setEntry(0, 0, next);
    matrix.setEntry(1, 1, next);
    matrix.setEntry(
      0,
      3,
      viewport.width / 2 - (viewport.width / 2 - matrix.entry(0, 3)) * ratio,
    );
    matrix.setEntry(
      1,
      3,
      viewport.height / 2 - (viewport.height / 2 - matrix.entry(1, 3)) * ratio,
    );
    _transform.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    final event = knowledgeMap(widget.data['event']);
    final rounds = (widget.data['rounds'] as List? ?? [])
        .map(knowledgeMap)
        .toList();
    final teams = (widget.data['teams'] as List? ?? [])
        .map(knowledgeMap)
        .toList();
    final champion = knowledgeMap(event['champion']);
    final bestOf = knowledgeInt(event['bestOf']);
    if (rounds.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 160, child: KnowledgeLandmarkArt(index: 11)),
          const Text(
            'الفرق المسجلة',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const Text('المواجهات بانتظار قرعة الإدارة'),
          for (final team in teams)
            ListTile(
              leading: const Icon(Icons.groups_rounded),
              title: Text('${team['name']}'),
              trailing: Text('${team['members']} / ${event['teamSize']}'),
            ),
          if (teams.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('لم يُسجّل فريق بعد.'),
            ),
        ],
      );
    }
    final selected = _selectedRound.clamp(1, rounds.length);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final cardSize = Size(208, 112 + math.max(0, textScale - 1) * 80);
    final firstCount = (rounds.first['matches'] as List).length;
    final sideRounds = rounds.length - 1;
    final canvas = Size(
      (sideRounds * 2 + 1) * (cardSize.width + 40),
      math.max(480, (firstCount / 2).ceil() * (cardSize.height + 32)),
    );
    final nodes = <String, Offset>{};
    final matches = <String, Map<String, dynamic>>{};
    for (final round in rounds) {
      final n = knowledgeInt(round['number']);
      final list = (round['matches'] as List).map(knowledgeMap).toList();
      for (var index = 0; index < list.length; index++) {
        final right = index >= list.length / 2;
        final local = right ? index - list.length / 2 : index.toDouble();
        final x = n == rounds.length
            ? (canvas.width - cardSize.width) / 2
            : right
            ? canvas.width -
                  cardSize.width -
                  20 -
                  (n - 1) * (cardSize.width + 40)
            : 20 + (n - 1) * (cardSize.width + 40);
        final y = n == rounds.length
            ? canvas.height / 2 - cardSize.height / 2
            : (local + .5) * canvas.height / (list.length / 2) -
                  cardSize.height / 2;
        final key = '$n-${index + 1}';
        nodes[key] = Offset(x, y);
        matches[key] = list[index];
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          champion.isEmpty ? 'الطريق إلى الكأس' : 'البطل: ${champion['name']}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: knowledgeInk,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          bestOf > 1
              ? 'الأفضل من $bestOf · الحسم بـ ${bestOf ~/ 2 + 1} انتصارات'
              : 'مواجهة واحدة لكل دور',
          textAlign: TextAlign.center,
        ),
        if (knowledgeMap(event['prize']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${knowledgeMap(event['prize'])['title']}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: knowledgeInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final height =
                (constraints.maxWidth * canvas.height / canvas.width + 56)
                    .clamp(240.0, 500.0);
            final viewport = Size(constraints.maxWidth, height);
            if (_viewport != viewport || _canvas != canvas) {
              _viewport = viewport;
              _canvas = canvas;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _fit(viewport, canvas);
              });
            }
            return SizedBox(
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: const Color(0xFFEDF4F2),
                      child: InteractiveViewer(
                        transformationController: _transform,
                        constrained: false,
                        minScale: .08,
                        maxScale: 2.5,
                        boundaryMargin: const EdgeInsets.all(500),
                        child: RepaintBoundary(
                          key: const ValueKey('knowledge-bracket-chart'),
                          child: SizedBox(
                            width: canvas.width,
                            height: canvas.height,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _BracketConnectors(
                                      nodes,
                                      matches,
                                      cardSize,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: (canvas.width - 140) / 2,
                                  top:
                                      canvas.height / 2 -
                                      cardSize.height / 2 -
                                      154,
                                  width: 140,
                                  height: 145,
                                  child: const KnowledgeLandmarkArt(index: 11),
                                ),
                                for (final entry in matches.entries)
                                  Positioned(
                                    left: nodes[entry.key]!.dx,
                                    top: nodes[entry.key]!.dy,
                                    width: cardSize.width,
                                    height: cardSize.height,
                                    child: KnowledgeBracketMatch(
                                      match: entry.value,
                                      bestOf: bestOf,
                                      onTap: entry.value['canPlay'] == true
                                          ? () =>
                                                widget.onOpenMatch(entry.value)
                                          : null,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Material(
                      color: Colors.white,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'تكبير المخطط',
                            onPressed: () => _zoom(1.4),
                            icon: const Icon(Icons.add),
                          ),
                          IconButton(
                            tooltip: 'تصغير المخطط',
                            onPressed: () => _zoom(1 / 1.4),
                            icon: const Icon(Icons.remove),
                          ),
                          IconButton(
                            tooltip: 'عرض المخطط كاملاً',
                            onPressed: () => _fit(viewport, canvas),
                            icon: const Icon(Icons.fit_screen),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final round in rounds)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    selectedColor: const Color(0xFFD8EBE3),
                    backgroundColor: Colors.white,
                    labelStyle: const TextStyle(color: knowledgeInk),
                    label: Text(
                      knowledgeRoundTitle(
                        knowledgeInt(round['number']),
                        rounds.length,
                      ),
                    ),
                    selected: selected == knowledgeInt(round['number']),
                    onSelected: (_) => setState(
                      () => _selectedRound = knowledgeInt(round['number']),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final match in (rounds[selected - 1]['matches'] as List).map(
          knowledgeMap,
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: cardSize.height,
              child: KnowledgeBracketMatch(
                match: match,
                bestOf: bestOf,
                onTap: match['canPlay'] == true
                    ? () => widget.onOpenMatch(match)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class KnowledgeBracketMatch extends StatelessWidget {
  const KnowledgeBracketMatch({
    super.key,
    required this.match,
    required this.bestOf,
    this.onTap,
  });
  final Map<String, dynamic> match;
  final int bestOf;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final winner = knowledgeInt(match['winnerTeamId']);
    Widget team(String side, Color color) {
      final value = knowledgeMap(match['team$side']);
      final source = knowledgeMap(match['source$side']);
      final name =
          value['name'] ??
          (match['status'] == 'bye'
              ? 'تأهل مباشر'
              : source.isEmpty
              ? 'بانتظار القرعة'
              : 'فائز ${source['round']} / ${source['matchNumber']}');
      return Expanded(
        child: Row(
          children: [
            Icon(
              winner > 0 && knowledgeInt(value['id']) == winner
                  ? Icons.emoji_events_rounded
                  : Icons.shield_outlined,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$name',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${match[bestOf > 1 ? 'wins$side' : 'score$side'] ?? 0}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: knowledgeInk,
              ),
            ),
          ],
        ),
      );
    }

    final label = switch (match['status']) {
      'completed' => 'انتهت',
      'bye' => 'تأهل مباشر',
      'active' => 'مباشر',
      'pending' => 'جاهزة',
      _ => 'بانتظار المتأهلين',
    };
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: match['canPlay'] == true
              ? knowledgeTeal
              : const Color(0xFFCDDCD7),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'المواجهة ${match['matchNumber']}',
                      maxLines: 2,
                      style: const TextStyle(fontSize: 11, color: knowledgeInk),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 11, color: knowledgeInk),
                    ),
                  ),
                  if (onTap != null) const Icon(Icons.chevron_left, size: 16),
                ],
              ),
              team('A', knowledgeTeal),
              team('B', knowledgeCoral),
            ],
          ),
        ),
      ),
    );
  }
}

class _BracketConnectors extends CustomPainter {
  const _BracketConnectors(this.nodes, this.matches, this.size);
  final Map<String, Offset> nodes;
  final Map<String, Map<String, dynamic>> matches;
  final Size size;
  @override
  void paint(Canvas canvas, Size bounds) {
    for (final entry in matches.entries) {
      final target = nodes[entry.key]!;
      for (final side in ['A', 'B']) {
        final source = knowledgeMap(entry.value['source$side']);
        final from = nodes['${source['round']}-${source['matchNumber']}'];
        if (from == null) continue;
        final toRight = target.dx > from.dx;
        final a = Offset(
          from.dx + (toRight ? size.width : 0),
          from.dy + size.height / 2,
        );
        final b = Offset(
          target.dx + (toRight ? 0 : size.width),
          target.dy + size.height / 2,
        );
        final mid = (a.dx + b.dx) / 2;
        canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(mid, a.dy)
            ..lineTo(mid, b.dy)
            ..lineTo(b.dx, b.dy),
          Paint()
            ..color = knowledgeMap(entry.value['team$side']).isNotEmpty
                ? knowledgeGold
                : const Color(0xFF9CB6AB)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BracketConnectors old) =>
      old.nodes != nodes || old.matches != matches || old.size != size;
}
