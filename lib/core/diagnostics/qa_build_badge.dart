import 'package:flutter/material.dart';

import 'build_info.dart';

/// A small, non-interactive "QA {shortSHA}" badge overlaid on the app in
/// non-store QA builds (Social V3 §6). It exists so a tester can confirm at a
/// glance which build is installed — preventing another stale-APK confusion.
///
/// Controlled by the `SHOW_QA_BADGE` dart-define (default off), so production
/// store builds are clean. Enable it for the verification APK:
/// `--dart-define=SHOW_QA_BADGE=true`.
class QaBuildBadge extends StatelessWidget {
  const QaBuildBadge({super.key, required this.child});

  final Widget child;

  static const bool _enabled =
      bool.fromEnvironment('SHOW_QA_BADGE', defaultValue: false);

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return child;
    final info = BuildInfo.compileTime;
    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: Stack(
        children: [
          child,
          Positioned(
            top: MediaQuery.of(context).padding.top + 2,
            right: 6,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xCCB00020),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'QA ${info.shortSha}',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
