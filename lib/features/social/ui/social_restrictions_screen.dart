import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';

class SocialRestrictionsScreen extends ConsumerStatefulWidget {
  final int? initialRestrictionId;
  final String? initialCapabilityKey;
  final String? initialReason;
  final String? initialStartsAt;
  final String? initialEndsAt;

  const SocialRestrictionsScreen({
    super.key,
    this.initialRestrictionId,
    this.initialCapabilityKey,
    this.initialReason,
    this.initialStartsAt,
    this.initialEndsAt,
  });

  @override
  ConsumerState<SocialRestrictionsScreen> createState() =>
      _SocialRestrictionsScreenState();
}

class _SocialRestrictionsScreenState
    extends ConsumerState<SocialRestrictionsScreen> {
  bool _loading = true;
  String? _error;
  List<SocialCapabilityRestrictionItem> _items =
      const <SocialCapabilityRestrictionItem>[];

  SocialApi get _api => ref.read(socialApiProvider);

  bool get _hasInitialNotice =>
      (widget.initialCapabilityKey ?? '').trim().isNotEmpty ||
      (widget.initialReason ?? '').trim().isNotEmpty ||
      (widget.initialStartsAt ?? '').trim().isNotEmpty ||
      (widget.initialEndsAt ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await _api.getMyActiveSocialRestrictions();
      final raw = List<dynamic>.from(out['items'] as List? ?? const []);
      final items = raw
          .whereType<Map>()
          .map(
            (item) => SocialCapabilityRestrictionItem.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialRestrictionsLoadFailed,
        );
      });
    }
  }

  String _capabilityLabel(String capabilityKey) {
    final l10n = context.l10n;
    switch (capabilityKey.trim().toLowerCase()) {
      case 'story_create':
        return l10n.socialRestrictionsCapabilityStory;
      case 'reel_create':
        return l10n.socialRestrictionsCapabilityReel;
      case 'comment_create':
        return l10n.socialRestrictionsCapabilityComments;
      case 'community_post_create':
        return l10n.socialRestrictionsCapabilityCommunity;
      default:
        return l10n.socialRestrictionsCapabilityRegular;
    }
  }

  DateTime? _parseDate(String? raw) {
    if ((raw ?? '').trim().isEmpty) return null;
    return DateTime.tryParse(raw!.trim());
  }

  String _dateText(DateTime? value) {
    if (value == null) return context.l10n.commonNotSet;
    final local = value.toLocal();
    final date =
        '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date  $time';
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: context.appTextDirection,
        children: [
          Expanded(
            child: Text(
              value,
              textDirection: context.appTextDirection,
              textAlign: context.isEnglishLocale
                  ? TextAlign.left
                  : TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$label:',
            textDirection: context.appTextDirection,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticeCard() {
    final l10n = context.l10n;
    final capabilityKey = widget.initialCapabilityKey;
    final reason = (widget.initialReason ?? '').trim();
    final startsAt = _parseDate(widget.initialStartsAt);
    final endsAt = _parseDate(widget.initialEndsAt);
    return Card(
      color: const Color(0xFF4B1117),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              l10n.socialRestrictionsLatestNoticeTitle,
              textDirection: context.appTextDirection,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 10),
            if ((capabilityKey ?? '').trim().isNotEmpty)
              _detailRow(
                l10n.socialRestrictionsCapabilityLabel,
                _capabilityLabel(capabilityKey!),
              ),
            if (reason.isNotEmpty)
              _detailRow(l10n.socialRestrictionsReasonLabel, reason),
            if (startsAt != null)
              _detailRow(
                l10n.socialRestrictionsStartLabel,
                _dateText(startsAt),
              ),
            _detailRow(
              l10n.socialRestrictionsEndsAtLabel,
              endsAt == null
                  ? l10n.socialRestrictionsUntilFurtherNotice
                  : _dateText(endsAt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _restrictionCard(SocialCapabilityRestrictionItem item) {
    final l10n = context.l10n;
    final isHighlighted =
        widget.initialRestrictionId != null &&
        widget.initialRestrictionId == item.id;
    return Card(
      color: isHighlighted ? const Color(0xFF4B1117) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              textDirection: context.appTextDirection,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    l10n.socialRestrictionsActiveChip,
                    style: const TextStyle(
                      color: Color(0xFFFFB4B4),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '#${item.id}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _detailRow(
              l10n.socialRestrictionsCapabilityLabel,
              _capabilityLabel(item.capabilityKey),
            ),
            _detailRow(
              l10n.socialRestrictionsReasonLabel,
              (item.reason ?? '').trim().isEmpty
                  ? l10n.socialRestrictionsNoAdditionalNote
                  : item.reason!.trim(),
            ),
            _detailRow(
              l10n.socialRestrictionsStartLabel,
              _dateText(item.startsAt),
            ),
            _detailRow(
              l10n.socialRestrictionsEndsAtLabel,
              item.endsAt == null
                  ? l10n.socialRestrictionsUntilFurtherNotice
                  : _dateText(item.endsAt),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Directionality(
      textDirection: context.appTextDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.socialRestrictionsTitle),
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: l10n.commonRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.socialRestrictionsIntro,
                    textDirection: context.appTextDirection,
                    textAlign: context.isEnglishLocale
                        ? TextAlign.left
                        : TextAlign.right,
                  ),
                ),
              ),
              if (_hasInitialNotice) ...[
                const SizedBox(height: 12),
                _noticeCard(),
              ],
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      textDirection: context.appTextDirection,
                      textAlign: context.isEnglishLocale
                          ? TextAlign.left
                          : TextAlign.right,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                )
              else if (_items.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l10n.socialRestrictionsEmpty,
                      textDirection: context.appTextDirection,
                      textAlign: context.isEnglishLocale
                          ? TextAlign.left
                          : TextAlign.right,
                    ),
                  ),
                )
              else
                ..._items.map(_restrictionCard),
            ],
          ),
        ),
      ),
    );
  }
}
