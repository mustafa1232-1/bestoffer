import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mimo/mimo_character.dart';
import '../state/admin_controller.dart';
import 'admin_support_tickets_screen.dart';

const _navy = Color(0xFF0B2440);
const _green = Color(0xFF2F5E46);
const _gold = Color(0xFFB8893F);
const _muted = Color(0xFF5B6470);
const _red = Color(0xFF9A3B30);

/// Admin view of Mimo: usage & estimated cost, quality, demand the app
/// doesn't cover yet, what Mimo learned (approve/reject/edit) and his tickets.
class AdminMimoDashboardScreen extends ConsumerStatefulWidget {
  const AdminMimoDashboardScreen({super.key});

  @override
  ConsumerState<AdminMimoDashboardScreen> createState() =>
      _AdminMimoDashboardScreenState();
}

class _AdminMimoDashboardScreenState
    extends ConsumerState<AdminMimoDashboardScreen> {
  int _days = 30;
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() =>
      ref.read(adminApiProvider).mimoDashboard(days: _days);

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              SizedBox(
                width: 34,
                height: 36,
                child: MimoCharacter(
                  mood: MimoMood.happy,
                  sitting: false,
                  animate: false,
                ),
              ),
              SizedBox(width: 8),
              Text('لوحة ميمو'),
            ],
          ),
          actions: [
            PopupMenuButton<int>(
              tooltip: 'الفترة',
              initialValue: _days,
              onSelected: (d) {
                _days = d;
                _reload();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 1, child: Text('آخر يوم')),
                PopupMenuItem(value: 7, child: Text('آخر 7 أيام')),
                PopupMenuItem(value: 30, child: Text('آخر 30 يوم')),
                PopupMenuItem(value: 90, child: Text('آخر 90 يوم')),
              ],
              icon: const Icon(Icons.date_range_rounded),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'نظرة عامة'),
              Tab(text: 'أجوبة ضعيفة'),
              Tab(text: 'يطلبون وماكو'),
              Tab(text: 'شنو تعلم'),
              Tab(text: 'تذاكر ميمو'),
            ],
          ),
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError || snap.data == null) {
              return _Error(onRetry: _reload);
            }
            final d = snap.data!;
            return TabBarView(
              children: [
                _Overview(data: d),
                _BadAnswers(rows: _rows(d['badAnswers'])),
                _Demand(demand: _map(d['demand'])),
                const _KnowledgeTab(),
                _Tickets(rows: _rows(d['tickets'])),
              ],
            );
          },
        ),
      ),
    );
  }
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _rows(Object? v) => [
  for (final e in (v is List ? v : const [])) _map(e),
];

num _n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

