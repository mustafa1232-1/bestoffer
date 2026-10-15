import 'package:flutter/material.dart';

import 'social_design_theme.dart';

class SocialFeedSkeleton extends StatefulWidget {
  const SocialFeedSkeleton({super.key});

  @override
  State<SocialFeedSkeleton> createState() => _SocialFeedSkeletonState();
}

class _SocialFeedSkeletonState extends State<SocialFeedSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
    } else {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: FadeTransition(
        opacity: Tween<double>(begin: .4, end: .85).animate(_pulse),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: List.generate(
              2,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Color(0xFFD6D6DB),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: ColoredBox(
                            color: Color(0xFFD6D6DB),
                            child: SizedBox(height: 12),
                          ),
                        ),
                        SizedBox(width: 90),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AspectRatio(
                      aspectRatio: 1.4,
                      child: ColoredBox(
                        color: SocialDesignTheme.indigo.withValues(alpha: .1),
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
