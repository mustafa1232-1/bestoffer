import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/appbar_quick_actions.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_profile_screen.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

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

  List<SocialRelationRequest> _incoming = const <SocialRelationRequest>[];
  List<SocialRelationRequest> _outgoing = const <SocialRelationRequest>[];
  bool _loadingIncoming = true;
  bool _loadingOutgoing = true;
  bool _actionBusy = false;
  String? _error;

  intl.DateFormat get _dateFormat => intl.DateFormat(
    'd/M hh:mm a',
    Localizations.localeOf(context).languageCode == 'en' ? 'en' : 'ar',
  );

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
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialRelationRequestsLoadIncomingFailed,
        );
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
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialRelationRequestsLoadOutgoingFailed,
        );
      });
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: Directionality.of(context)),
      ),
    );
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
      _showSnack(
        context.l10n.socialRelationRequestsAccepted(request.user.fullName),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        mapAnyError(
          e,
          fallback: context.l10n.socialRelationRequestsAcceptFailed,
        ),
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
      _showSnack(context.l10n.socialRelationRequestsRejected);
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        mapAnyError(
          e,
          fallback: context.l10n.socialRelationRequestsRejectFailed,
        ),
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
      _showSnack(context.l10n.socialRelationRequestsCancelled);
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        mapAnyError(
          e,
          fallback: context.l10n.socialRelationRequestsCancelFailed,
        ),
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
    if (value == null) return context.l10n.socialRelationRequestsNoTimestamp;
    return _dateFormat.format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.socialProfileManageConnectionRequests),
          actions: [
            IconButton(
              tooltip: l10n.commonRefresh,
              onPressed: _bootstrap,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const AppBarQuickActions(
              compact: true,
              includeFriendRequests: false,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: '${l10n.commonIncoming} (${_incoming.length})'),
              Tab(text: '${l10n.commonOutgoing} (${_outgoing.length})'),
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
                  textDirection: Directionality.of(context),
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
                    emptyText: l10n.socialRelationRequestsEmptyIncoming,
                    dateFormatter: _formatRequestedAt,
                    onOpenProfile: _openProfile,
                    actionsBuilder: (request) => Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _actionBusy
                              ? null
                              : () => _rejectRequest(request),
                          child: Text(l10n.commonReject),
                        ),
                        FilledButton(
                          onPressed: _actionBusy
                              ? null
                              : () => _acceptRequest(request),
                          child: Text(l10n.commonAccept),
                        ),
                      ],
                    ),
                  ),
                  _RequestsList(
                    loading: _loadingOutgoing,
                    requests: _outgoing,
                    emptyText: l10n.socialRelationRequestsEmptyOutgoing,
                    dateFormatter: _formatRequestedAt,
                    onOpenProfile: _openProfile,
                    actionsBuilder: (request) => FilledButton.tonal(
                      onPressed: _actionBusy
                          ? null
                          : () => _cancelRequest(request),
                      child: Text(l10n.socialRelationRequestsCancelAction),
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
    final l10n = context.l10n;
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (requests.isEmpty) {
      return Center(
        child: Text(
          emptyText,
          textDirection: Directionality.of(context),
          textAlign: TextAlign.center,
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
                    ? AppCachedImageProvider(user.imageUrl!)
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
                textDirection: Directionality.of(context),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            subtitle: Text(
              '${l10n.commonSince} ${dateFormatter(request.requestedAt)}',
              textDirection: Directionality.of(context),
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
