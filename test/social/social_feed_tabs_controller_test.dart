import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/state/social_controller.dart';
import 'package:social_core/social_api.dart';

class _TabApi extends SocialApi {
  _TabApi() : super(Dio());
  final requests =
      <
        ({
          String feed,
          int? cursor,
          String? kind,
          Completer<Map<String, dynamic>> result,
        })
      >[];

  @override
  Future<Map<String, dynamic>> listFeedTabPosts({
    required String feed,
    int limit = 20,
    int? beforeId,
    String? kind,
  }) {
    final result = Completer<Map<String, dynamic>>();
    requests.add((feed: feed, cursor: beforeId, kind: kind, result: result));
    return result.future;
  }
}

Map<String, dynamic> _page(int id, {int? cursor}) => {
  'posts': [
    {
      'id': id,
      'userId': 7,
      'caption': 'post $id',
      'author': {'id': 7, 'fullName': 'Member'},
    },
  ],
  'nextCursor': cursor,
};

void main() {
  test(
    'late responses from the previous tab cannot overwrite the new tab',
    () async {
      final api = _TabApi();
      final container = ProviderContainer(
        overrides: [socialApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final controller = container.read(socialControllerProvider.notifier);
      final first = controller.setFeedTab('following');
      final second = controller.setFeedTab('latest');
      api.requests[1].result.complete(_page(90));
      await second;
      api.requests[0].result.complete(_page(10));
      await first;
      expect(container.read(socialControllerProvider).feedTab, 'latest');
      expect(container.read(socialControllerProvider).posts.single.id, 90);
    },
  );

  test(
    'following pagination uses the server cursor and retains the selected tab',
    () async {
      final api = _TabApi();
      final container = ProviderContainer(
        overrides: [socialApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final controller = container.read(socialControllerProvider.notifier);
      final first = controller.setFeedTab('following');
      api.requests[0].result.complete(_page(90, cursor: 90));
      await first;
      final next = controller.loadMorePosts();
      expect(api.requests[1].feed, 'following');
      expect(api.requests[1].cursor, 90);
      api.requests[1].result.complete(_page(80));
      await next;
      expect(container.read(socialControllerProvider).posts.map((p) => p.id), [
        90,
        80,
      ]);
      expect(container.read(socialControllerProvider).nextPostsCursor, isNull);
    },
  );

  test(
    'load failure is a separate UI flag without raw exception text',
    () async {
      final api = _TabApi();
      final container = ProviderContainer(
        overrides: [socialApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final running = container
          .read(socialControllerProvider.notifier)
          .setFeedTab('latest');
      api.requests.single.result.completeError(
        Exception('private debug context'),
      );
      await running;
      expect(container.read(socialControllerProvider).postsLoadFailed, isTrue);
      expect(container.read(socialControllerProvider).error, isNull);
    },
  );
}
