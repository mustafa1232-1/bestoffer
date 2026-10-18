import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/games_api.dart';
import 'knowledge_series_picker.dart';
import 'knowledge_game_screen.dart';

class AdminTeamCodeScreen extends ConsumerStatefulWidget {
  const AdminTeamCodeScreen({super.key});

  @override
  ConsumerState<AdminTeamCodeScreen> createState() =>
      _AdminTeamCodeScreenState();
}

class _AdminTeamCodeScreenState extends ConsumerState<AdminTeamCodeScreen> {
  Map<String, dynamic>? _overview;
  Map<String, dynamic> _knowledgeOverview = const {};
  List<Map<String, dynamic>> _knowledgeQuestions = const [];
  List<Map<String, dynamic>> _mafiaReports = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(gamesApiProvider);
      final value = await api.adminOverview();
      final reports = await api.mafiaReports().catchError(
        (_) => <Map<String, dynamic>>[],
      );
      final knowledge = await api.knowledgeAdminOverview().catchError(
        (_) => <String, dynamic>{},
      );
      final questions = await api
          .knowledgeAdminQuestions(limit: 20)
          .catchError((_) => <Map<String, dynamic>>[]);
      if (!mounted) return;
      setState(() {
        _overview = value;
        _mafiaReports = reports;
        _knowledgeOverview = knowledge;
        _knowledgeQuestions = questions;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'تعذر تحميل بيانات اللعبة. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createKnowledgeTournament() async {
    final title = TextEditingController(text: 'بطولة خريطة المعرفة');
    final prize = TextEditingController();
    final description = TextEditingController();
    var teamSize = 2;
    var maxTeams = 12;
    var bestOf = 3;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إنشاء بطولة معرفة'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    maxLength: 160,
                    decoration: const InputDecoration(labelText: 'اسم البطولة'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: teamSize,
                    decoration: const InputDecoration(labelText: 'حجم كل فريق'),
                    items: [1, 2, 3, 4]
                        .map(
                          (size) => DropdownMenuItem(
                            value: size,
                            child: Text(size == 1 ? 'فردي' : '$size لاعبين'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => teamSize = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: '$maxTeams',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الحد الأعلى للفرق (2 إلى 64)',
                    ),
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null) maxTeams = parsed.clamp(2, 64);
                    },
                  ),
                  const SizedBox(height: 8),
                  KnowledgeSeriesPicker(
                    value: bestOf,
                    onChanged: (value) => setDialogState(() => bestOf = value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: prize,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'عنوان الجائزة (اختياري)',
                    ),
                  ),
                  TextField(
                    controller: description,
                    maxLength: 500,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'تفاصيل الجائزة وشروطها',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'تسجيل الفوز لا يصرف جائزة تلقائياً؛ تعتمدها الإدارة وتنفذها يدوياً.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) {
      title.dispose();
      prize.dispose();
      description.dispose();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(gamesApiProvider)
          .createKnowledgeTournament(
            title: title.text.trim(),
            teamSize: teamSize,
            maxTeams: maxTeams,
            bestOf: bestOf,
            prizeTitle: prize.text.trim().isEmpty ? null : prize.text.trim(),
            prizeDescription: description.text.trim().isEmpty
                ? null
                : description.text.trim(),
          );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر إنشاء البطولة: $error')));
      }
    } finally {
      title.dispose();
      prize.dispose();
      description.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startKnowledgeTournament(Map<String, dynamic> event) async {
    final eventId = int.tryParse('${event['id']}') ?? 0;
    if (eventId <= 0 || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(gamesApiProvider).startKnowledgeTournament(eventId);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر بدء البطولة: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createKnowledgeQuestion() async {
    final question = TextEditingController();
    final explanation = TextEditingController();
    final options = List.generate(4, (_) => TextEditingController());
    const categories = <String, String>{
      'space': 'الفضاء والفلك',
      'math': 'الحساب الذهني',
      'logic': 'المنطق والألغاز',
      'iraq': 'العراق وبلاد الرافدين',
      'science': 'العلوم والطبيعة',
      'history': 'التاريخ والحضارات',
      'geography': 'الجغرافيا',
      'culture': 'الثقافة واللغة',
      'sports': 'الرياضة',
      'technology': 'التقنية',
      'nature': 'عالم الحيوان',
    };
    var category = 'iraq';
    var difficulty = 'easy';
    var answerIndex = 0;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة سؤال'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'الفئة'),
                    items: categories.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => category = value);
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: difficulty,
                    decoration: const InputDecoration(
                      labelText: 'الصعوبة والمدة',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'easy',
                        child: Text('سهل · 30 ثانية'),
                      ),
                      DropdownMenuItem(
                        value: 'medium',
                        child: Text('متوسط · 20 ثانية'),
                      ),
                      DropdownMenuItem(
                        value: 'hard',
                        child: Text('صعب · 15 ثانية'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => difficulty = value);
                      }
                    },
                  ),
                  TextField(
                    controller: question,
                    maxLength: 1000,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'نص السؤال'),
                  ),
                  for (var i = 0; i < options.length; i++)
                    TextField(
                      controller: options[i],
                      maxLength: 200,
                      decoration: InputDecoration(labelText: 'الخيار ${i + 1}'),
                    ),
                  DropdownButtonFormField<int>(
                    initialValue: answerIndex,
                    decoration: const InputDecoration(
                      labelText: 'الإجابة الصحيحة',
                    ),
                    items: List.generate(
                      4,
                      (index) => DropdownMenuItem(
                        value: index,
                        child: Text('الخيار ${index + 1}'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => answerIndex = value);
                      }
                    },
                  ),
                  TextField(
                    controller: explanation,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'شرح الإجابة (اختياري)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ السؤال'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) {
      question.dispose();
      explanation.dispose();
      for (final option in options) {
        option.dispose();
      }
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(gamesApiProvider)
          .createKnowledgeQuestion(
            category: category,
            difficulty: difficulty,
            question: question.text.trim(),
            options: options.map((item) => item.text.trim()).toList(),
            answerIndex: answerIndex,
            explanation: explanation.text.trim().isEmpty
                ? null
                : explanation.text.trim(),
          );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر حفظ السؤال: $error')));
      }
    } finally {
      question.dispose();
      explanation.dispose();
      for (final option in options) {
        option.dispose();
      }
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setKnowledgeQuestionActive(
    Map<String, dynamic> question,
    bool active,
  ) async {
    final questionId = int.tryParse('${question['id']}');
    if (questionId == null) return;
    try {
      await ref
          .read(gamesApiProvider)
          .setKnowledgeQuestionActive(questionId, active);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر تحديث السؤال: $error')));
      }
    }
  }

