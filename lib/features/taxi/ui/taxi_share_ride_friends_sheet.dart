import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../features/auth/state/auth_controller.dart';
import '../../../features/social/data/social_api.dart';
import '../data/taxi_api.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

final _taxiShareSocialApiProvider = Provider<SocialApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return SocialApi(dio);
});

class _TaxiFriendOption {
  final int id;
  final String fullName;
  final String? imageUrl;

  const _TaxiFriendOption({
    required this.id,
    required this.fullName,
    required this.imageUrl,
  });
}

Future<void> showTaxiRideShareFriendsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required int rideId,
  required int currentUserId,
  required TaxiApi taxiApi,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TaxiRideShareFriendsSheet(
      rideId: rideId,
      currentUserId: currentUserId,
      taxiApi: taxiApi,
    ),
  );
}

class _TaxiRideShareFriendsSheet extends ConsumerStatefulWidget {
  final int rideId;
  final int currentUserId;
  final TaxiApi taxiApi;

  const _TaxiRideShareFriendsSheet({
    required this.rideId,
    required this.currentUserId,
    required this.taxiApi,
  });

  @override
  ConsumerState<_TaxiRideShareFriendsSheet> createState() =>
      _TaxiRideShareFriendsSheetState();
}

class _TaxiRideShareFriendsSheetState
    extends ConsumerState<_TaxiRideShareFriendsSheet> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<_TaxiFriendOption> _friends = const [];
  Set<int> _selectedIds = <int>{};

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
      final socialApi = ref.read(_taxiShareSocialApiProvider);
      final results = await Future.wait([
        socialApi.listUserFriends(userId: widget.currentUserId),
        widget.taxiApi.listRideSharedFriendIds(rideId: widget.rideId),
      ]);

      final friendsResponse = Map<String, dynamic>.from(results[0] as Map);
      final selectedIds = results[1] as List<int>;
      final rawUsers = friendsResponse['users'];
      final friends = <_TaxiFriendOption>[];

      if (rawUsers is List) {
        for (final item in rawUsers.whereType<Map>()) {
          final map = Map<String, dynamic>.from(item);
          final user = map['user'] is Map
              ? Map<String, dynamic>.from(map['user'] as Map)
              : map;
          final id = int.tryParse('${user['id'] ?? ''}');
          final fullName = '${user['fullName'] ?? user['full_name'] ?? ''}'
              .trim();
          if (id == null || id <= 0 || fullName.isEmpty) continue;
          friends.add(
            _TaxiFriendOption(
              id: id,
              fullName: fullName,
              imageUrl:
                  '${user['imageUrl'] ?? user['image_url'] ?? ''}'
                      .trim()
                      .isEmpty
                  ? null
                  : '${user['imageUrl'] ?? user['image_url']}',
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _friends = friends;
        _selectedIds = selectedIds.toSet();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.taxiShareRideFriendsLoadFailed;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.taxiApi.shareRideWithFriends(
        rideId: widget.rideId,
        friendUserIds: _selectedIds.toList()..sort(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.taxiShareRideFriendsSaved)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.l10n.taxiShareRideFriendsSaveFailed;
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.taxiShareRideFriendsTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.taxiShareRideFriendsSubtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: _buildBody(context),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.commonClose),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share_location_rounded),
                  label: Text(l10n.taxiShareRideFriendsSaveAction),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_friends.isEmpty) {
      return Center(child: Text(context.l10n.taxiShareRideFriendsEmpty));
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _friends.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final friend = _friends[index];
        final selected = _selectedIds.contains(friend.id);
        return CheckboxListTile(
          value: selected,
          controlAffinity: ListTileControlAffinity.leading,
          secondary: CircleAvatar(
            backgroundImage: friend.imageUrl != null
                ? AppCachedImageProvider(friend.imageUrl!)
                : null,
            child: friend.imageUrl == null
                ? Text(friend.fullName.substring(0, 1))
                : null,
          ),
          title: Text(friend.fullName),
          subtitle: Text(
            context.l10n.taxiShareRideFriendsId(friend.id.toString()),
          ),
          onChanged: (value) {
            setState(() {
              if (value == true) {
                _selectedIds.add(friend.id);
              } else {
                _selectedIds.remove(friend.id);
              }
            });
          },
        );
      },
    );
  }
}
