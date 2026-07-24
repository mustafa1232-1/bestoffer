import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_guard.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_content_navigation.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialDiscoveryPeopleScreen extends ConsumerStatefulWidget {
  final List<SocialUserSearchResult> people;
  final String? title;

  const SocialDiscoveryPeopleScreen({
    super.key,
    required this.people,
    this.title,
  });

  @override
  ConsumerState<SocialDiscoveryPeopleScreen> createState() =>
      _SocialDiscoveryPeopleScreenState();
}

class _SocialDiscoveryPeopleScreenState
    extends ConsumerState<SocialDiscoveryPeopleScreen> {
  late List<SocialUserSearchResult> _people;
  final Set<int> _busyUserIds = <int>{};

  @override
  void initState() {
    super.initState();
    _people = widget.people;
  }

  String _relationButtonLabel(SocialRelation relation) {
    final l10n = context.l10n;
    if (relation.isBlocked) return l10n.socialDiscoveryPeopleBlocked;
    if (relation.isAccepted) return l10n.socialDiscoveryPeopleFollowing;
    if (relation.isPendingOutgoing) {
      return l10n.socialDiscoveryPeopleCancelRequest;
    }
    if (relation.isPendingIncoming) return l10n.socialDiscoveryPeopleAccept;
    return l10n.socialDiscoveryPeopleFollow;
  }

  String _relationStatusText(SocialUserSearchResult person) {
    final l10n = context.l10n;
    final username = (person.user.username ?? '').trim();
    if (person.relation.isAccepted) {
      return username.isNotEmpty
          ? '@$username'
          : l10n.socialDiscoveryPeopleAlreadyConnected;
    }
    if (person.relation.isPendingOutgoing) {
      return l10n.socialDiscoveryPeopleWaitingForResponse;
    }
    if (person.relation.isPendingIncoming) {
      return l10n.socialDiscoveryPeopleSentYouRequest;
    }
    if (person.relation.isBlockedByMe) {
      return l10n.socialDiscoveryPeopleYouBlocked;
    }
    if (person.relation.isBlockedByOther) {
      return l10n.socialDiscoveryPeopleBlockedYou;
    }
    return username.isNotEmpty ? '@$username' : person.user.role;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _patchRelation(int userId, SocialRelation relation) {
    setState(() {
      _people = _people
          .map(
            (item) => item.user.id == userId
                ? SocialUserSearchResult(user: item.user, relation: relation)
                : item,
          )
          .toList(growable: false);
    });
  }

  Future<void> _onRelationPressed(SocialUserSearchResult item) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'المتابعة',
      featureEnglish: 'following',
    )) {
      return;
    }
    if (!mounted) return;
    final l10n = context.l10n;
    if (_busyUserIds.contains(item.user.id) || item.relation.isAccepted) return;
    if (item.relation.isBlockedByOther) {
      _snack(l10n.socialDiscoveryPeopleBlockedActionUnavailable);
      return;
    }
    if (item.relation.isBlockedByMe) {
      _snack(l10n.socialDiscoveryPeopleUnblockFirst);
      return;
    }

    setState(() => _busyUserIds.add(item.user.id));
    try {
      final api = ref.read(socialApiProvider);
      late final Map<String, dynamic> out;
      late final String successMessage;

      if (item.relation.isPendingIncoming) {
        out = await api.acceptRelationRequest(item.user.id);
        successMessage = l10n.socialDiscoveryPeopleAccepted;
      } else if (item.relation.isPendingOutgoing) {
        out = await api.cancelRelationRequest(item.user.id);
        successMessage = l10n.socialDiscoveryPeopleCancelled;
      } else {
        out = await api.sendRelationRequest(item.user.id);
        successMessage = l10n.socialDiscoveryPeopleRequestSent;
      }

      final rawRelation = out['relation'];
      if (rawRelation is Map) {
        _patchRelation(
          item.user.id,
          SocialRelation.fromJson(Map<String, dynamic>.from(rawRelation)),
        );
      }
      _snack(successMessage);
    } catch (error) {
      _snack(
        mapAnyError(error, fallback: l10n.socialDiscoveryPeopleActionFailed),
      );
    } finally {
      if (mounted) {
        setState(() => _busyUserIds.remove(item.user.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? l10n.socialDiscoveryPeopleSuggestedTitle),
      ),
      body: _people.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(24, 120, 24, 24),
              children: [
                Icon(
                  Icons.people_alt_outlined,
                  size: 54,
                  color: scheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.socialDiscoveryPeopleEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              itemCount: _people.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final person = _people[index];
                final username = (person.user.username ?? '').trim();
                final busy = _busyUserIds.contains(person.user.id);
                final relation = person.relation;
                final canAct = !relation.isBlocked && !relation.isAccepted;
                return InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    openSocialProfileGuarded(
                      context,
                      userId: person.user.id,
                      initialName: person.user.fullName,
                    );
                  },
                  child: Ink(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundImage:
                              (person.user.imageUrl ?? '').trim().isNotEmpty
                              ? AppCachedImageProvider(person.user.imageUrl!)
                              : null,
                          child: (person.user.imageUrl ?? '').trim().isEmpty
                              ? const Icon(Icons.person_outline)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                person.user.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _relationStatusText(person),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (username.isNotEmpty &&
                                  _relationStatusText(person) !=
                                      '@$username') ...[
                                const SizedBox(height: 2),
                                Text(
                                  '@$username',
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (canAct)
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () => _onRelationPressed(person),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(110, 42),
                            ),
                            child: busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(_relationButtonLabel(relation)),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.34,
                                ),
                              ),
                            ),
                            child: Text(
                              _relationButtonLabel(relation),
                              style: TextStyle(
                                color: relation.isBlocked
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
