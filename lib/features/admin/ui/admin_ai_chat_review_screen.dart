import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';

class AdminAiChatReviewScreen extends ConsumerStatefulWidget {
  const AdminAiChatReviewScreen({super.key});

  @override
  ConsumerState<AdminAiChatReviewScreen> createState() =>
      _AdminAiChatReviewScreenState();
}

class _AdminAiChatReviewScreenState
    extends ConsumerState<AdminAiChatReviewScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  bool _loadingUsers = true;
  bool _loadingSessions = false;
  bool _loadingMessages = false;
  String? _usersError;
  String? _sessionsError;
  String? _messagesError;
  int _usersTotal = 0;
  int _sessionsTotal = 0;
  int _mobileStep = 0;

  Map<String, dynamic>? _selectedUser;
  Map<String, dynamic>? _selectedSession;
  List<Map<String, dynamic>> _users = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _sessions = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _messages = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadUsers);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() {
      _loadingUsers = true;
      _usersError = null;
    });
    try {
      final data = await ref
          .read(adminApiProvider)
          .aiChatReviewUsers(search: _searchController.text.trim(), limit: 80);
      final items = _readItems(data);
      if (!mounted) return;
      Map<String, dynamic>? nextSelected;
      final selectedId = _readInt(_selectedUser?['customer_user_id']);
      if (selectedId != null) {
        for (final item in items) {
          if (_readInt(item['customer_user_id']) == selectedId) {
            nextSelected = item;
            break;
          }
        }
      }
      nextSelected ??= items.isEmpty ? null : items.first;
      setState(() {
        _users = items;
        _usersTotal = _readInt(data['total']) ?? items.length;
        _selectedUser = nextSelected;
        _loadingUsers = false;
      });
      if (nextSelected != null) {
        await _loadSessionsForUser(nextSelected, preserveSelected: true);
      } else if (mounted) {
        setState(() {
          _sessions = const <Map<String, dynamic>>[];
          _messages = const <Map<String, dynamic>>[];
          _selectedSession = null;
          _sessionsTotal = 0;
          _mobileStep = 0;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingUsers = false;
        _usersError = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) => 'تعذر تحميل مستخدمي المساعد الآن.',
        );
      });
    }
  }

  Future<void> _loadSessionsForUser(
    Map<String, dynamic> user, {
    bool preserveSelected = false,
  }) async {
    final customerUserId = _readInt(user['customer_user_id']);
    if (customerUserId == null) return;
    if (!mounted) return;
    setState(() {
      _selectedUser = user;
      _loadingSessions = true;
      _sessionsError = null;
      _messagesError = null;
    });
    try {
      final data = await ref
          .read(adminApiProvider)
          .aiChatReviewUserSessions(customerUserId: customerUserId, limit: 80);
      final items = _readItems(data);
      if (!mounted) return;
      Map<String, dynamic>? nextSelected;
      final selectedId = preserveSelected
          ? _readInt(_selectedSession?['id'])
          : null;
      if (selectedId != null) {
        for (final item in items) {
          if (_readInt(item['id']) == selectedId) {
            nextSelected = item;
            break;
          }
        }
      }
      nextSelected ??= items.isEmpty ? null : items.first;
      setState(() {
        _sessions = items;
        _sessionsTotal = _readInt(data['total']) ?? items.length;
        _selectedSession = nextSelected;
        _loadingSessions = false;
      });
      if (nextSelected != null) {
        await _loadMessages(nextSelected);
      } else if (mounted) {
        setState(() => _messages = const <Map<String, dynamic>>[]);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSessions = false;
        _sessionsError = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) => 'تعذر تحميل جلسات هذا المستخدم.',
        );
      });
    }
  }

  Future<void> _loadMessages(Map<String, dynamic> session) async {
    final sessionId = _readInt(session['id']);
    if (sessionId == null) return;
    setState(() {
      _selectedSession = session;
      _loadingMessages = true;
      _messagesError = null;
    });
    try {
      final data = await ref
          .read(adminApiProvider)
          .aiChatReviewMessages(sessionId: sessionId, limit: 240);
      final items = _readItems(data).reversed.toList(growable: false);
      if (!mounted) return;
      setState(() {
        _messages = items;
        _loadingMessages = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMessages = false;
        _messagesError = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) => 'تعذر تحميل رسائل هذه الجلسة.',
        );
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (_mobileStep != 0) setState(() => _mobileStep = 0);
    _searchDebounce = Timer(const Duration(milliseconds: 420), _loadUsers);
  }

  void _openUser(Map<String, dynamic> user, {required bool wide}) {
    if (!wide) setState(() => _mobileStep = 1);
    unawaited(_loadSessionsForUser(user));
  }

  void _openSession(Map<String, dynamic> session, {required bool wide}) {
    if (!wide) setState(() => _mobileStep = 2);
    unawaited(_loadMessages(session));
  }

  void _mobileBack() {
    if (_mobileStep <= 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _mobileStep -= 1);
  }

  List<Map<String, dynamic>> _readItems(Map<String, dynamic> data) {
    return List<dynamic>.from(data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  String _text(Object? value, {String fallback = '-'}) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? fallback : text;
  }

  String _formatDate(Object? value) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      appBar: AppBar(
        leading: !wide && _mobileStep > 0
            ? IconButton(
                tooltip: 'رجوع',
                onPressed: _mobileBack,
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        title: Text(
          !wide && _mobileStep == 1
              ? 'جلسات المستخدم'
              : !wide && _mobileStep == 2
              ? 'رسائل جلسة المساعد'
              : 'مراجعة محادثات الذكاء الاصطناعي',
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loadingUsers ? null : _loadUsers,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: wide
              ? Row(
                  children: [
                    SizedBox(width: 320, child: _buildUsersPane(context)),
                    const SizedBox(width: 12),
                    SizedBox(width: 340, child: _buildSessionsPane(context)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildMessagesPane(context)),
                  ],
                )
              : switch (_mobileStep) {
                  0 => _buildUsersPane(context, wide: false),
                  1 => _buildSessionsPane(context, wide: false),
                  _ => _buildMessagesPane(context),
                },
        ),
      ),
    );
  }

  Widget _buildUsersPane(BuildContext context, {bool wide = true}) {
    return _AdminReviewCard(
      title: 'المستخدمون الذين استخدموا المساعد ($_usersTotal)',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'ابحث باسم المستخدم أو رقم الهاتف',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_loadingUsers) const LinearProgressIndicator(),
          if (_usersError != null) _ErrorStrip(message: _usersError!),
          Expanded(
            child: _users.isEmpty && !_loadingUsers
                ? const _EmptyStrip(message: 'لا توجد محادثات محفوظة بعد')
                : ListView.separated(
                    itemCount: _users.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final selected =
                          _readInt(user['customer_user_id']) ==
                          _readInt(_selectedUser?['customer_user_id']);
                      return ListTile(
                        selected: selected,
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.36),
                        leading: CircleAvatar(
                          child: Text(
                            _text(
                              user['full_name'],
                              fallback: 'م',
                            ).characters.first,
                          ),
                        ),
                        title: Text(
                          _text(user['full_name'], fallback: 'مستخدم'),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            _text(user['phone']),
                            'جلسات: ${_readInt(user['sessions_count']) ?? 0}',
                            'رسائل: ${_readInt(user['messages_count']) ?? 0}',
                            _formatDate(user['last_message_at']),
                          ].join(' • '),
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.arrow_back_ios_new_rounded),
                        onTap: () => _openUser(user, wide: wide),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsPane(BuildContext context, {bool wide = true}) {
    final user = _selectedUser;
    return _AdminReviewCard(
      title: user == null
          ? 'جلسات المستخدم'
          : 'جلسات ${_text(user['full_name'], fallback: 'المستخدم')} ($_sessionsTotal)',
      child: Column(
        children: [
          if (_loadingSessions) const LinearProgressIndicator(),
          if (_sessionsError != null) _ErrorStrip(message: _sessionsError!),
          Expanded(
            child: user == null
                ? const _EmptyStrip(message: 'اختر مستخدمًا أولًا')
                : _sessions.isEmpty && !_loadingSessions
                ? const _EmptyStrip(message: 'لا توجد جلسات لهذا المستخدم')
                : ListView.separated(
                    itemCount: _sessions.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      final selected =
                          _readInt(session['id']) ==
                          _readInt(_selectedSession?['id']);
                      return ListTile(
                        selected: selected,
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withValues(alpha: 0.32),
                        leading: const Icon(Icons.forum_rounded),
                        title: Text(
                          _text(session['title'], fallback: 'جلسة مساعد ذكي'),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            'رسائل: ${_readInt(session['messages_count']) ?? 0}',
                            _formatDate(session['last_message_at']),
                            _text(session['last_message_text']),
                          ].join(' • '),
                          textAlign: TextAlign.right,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.arrow_back_ios_new_rounded),
                        onTap: () => _openSession(session, wide: wide),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesPane(BuildContext context) {
    final session = _selectedSession;
    return _AdminReviewCard(
      title: session == null
          ? 'رسائل الجلسة'
          : _text(session['title'], fallback: 'رسائل جلسة المساعد'),
      trailing: session == null
          ? null
          : Text(
              '${_text(session['phone'])} • ${_formatDate(session['created_at'])}',
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.bodySmall,
            ),
      child: Column(
        children: [
          if (_loadingMessages) const LinearProgressIndicator(),
          if (_messagesError != null) _ErrorStrip(message: _messagesError!),
          Expanded(
            child: session == null
                ? const _EmptyStrip(message: 'اختر جلسة لعرض الرسائل')
                : _messages.isEmpty && !_loadingMessages
                ? const _EmptyStrip(message: 'لا توجد رسائل في هذه الجلسة')
                : ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _AdminAiMessageBubble(message: _messages[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AdminReviewCard extends StatelessWidget {
  const _AdminReviewCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(height: 4),
                  Align(alignment: Alignment.centerRight, child: trailing),
                ],
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        textAlign: TextAlign.right,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _EmptyStrip extends StatelessWidget {
  const _EmptyStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
      ),
    );
  }
}

class _AdminAiMessageBubble extends StatelessWidget {
  const _AdminAiMessageBubble({required this.message});

  final Map<String, dynamic> message;

  String _text(Object? value, {String fallback = '-'}) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? fallback : text;
  }

  String _formatTime(Object? value) {
    final raw = '${value ?? ''}'.trim();
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final role = _text(message['role']).toLowerCase();
    final isAssistant = role == 'assistant';
    final metadata = message['metadata'] is Map
        ? Map<String, dynamic>.from(message['metadata'] as Map)
        : const <String, dynamic>{};
    final domain = _text(metadata['assistDomain'], fallback: '');
    final type = _text(metadata['type'], fallback: '');
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isAssistant ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isAssistant
              ? colorScheme.primaryContainer.withValues(alpha: 0.50)
              : colorScheme.secondaryContainer.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isAssistant
                ? colorScheme.primary.withValues(alpha: 0.22)
                : colorScheme.secondary.withValues(alpha: 0.20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  _formatTime(message['created_at']),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const Spacer(),
                Text(
                  isAssistant ? 'المساعد' : 'المستخدم',
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              _text(message['text']),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (domain.isNotEmpty || type.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                textDirection: TextDirection.rtl,
                children: [
                  if (domain.isNotEmpty)
                    Chip(
                      label: Text('المجال: $domain'),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (type.isNotEmpty)
                    Chip(
                      label: Text('النوع: $type'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
