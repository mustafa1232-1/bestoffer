import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../state/social_saved_controller.dart';

class SocialSaveSheet extends ConsumerStatefulWidget {
  const SocialSaveSheet({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.initiallySaved,
  });

  final String entityType;
  final int entityId;
  final bool initiallySaved;

  @override
  ConsumerState<SocialSaveSheet> createState() => _SocialSaveSheetState();
}

class _SocialSaveSheetState extends ConsumerState<SocialSaveSheet> {
  final Set<int> _selectedCollectionIds = <int>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () =>
          ref.read(socialSavedControllerProvider.notifier).load(refresh: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(socialSavedControllerProvider);
    final collections = state.collections;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.socialSaveSheetTitle,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.socialSaveSheetBody,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (state.loading && collections.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: collections
                    .map(
                      (collection) => FilterChip(
                        selected: _selectedCollectionIds.contains(
                          collection.id,
                        ),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedCollectionIds.add(collection.id);
                            } else {
                              _selectedCollectionIds.remove(collection.id);
                            }
                          });
                        },
                        label: Text(
                          '${collection.title} (${collection.itemsCount})',
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: state.mutating
                  ? null
                  : () async {
                      final saved = await ref
                          .read(socialSavedControllerProvider.notifier)
                          .toggleSaved(
                            entityType: widget.entityType,
                            entityId: widget.entityId,
                            collectionIds: _selectedCollectionIds.toList(
                              growable: false,
                            ),
                          );
                      if (!context.mounted) return;
                      Navigator.of(context).pop(saved);
                    },
              icon: Icon(
                widget.initiallySaved
                    ? Icons.bookmark_remove_outlined
                    : Icons.bookmark_add_outlined,
              ),
              label: Text(
                widget.initiallySaved
                    ? l10n.socialSaveSheetUpdate
                    : l10n.socialSaveSheetSaveNow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
