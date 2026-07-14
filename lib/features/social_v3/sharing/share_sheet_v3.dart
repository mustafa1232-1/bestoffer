import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'canonical_links.dart';

/// What is being shared.
enum ShareEntityKind { reel, post, story }

/// Immutable descriptor for the share target.
class ShareTargetV3 {
  const ShareTargetV3({
    required this.kind,
    required this.entityId,
    required this.ownerId,
    required this.title,
    this.subtitle,
  });

  final ShareEntityKind kind;
  final int entityId;
  final int ownerId;
  final String title;
  final String? subtitle;
}

/// The unified Social V3 Share Sheet (§9). Fixed option order:
/// 1. Add to Story · 2. recent conversations · 3. search users ·
/// 4. copy link · 5. external share · 6. more.
///
/// External/copy actions only ever emit the **canonical** app URL — never an
/// HLS manifest, R2 key, temporary upload URL, or internal API route.
class ShareSheetV3 extends StatelessWidget {
  const ShareSheetV3({
    super.key,
    required this.target,
    this.links = const SocialCanonicalLinks(),
    this.onAddToStory,
    this.onSendToChat,
    this.onSearchUsers,
    this.onExternalShare,
    this.recentConversations = const [],
    this.onOpenConversation,
  });

  final ShareTargetV3 target;
  final SocialCanonicalLinks links;
  final VoidCallback? onAddToStory;
  final VoidCallback? onSendToChat;
  final VoidCallback? onSearchUsers;

  /// Receives the guarded canonical URL for OS-level share.
  final void Function(String canonicalUrl)? onExternalShare;
  final List<String> recentConversations;
  final void Function(String conversation)? onOpenConversation;

  String get canonicalUrl {
    switch (target.kind) {
      case ShareEntityKind.reel:
        return links.reel(target.entityId);
      case ShareEntityKind.post:
        return links.post(target.entityId);
      case ShareEntityKind.story:
        return links.story(target.ownerId, target.entityId);
    }
  }

  static Future<void> show(
    BuildContext context, {
    required ShareTargetV3 target,
    SocialCanonicalLinks links = const SocialCanonicalLinks(),
    VoidCallback? onAddToStory,
    void Function(String canonicalUrl)? onExternalShare,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D1B2A),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ShareSheetV3(
        target: target,
        links: links,
        onAddToStory: onAddToStory,
        onExternalShare: onExternalShare,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Row(
            icon: Icons.add_circle_outline,
            label: 'إضافة إلى القصة',
            onTap: onAddToStory,
          ),
          if (recentConversations.isNotEmpty)
            SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final name in recentConversations)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: ActionChip(
                        label: Text(name),
                        onPressed: () => onOpenConversation?.call(name),
                      ),
                    ),
                ],
              ),
            ),
          _Row(
            icon: Icons.search,
            label: 'بحث عن مستخدمين',
            onTap: onSearchUsers,
          ),
          _Row(
            icon: Icons.link,
            label: 'نسخ الرابط',
            onTap: () {
              final safe = links.guardShareUrl(canonicalUrl);
              Clipboard.setData(ClipboardData(text: safe));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ الرابط')),
              );
            },
          ),
          _Row(
            icon: Icons.ios_share,
            label: 'مشاركة خارجية',
            onTap: () => onExternalShare?.call(links.guardShareUrl(canonicalUrl)),
          ),
          _Row(
            icon: Icons.more_horiz,
            label: 'المزيد',
            onTap: onSendToChat,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }
}
