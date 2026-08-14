import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> configureEdgeToEdgeSystemUi() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Do NOT set statusBarColor / systemNavigationBarColor / systemNavigationBarDividerColor.
  // Passing any non-null color (even transparent) makes the Flutter engine's
  // PlatformPlugin call the deprecated Window.setStatusBarColor / setNavigationBarColor /
  // setNavigationBarDividerColor APIs. Google Play flags those on Android 15, where they
  // are also no-ops. Edge-to-edge transparency is already established natively by
  // enableEdgeToEdge() in MainActivity.onCreate, so these colors are redundant here.
  // Only icon brightness is set — it routes to the non-deprecated WindowInsetsController
  // appearance APIs.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
}

class EdgeToEdgeSystemUi extends StatefulWidget {
  final Widget child;

  const EdgeToEdgeSystemUi({super.key, required this.child});

  @override
  State<EdgeToEdgeSystemUi> createState() => _EdgeToEdgeSystemUiState();
}

class _EdgeToEdgeSystemUiState extends State<EdgeToEdgeSystemUi>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      configureEdgeToEdgeSystemUi();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      configureEdgeToEdgeSystemUi();
    }
  }

  @override
  void didChangeMetrics() {
    configureEdgeToEdgeSystemUi();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Colors intentionally omitted — see configureEdgeToEdgeSystemUi above.
      value: const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: widget.child,
    );
  }
}
