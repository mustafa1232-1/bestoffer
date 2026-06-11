import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/utils/currency.dart';
import '../../models/merchant_payment_selection_preview_model.dart';

class MerchantAutoMatchSuggestionSheet extends StatelessWidget {
  final MerchantPaymentSelectionPreviewModel preview;

  const MerchantAutoMatchSuggestionSheet({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lower = preview.nearestLowerAmount;
    final higher = preview.nearestHigherAmount;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.merchantAutoMatchSuggestionTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(preview.message),
            const SizedBox(height: 12),
            if (higher > 0)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                tileColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                title: Text(l10n.merchantAutoMatchSuggestionUseHigher),
                subtitle: Text(formatIqd(higher)),
                trailing: const Icon(Icons.arrow_upward_rounded),
                onTap: () => Navigator.of(context).pop(higher),
              ),
            if (higher > 0 && lower > 0) const SizedBox(height: 8),
            if (lower > 0)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                tileColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                title: Text(l10n.merchantAutoMatchSuggestionUseLower),
                subtitle: Text(formatIqd(lower)),
                trailing: const Icon(Icons.arrow_downward_rounded),
                onTap: () => Navigator.of(context).pop(lower),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
          ],
        ),
      ),
    );
  }
}
