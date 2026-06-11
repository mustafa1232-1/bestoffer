import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_profile_screen.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

enum SocialConnectionListMode { followers, following, friends }

class SocialUserConnectionsScreen extends ConsumerStatefulWidget {
  final int userId;
  final SocialConnectionListMode mode;
  final String title;

  const SocialUserConnectionsScreen({
    super.key,
    required this.userId,
    required this.mode,
    required this.title,
  });

  @override
  ConsumerState<SocialUserConnectionsScreen> createState() =>
      _SocialUserConnectionsScreenState();
}

class _SocialUserConnectionsScreenState
    extends ConsumerState<SocialUserConnectionsScreen> {
  bool _loading = true;
  String? _error;
  List<SocialUserSearchResult> _users = const <SocialUserSearchResult>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  String _roleLabel(String role, BuildContext context) {
    final l10n = context.l10n;
    switch (role.trim().toLowerCase()) {
      case 'owner':
        return l10n.socialConnectionsRoleMerchant;
      case 'delivery':
        return l10n.socialConnectionsRoleDelivery;
      case 'taxi_captain':
        return l10n.socialConnectionsRoleTaxiCaptain;
      case 'super_admin':
        return l10n.socialConnectionsRoleSuperAdmin;
      default:
        return l10n.socialConnectionsRoleUser;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(socialApiProvider);
      final out = await switch (widget.mode) {
        SocialConnectionListMode.followers => api.listUserFollowers(
          userId: widget.userId,
        ),
        SocialConnectionListMode.following => api.listUserFollowing(
          userId: widget.userId,
        ),
        SocialConnectionListMode.friends => api.listUserFriends(
          userId: widget.userId,
        ),
      };
      final rows = List<dynamic>.from(out['users'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        _users = rows
            .map(
              (item) => SocialUserSearchResult.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(child: Text(_error!)),
                  ],
                )
              : _users.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(child: Text(l10n.socialConnectionsEmpty)),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _users.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SocialProfileScreen(
                              userId: user.user.id,
                              initialName: user.user.fullName,
                            ),
                          ),
                        );
                      },
                      leading: CircleAvatar(
                        backgroundImage:
                            (user.user.imageUrl ?? '').trim().isNotEmpty
                            ? AppCachedImageProvider(user.user.imageUrl!)
                            : null,
                        child: (user.user.imageUrl ?? '').trim().isEmpty
                            ? const Icon(Icons.person_outline_rounded)
                            : null,
                      ),
                      title: Text(
                        user.user.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(_roleLabel(user.user.role, context)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
