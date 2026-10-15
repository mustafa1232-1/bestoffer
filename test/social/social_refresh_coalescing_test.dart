import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/social/state/social_controller.dart';
import 'package:social_core/social_api.dart';

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = AuthState(
      token: 'test',
      user: UserModel.fromJson({
        'id': 1,
        'full_name': 'Tester',
        'role': 'user',
      }),
    );
  }
}

class _Api extends SocialApi {
  _Api() : super(Dio());
  final pending = <Completer<Map<String, dynamic>>>[];
  Future<Map<String, dynamic>> request() {
    final result = Completer<Map<String, dynamic>>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<Map<String, dynamic>> listStories({
    int limitUsers = 32,
    int maxPerUser = 10,
  }) => request();
  @override
  Future<Map<String, dynamic>> listThreads() => request();
}

void main() {
  for (final stories in [true, false]) {
    test(
      '${stories ? 'stories' : 'threads'} coalesce concurrent refreshes without dropping final refresh',
      () async {
        final api = _Api();
        final container = ProviderContainer(
          overrides: [
            socialApiProvider.overrideWithValue(api),
            authControllerProvider.overrideWith((ref) => _Auth(ref)),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(socialControllerProvider.notifier);
        Future<void> refresh() =>
            stories ? controller.loadStories() : controller.loadThreads();
        final requests = List.generate(5, (_) => refresh());
        expect(api.pending.length, 1);
        api.pending[0].complete({});
        await Future<void>.delayed(Duration.zero);
        expect(api.pending.length, 2);
        api.pending[1].complete({});
        await Future.wait(requests);
        expect(api.pending.length, 2);
        final state = container.read(socialControllerProvider);
        expect(state.loadingStories, isFalse);
        expect(state.loadingThreads, isFalse);
      },
    );
  }
}
