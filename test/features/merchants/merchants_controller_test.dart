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

  @override
  Future<List<dynamic>> list({
    String? type,
    String? search,
    String? activityType,
    String? discoverySubcategory,
    String? department,
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
    'new merchant filters start their own request while another list is loading',
    () async {
      final api = _SequencedMerchantsApi();
      final container = ProviderContainer(
        overrides: [merchantsApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final controller = container.read(merchantsControllerProvider.notifier);

      final generalFuture = controller.loadWithFilters(type: 'market');
      expect(api.requests, hasLength(1));

      final vapesFuture = controller.loadWithFilters(
        type: 'market',
        activityType: 'smoking_supplies',
        discoverySubcategory: 'vapes',
      );

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
