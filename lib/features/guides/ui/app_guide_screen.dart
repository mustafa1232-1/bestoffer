import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../../admin/state/admin_controller.dart';

/// دليل استخدام scope-aware (المرحلة 10). يعرض فقط أقسام النطاق المحدد، وفي نطاق
/// الإدارة يُصفّي الخادم الأقسام حسب صلاحيات الموظف. مع بحث محلي.
class AppGuideScreen extends ConsumerStatefulWidget {
  const AppGuideScreen({super.key, this.appScope = 'admin'});

  final String appScope;

  @override
  ConsumerState<AppGuideScreen> createState() => _AppGuideScreenState();
}

class _AppGuideScreenState extends ConsumerState<AppGuideScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sections = const [];
  String _query = '';

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
      final data = await ref.read(adminApiProvider).fetchGuide(widget.appScope);
      final sections = ((data['sections'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _sections = sections);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.lt(
            ar: 'تعذّر تحميل الدليل.',
            en: 'Unable to load the guide.',
          ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _sections;
    return _sections
        .where((s) =>
            '${s['title'] ?? ''}'.toLowerCase().contains(q) ||
            '${s['body'] ?? ''}'.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'دليل الاستخدام', en: 'Usage guide')),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(MaslakiSpacing.md),
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: context.lt(ar: 'ابحث في الدليل', en: 'Search the guide'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? MaslakiEmptyState(
                              icon: Icons.menu_book_outlined,
                              title: context.lt(ar: 'لا توجد نتائج', en: 'No results'),
                              body: context.lt(
                                ar: 'لا يوجد قسم مطابق لبحثك.',
                                en: 'No section matches your search.',
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: MaslakiSpacing.md,
                              ),
                              children: [
                                for (final s in _filtered)
                                  Card(
                                    child: ExpansionTile(
                                      title: Text('${s['title'] ?? ''}'),
                                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                      children: [
                                        Align(
                                          alignment: AlignmentDirectional.centerStart,
                                          child: Text('${s['body'] ?? ''}'),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
    );
  }
}
