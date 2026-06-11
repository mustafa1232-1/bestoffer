import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/paid_upgrades_api.dart';
import '../models/paid_upgrade_models.dart';

final myPaidUpgradesSummaryProvider =
    FutureProvider.autoDispose<PaidUpgradesSummaryModel>((ref) async {
      final raw = await ref.read(paidUpgradesApiProvider).me();
      return PaidUpgradesSummaryModel.fromJson(raw);
    });
