import 'package:flutter/material.dart';

/// Segmented story progress bar (§5).
///
/// Shows one segment per item **of the current group only** — never one segment
/// for every story of every account. Items before [currentIndex] are full,
/// the current item shows [currentProgress] (0..1), later items are empty.
class StoryProgressBarV3 extends StatelessWidget {
  const StoryProgressBarV3({
    super.key,
    required this.itemCount,
    required this.currentIndex,
    required this.currentProgress,
  });

  final int itemCount;
  final int currentIndex;
  final double currentProgress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(itemCount, (i) {
        final double fill;
        if (i < currentIndex) {
          fill = 1.0;
        } else if (i == currentIndex) {
          fill = currentProgress.clamp(0.0, 1.0);
        } else {
          fill = 0.0;
        }
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fill,
                minHeight: 3,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ),
        );
      }),
    );
  }
}
