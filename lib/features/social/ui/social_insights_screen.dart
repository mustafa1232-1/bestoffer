import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../state/social_profile_insights_controller.dart';
import 'widgets/social_post_card_v2.dart';

class SocialInsightsScreen extends ConsumerWidget {
  final int userId;
  final String? title;

  const SocialInsightsScreen({super.key, required this.userId, this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final insightsAsync = ref.watch(socialProfileInsightsProvider(userId));

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(title: Text(title ?? l10n.socialProfileInsights)),
        body: insightsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insights_outlined, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    mapAnyError(error, fallback: l10n.commonUnexpectedError),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () =>
                        ref.invalidate(socialProfileInsightsProvider(userId)),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l10n.commonRetry),
                  ),
                ],
              ),
            ),
          ),
          data: (insights) {
            final summary = insights.summary;
            final cards = <_InsightCardData>[
              _InsightCardData(
                label: l10n.socialInsightsImpressions,
                value: '${summary['impressionsCount'] ?? 0}',
                icon: Icons.visibility_outlined,
              ),
              _InsightCardData(
                label: l10n.socialInsightsLikes,
                value: '${summary['likesCount'] ?? 0}',
                icon: Icons.favorite_border_rounded,
              ),
              _InsightCardData(
                label: l10n.socialInsightsComments,
                value: '${summary['commentsCount'] ?? 0}',
                icon: Icons.mode_comment_outlined,
              ),
              _InsightCardData(
                label: l10n.socialInsightsSaves,
                value: '${summary['savesCount'] ?? 0}',
                icon: Icons.bookmark_outline_rounded,
              ),
              _InsightCardData(
                label: l10n.socialInsightsReelViews,
                value: '${summary['reelViewsCount'] ?? 0}',
                icon: Icons.ondemand_video_outlined,
              ),
              _InsightCardData(
                label: l10n.socialInsightsCompletion,
                value:
                    '${(((summary['averageCompletionRate'] ?? 0) as num).toDouble() * 100).toStringAsFixed(0)}%',
                icon: Icons.track_changes_outlined,
              ),
            ];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cards
                      .map((card) => _InsightCard(data: card))
                      .toList(growable: false),
                ),
                const SizedBox(height: 18),
                _SectionTitle(title: l10n.socialInsightsBestPostingTimes),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: insights.bestPostingTimes
                      .map(
                        (row) => Chip(
                          label: Text(
                            l10n.socialInsightsPostingHourSummary(
                              _asInt(row['hourOfDay']),
                              _asInt(row['postsCount']),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 18),
                _SectionTitle(title: l10n.socialInsightsAudienceLocality),
                const SizedBox(height: 8),
                ...insights.audienceLocality.map(
                  (row) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(
                      [
                        if ('${row['building'] ?? ''}'.trim().isNotEmpty)
                          '${row['building']}',
                        if ('${row['compound'] ?? ''}'.trim().isNotEmpty)
                          '${row['compound']}',
                        if ('${row['block'] ?? ''}'.trim().isNotEmpty)
                          '${row['block']}',
                      ].join(' - '),
                    ),
                    trailing: Text('${row['impressionsCount'] ?? 0}'),
                  ),
                ),
                const SizedBox(height: 18),
                _SectionTitle(title: l10n.socialInsightsTopContent),
                const SizedBox(height: 8),
                ...insights.topContent.map(
                  (post) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SocialPostCardV2(post: post),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InsightCardData {
  final String label;
  final String value;
  final IconData icon;

  const _InsightCardData({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class _InsightCard extends StatelessWidget {
  final _InsightCardData data;

  const _InsightCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 44) / 2;
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon),
          const SizedBox(height: 12),
          Text(
            data.value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            data.label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}
