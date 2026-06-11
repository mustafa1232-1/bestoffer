import 'dart:async';

import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/parsers.dart';
import '../../auth/state/auth_controller.dart';
import '../data/assistant_api.dart';

final assistantApiProvider = Provider<AssistantApi>((ref) {
  return AssistantApi(ref.read(dioClientProvider).dio);
});

class AssistantChatScreen extends ConsumerStatefulWidget {
  const AssistantChatScreen({super.key});

  @override
  ConsumerState<AssistantChatScreen> createState() =>
      _AssistantChatScreenState();
}

class _AssistantChatScreenState extends ConsumerState<AssistantChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _sending = false;
  bool _refreshingSession = false;
  bool _quickLoading = false;
  bool _memoryEnabled = true;
  int? _sessionId;
  String? _error;
  String? _warning;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _quickResult;
  List<Map<String, dynamic>> _messages = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _topics = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  AssistantApi get _assistantApi => ref.read(assistantApiProvider);

  Future<void> _bootstrap({bool forceNewSession = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _warning = null;
    });

    try {
      final sessionPayload = forceNewSession
          ? await _assistantApi.startNewSession()
          : await _assistantApi.getCurrentSession();
      Map<String, dynamic>? profilePayload;
      List<Map<String, dynamic>> topics = const <Map<String, dynamic>>[];
      String? warning;

      try {
        profilePayload = await _assistantApi.getAiUserProfile();
      } catch (error) {
        warning = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) =>
              'المساعد يعمل، لكن تعذر تحميل تفضيلات الذكاء الاصطناعي الآن.',
        );
      }

      try {
        topics = await _assistantApi.listAiTopics();
      } catch (error) {
        warning ??= mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) =>
              'المساعد يعمل، لكن اقتراحات المواضيع غير متاحة حاليًا.',
        );
      }

      if (!mounted) return;
      setState(() {
        _syncSessionPayload(sessionPayload);
        _applyAiProfile(profilePayload);
        _topics = topics;
        _warning = warning;
        _loading = false;
      });
      _jumpToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) => 'تعذر تشغيل المساعد الذكي حاليًا.',
        );
      });
    }
  }

  void _syncSessionPayload(Map<String, dynamic> payload) {
    _sessionId = tryParseLocalizedInt(payload['sessionId']) ?? _sessionId;
    _messages = _readMapList(payload['messages']);
  }

  void _applyAiProfile(Map<String, dynamic>? payload) {
    final profile = payload?['profile'];
    if (profile is! Map) return;
    _profile = Map<String, dynamic>.from(profile);
    final consent = profile['consentFlags'];
    if (consent is Map) {
      _memoryEnabled = consent['memoryEnabled'] != false;
    }
  }

  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _sending = true;
      _warning = null;
    });
    try {
      final payload = await _assistantApi.chat(
        message: text,
        sessionId: _sessionId,
      );
      if (!mounted) return;
      _messageController.clear();
      setState(() {
        _quickResult = null;
        _syncSessionPayload(payload);
        _sending = false;
      });
      _jumpToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _warning = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) =>
              'تعذر إرسال الرسالة الآن. إذا كانت خدمات الذكاء غير متاحة فسيعود النظام للعمل عند توفرها.',
        );
      });
    }
  }

  Future<void> _startFreshSession() async {
    if (_refreshingSession) return;
    setState(() => _refreshingSession = true);
    try {
      await _bootstrap(forceNewSession: true);
    } finally {
      if (mounted) setState(() => _refreshingSession = false);
    }
  }

  Future<void> _toggleMemory(bool enabled) async {
    final previous = _memoryEnabled;
    setState(() {
      _memoryEnabled = enabled;
      _warning = null;
    });
    try {
      final payload = await _assistantApi.setAiMemoryConsent(enabled: enabled);
      if (!mounted) return;
      _applyAiProfile(payload);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _memoryEnabled = previous;
        _warning = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) => 'تعذر تحديث إعدادات ذاكرة المساعد الآن.',
        );
      });
    }
  }

  Future<void> _runQuickAction(_AssistantQuickAction action) async {
    if (_quickLoading) return;
    final query = await _askForQuery(action);
    if (!mounted || query == null || query.trim().isEmpty) return;
    setState(() {
      _quickLoading = true;
      _warning = null;
    });
    try {
      late final Map<String, dynamic> result;
      switch (action) {
        case _AssistantQuickAction.commerce:
          result = await _assistantApi.recommendCommerce(query: query);
          break;
        case _AssistantQuickAction.jobs:
          result = await _assistantApi.recommendJobs(query: query);
          break;
        case _AssistantQuickAction.appSearch:
          result = await _assistantApi.appSearch(query: query);
          break;
        case _AssistantQuickAction.webSearch:
          result = await _assistantApi.webSearch(query: query);
          break;
      }
      if (!mounted) return;
      setState(() {
        _quickResult = <String, dynamic>{
          'action': action.name,
          'query': query,
          ...result,
        };
        _quickLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _quickLoading = false;
        _warning = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) => 'تعذر تنفيذ الطلب الذكي الآن.',
        );
      });
    }
  }

  Future<String?> _askForQuery(_AssistantQuickAction action) async {
    final controller = TextEditingController();
    final label = switch (action) {
      _AssistantQuickAction.commerce => 'صف ما تريد شراءه أو مطعمًا تبحث عنه',
      _AssistantQuickAction.jobs => 'اكتب نوع الوظيفة أو المهارة أو الموقع',
      _AssistantQuickAction.appSearch => 'ابحث داخل التطبيق عن متجر أو خدمة',
      _AssistantQuickAction.webSearch => 'اكتب سؤالك للبحث على الويب',
    };
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Container(
            margin: const EdgeInsets.all(MaslakiSpacing.md),
            padding: const EdgeInsets.all(MaslakiSpacing.md),
            decoration: BoxDecoration(
              color: context.maslakiTokens.cardPrimary,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: context.maslakiTokens.borderSubtle.withValues(
                  alpha: 0.9,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'نفّذ الآن',
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: MaslakiSpacing.xs),
                Text(
                  label,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: MaslakiSpacing.md),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textDirection: TextDirection.rtl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: label,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: MaslakiSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: MaslakiOutlineButton(
                        onPressed: () =>
                            Navigator.of(sheetContext).pop<String>(null),
                        label: 'إلغاء',
                        icon: Icons.close_rounded,
                      ),
                    ),
                    const SizedBox(width: MaslakiSpacing.sm),
                    Expanded(
                      child: MaslakiPrimaryButton(
                        onPressed: () => Navigator.of(
                          sheetContext,
                        ).pop<String>(controller.text.trim()),
                        label: 'تشغيل',
                        icon: Icons.auto_awesome_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();
    return result;
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  List<Map<String, dynamic>> _readMapList(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  String _profileName() {
    final profile = _profile;
    if (profile == null) return '';
    const keys = <String>[
      'displayName',
      'display_name',
      'realName',
      'real_name',
      'nickname',
    ];
    for (final key in keys) {
      final value = '${profile[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _profileCity() {
    final city = '${_profile?['city'] ?? ''}'.trim();
    return city;
  }

  List<Map<String, dynamic>> _quickResultItems() {
    final quickResult = _quickResult;
    if (quickResult == null) return const <Map<String, dynamic>>[];
    final items = quickResult['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  String _quickItemTitle(Map<String, dynamic> item) {
    for (final key in const <String>[
      'title',
      'name',
      'merchantName',
      'merchant_name',
      'jobTitle',
      'job_title',
      'label',
    ]) {
      final value = '${item[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return 'عنصر مقترح';
  }

  String _quickItemSubtitle(Map<String, dynamic> item) {
    final parts = <String>[];
    for (final key in const <String>[
      'reason',
      'categoryName',
      'merchantType',
      'city',
      'salaryLabel',
      'priceLabel',
      'summary',
      'snippet',
      'url',
    ]) {
      final value = '${item[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        parts.add(value);
      }
      if (parts.length >= 2) break;
    }
    return parts.join(' • ');
  }

  String _messageText(Map<String, dynamic> message) {
    final text = '${message['text'] ?? ''}'.trim();
    if (text.isNotEmpty) return text;
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final rawUserName = auth.user?.fullName.trim() ?? '';
    final displayName = _profileName().isNotEmpty
        ? _profileName()
        : (rawUserName.isNotEmpty ? rawUserName : context.l10n.appName);
    final city = _profileCity();
    final quickItems = _quickResultItems();

    return Scaffold(
      appBar: MaslakiTopBar(
        title: 'المساعد الذكي',
        subtitle: 'اقتراحات، بحث، ومحادثة ذكية داخل مسلكي',
        actions: [
          IconButton(
            tooltip: 'جلسة جديدة',
            onPressed: _refreshingSession ? null : _startFreshSession,
            icon: _refreshingSession
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MaslakiScreenFrame(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _AssistantErrorCard(
                      message: _error!,
                      onRetry: _bootstrap,
                    )
                  : ListView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        MaslakiCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                textDirection: TextDirection.rtl,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          displayName,
                                          textDirection: TextDirection.rtl,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                        const SizedBox(
                                          height: MaslakiSpacing.xs,
                                        ),
                                        Text(
                                          city.isEmpty
                                              ? 'المساعد جاهز لترتيب اقتراحاتك وطلباتك.'
                                              : 'مهيأ الآن لمدينة $city',
                                          textDirection: TextDirection.rtl,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: MaslakiSpacing.sm),
                                  const MaslakiStatusPill(
                                    label: 'نشط',
                                    icon: Icons.auto_awesome_rounded,
                                  ),
                                ],
                              ),
                              const SizedBox(height: MaslakiSpacing.md),
                              SwitchListTile.adaptive(
                                value: _memoryEnabled,
                                onChanged: _toggleMemory,
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'تفعيل ذاكرة المساعد',
                                  textDirection: TextDirection.rtl,
                                ),
                                subtitle: const Text(
                                  'يحفظ التفضيلات والأنماط لتقديم اقتراحات أدق لاحقًا.',
                                  textDirection: TextDirection.rtl,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_warning != null) ...[
                          const SizedBox(height: MaslakiSpacing.md),
                          MaslakiCard(
                            borderColor: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.4),
                            child: Text(
                              _warning!,
                              textDirection: TextDirection.rtl,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                        const SizedBox(height: MaslakiSpacing.md),
                        MaslakiCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'أوامر سريعة',
                                textDirection: TextDirection.rtl,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: MaslakiSpacing.md),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: MaslakiSpacing.sm,
                                runSpacing: MaslakiSpacing.sm,
                                children: [
                                  _QuickActionChip(
                                    icon: Icons.shopping_bag_outlined,
                                    label: 'اقتراح متاجر',
                                    onTap: () => _runQuickAction(
                                      _AssistantQuickAction.commerce,
                                    ),
                                  ),
                                  _QuickActionChip(
                                    icon: Icons.work_outline_rounded,
                                    label: 'اقتراح وظائف',
                                    onTap: () => _runQuickAction(
                                      _AssistantQuickAction.jobs,
                                    ),
                                  ),
                                  _QuickActionChip(
                                    icon: Icons.search_rounded,
                                    label: 'بحث داخل التطبيق',
                                    onTap: () => _runQuickAction(
                                      _AssistantQuickAction.appSearch,
                                    ),
                                  ),
                                  _QuickActionChip(
                                    icon: Icons.public_rounded,
                                    label: 'بحث ويب',
                                    onTap: () => _runQuickAction(
                                      _AssistantQuickAction.webSearch,
                                    ),
                                  ),
                                ],
                              ),
                              if (_topics.isNotEmpty) ...[
                                const SizedBox(height: MaslakiSpacing.md),
                                Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: MaslakiSpacing.sm,
                                  runSpacing: MaslakiSpacing.sm,
                                  children: _topics.take(6).map((topic) {
                                    final label =
                                        '${topic['topicLabel'] ?? topic['topic'] ?? topic['name'] ?? ''}'
                                            .trim();
                                    if (label.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return MaslakiChip(
                                      label: label,
                                      icon: Icons.bolt_rounded,
                                      onTap: () {
                                        _messageController.text = label;
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                              if (_quickLoading) ...[
                                const SizedBox(height: MaslakiSpacing.md),
                                const LinearProgressIndicator(),
                              ],
                            ],
                          ),
                        ),
                        if (_quickResult != null) ...[
                          const SizedBox(height: MaslakiSpacing.md),
                          MaslakiCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${_quickResult?['summary'] ?? 'نتيجة ذكية'}',
                                  textDirection: TextDirection.rtl,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                if (quickItems.isEmpty) ...[
                                  const SizedBox(height: MaslakiSpacing.sm),
                                  const Text(
                                    'لا توجد عناصر مطابقة الآن، لكن يمكنك تعديل الطلب أو إعادة المحاولة.',
                                    textDirection: TextDirection.rtl,
                                  ),
                                ],
                                for (final item in quickItems.take(4)) ...[
                                  const SizedBox(height: MaslakiSpacing.sm),
                                  MaslakiListRowCard(
                                    title: _quickItemTitle(item),
                                    subtitle: _quickItemSubtitle(item),
                                    leadingIcon: Icons.auto_awesome_motion_rounded,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: MaslakiSpacing.md),
                        if (_messages.isEmpty)
                          const MaslakiEmptyState(
                            icon: Icons.forum_outlined,
                            title: 'ابدأ المحادثة الآن',
                            body:
                                'اسأل عن متجر، خدمة، عرض، أو اكتب ما تحتاجه وسيرتب لك المساعد الخيارات الأنسب.',
                          )
                        else
                          ..._messages.map(
                            (message) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: MaslakiSpacing.sm,
                              ),
                              child: _AssistantMessageBubble(
                                role: '${message['role'] ?? ''}',
                                text: _messageText(message),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                MaslakiSpacing.md,
                0,
                MaslakiSpacing.md,
                MaslakiSpacing.md,
              ),
              child: MaslakiCard(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 4,
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                          hintText: 'اكتب سؤالك أو طلبك هنا...',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: MaslakiSpacing.sm),
                    MaslakiPrimaryButton(
                      onPressed: _sending ? null : _sendMessage,
                      icon: _sending
                          ? null
                          : Icons.send_rounded,
                      label: _sending ? 'جارٍ الإرسال' : 'إرسال',
                      expanded: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _AssistantQuickAction { commerce, jobs, appSearch, webSearch }

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MaslakiChip(
      label: label,
      icon: icon,
      onTap: onTap,
    );
  }
}

class _AssistantMessageBubble extends StatelessWidget {
  final String role;
  final String text;

  const _AssistantMessageBubble({
    required this.role,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final isAssistant = role.trim().toLowerCase() == 'assistant';
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    return Align(
      alignment: isAssistant ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(MaslakiSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isAssistant
              ? tokens.surfacePrimary.withValues(alpha: 0.94)
              : visual.accentBlue.withValues(alpha: 0.16),
          border: Border.all(
            color: isAssistant
                ? tokens.primaryAccent.withValues(alpha: 0.34)
                : visual.accentCyan.withValues(alpha: 0.24),
          ),
        ),
        child: Column(
          crossAxisAlignment: isAssistant
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              isAssistant ? 'المساعد' : 'أنت',
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: isAssistant ? tokens.primaryAccent : visual.accentCyan,
              ),
            ),
            const SizedBox(height: MaslakiSpacing.xs),
            Text(
              text,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantErrorCard extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _AssistantErrorCard({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MaslakiCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.assistant_outlined, size: 42),
            const SizedBox(height: MaslakiSpacing.md),
            Text(
              message,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MaslakiSpacing.md),
            MaslakiPrimaryButton(
              onPressed: () => onRetry(),
              icon: Icons.refresh_rounded,
              label: 'إعادة المحاولة',
            ),
          ],
        ),
      ),
    );
  }
}
