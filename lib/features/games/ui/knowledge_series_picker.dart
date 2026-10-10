import 'package:flutter/material.dart';

class KnowledgeSeriesPicker extends StatelessWidget {
  const KnowledgeSeriesPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('نظام الجولات', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      SegmentedButton<int>(
        segments: [
          for (final n in [3, 5, 9])
            ButtonSegment(value: n, label: Text('$n جولات')),
        ],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: (selected) => onChanged(selected.single),
      ),
      const SizedBox(height: 8),
      Text(
        'الحسم بـ ${value ~/ 2 + 1} انتصارات · 5 أسئلة لكل جولة',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13),
      ),
    ],
  );
}
