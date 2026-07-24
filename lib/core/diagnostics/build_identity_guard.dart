import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

@immutable
class BuildIdentitySpec {
  const BuildIdentitySpec({
    required this.surface,
    required this.flavor,
    required this.applicationId,
    required this.bootstrap,
  });

  final String surface;
  final String flavor;
  final String applicationId;
  final String bootstrap;

  static const user = BuildIdentitySpec(
    surface: 'user',
    flavor: 'user',
    applicationId: 'com.maslaki.user',
    bootstrap: 'runUserAppBootstrap',
  );

  static const store = BuildIdentitySpec(
    surface: 'store',
    flavor: 'store',
    applicationId: 'com.maslaki.store',
    bootstrap: 'runStoreAppBootstrap',
  );

  static const delivery = BuildIdentitySpec(
    surface: 'delivery',
    flavor: 'delivery',
    applicationId: 'com.maslaki.delivery',
    bootstrap: 'runDeliveryAppBootstrap',
  );

  static const captain = BuildIdentitySpec(
    surface: 'captain',
    flavor: 'captain',
    applicationId: 'com.maslaki.captain',
    bootstrap: 'runTaxiCaptainAppBootstrap',
  );
}

class BuildIdentityGuard {
  const BuildIdentityGuard._();

  static const String _compiledFlavor = String.fromEnvironment(
    'APP_FLAVOR',
    defaultValue: '',
  );
  static const String _compiledSurface = String.fromEnvironment(
    'APP_SURFACE',
    defaultValue: '',
  );

  static Future<bool> validateOrShow(BuildIdentitySpec spec) async {
    final actualPackageName = await _packageName();
    final failures = <String>[];

    // The reverse-DNS applicationId (com.maslaki.*) is the real OS package name
    // ONLY on the shipping mobile surfaces. On desktop/web the platform package
    // name is the product name (e.g. "Maslaki"), so it can never equal the
    // applicationId — enforcing equality there would block local UI smoke-tests
    // without adding any integrity value. We keep full package enforcement on
    // Android/iOS and skip only the package check on desktop/web. The
    // compile-time flavor/surface checks below still run on every platform.
    final enforcesPackageIdentity =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    if (enforcesPackageIdentity &&
        actualPackageName.isNotEmpty &&
        actualPackageName != spec.applicationId) {
      failures.add('package=$actualPackageName expected=${spec.applicationId}');
    }
    if (_compiledFlavor.isNotEmpty && _compiledFlavor != spec.flavor) {
      failures.add('flavor=$_compiledFlavor expected=${spec.flavor}');
    }
    if (_compiledSurface.isNotEmpty && _compiledSurface != spec.surface) {
      failures.add('surface=$_compiledSurface expected=${spec.surface}');
    }

    if (failures.isEmpty) return true;

    final message =
        'Build identity mismatch: bootstrap=${spec.bootstrap} '
        'compiledSurface=${_compiledSurface.isEmpty ? "?" : _compiledSurface} '
        'compiledFlavor=${_compiledFlavor.isEmpty ? "?" : _compiledFlavor} '
        'actualPackage=${actualPackageName.isEmpty ? "?" : actualPackageName} '
        'expectedPackage=${spec.applicationId}';
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(message),
        library: 'build identity',
        context: ErrorDescription('while validating app surface identity'),
        informationCollector: () sync* {
          for (final failure in failures) {
            yield DiagnosticsProperty<String>('failure', failure);
          }
        },
      ),
    );
    runApp(BuildIdentityMismatchApp(spec: spec, failures: failures));
    return false;
  }

  static Future<String> _packageName() async {
    try {
      return (await PackageInfo.fromPlatform()).packageName.trim();
    } catch (_) {
      return '';
    }
  }
}

class BuildIdentityMismatchApp extends StatelessWidget {
  const BuildIdentityMismatchApp({
    required this.spec,
    required this.failures,
    super.key,
  });

  final BuildIdentitySpec spec;
  final List<String> failures;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(
          backgroundColor: const Color(0xfff8fafc),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xffcbd5e1)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Build Misconfiguration',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Color(0xff0f172a),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'This app package was built with the wrong Flutter entrypoint or flavor.',
                          style: TextStyle(color: Color(0xff334155)),
                        ),
                        const SizedBox(height: 16),
                        Text('Bootstrap: ${spec.bootstrap}'),
                        Text('Expected package: ${spec.applicationId}'),
                        Text('Expected flavor: ${spec.flavor}'),
                        Text('Expected surface: ${spec.surface}'),
                        const SizedBox(height: 16),
                        for (final failure in failures)
                          Text(
                            failure,
                            style: const TextStyle(color: Color(0xffb91c1c)),
                          ),
                      ],
                    ),
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
