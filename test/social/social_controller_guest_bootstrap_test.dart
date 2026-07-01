import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/social/state/social_controller.dart';
import 'package:social_core/social_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }
}

class _CountingSocialApi extends SocialApi {
  _CountingSocialApi() : super(Dio());

  int listPostsCalls = 0;
  int listStoriesCalls = 0;
  int listThreadsCalls = 0;

  @override
  Future<Map<String, dynamic>> listPosts({
    int limit = 20,
    int? beforeId,
    String? kind,
  }) async {
    listPostsCalls += 1;
    return const <String, dynamic>{
      'posts': <dynamic>[],
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> listStories({
    int limitUsers = 32,
    int maxPerUser = 10,
  }) async {
    listStoriesCalls += 1;
    return const <String, dynamic>{'stories': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> listThreads() async {
    listThreadsCalls += 1;
    return const <String, dynamic>{'threads': <dynamic>[]};
  }
}

void main() {
  test('guest bootstrap skips protected community threads', () async {
    final api = _CountingSocialApi();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(ref, const AuthState()),
        ),
        socialApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    await container.read(socialControllerProvider.notifier).bootstrap();

    expect(api.listStoriesCalls, 1);
    expect(api.listPostsCalls, 1);
    expect(api.listThreadsCalls, 0);
    expect(container.read(socialControllerProvider).error, isNull);
  });
}
