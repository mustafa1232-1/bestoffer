import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'build_info.dart';

/// Hidden build-identity diagnostics screen (Social V3 §0).
///
/// Reached by a deliberate gesture (tapping the version label in Settings seven
/// times). It reports the authoritative [BuildInfo] so an on-device screenshot
/// can prove which SHA is actually installed — the acceptance gate for the
/// whole remediation.
class BuildDiagnosticsScreen extends StatefulWidget {
  const BuildDiagnosticsScreen({super.key});

  @override
  State<BuildDiagnosticsScreen> createState() => _BuildDiagnosticsScreenState();
}

class _BuildDiagnosticsScreenState extends State<BuildDiagnosticsScreen> {
  BuildInfo _info = BuildInfo.compileTime;

  @override
  void initState() {
    super.initState();
    BuildInfo.load().then((value) {
      if (!mounted) return;
      setState(() => _info = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Scaffold(
      backgroundColor: tokens.backgroundPrimary,
      appBar: const MaslakiTopBar(
        title: 'Build diagnostics',
        subtitle: 'Authoritative build identity',
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          MaslakiCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        _info.isAuthoritative
                            ? Icons.verified_rounded
                            : Icons.warning_amber_rounded,
                        color: _info.isAuthoritative
                            ? tokens.primaryAccent
                            : Colors.orangeAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _info.isAuthoritative
                              ? 'Release build — SHA is authoritative'
                              : 'Dev build — SHA not injected',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._info.toRows().map(
                        (row) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 140,
                                child: Text(
                                  row.key,
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SelectableText(
                                  row.value,
                                  style: const TextStyle(
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _info.toLogLine()),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Build identity copied'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy build identity'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
