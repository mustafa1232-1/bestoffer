import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';
import 'admin_social_restrictions_screen.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class AdminSocialUsersScreen extends ConsumerStatefulWidget {
  final bool selectionMode;

  const AdminSocialUsersScreen({super.key, this.selectionMode = false});

  @override
  ConsumerState<AdminSocialUsersScreen> createState() =>
      _AdminSocialUsersScreenState();
}

class _AdminSocialUsersScreenState
    extends ConsumerState<AdminSocialUsersScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _busy = false;
  String? _error;
  int? _nextCursor;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _load(refresh: true));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  bool _isDisabled(Map<String, dynamic> item) {
    return item['isAccountDisabled'] == true ||
        item['is_account_disabled'] == true;
  }

  String _roleLabel(Map<String, dynamic> item) {
    final role = '${item['role'] ?? ''}'.trim();
    if (role.isEmpty) return '-';
    return role;
  }

  Map<String, dynamic> _unwrapPayload(Map<String, dynamic> raw) {
    final data = raw['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return raw;
  }

  Future<void> _load({required bool refresh}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (_nextCursor == null || _loadingMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final out = await ref
          .read(adminApiProvider)
          .socialUsersForModeration(
            search: _searchCtrl.text.trim(),
            limit: 60,
            beforeId: refresh ? null : _nextCursor,
          );
      final payload = _unwrapPayload(out);
      final rows = List<dynamic>.from(payload['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        final nextCursorRaw = payload['nextCursor'] ?? payload['next_cursor'];
        _nextCursor = _readInt(nextCursorRaw) > 0
            ? _readInt(nextCursorRaw)
            : null;
        _items = refresh ? rows : [..._items, ...rows];
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = mapAnyError(e, fallback: 'تعذر تحميل المستخدمين.');
      });
    }
  }

  Future<String?> _askNote({
    required String title,
    String? initialValue,
  }) async {
    final ctrl = TextEditingController(text: initialValue ?? '');
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title, textAlign: TextAlign.end),
          content: TextField(
            controller: ctrl,
            minLines: 2,
            maxLines: 5,
            textDirection: Directionality.of(context),
            decoration: const InputDecoration(
              labelText: 'ملاحظة الإدارة (تظهر للمستخدم)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.l10n.commonConfirm),
            ),
          ],
        );
      },
    );
    final note = ctrl.text.trim();
    ctrl.dispose();
    if (approved != true) return null;
    return note;
  }

  Future<void> _setAccountStatus({
    required Map<String, dynamic> item,
    required bool disable,
  }) async {
    if (_busy) return;
    final userId = _readInt(item['id']);
    if (userId <= 0) return;
    String? note;
    if (disable) {
      note = await _askNote(title: 'تعطيل الحساب');
      if (note == null) return;
    }
    setState(() => _busy = true);
    try {
      final out = await ref
          .read(adminApiProvider)
          .setSocialUserAccountStatus(
            userId: userId,
            isDisabled: disable,
            note: note,
          );
      final updated = out['user'];
      if (!mounted) return;
      setState(() {
        if (updated is Map) {
          final updatedMap = Map<String, dynamic>.from(updated);
          _items = _items
              .map((row) => _readInt(row['id']) == userId ? updatedMap : row)
              .toList(growable: false);
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(disable ? 'تم تعطيل الحساب.' : 'تم تفعيل الحساب.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapAnyError(e, fallback: 'تعذر تحديث حالة الحساب.')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRestrictions(Map<String, dynamic> item) async {
    final userId = _readInt(item['id']);
    if (userId <= 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminSocialRestrictionsScreen(initialUserId: userId),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> item) {
    final scheme = Theme.of(context).colorScheme;
    final userId = _readInt(item['id']);
    final username = '${item['username'] ?? ''}'.trim();
    final fullName = '${item['fullName'] ?? item['full_name'] ?? ''}'.trim();
    final phone = '${item['phone'] ?? ''}'.trim();
    final role = _roleLabel(item);
    final isSuperAdmin =
        item['isSuperAdmin'] == true || item['is_super_admin'] == true;
    final isDisabled = _isDisabled(item);
    final imageUrl = '${item['imageUrl'] ?? item['image_url'] ?? ''}'.trim();
    final note =
        '${item['accountDisabledNote'] ?? item['account_disabled_note'] ?? ''}'
            .trim();
    final statusColor = isDisabled
        ? const Color(0xFFDC2626)
        : const Color(0xFF0E9F6E);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.selectionMode
            ? () => Navigator.of(context).pop<int>(userId)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: imageUrl.isNotEmpty
                        ? AppCachedImageProvider(imageUrl)
                        : null,
                    child: imageUrl.isEmpty
                        ? const Icon(Icons.person_outline_rounded)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username.isNotEmpty ? '@$username' : '#$userId',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        if (fullName.isNotEmpty)
                          Text(
                            fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (phone.isNotEmpty)
                          Text(
                            phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: statusColor.withValues(alpha: 0.14),
                    ),
                    child: Text(
                      isDisabled ? 'معطّل' : 'نشط',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(label: 'الدور: $role'),
                  if (isSuperAdmin) const _MetaChip(label: 'Super Admin'),
                  _MetaChip(label: 'ID: $userId'),
                ],
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    note,
                    textDirection: Directionality.of(context),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _openRestrictions(item),
                    icon: const Icon(Icons.gpp_bad_outlined),
                    label: const Text('قيود السوشل'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _setAccountStatus(
                            item: item,
                            disable: !isDisabled,
                          ),
                    icon: Icon(
                      isDisabled
                          ? Icons.lock_open_rounded
                          : Icons.block_rounded,
                    ),
                    label: Text(isDisabled ? 'تفعيل الحساب' : 'تعطيل الحساب'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.selectionMode ? 'اختيار مستخدم' : 'إدارة مستخدمي السوشل',
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: context.l10n.commonSearch,
                  onPressed: () => _load(refresh: true),
                  icon: const Icon(Icons.search_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(refresh: true),
                    decoration: InputDecoration(
                      labelText: context.l10n.commonSearch,
                      hintText: 'ID / @username / الاسم / الهاتف',
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                textDirection: Directionality.of(context),
              ),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 100),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 100),
                child: Center(child: Text('لا يوجد مستخدمون مطابقون للبحث.')),
              )
            else ...[
              const SizedBox(height: 10),
              ..._items.map(_buildUserCard),
              if (_nextCursor != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton.icon(
                    onPressed: _loadingMore
                        ? null
                        : () => _load(refresh: false),
                    icon: _loadingMore
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more_rounded),
                    label: const Text('تحميل المزيد'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;

  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: scheme.surfaceContainerHighest,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
