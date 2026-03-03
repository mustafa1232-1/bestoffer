import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/network/api_error_mapper.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_profile_screen.dart';

class SocialRelationRequestsScreen extends ConsumerStatefulWidget {
  const SocialRelationRequestsScreen({super.key});

  @override
  ConsumerState<SocialRelationRequestsScreen> createState() =>
      _SocialRelationRequestsScreenState();
}

class _SocialRelationRequestsScreenState
    extends ConsumerState<SocialRelationRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final SocialApi _api;
  final intl.DateFormat _dateFormat = intl.DateFormat('d/M hh:mm a', 'ar');

  List<SocialRelationRequest> _incoming = const <SocialRelationRequest>[];
  List<SocialRelationRequest> _outgoing = const <SocialRelationRequest>[];
  bool _loadingIncoming = true;
  bool _loadingOutgoing = true;
  bool _actionBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _api = ref.read(socialApiProvider);
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadIncoming(), _loadOutgoing()]);
  }

  Future<void> _loadIncoming() async {
    setState(() {
      _loadingIncoming = true;
      _error = null;
    });
    try {
      final out = await _api.listIncomingRelationRequests();
      final rows = List<dynamic>.from(out['requests'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        _incoming = rows
            .map(
              (e) => SocialRelationRequest.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(growable: false);
        _loadingIncoming = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingIncoming = false;
        _error = mapAnyError(e, fallback: 'تعذر تحميل طلبات المتابعة الواردة.');
      });
    }
  }

  Future<void> _loadOutgoing() async {
    setState(() {
      _loadingOutgoing = true;
      _error = null;
    });
    try {
      final out = await _api.listOutgoingRelationRequests();
      final rows = List<dynamic>.from(out['requests'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        _outgoing = rows
            .map(
              (e) => SocialRelationRequest.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(growable: false);
        _loadingOutgoing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOutgoing = false;
        _error = mapAnyError(e, fallback: 'تعذر تحميل طلبات المتابعة الصادرة.');
      });
    }
  }

  Future<void> _acceptRequest(SocialRelationRequest request) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await _api.acceptRelationRequest(request.user.id);
      if (!mounted) return;
      setState(() {
        _incoming = _incoming
            .where((r) => r.user.id != request.user.id)
            .toList();
      });
      await ref.read(socialControllerProvider.notifier).loadThreads();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم قبول متابعة ${request.user.fullName}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapAnyError(e, fallback: 'تعذر قبول الطلب.'))),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _rejectRequest(SocialRelationRequest request) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await _api.rejectRelationRequest(request.user.id);
      if (!mounted) return;
      setState(() {
        _incoming = _incoming
            .where((r) => r.user.id != request.user.id)
            .toList();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم رفض الطلب')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapAnyError(e, fallback: 'تعذر رفض الطلب.'))),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _cancelRequest(SocialRelationRequest request) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await _api.cancelRelationRequest(request.user.id);
      if (!mounted) return;
      setState(() {
        _outgoing = _outgoing
            .where((r) => r.user.id != request.user.id)
            .toList();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إلغاء الطلب')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapAnyError(e, fallback: 'تعذر إلغاء الطلب.'))),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _openProfile(SocialAuthor author) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialProfileScreen(
          userId: author.id,
          initialName: author.fullName,
        ),
      ),
    );
  }

  String _formatRequestedAt(DateTime? value) {
    if (value == null) return 'بدون وقت';
    return _dateFormat.format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('طلبات المتابعة'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _bootstrap,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: 'واردة (${_incoming.length})'),
              Tab(text: 'صادرة (${_outgoing.length})'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Theme.of(context).colorScheme.errorContainer,
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _RequestsList(
                    loading: _loadingIncoming,
                    requests: _incoming,
                    emptyText: 'لا توجد طلبات متابعة واردة حالياً.',
                    dateFormatter: _formatRequestedAt,
                    onOpenProfile: _openProfile,
                    actionsBuilder: (request) => Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _actionBusy
                              ? null
                              : () => _rejectRequest(request),
                          child: const Text('رفض'),
                        ),
                        FilledButton(
                          onPressed: _actionBusy
                              ? null
                              : () => _acceptRequest(request),
                          child: const Text('قبول'),
                        ),
                      ],
                    ),
                  ),
                  _RequestsList(
                    loading: _loadingOutgoing,
                    requests: _outgoing,
                    emptyText: 'لا توجد طلبات متابعة صادرة حالياً.',
                    dateFormatter: _formatRequestedAt,
                    onOpenProfile: _openProfile,
                    actionsBuilder: (request) => FilledButton.tonal(
                      onPressed: _actionBusy
                          ? null
                          : () => _cancelRequest(request),
                      child: const Text('إلغاء الطلب'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestsList extends StatelessWidget {
  final bool loading;
  final List<SocialRelationRequest> requests;
  final String emptyText;
  final String Function(DateTime?) dateFormatter;
  final Future<void> Function(SocialAuthor) onOpenProfile;
  final Widget Function(SocialRelationRequest) actionsBuilder;

  const _RequestsList({
    required this.loading,
    required this.requests,
    required this.emptyText,
    required this.dateFormatter,
    required this.onOpenProfile,
    required this.actionsBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (requests.isEmpty) {
      return Center(
        child: Text(
          emptyText,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: requests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final request = requests[index];
        final user = request.user;
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            leading: InkWell(
              onTap: () => onOpenProfile(user),
              borderRadius: BorderRadius.circular(999),
              child: CircleAvatar(
                backgroundImage: (user.imageUrl ?? '').trim().isNotEmpty
                    ? NetworkImage(user.imageUrl!)
                    : null,
                child: (user.imageUrl ?? '').trim().isEmpty
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
            ),
            title: InkWell(
              onTap: () => onOpenProfile(user),
              borderRadius: BorderRadius.circular(8),
              child: Text(
                user.fullName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            subtitle: Text(
              'منذ ${dateFormatter(request.requestedAt)}',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: actionsBuilder(request),
          ),
        );
      },
    );
  }
}