String _fmt(num v) => v.round().toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('ما گدرت أجيب بيانات ميمو'),
          const SizedBox(height: 8),
          FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final k = _map(data['kpis']);
    final satisfaction = k['satisfaction'];
    final cards = <(IconData, String, String, Color)>[
      (Icons.forum_rounded, 'أسئلة', _fmt(_n(k['questions'])), _navy),
      (Icons.people_alt_rounded, 'مستخدمين', _fmt(_n(k['users'])), _navy),
      (
        Icons.thumb_up_alt_rounded,
        'الرضا',
        satisfaction == null ? '—' : '$satisfaction%',
        _green,
      ),
      (
        Icons.timer_rounded,
        'متوسط الرد',
        '${_n(k['avgReplySeconds'])} ث',
        _navy,
      ),
      (
        Icons.attach_money_rounded,
        'الكلفة (تقدير)',
        '\$${_n(k['estimatedCostUsd'])}',
        _gold,
      ),
      (
        Icons.calculate_rounded,
        'كلفة السؤال',
        '\$${_n(k['costPerQuestionUsd'])}',
        _gold,
      ),
      (
        Icons.add_shopping_cart_rounded,
        'إضافات للسلة',
        _fmt(_n(k['cartAdds'])),
        _green,
      ),
      (
        Icons.support_agent_rounded,
        'تذاكر رفعها',
        '${_n(k['escalations'])} (${_n(k['escalationsOpen'])} مفتوحة)',
        _red,
      ),
      (
        Icons.school_rounded,
        'معلومات تعلمها',
        '${_n(k['learnedVerified'])} مؤكدة • ${_n(k['learnedCommunity'])} محلية',
        _green,
      ),
      (
        Icons.auto_fix_high_rounded,
        'حلول دعم تعلمها',
        _fmt(_n(k['playbooks'])),
        _green,
      ),
      (
        Icons.campaign_rounded,
        'مبادرات ميمو',
        '${_n(k['nudgesShown'])} ظهرت • ${_n(k['nudgesTapped'])} انضغطت',
        _gold,
      ),
      (
        Icons.thumb_down_alt_rounded,
        'تقييم سلبي',
        _fmt(_n(k['feedbackDown'])),
        _red,
      ),
    ];
    final daily = _rows(data['daily']);
    final tools = _rows(data['tools']);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 3 : 2);
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: [
                for (final (icon, label, value, color) in cards)
                  _KpiCard(
                    icon: icon,
                    label: label,
                    value: value,
                    color: color,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'الأسئلة يومياً',
          child: _Bars(
            values: [for (final r in daily) _n(r['questions']).toDouble()],
            labels: [for (final r in daily) '${r['day']}'.substring(5)],
            color: _navy,
          ),
        ),
        _Section(
          title: 'الكلفة اليومية التقديرية (\$)',
          child: _Bars(
            values: [for (final r in daily) _n(r['cost_usd']).toDouble()],
            labels: [for (final r in daily) '${r['day']}'.substring(5)],
            color: _gold,
            decimals: 2,
          ),
        ),
        _Section(
          title: 'شنو يستخدم ميمو أكثر',
          child: Column(
            children: [
              for (final t in tools)
                ListTile(
                  dense: true,
                  title: Text(_toolName('${t['tool']}')),
                  trailing: Text(_fmt(_n(t['n']))),
                ),
              if (tools.isEmpty) const Text('ماكو بيانات بعد'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${data['costNote'] ?? ''}',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  static String _toolName(String t) =>
      const {
        'search_products': 'البحث بالمنتجات',
        'find_stores': 'البحث بالمحلات',
        'get_store_menu': 'فتح المنيو',
        'pick_for_me': 'اختارلي انت',
        'quote_order': 'حساب الفاتورة',
        'web_search': 'البحث بالإنترنت',
        'think_deeply': 'التفكير العميق',
        'recall_knowledge': 'شنو علموه',
        'learn_fact': 'تعلّم معلومة',
        'diagnose_problem': 'فحص مشكلة',
        'escalate_to_admin': 'رفع للإدارة',
        'app_guide': 'دليل التطبيق',
        'remember': 'حفظ بالذاكرة',
      }[t] ??
      t;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6D9BD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6D9BD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(color: _navy, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Simple bar chart (no extra packages).
class _Bars extends StatelessWidget {
  const _Bars({
    required this.values,
    required this.labels,
    required this.color,
    this.decimals = 0,
  });

  final List<double> values;
  final List<String> labels;
  final Color color;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const Text('ماكو بيانات بعد');
    final max = values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 150,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: Tooltip(
                  message:
                      '${labels[i]}: ${values[i].toStringAsFixed(decimals)}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: max <= 0
                                ? 0.02
                                : (values[i] / max).clamp(0.02, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        if (values.length <= 14)
                          Text(
                            labels[i],
                            style: const TextStyle(fontSize: 9, color: _muted),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BadAnswers extends StatelessWidget {
  const _BadAnswers({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('ماكو أجوبة سلبية بهالفترة 👍'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = rows[i];
        return _Section(
          title: 'سأل: ${r['question'] ?? '—'}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ميمو جاوب: ${r['answer'] ?? ''}'),
              if ('${r['reason'] ?? ''}'.isNotEmpty)
                Text(
                  'السبب: ${r['reason']}',
                  style: const TextStyle(color: _red),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Demand extends StatelessWidget {
  const _Demand({required this.demand});

  final Map<String, dynamic> demand;

  @override
  Widget build(BuildContext context) {
    final unmet = _rows(demand['unmet']);
    final misses = _rows(demand['misses']);
    final synonyms = _rows(demand['synonyms']);
    Widget list(List<Map<String, dynamic>> rows, String empty) => rows.isEmpty
        ? Text(empty, style: const TextStyle(color: _muted))
        : Column(
            children: [
              for (final r in rows)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.search_off_rounded, color: _gold),
                  title: Text('${r['text']}'),
                  trailing: Text('${r['times']} مرة'),
                ),
            ],
          );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _Section(
          title: 'يطلبوه وماكو بالتطبيق (فرصة تجارية)',
          child: list(unmet, 'ماكو بعد'),
        ),
        _Section(
          title: 'كلمات بحث ما لگت نتيجة',
          child: list(misses, 'ماكو بعد'),
        ),
        _Section(
          title: 'كلمات تعلمها ميمو (مرادفات)',
          child: synonyms.isEmpty
              ? const Text('ماكو بعد', style: TextStyle(color: _muted))
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in synonyms)
                      Chip(
                        label: Text(
                          '${s['term']} ← ${s['alias']} (${s['hits']})',
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _KnowledgeTab extends ConsumerStatefulWidget {
  const _KnowledgeTab();

  @override
  ConsumerState<_KnowledgeTab> createState() => _KnowledgeTabState();
}

class _KnowledgeTabState extends ConsumerState<_KnowledgeTab> {
  String? _status;
  String _q = '';
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() => ref
      .read(adminApiProvider)
      .mimoKnowledge(status: _status, query: _q.isEmpty ? null : _q);

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _setStatus(Map<String, dynamic> item, String status) async {
    await ref
        .read(adminApiProvider)
        .updateMimoKnowledge((item['id'] as num).toInt(), status: status);
    _reload();
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final c = TextEditingController(text: '${item['answer'] ?? ''}');
    final answer = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item['question'] ?? ''}'),
        content: TextField(controller: c, minLines: 2, maxLines: 6),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(c.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    c.dispose();
    if (answer == null || answer.length < 2) return;
    await ref
        .read(adminApiProvider)
        .updateMimoKnowledge((item['id'] as num).toInt(), answer: answer);
    _reload();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المعلومة؟'),
        content: Text('${item['question'] ?? ''}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('لا'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('احذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(adminApiProvider)
        .deleteMimoKnowledge((item['id'] as num).toInt());
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'دوّر بالمعلومات…',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) {
                    _q = v.trim();
                    _reload();
                  },
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String?>(
                value: _status,
                onChanged: (v) {
                  _status = v;
                  _reload();
                },
                items: const [
                  DropdownMenuItem(value: null, child: Text('الكل')),
                  DropdownMenuItem(value: 'verified', child: Text('مؤكدة')),
                  DropdownMenuItem(value: 'community', child: Text('محلية')),
                  DropdownMenuItem(value: 'rejected', child: Text('مرفوضة')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snap.data ?? const [];
              if (items.isEmpty) {
                return const Center(child: Text('ميمو بعده ما تعلم شي هنا'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final it = items[i];
                  final status = '${it['status']}';
                  final playbook = it['playbook'] == true;
                  return _Section(
                    title: '${playbook ? '🛠️ ' : ''}${it['question'] ?? ''}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${it['answer'] ?? ''}'),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(
                              label: Text(
                                status == 'verified'
                                    ? 'مؤكدة'
                                    : status == 'community'
                                    ? 'محلية (${it['confirmations']} تأكيد)'
                                    : 'مرفوضة',
                              ),
                              backgroundColor: status == 'verified'
                                  ? const Color(0xFFE3F0E8)
                                  : status == 'community'
                                  ? const Color(0xFFF7F1E7)
                                  : const Color(0xFFFBE4E1),
                            ),
                            Text(
                              'استُخدمت ${it['uses'] ?? 0} مرة',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                            if (status != 'verified')
                              TextButton.icon(
                                onPressed: () => _setStatus(it, 'verified'),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('اعتمد'),
                              ),
                            if (status != 'rejected')
                              TextButton.icon(
                                onPressed: () => _setStatus(it, 'rejected'),
                                icon: const Icon(Icons.block_rounded),
                                label: const Text('ارفض'),
                              ),
                            IconButton(
                              tooltip: 'تعديل',
                              onPressed: () => _edit(it),
                              icon: const Icon(Icons.edit_rounded),
                            ),
                            IconButton(
                              tooltip: 'حذف',
                              onPressed: () => _delete(it),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: _red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Tickets extends StatelessWidget {
  const _Tickets({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('ميمو ما رفع أي تذكرة بعد'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = rows[i];
        final urgent = t['priority'] == 'urgent';
        return ListTile(
          leading: Icon(
            urgent
                ? Icons.notification_important_rounded
                : Icons.support_agent_rounded,
            color: urgent ? _red : _navy,
          ),
          title: Text('${t['subject'] ?? ''}'),
          subtitle: Text('${t['ticket_number'] ?? ''} • ${t['status'] ?? ''}'),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AdminSupportTicketDetailsScreen(
                ticketId: (t['id'] as num).toInt(),
              ),
            ),
          ),
        );
      },
    );
  }
}
