import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_chat_thread_screen.dart';
import 'widgets/social_identity_view.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialMessageRequestsScreen extends ConsumerStatefulWidget {
  const SocialMessageRequestsScreen({super.key});

  @override
  ConsumerState<SocialMessageRequestsScreen> createState() =>
      _SocialMessageRequestsScreenState();
}

class _SocialMessageRequestsScreenState
    extends ConsumerState<SocialMessageRequestsScreen> {
  bool _loading = true;
  bool _mutating = false;
  String? _error;
  List<SocialChatThread> _threads = const <SocialChatThread>[];

  SocialApi get _api => ref.read(socialApiProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await _api.listChatRequests();
      final raw = List<dynamic>.from(out['threads'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        _threads = raw
            .map(
              (row) => SocialChatThread.fromJson(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.socialMessageRequestsLoadFailed,
        );
      });
    }
  }

  Future<void> _accept(SocialChatThread thread) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      await _api.acceptChatRequest(thread.id);
      if (!mounted) return;
      setState(() {
        _threads = _threads.where((item) => item.id != thread.id).toList();
        _mutating = false;
      });
      _showMessage(context.l10n.socialMessageRequestsAccepted);
    } catch (error) {
      if (!mounted) return;
      setState(() => _mutating = false);
      _showMessage(
        mapAnyError(
          error,
          fallback: context.l10n.socialMessageRequestsAcceptFailed,
        ),
      );
    }
  }

  Future<void> _reject(SocialChatThread thread) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      await _api.rejectChatRequest(thread.id);
      if (!mounted) return;
      setState(() {
        _threads = _threads.where((item) => item.id != thread.id).toList();
        _mutating = false;
      });
      _showMessage(context.l10n.socialMessageRequestsRejected);
    } catch (error) {
      if (!mounted) return;
      setState(() => _mutating = false);
      _showMessage(
        mapAnyError(
          error,
          fallback: context.l10n.socialMessageRequestsRejectFailed,
        ),
      );
    }
  }

  Future<void> _block(SocialChatThread thread) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      await _api.blockChatRequest(thread.id);
      if (!mounted) return;
      setState(() {
        _threads = _threads.where((item) => item.id != thread.id).toList();
        _mutating = false;
      });
      _showMessage(context.l10n.socialMessageRequestsBlocked);
    } catch (error) {
      if (!mounted) return;
      setState(() => _mutating = false);
      _showMessage(
        mapAnyError(
          error,
          fallback: context.l10n.socialMessageRequestsBlockFailed,
        ),
      );
    }
  }

  Future<void> _openThread(SocialChatThread thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialChatThreadScreen(
          threadId: thread.id,
          peerName: socialPrimaryIdentityLabel(thread.peer),
          peerPhone: thread.peerPhone,
          peerUserId: thread.peer.id,
          peerImageUrl: thread.peer.imageUrl,
          readOnly: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.socialMessageRequestsTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 240),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _threads.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 120, 24, 24),
                children: [
                  Icon(
                    Icons.mark_chat_unread_outlined,
                    size: 54,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.socialMessageRequestsEmpty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  if ((_error ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                itemCount: _threads.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final thread = _threads[index];
                  final preview =
                      thread.lastMessage?.previewText.trim().isNotEmpty == true
                      ? thread.lastMessage!.previewText.trim()
                      : l10n.socialMessageRequestsPreviewHint;
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _openThread(thread),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.62,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundImage:
                                    (thread.peer.imageUrl ?? '')
                                        .trim()
                                        .isNotEmpty
                                    ? AppCachedImageProvider(
                                        thread.peer.imageUrl!,
                                      )
                                    : null,
                                child:
                                    (thread.peer.imageUrl ?? '').trim().isEmpty
                                    ? const Icon(Icons.person_outline)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SocialIdentityView(
                                      author: thread.peer,
                                      primaryStyle: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      preview,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: scheme.onSurface.withValues(
                                          alpha: 0.78,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: _mutating
                                      ? null
                                      : () => _accept(thread),
                                  child: Text(l10n.commonAccept),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _mutating
                                      ? null
                                      : () => _reject(thread),
                                  child: Text(l10n.commonReject),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _mutating
                                      ? null
                                      : () => _block(thread),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: scheme.error,
                                  ),
                                  child: Text(l10n.commonBlock),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
