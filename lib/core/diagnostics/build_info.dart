import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constants/api.dart';

/// Authoritative build-identity contract.
///
/// Why this exists: a device screenshot is only trustworthy if the *installed
/// binary* can prove which source it was built from. Section 0 of the Social V3
/// remediation requires the running app to self-report its git SHA so we can
/// tell a stale APK apart from a fresh build of the intended commit.
///
/// The build-time values (git SHA, branch, timestamp, backend SHA) are injected
/// with `--dart-define` at `flutter build` time, e.g.:
///
/// ```
/// flutter build apk --flavor user \
///   --dart-define=GIT_SHA=$(git rev-parse HEAD) \
///   --dart-define=GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD) \
///   --dart-define=BUILD_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
///   --dart-define=BACKEND_RELEASE_SHA=<railway release sha> \
///   --dart-define=APP_FLAVOR=user \
///   --dart-define=APP_VERSION=1.0.1+9
/// ```
///
/// When a define is absent (e.g. `flutter run` during development) the field
/// falls back to a clearly non-authoritative sentinel so nobody mistakes a dev
/// build for a release one.
@immutable
class BuildInfo {
  const BuildInfo({
    required this.gitSha,
    required this.gitBranch,
    required this.buildTimestamp,
    required this.flutterVersion,
    required this.appFlavor,
    required this.applicationId,
    required this.appVersion,
    required this.backendBaseUrl,
    required this.backendReleaseSha,
  });

  /// Full git commit SHA the binary was built from. `unknown-dev` when the
  /// build did not inject `GIT_SHA` (i.e. not an authoritative release build).
  final String gitSha;
  final String gitBranch;

  /// ISO-8601 UTC timestamp of the build, or `unknown-dev`.
  final String buildTimestamp;

  /// Flutter/Dart toolchain version string captured at build time.
  final String flutterVersion;

  /// App flavor (user / company / delivery / captain / ...).
  final String appFlavor;

  /// Resolved Android/iOS applicationId — filled at runtime from
  /// [PackageInfo]. Empty until [load] completes.
  final String applicationId;

  /// Human app version, e.g. `1.0.1+9`. Prefers the runtime [PackageInfo]
  /// version+build when available, otherwise the `APP_VERSION` define.
  final String appVersion;

  final String backendBaseUrl;

  /// Backend (Railway) release SHA the app expects to talk to, or `unknown`.
  final String backendReleaseSha;

  static const String _sha = String.fromEnvironment('GIT_SHA', defaultValue: 'unknown-dev');
  static const String _branch =
      String.fromEnvironment('GIT_BRANCH', defaultValue: 'unknown-dev');
  static const String _timestamp =
      String.fromEnvironment('BUILD_TIMESTAMP', defaultValue: 'unknown-dev');
  // NOTE: `FLUTTER_VERSION` is reserved by the Flutter tool and cannot be set
  // via --dart-define, so we use a non-reserved name for the build stamp.
  static const String _flutterVersion =
      String.fromEnvironment('BUILD_FLUTTER_VERSION', defaultValue: 'unknown-dev');
  static const String _flavor =
      String.fromEnvironment('APP_FLAVOR', defaultValue: 'user');
  static const String _appVersionDefine =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
  static const String _backendReleaseSha =
      String.fromEnvironment('BACKEND_RELEASE_SHA', defaultValue: 'unknown');

  /// The compile-time snapshot, available synchronously and without any plugin
  /// call. Use this for the very-first startup log line. [applicationId] and the
  /// resolved [appVersion] are enriched by [load].
  static BuildInfo get compileTime => BuildInfo(
        gitSha: _sha,
        gitBranch: _branch,
        buildTimestamp: _timestamp,
        flutterVersion: _flutterVersion,
        appFlavor: _flavor,
        applicationId: '',
        appVersion: _appVersionDefine,
        backendBaseUrl: Api.baseUrl,
        backendReleaseSha: _backendReleaseSha,
      );

  /// Enriches the compile-time snapshot with runtime package metadata
  /// (applicationId, installed version+build). Never throws — falls back to the
  /// compile-time values if the platform channel is unavailable (e.g. tests).
  static Future<BuildInfo> load() async {
    final base = compileTime;
    try {
      final pkg = await PackageInfo.fromPlatform();
      final resolvedVersion = pkg.version.isEmpty
          ? base.appVersion
          : '${pkg.version}+${pkg.buildNumber}';
      return BuildInfo(
        gitSha: base.gitSha,
        gitBranch: base.gitBranch,
        buildTimestamp: base.buildTimestamp,
        flutterVersion: base.flutterVersion,
        appFlavor: base.appFlavor,
        applicationId: pkg.packageName,
        appVersion: resolvedVersion,
        backendBaseUrl: base.backendBaseUrl,
        backendReleaseSha: base.backendReleaseSha,
      );
    } catch (_) {
      return base;
    }
  }

  /// Short SHA for compact display (first 12 chars, matching `git log --oneline`
  /// plus a little margin), or the sentinel when unknown.
  String get shortSha =>
      gitSha.length > 12 ? gitSha.substring(0, 12) : gitSha;

  /// True when this build carries an authoritative git SHA (a real release
  /// build), false for a plain `flutter run` dev build.
  bool get isAuthoritative => gitSha != 'unknown-dev' && gitSha.isNotEmpty;

  /// Single-line summary suitable for the startup log.
  String toLogLine() =>
      '[buildinfo] sha=$shortSha branch=$gitBranch flavor=$appFlavor '
      'appId=${applicationId.isEmpty ? "?" : applicationId} '
      'version=$appVersion builtAt=$buildTimestamp '
      'backend=$backendBaseUrl backendSha=$backendReleaseSha '
      'authoritative=$isAuthoritative';

  /// Ordered key/value rows for the diagnostics screen.
  List<MapEntry<String, String>> toRows() => <MapEntry<String, String>>[
        MapEntry('Git SHA', gitSha),
        MapEntry('Git branch', gitBranch),
        MapEntry('Build timestamp (UTC)', buildTimestamp),
        MapEntry('Flutter version', flutterVersion),
        MapEntry('App flavor', appFlavor),
        MapEntry('applicationId', applicationId.isEmpty ? '(loading…)' : applicationId),
        MapEntry('App version', appVersion),
        MapEntry('Backend base URL', backendBaseUrl),
        MapEntry('Backend release SHA', backendReleaseSha),
        MapEntry('Authoritative build', isAuthoritative ? 'yes' : 'NO (dev build)'),
      ];
}