  Future<void> _reviewMafiaReport(Map<String, dynamic> report) async {
    final reportId = int.tryParse('${report['reportId']}') ?? 0;
    if (reportId <= 0 || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(gamesApiProvider).reviewMafiaReport(reportId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم توثيق مراجعة البلاغ.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر تحديث البلاغ الآن.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _saving = true);
    try {
      await ref.read(gamesApiProvider).updateCampaign(enabled: enabled);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled ? 'تم تشغيل اللعبة.' : 'تم إيقاف اللعبة.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لم يتم حفظ التغيير.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editCampaign(Map<String, dynamic> campaign) async {
    final rewardController = TextEditingController(
      text: '${campaign['rewardValue'] ?? 0}',
    );
    final daysController = TextEditingController(
      text: '${campaign['rewardValidDays'] ?? 7}',
    );
    final limitController = TextEditingController(
      text: '${campaign['claimLimit'] ?? ''}',
    );
    var startsAt = DateTime.tryParse('${campaign['startsAt'] ?? ''}');
    var endsAt = DateTime.tryParse('${campaign['endsAt'] ?? ''}');
    var rewardType = '${campaign['rewardType'] ?? 'mock_coupon'}';

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickDate(bool start) async {
            final current = (start ? startsAt : endsAt)?.toLocal();
            final date = await showDatePicker(
              context: context,
              initialDate: current ?? DateTime.now(),
              firstDate: DateTime(2024),
              lastDate: DateTime(2035),
            );
            if (date == null) return;
            setDialogState(() {
              if (start) {
                startsAt = DateTime(date.year, date.month, date.day);
              } else {
                endsAt = DateTime(date.year, date.month, date.day, 23, 59, 59);
              }
            });
          }

          return AlertDialog(
            title: const Text('إعدادات حملة الاختبار'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: rewardType,
                      decoration: const InputDecoration(
                        labelText: 'نوع المكافأة التجريبية',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'mock_coupon',
                          child: Text('كوبون تجريبي'),
                        ),
                        DropdownMenuItem(
                          value: 'test_badge',
                          child: Text('شارة تجريبية'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) rewardType = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: rewardController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'قيمة المكافأة',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: daysController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الصلاحية بالأيام',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: limitController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الحد الأقصى للمطالبات',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickDate(true),
                            icon: const Icon(Icons.event_rounded),
                            label: Text(_dateLabel(startsAt, 'تاريخ البدء')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickDate(false),
                            icon: const Icon(Icons.event_available_rounded),
                            label: Text(_dateLabel(endsAt, 'تاريخ الانتهاء')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );

    if (save != true || !mounted) {
      rewardController.dispose();
      daysController.dispose();
      limitController.dispose();
      return;
    }
    final reward = num.tryParse(rewardController.text.trim());
    final days = int.tryParse(daysController.text.trim());
    final limit = int.tryParse(limitController.text.trim());
    rewardController.dispose();
    daysController.dispose();
    limitController.dispose();
    if (reward == null || days == null || limit == null || days < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تحقق من قيم المكافأة والصلاحية والحد.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(gamesApiProvider)
          .updateCampaign(
            enabled: campaign['configuredEnabled'] == true,
            rewardType: rewardType,
            rewardValue: reward,
            rewardValidDays: days,
            claimLimit: limit,
            startsAt: startsAt,
            endsAt: endsAt,
          );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر حفظ إعدادات الحملة.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final campaign = Map<String, dynamic>.from(
      _overview?['campaign'] as Map? ?? const {},
    );
    final stats = Map<String, dynamic>.from(
      _overview?['stats'] as Map? ?? const {},
    );
    final enabled = campaign['configuredEnabled'] == true;
    final available = campaign['enabled'] == true;
    final recentRooms = _listOfMaps(_overview?['recentRooms']);
    final recentClaims = _listOfMaps(_overview?['recentClaims']);
    final knowledgeEvents = _listOfMaps(_knowledgeOverview['events']);
    final knowledgeStats = Map<String, dynamic>.from(
      _knowledgeOverview['stats'] as Map? ?? const {},
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة ألعاب مسلكي'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(_error!),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'بطولات خريطة المعرفة',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Text(
                                'أسئلة: ${_knowledgeOverview['bankSize'] ?? 0}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'بطولات ${knowledgeStats['events'] ?? 0} • فرق ${knowledgeStats['teams'] ?? 0} • نشطة ${knowledgeStats['active_events'] ?? 0}',
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _saving
                                ? null
                                : _createKnowledgeTournament,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('إنشاء بطولة'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : _createKnowledgeQuestion,
                            icon: const Icon(Icons.quiz_outlined),
                            label: const Text('إضافة سؤال وخيارات'),
                          ),
                          for (final question in _knowledgeQuestions.take(8))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${question['question']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${question['category']} · ${question['difficulty']} · ${question['timeLimitSeconds']} ثانية',
                              ),
                              trailing: Switch(
                                value: question['active'] == true,
                                onChanged: _saving
                                    ? null
                                    : (value) => _setKnowledgeQuestionActive(
                                        question,
                                        value,
                                      ),
                              ),
                            ),
                          if (knowledgeEvents.isEmpty)
                            const ListTile(
                              title: Text('لا توجد بطولات معرفة حالياً.'),
                            ),
                          for (final event in knowledgeEvents)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.emoji_events_outlined,
                                color: Color(0xFFC18B2F),
                              ),
                              title: Text('${event['title']}'),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      KnowledgeEventScreen(event: event),
                                ),
                              ),
                              subtitle: Text(
                                '${event['teams'] ?? 0}/${event['max_teams'] ?? 0} فريق • ${event['team_size'] ?? 1} لاعب/فريق • ${event['status']}',
                              ),
                              trailing: event['status'] == 'registration'
                                  ? IconButton(
                                      tooltip: 'بدء البطولة',
                                      onPressed: _saving
                                          ? null
                                          : () => _startKnowledgeTournament(
                                              event,
                                            ),
                                      icon: const Icon(
                                        Icons.play_arrow_rounded,
                                      ),
                                    )
                                  : const Icon(Icons.chevron_left_rounded),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.vpn_key_rounded),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'حملة شفرة الفريق التجريبية',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Switch(
                                value: enabled,
                                onChanged: _saving ? null : _setEnabled,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            available
                                ? 'متاحة للمستخدمين الآن'
                                : enabled
                                ? 'مفعلة، لكنها خارج مدة الحملة'
                                : 'موقوفة للمستخدمين',
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'المكافآت في هذه الحملة تجريبية وغير قابلة للاستخدام الحقيقي.',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _editCampaign(campaign),
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('تعديل الحملة والمكافأة'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _Metric(label: 'الغرف', value: stats['rooms']),
                      _Metric(
                        label: 'الجلسات المكتملة',
                        value: stats['completed_sessions'],
                      ),
                      _Metric(label: 'المشاركات', value: stats['memberships']),
                      _Metric(label: 'المكافآت', value: stats['claims']),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'بلاغات ليلة مسلكي',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Badge(
                        label: Text(
                          '${_mafiaReports.where((item) => item['status'] != 'reviewed').length}',
                        ),
                        child: const Icon(Icons.shield_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_mafiaReports.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.verified_user_outlined),
                      title: Text('لا توجد بلاغات حالياً.'),
                    )
                  else
                    ..._mafiaReports
                        .take(20)
                        .map(
                          (report) => Card(
                            child: ListTile(
                              leading: Icon(
                                report['status'] == 'reviewed'
                                    ? Icons.task_alt_rounded
                                    : Icons.flag_rounded,
                                color: report['status'] == 'reviewed'
                                    ? Colors.green
                                    : Colors.redAccent,
                              ),
                              title: Text(
                                '${report['targetName'] ?? 'لاعب'} • ${_mafiaReportReason('${report['reason']}')}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                'الغرفة #${report['roomId']} • المُبلّغ: ${report['reporterName'] ?? 'مستخدم'}'
                                '${('${report['details'] ?? ''}').trim().isEmpty ? '' : '\n${report['details']}'}',
                              ),
                              isThreeLine: ('${report['details'] ?? ''}')
                                  .trim()
                                  .isNotEmpty,
                              trailing: report['status'] == 'reviewed'
                                  ? const Text('تمت المراجعة')
                                  : TextButton(
                                      onPressed: _saving
                                          ? null
                                          : () => _reviewMafiaReport(report),
                                      child: const Text('تمت المراجعة'),
                                    ),
                            ),
                          ),
                        ),
                  const SizedBox(height: 20),
                  const Text(
                    'أحدث الغرف',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  if (recentRooms.isEmpty)
                    const ListTile(title: Text('لا توجد غرف حتى الآن.'))
                  else
                    ...recentRooms
                        .take(10)
                        .map(
                          (room) => ListTile(
                            leading: const Icon(Icons.meeting_room_outlined),
                            title: Text(
                              'غرفة #${room['id']} • ${room['status']}',
                            ),
                            subtitle: Text(
                              '${room['mode']} • ${room['memberCount']} لاعب',
                            ),
                          ),
                        ),
                  const SizedBox(height: 12),
                  const Text(
                    'أحدث المطالبات التجريبية',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  if (recentClaims.isEmpty)
                    const ListTile(title: Text('لا توجد مطالبات حتى الآن.'))
                  else
                    ...recentClaims
                        .take(10)
                        .map(
                          (claim) => ListTile(
                            leading: const Icon(Icons.redeem_outlined),
                            title: Text('${claim['userName']}'),
                            subtitle: Text(
                              '${claim['rewardType']} • ${claim['score']} نقطة',
                            ),
                          ),
                        ),
                ],
              ),
      ),
    );
  }
}

String _mafiaReportReason(String reason) => switch (reason) {
  'harassment' => 'إساءة أو مضايقة',
  'inappropriate_audio' => 'محتوى صوتي غير مناسب',
  'cheating' => 'غش أو تواطؤ',
  'spam' => 'إزعاج متكرر',
  _ => 'سبب آخر',
};

String _dateLabel(DateTime? value, String fallback) {
  if (value == null) return fallback;
  final date = value.toLocal();
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

List<Map<String, dynamic>> _listOfMaps(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : const [];

class _Metric extends StatelessWidget {
  final String label;
  final Object? value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 158,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${value ?? 0}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(label),
          ],
        ),
      ),
    ),
  );
}
