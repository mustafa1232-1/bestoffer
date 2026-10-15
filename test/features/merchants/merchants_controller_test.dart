import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/merchants/data/merchants_api.dart';
import 'package:maslaki/features/merchants/state/merchants_controller.dart';

class _MerchantListRequest {
  const _MerchantListRequest({
    this.type,
    this.search,
    this.activityType,
    this.discoverySubcategory,
    this.department,
  });

  final String? type;
  final String? search;
  final String? activityType;
  final String? discoverySubcategory;
  final String? department;
}

class _SequencedMerchantsApi extends MerchantsApi {
  _SequencedMerchantsApi() : super(Dio());

  final requests = <_MerchantListRequest>[];
  final _completers = <Completer<List<dynamic>>>[];
  final latitudes = <double?>[];
  final longitudes = <double?>[];

  @override
  Future<List<dynamic>> list({
    String? type,
    String? search,
    String? activityType,
    String? discoverySubcategory,
    String? department,
    double? latitude,
    double? longitude,
  }) {
    final completer = Completer<List<dynamic>>();
    requests.add(
      _MerchantListRequest(
        type: type,
        search: search,
        activityType: activityType,
        discoverySubcategory: discoverySubcategory,
        department: department,
      ),
    );
    latitudes.add(latitude);
    longitudes.add(longitude);
    _completers.add(completer);
    return completer.future;
  }

  void complete(int index, List<dynamic> data) {
    _completers[index].complete(data);
  }
}

Map<String, dynamic> _merchantJson({
  required int id,
  required String name,
  String activityType = 'market',
  List<String> discoverySubcategories = const <String>[],
}) {
  return {
    'id': id,
    'name': name,
    'type': 'market',
    'activityType': activityType,
    'discoverySubcategories': discoverySubcategories,
    'isOpen': true,
    'hasDiscountOffer': false,
    'hasFreeDeliveryOffer': false,
  };
}

void main() {
  test(
    'public merchant browsing never waits for or starts a GPS lookup',
    () async {
      final gps = Completer<MerchantBrowsePosition?>();
      var locationLookups = 0;
      final api = _SequencedMerchantsApi();
      final container = ProviderContainer(
        overrides: [
          merchantsApiProvider.overrideWithValue(api),
          merchantBrowsePositionProvider.overrideWith((_) {
            locationLookups++;
            return gps.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(merchantsControllerProvider.notifier);
      final load = controller.load(type: 'market');
      await Future<void>.delayed(Duration.zero);
      expect(api.requests, hasLength(1));
      api.complete(0, [_merchantJson(id: 1, name: 'First render')]);
      await load;
      expect(
        container.read(merchantsControllerProvider).requireValue.single.name,
        'First render',
      );
      expect(gps.isCompleted, isFalse);
      gps.complete(const MerchantBrowsePosition(latitude: 33, longitude: 44));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(api.requests, hasLength(1));
      expect(locationLookups, 0);
      expect(api.latitudes.single, isNull);
      expect(
        container.read(merchantsControllerProvider).requireValue.single.name,
        'First render',
      );
    },
  );

  test(
    'loads the public market catalogue when location is unavailable',
    () async {
      final api = _SequencedMerchantsApi();
      final container = ProviderContainer(
        overrides: [
          merchantsApiProvider.overrideWithValue(api),
          merchantBrowsePositionProvider.overrideWith((_) async => null),
        ],
      );
      addTearDown(container.dispose);

      final future = container
          .read(merchantsControllerProvider.notifier)
          .loadWithFilters(type: 'market');
      await Future<void>.delayed(Duration.zero);
      api.complete(0, [_merchantJson(id: 1, name: 'Public Market')]);
      await future;

      expect(
        container.read(merchantsControllerProvider).requireValue,
        hasLength(1),
      );
      expect(api.latitudes.single, isNull);
      expect(api.longitudes.single, isNull);
    },
  );

  test(
    'new merchant filters start their own request while another list is loading',
    () async {
      final api = _SequencedMerchantsApi();
      final container = ProviderContainer(
        overrides: [
          merchantsApiProvider.overrideWithValue(api),
          merchantBrowsePositionProvider.overrideWith(
            (_) async => const MerchantBrowsePosition(
              latitude: 33.19302,
              longitude: 44.62071,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(merchantsControllerProvider.notifier);

      final generalFuture = controller.loadWithFilters(type: 'market');
      await Future<void>.delayed(Duration.zero);
      expect(api.requests, hasLength(1));

      final vapesFuture = controller.loadWithFilters(
        type: 'market',
        activityType: 'smoking_supplies',
        discoverySubcategory: 'vapes',
      );
      await Future<void>.delayed(Duration.zero);

      expect(api.requests, hasLength(2));
      expect(api.requests[1].activityType, 'smoking_supplies');
      expect(api.requests[1].discoverySubcategory, 'vapes');

      api.complete(1, [
        _merchantJson(
          id: 2,
          name: 'Toha Vapes',
          activityType: 'smoking_supplies',
          discoverySubcategories: const ['vapes'],
        ),
      ]);
      await vapesFuture;

      var merchants = container.read(merchantsControllerProvider).requireValue;
      expect(merchants.map((merchant) => merchant.name), ['Toha Vapes']);

      api.complete(0, [_merchantJson(id: 1, name: 'General Market')]);
      await generalFuture;

      merchants = container.read(merchantsControllerProvider).requireValue;
      expect(merchants.map((merchant) => merchant.name), ['Toha Vapes']);
    },
  );
}
