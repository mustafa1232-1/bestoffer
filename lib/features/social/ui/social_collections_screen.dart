import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../models/social_models.dart';
import '../state/social_saved_controller.dart';

class SocialCollectionsScreen extends ConsumerStatefulWidget {
  const SocialCollectionsScreen({super.key});

  @override
  ConsumerState<SocialCollectionsScreen> createState() =>
      _SocialCollectionsScreenState();
}

class _SocialCollectionsScreenState
    extends ConsumerState<SocialCollectionsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () =>
          ref.read(socialSavedControllerProvider.notifier).load(refresh: true),
    );
  }

  Future<void> _showCreateSheet({SocialSavedCollection? collection}) async {
    final l10n = context.l10n;
    final titleCtrl = TextEditingController(text: collection?.title ?? '');
    final descriptionCtrl = TextEditingController(
      text: collection?.description ?? '',
    );
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: l10n.socialCollectionsTitleLabel,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descriptionCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.socialCollectionsDescriptionLabel,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                collection == null
                    ? l10n.socialCollectionsCreateCollection
                    : l10n.socialCollectionsSaveChanges,
              ),
            ),
          ],
        ),
      ),
    );
    if (approved != true) return;
    if (collection == null) {
      await ref
          .read(socialSavedControllerProvider.notifier)
          .createCollection(
            title: titleCtrl.text.trim(),
            description: descriptionCtrl.text.trim(),
          );
    } else {
      await ref
          .read(socialSavedControllerProvider.notifier)
          .renameCollection(
            collectionId: collection.id,
            title: titleCtrl.text.trim(),
            description: descriptionCtrl.text.trim(),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(socialSavedControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.socialCollectionsTitle),
        actions: [
          IconButton(
            onPressed: _showCreateSheet,
            icon: const Icon(Icons.add_rounded),
            tooltip: l10n.socialCollectionsCreateCollection,
          ),
        ],
      ),
      body: state.loading && state.collections.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.collections.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (_, index) {
                final collection = state.collections[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    title: Text(
                      collection.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      [
                        if ((collection.description ?? '').trim().isNotEmpty)
                          collection.description!.trim(),
                        l10n.socialCollectionsItemsCount(collection.itemsCount),
                      ].join('\n'),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        switch (value) {
                          case 'edit':
                            await _showCreateSheet(collection: collection);
                            break;
                          case 'delete':
                            await ref
                                .read(socialSavedControllerProvider.notifier)
                                .deleteCollection(collection.id);
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(l10n.commonEdit),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(l10n.commonDelete),
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
