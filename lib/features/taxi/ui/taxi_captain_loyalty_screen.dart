import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../data/taxi_api.dart';

TaxiApi _api(WidgetRef ref) => TaxiApi(ref.read(dioClientProvider).dio);

class TaxiCaptainLoyaltyScreen extends ConsumerStatefulWidget {
  const TaxiCaptainLoyaltyScreen({super.key});

  @override
  ConsumerState<TaxiCaptainLoyaltyScreen> createState() =>
      _TaxiCaptainLoyaltyScreenState();
}

class _TaxiCaptainLoyaltyScreenState
    extends ConsumerState<TaxiCaptainLoyaltyScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _ledger = const [];
  List<Map<String, dynamic>> _contests = const [];
  List<Map<String, dynamic>> _rewards = const [];
  Map<String, dynamic> _governance = const {};
  List<Map<String, dynamic>> _warnings = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        _api(ref).getCaptainSubscriptionLedger(limit: 80),
        _api(ref).getCaptainContests(limit: 80),
        _api(ref).getCaptainRewards(limit: 80),
        _api(ref).getCaptainGovernanceStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        final ledgerRes = responses[0];
        _summary = Map<String, dynamic>.from(
          ledgerRes['summary'] as Map? ?? const {},
        );
        _ledger = List<Map<String, dynamic>>.from(
          (ledgerRes['ledger'] as List? ?? const []).whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
        final contestsRes = responses[1];
        _contests = List<Map<String, dynamic>>.from(
          (contestsRes['contests'] as List? ?? const []).whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
        _rewards = List<Map<String, dynamic>>.from(
          (responses[2]['rewards'] as List? ?? const []).whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
        _governance = Map<String, dynamic>.from(
          (responses[3]['governance'] as Map?) ?? const {},
        );
        _warnings = List<Map<String, dynamic>>.from(
          (responses[3]['warnings'] as List? ?? const []).whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyErrorL10n(
          error,
          fallbackBuilder: (l10n) => l10n.taxiCaptainLoyaltyLoadFailed,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.taxiCaptainContestsTitle)),
        body: Center(child: Text(_error!)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.taxiCaptainContestsTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(l10n.taxiCaptainSubscriptionSummary),
                subtitle: Text(
                  '${l10n.taxiCaptainMonthlySubscription}: ${_summary['monthlySubscriptionAmountIqd'] ?? 0}\n'
                  '${l10n.taxiCaptainApprovedCredits}: ${_summary['approvedCreditsIqd'] ?? 0}\n'
                  '${l10n.taxiCaptainPayableAmount}: ${_summary['payableAmountIqd'] ?? 0}',
                ),
                isThreeLine: true,
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(l10n.taxiCaptainGovernanceStatus),
                subtitle: Text(
                  '${_governance['governanceStatus'] ?? 'active'}\n'
                  '${l10n.taxiCaptainWarningsCount}: ${_warnings.length}',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.taxiCaptainLedgerTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ..._ledger.map(
              (item) => Card(
                child: ListTile(
                  title: Text(item['entryType']?.toString() ?? '-'),
                  subtitle: Text(item['createdAt']?.toString() ?? '-'),
                  trailing: Text('${item['amountIqd'] ?? 0}'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.taxiCaptainContestsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ..._contests.map(
              (item) => Card(
                child: ListTile(
                  title: Text(item['title']?.toString() ?? '-'),
                  subtitle: Text(
                    '${item['progressValue'] ?? 0} / ${item['targetValue'] ?? 0}',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.taxiCaptainRewardsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ..._rewards.map(
              (item) => Card(
                child: ListTile(
                  title: Text(item['rewardType']?.toString() ?? '-'),
                  subtitle: Text(item['createdAt']?.toString() ?? '-'),
                  trailing: Text('${item['rewardValue'] ?? 0}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
