import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/media/media_cache_service.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/platform/app_platform_capabilities.dart';
import '../../paid_upgrades/state/paid_upgrades_summary_provider.dart';
import '../../paid_upgrades/ui/paid_upgrades_home_screen.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import '../state/social_saved_controller.dart';
import 'social_call_screen.dart';
import 'social_chat_thread_screen.dart';
import 'social_profile_archive_screen.dart';
import 'social_insights_screen.dart';
import 'social_profile_account_management_screen.dart';
import 'social_profile_activity_screen.dart';
import 'social_profile_admin_actions_screen.dart';
import 'social_profile_posts_screen.dart';
import 'social_premium_membership_screen.dart';
import 'social_activity_screen.dart';
import 'social_content_navigation.dart';
import 'social_relation_requests_screen.dart';
import 'social_reported_posts_screen.dart';
import 'social_residence_change_screen.dart';
import 'social_saved_screen.dart';
import 'social_story_quick_viewer.dart';
import 'social_story_archive_screen.dart';
import 'social_tagged_posts_screen.dart';
import 'social_user_connections_screen.dart';
import 'widgets/social_identity_view.dart';
import 'widgets/social_post_card_v2.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

/// Purpose: شاشة الملف الشخصي الاجتماعي مع tabs للمحتوى والعلاقات والهايلايت وإجراءات المتابعة/الحظر.
/// Used by: feed، المحادثات، mention routes، والبحث داخل المجتمع.
/// Depends on: `SocialApi`, `socialControllerProvider`, وواجهات relation/chat/call/insights الفرعية.
/// Critical notes: الشاشة تدير أكثر من مصدر حالة محلياً لتفادي إعادة تحميل كل شيء عند تبديل tab أو pagination.
/// Maintenance notes: إذا ظهرت profile data قديمة أو ناقصة افحص `getUserProfile`, ثم loaders المحلية `_loadProfile/_loadPosts/_loadHighlights`.
/// شاشة الملف الشخصي العامة أو الذاتية في مجتمع التطبيق.
class SocialProfileScreen extends ConsumerStatefulWidget {
  final int userId;
  final String? initialName;

  const SocialProfileScreen({
    super.key,
    required this.userId,
    this.initialName,
  });

  @override
  ConsumerState<SocialProfileScreen> createState() =>
      _SocialProfileScreenState();
}

enum _ProfileContentTab { posts, reels, saved, reviews, tagged }

class _SocialProfileScreenState extends ConsumerState<SocialProfileScreen> {
  late final SocialApi _api;

  final Map<String, List<SocialPost>> _postsByKey = <String, List<SocialPost>>{
    _allPostsKey: <SocialPost>[],
  };
  final Map<String, int?> _nextCursorByKey = <String, int?>{};
  final Map<String, bool> _loadingByKey = <String, bool>{};

  SocialUserProfile? _profile;
  List<SocialStoryHighlight> _highlights = <SocialStoryHighlight>[];

  bool _loadingProfile = false;
  bool _loadingHighlights = false;
  bool _postsPrivateForViewer = false;
  bool _storiesPrivateForViewer = false;
  String? _error;
  bool _relationBusy = false;
  _ProfileContentTab _selectedTab = _ProfileContentTab.posts;

  /// يطلق تحميل الملف، الهايلايت، وأول دفعة منشورات بالتوازي لأن الشاشة تعتمد عليها كلها.
  @override
  void initState() {
    super.initState();
    _api = ref.read(socialApiProvider);
    Future.microtask(_bootstrap);
  }

  /// نقطة bootstrap الموحدة للشاشة عند أول فتح أو عند الحاجة لإعادة التهيئة الكاملة.
  Future<void> _bootstrap() async {
    await Future.wait([
      _loadProfile(),
      _loadHighlights(),
      _loadPosts(kind: null, refresh: true),
    ]);
  }

  String _keyOfKind(String? kind) => kind ?? _allPostsKey;

  List<SocialPost> _postsForKind(String? kind) {
    final key = _keyOfKind(kind);
    return _postsByKey[key] ?? const <SocialPost>[];
  }

  bool _isLoadingKind(String? kind) => _loadingByKey[_keyOfKind(kind)] == true;

  /// يجلب بطاقة الملف الشخصي الأساسية ويعيد ضبط رسالة الخطأ المحلية.
  ///
  /// إذا فشل هذا المسار بينما تنجح بقية loaders فغالباً الخلل في route الملف
  /// نفسه أو ownership/visibility checks داخل الباكند.
  Future<void> _loadProfile() async {
    setState(() {
      _loadingProfile = true;
      _error = null;
    });
    try {
      final out = await _api.getUserProfile(widget.userId);
      final raw = out['profile'];
      if (!mounted) return;
      if (raw is Map) {
        setState(() {
          _profile = SocialUserProfile.fromJson(Map<String, dynamic>.from(raw));
          _loadingProfile = false;
        });
      } else {
        setState(() {
          _loadingProfile = false;
          _error = 'تعذر تحميل الملف الشخصي.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _error = mapAnyError(e, fallback: 'تعذر تحميل الملف الشخصي.');
      });
    }
  }

  /// يجلب highlights مع مراعاة الخصوصية؛ وعند كونها خاصة يعرض حالة خالية مقصودة.
  Future<void> _loadHighlights() async {
    setState(() {
      _loadingHighlights = true;
      _error = null;
    });
    try {
      final out = await _api.listUserHighlights(widget.userId);
      final storiesPrivate = _parseBool(
        out['storiesPrivate'] ?? out['stories_private'],
      );
      final raw = List<dynamic>.from(out['highlights'] as List? ?? const []);
      final next = raw
          .map(
            (e) => SocialStoryHighlight.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _storiesPrivateForViewer = storiesPrivate;
        _highlights = storiesPrivate ? const <SocialStoryHighlight>[] : next;
        _loadingHighlights = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingHighlights = false;
        _error = mapAnyError(e, fallback: 'تعذر تحميل الهايلايت.');
      });
    }
  }

  /// يجلب منشورات نوع معين مع pagination ودمج dedupe حسب المعرف.
  ///
  /// الدمج حسب `post.id` مقصود لتفادي تكرار العناصر عندما تتقاطع نتائج
  /// refresh مع scroll pagination أو عندما يرجع الباكند نفس post في أكثر من نافذة.
  Future<void> _loadPosts({required String? kind, bool refresh = false}) async {
    final key = _keyOfKind(kind);
    if (_isLoadingKind(kind)) return;

    final beforeId = refresh ? null : _nextCursorByKey[key];
    if (!refresh && beforeId == null) return;

    setState(() {
      _loadingByKey[key] = true;
      _error = null;
    });

    try {
      final out = await _api.listUserPosts(
        userId: widget.userId,
        kind: kind,
        limit: 24,
        beforeId: beforeId,
      );
      final postsPrivate = _parseBool(
        out['postsPrivate'] ?? out['posts_private'],
      );
      final raw = List<dynamic>.from(out['posts'] as List? ?? const []);
      final fetched = raw
          .map((e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
      if (!mounted) return;

      final previous = refresh
          ? const <SocialPost>[]
          : (_postsByKey[key] ?? const <SocialPost>[]);
      final mergedById = <int, SocialPost>{};
      for (final post in previous) {
        mergedById[post.id] = post;
      }
      for (final post in fetched) {
        mergedById[post.id] = post;
      }
      final merged = mergedById.values.toList(growable: false)
        ..sort((a, b) => b.id.compareTo(a.id));

      setState(() {
        _postsPrivateForViewer = postsPrivate;
        _postsByKey[key] = merged;
        _nextCursorByKey[key] = _parseInt(out['nextCursor']);
        _loadingByKey[key] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingByKey[key] = false;
        _error = mapAnyError(e, fallback: 'تعذر تحميل منشورات المستخدم.');
      });
    }
  }

  /// يعيد تحميل كل المقاطع المفتوحة حالياً، وليس tab واحداً فقط.
  ///
  /// هذا يحافظ على اتساق counts والـ grids بعد أي إجراء علاقة أو تعديل محتوى.
  Future<void> _refreshAll() async {
    final loadedKinds = _postsByKey.keys
        .where((key) => key != _allPostsKey)
        .map((key) => key)
        .toList(growable: false);
    await Future.wait([
      _loadProfile(),
      _loadHighlights(),
      _loadPosts(kind: null, refresh: true),
      ...loadedKinds.map(
        (key) =>
            _loadPosts(kind: key == _allPostsKey ? null : key, refresh: true),
      ),
    ]);
  }

  /// يبني نسخة profile جديدة بعد تغيير relation بدون انتظار round-trip كامل للواجهة.
  SocialUserProfile _copyProfileWithRelation(
    SocialUserProfile profile,
    SocialRelation relation,
  ) {
    return SocialUserProfile(
      id: profile.id,
      username: profile.username,
      fullName: profile.fullName,
      role: profile.role,
      isSuperAdmin: profile.isSuperAdmin,
      accountDisabled: profile.accountDisabled,
      viewerIsSuperAdmin: profile.viewerIsSuperAdmin,
      bio: profile.bio,
      workTitle: profile.workTitle,
      workCompany: profile.workCompany,
      age: profile.age,
      imageUrl: profile.imageUrl,
      phone: profile.phone,
      showPhone: profile.showPhone,
      postsPublic: profile.postsPublic,
      storiesPublic: profile.storiesPublic,
      relationsPublic: profile.relationsPublic,
      accountPrivate: profile.accountPrivate,
      contentPrivate: profile.contentPrivate,
      onlineStatusVisibility: profile.onlineStatusVisibility,
      lastSeenVisibility: profile.lastSeenVisibility,
      readReceiptsEnabled: profile.readReceiptsEnabled,
      typingIndicatorsEnabled: profile.typingIndicatorsEnabled,
      coreProfileLockedUntil: profile.coreProfileLockedUntil,
      localContext: profile.localContext,
      localContextMeta: profile.localContextMeta,
      accountLabelKey: profile.accountLabelKey,
      badges: profile.badges,
      isResidentVerified: profile.isResidentVerified,
      isMerchantVerified: profile.isMerchantVerified,
      isPremiumMember: profile.isPremiumMember,
      isCarSeller: profile.isCarSeller,
      isPropertySeller: profile.isPropertySeller,
      premiumBadgeVisible: profile.premiumBadgeVisible,
      tabs: profile.tabs,
      joinedAt: profile.joinedAt,
      isMe: profile.isMe,
      notificationPreference: profile.notificationPreference,
      superAdminControls: profile.superAdminControls,
      relation: relation,
      stats: profile.stats,
    );
  }

  /// يشغل إجراء relation موحداً مع optimistic-ish refresh ورسالة نجاح/فشل متسقة.
  Future<void> _runRelationAction(
    Future<Map<String, dynamic>> Function() action, {
    required String successMessage,
  }) async {
    final profile = _profile;
    if (profile == null || profile.isMe || _relationBusy) return;

    setState(() {
      _relationBusy = true;
      _error = null;
    });

    try {
      final out = await action();
      final rawRelation = out['relation'];
      if (!mounted) return;
      if (rawRelation is Map && _profile != null) {
        final relation = SocialRelation.fromJson(
          Map<String, dynamic>.from(rawRelation),
        );
        setState(() {
          _profile = _copyProfileWithRelation(_profile!, relation);
        });
      }
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapAnyError(e, fallback: 'تعذر تنفيذ الإجراء حالياً.')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _relationBusy = false);
      }
    }
  }

  Future<void> _sendRelationRequest() async {
    await _runRelationAction(
      () => _api.sendRelationRequest(widget.userId),
      successMessage: 'تم إرسال طلب المتابعة',
    );
  }

  Future<void> _acceptRelationRequest() async {
    await _runRelationAction(
      () => _api.acceptRelationRequest(widget.userId),
      successMessage: 'تم قبول طلب المتابعة',
    );
    await ref.read(socialControllerProvider.notifier).loadThreads();
  }

  Future<void> _cancelRelationRequest() async {
    await _runRelationAction(
      () => _api.cancelRelationRequest(widget.userId),
      successMessage: 'تم إلغاء الطلب',
    );
  }

  Future<void> _removeRelation() async {
    await _runRelationAction(
      () => _api.removeRelation(widget.userId),
      successMessage: 'تم إلغاء المتابعة',
    );
  }

  Future<void> _blockRelation() async {
    await _runRelationAction(
      () => _api.blockRelation(widget.userId),
      successMessage: 'تم حظر هذا المستخدم',
    );
  }

  Future<void> _unblockRelation() async {
    await _runRelationAction(
      () => _api.unblockRelation(widget.userId),
      successMessage: 'تم فك الحظر',
    );
  }

  Future<void> _setNotificationPreference(bool enabled) async {
    final profile = _profile;
    if (profile == null || profile.isMe || _relationBusy) return;

    setState(() {
      _relationBusy = true;
      _error = null;
    });
    try {
      final out = await _api.setUserNotificationPreference(
        userId: widget.userId,
        enabled: enabled,
      );
      final raw =
          out['notificationPreference'] ?? out['notification_preference'];
      if (raw is Map && mounted && _profile != null) {
        final nextPref = SocialUserNotificationPreference.fromJson(
          Map<String, dynamic>.from(raw),
        );
        setState(() {
          _profile = SocialUserProfile(
            id: _profile!.id,
            username: _profile!.username,
            fullName: _profile!.fullName,
            role: _profile!.role,
            isSuperAdmin: _profile!.isSuperAdmin,
            accountDisabled: _profile!.accountDisabled,
            viewerIsSuperAdmin: _profile!.viewerIsSuperAdmin,
            bio: _profile!.bio,
            workTitle: _profile!.workTitle,
            workCompany: _profile!.workCompany,
            age: _profile!.age,
            imageUrl: _profile!.imageUrl,
            phone: _profile!.phone,
            showPhone: _profile!.showPhone,
            postsPublic: _profile!.postsPublic,
            storiesPublic: _profile!.storiesPublic,
            relationsPublic: _profile!.relationsPublic,
            accountPrivate: _profile!.accountPrivate,
            contentPrivate: _profile!.contentPrivate,
            onlineStatusVisibility: _profile!.onlineStatusVisibility,
            lastSeenVisibility: _profile!.lastSeenVisibility,
            readReceiptsEnabled: _profile!.readReceiptsEnabled,
            typingIndicatorsEnabled: _profile!.typingIndicatorsEnabled,
            coreProfileLockedUntil: _profile!.coreProfileLockedUntil,
            localContext: _profile!.localContext,
            localContextMeta: _profile!.localContextMeta,
            accountLabelKey: _profile!.accountLabelKey,
            badges: _profile!.badges,
            isResidentVerified: _profile!.isResidentVerified,
            isMerchantVerified: _profile!.isMerchantVerified,
            isPremiumMember: _profile!.isPremiumMember,
            isCarSeller: _profile!.isCarSeller,
            isPropertySeller: _profile!.isPropertySeller,
            premiumBadgeVisible: _profile!.premiumBadgeVisible,
            tabs: _profile!.tabs,
            joinedAt: _profile!.joinedAt,
            isMe: _profile!.isMe,
            notificationPreference: nextPref,
            superAdminControls: _profile!.superAdminControls,
            relation: _profile!.relation,
            stats: _profile!.stats,
          );
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'تم تفعيل إشعارات هذا المستخدم'
                : 'تم إيقاف إشعارات هذا المستخدم',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: 'تعذر تحديث تفضيل الإشعارات.'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _relationBusy = false);
      }
    }
  }

  Future<void> _runSuperAdminAction({
    required String action,
    required String successMessage,
  }) async {
    final profile = _profile;
    if (profile == null || profile.isMe || _relationBusy) return;

    setState(() {
      _relationBusy = true;
      _error = null;
    });
    try {
      await _api.runSuperAdminUserAction(userId: widget.userId, action: action);
      if (!mounted) return;
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapAnyError(e, fallback: 'تعذر تنفيذ أمر الأدمن.')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _relationBusy = false);
      }
    }
  }

  Future<void> _openChatWithUser() async {
    final profile = _profile;
    if (profile == null || profile.isMe) return;

    final thread = await ref
        .read(socialControllerProvider.notifier)
        .createThreadWithUser(profile.id);
    if (thread == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialChatThreadScreen(
          threadId: thread.id,
          peerName: socialPrimaryIdentityLabel(
            SocialAuthor(
              id: profile.id,
              username: profile.username,
              fullName: profile.fullName,
              imageUrl: profile.imageUrl,
              phone: profile.phone,
              role: profile.role,
              badges: profile.badges,
              isResidentVerified: profile.isResidentVerified,
              isMerchantVerified: profile.isMerchantVerified,
              isPremiumCreator:
                  profile.isPremiumMember && profile.premiumBadgeVisible,
            ),
          ),
          peerPhone: thread.peerPhone,
          peerUserId: profile.id,
          peerImageUrl: (thread.peer.imageUrl ?? '').trim().isNotEmpty
              ? thread.peer.imageUrl
              : profile.imageUrl,
        ),
      ),
    );
  }

  Future<void> _openInAppCall() async {
    final profile = _profile;
    if (profile == null || profile.isMe) return;

    final thread = await ref
        .read(socialControllerProvider.notifier)
        .createThreadWithUser(profile.id);
    if (thread == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialCallScreen(
          threadId: thread.id,
          isCaller: true,
          remoteDisplayName: (profile.username ?? '').trim().isNotEmpty
              ? '@${profile.username!.trim()}'
              : profile.fullName,
        ),
      ),
    );
  }

  Future<void> _confirmRemoveRelation({
    required String title,
    required String content,
    required String confirmLabel,
  }) async {
    if (!mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (approved == true) {
      await _removeRelation();
    }
  }

  Future<void> _onFollowPressed() async {
    final profile = _profile;
    if (profile == null || profile.isMe || _relationBusy) return;
    final relation = profile.relation;
    if (relation.isBlocked) return;

    if (relation.isAccepted) {
      await _confirmRemoveRelation(
        title: 'إلغاء المتابعة',
        content: 'سيتم إلغاء المتابعة وحالة الصداقة الحالية.',
        confirmLabel: 'إلغاء المتابعة',
      );
      return;
    }
    if (relation.isPendingOutgoing) {
      await _cancelRelationRequest();
      return;
    }
    if (relation.isPendingIncoming) {
      await _acceptRelationRequest();
      return;
    }
    await _sendRelationRequest();
  }

  String _followButtonLabel(SocialRelation relation) {
    if (relation.isAccepted) {
      return 'متابع';
    }
    if (relation.isPendingOutgoing) {
      return 'متابعة قيد الانتظار';
    }
    if (relation.isPendingIncoming) {
      return 'قبول المتابعة';
    }
    return 'متابعة';
  }

  Widget _buildSuperAdminActions(SocialUserProfile profile) {
    final controls = profile.superAdminControls;
    if (controls == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
          ),
          child: Text(
            controls.accountDisabled
                ? 'الحساب معطل حالياً'
                : 'الحساب مفعل حالياً',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _relationBusy
                  ? null
                  : () => _runSuperAdminAction(
                      action: controls.accountDisabled
                          ? 'enable_account'
                          : 'disable_account',
                      successMessage: controls.accountDisabled
                          ? 'تم تفعيل الحساب'
                          : 'تم تعطيل الحساب',
                    ),
              icon: Icon(
                controls.accountDisabled
                    ? Icons.lock_open_rounded
                    : Icons.block_rounded,
              ),
              label: Text(
                controls.accountDisabled ? 'تفعيل الحساب' : 'تعطيل الحساب',
              ),
            ),
            if (!controls.targetIsSuperAdmin && profile.role != 'admin')
              FilledButton.tonalIcon(
                onPressed: _relationBusy
                    ? null
                    : () => _runSuperAdminAction(
                        action: 'promote_admin',
                        successMessage: 'تمت ترقية المستخدم إلى أدمن',
                      ),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('ترقية إلى أدمن'),
              ),
            if (!controls.targetIsSuperAdmin && profile.role != 'user')
              OutlinedButton.icon(
                onPressed: _relationBusy
                    ? null
                    : () => _runSuperAdminAction(
                        action: 'demote_user',
                        successMessage: 'تمت إعادة الدور إلى مستخدم',
                      ),
                icon: const Icon(Icons.person_outline_rounded),
                label: const Text('إرجاع إلى مستخدم'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if ((controls.blockCode ?? '').isNotEmpty)
          OutlinedButton.icon(
            onPressed: _relationBusy
                ? null
                : () => _runSuperAdminAction(
                    action: controls.isBlockManager
                        ? 'revoke_block_manager'
                        : 'grant_block_manager',
                    successMessage: controls.isBlockManager
                        ? 'تمت إزالة إدارة البلوك'
                        : 'تمت ترقية مدير البلوك',
                  ),
            icon: const Icon(Icons.account_tree_outlined),
            label: Text(
              controls.isBlockManager
                  ? 'إزالة مدير البلوك (${controls.blockCode})'
                  : 'ترقية مدير البلوك (${controls.blockCode})',
            ),
          ),
        if ((controls.compoundCode ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _relationBusy
                ? null
                : () => _runSuperAdminAction(
                    action: controls.isCompoundManager
                        ? 'revoke_compound_manager'
                        : 'grant_compound_manager',
                    successMessage: controls.isCompoundManager
                        ? 'تمت إزالة إدارة المجمع'
                        : 'تمت ترقية مدير المجمع',
                  ),
            icon: const Icon(Icons.groups_2_outlined),
            label: Text(
              controls.isCompoundManager
                  ? 'إزالة مدير المجمع (${controls.compoundCode})'
                  : 'ترقية مدير المجمع (${controls.compoundCode})',
            ),
          ),
        ],
        if ((controls.buildingCode ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _relationBusy
                ? null
                : () => _runSuperAdminAction(
                    action: controls.isBuildingManager
                        ? 'revoke_building_manager'
                        : 'grant_building_manager',
                    successMessage: controls.isBuildingManager
                        ? 'تمت إزالة إدارة العمارة'
                        : 'تمت ترقية مدير العمارة',
                  ),
            icon: const Icon(Icons.apartment_rounded),
            label: Text(
              controls.isBuildingManager
                  ? 'إزالة مدير العمارة (${controls.buildingCode})'
                  : 'ترقية مدير العمارة (${controls.buildingCode})',
            ),
          ),
        ],
      ],
    );
  }

  String _relationStatusText(SocialRelation relation) {
    final profile = _profile;
    if (profile != null &&
        !profile.isMe &&
        profile.viewerIsSuperAdmin &&
        profile.superAdminControls != null) {
      return 'وضع إدارة السوبر أدمن';
    }
    if (relation.isBlockedByMe) {
      return 'هذا الحساب محظور من طرفك';
    }
    if (relation.isBlockedByOther) {
      return 'هذا الحساب قام بحظرك';
    }
    if (relation.isAccepted) {
      return 'صديقك ومتابع لك';
    }
    if (relation.isPendingIncoming) {
      return 'أرسل لك طلب صداقة/متابعة';
    }
    if (relation.isPendingOutgoing) {
      return 'طلب الصداقة بانتظار الرد';
    }
    return 'غير متابع';
  }

  Future<void> _openProfileContent(
    SocialPost post, {
    List<SocialPost>? contextPosts,
  }) async {
    await openSocialContent(
      context,
      post: post,
      reelContextPosts: contextPosts,
    );
  }

  Future<void> _openAvatarStoryOrImage() async {
    final profile = _profile;
    if (profile == null) return;

    var stories = ref.read(socialControllerProvider).stories;
    if (stories.isEmpty) {
      await ref
          .read(socialControllerProvider.notifier)
          .loadStories(silent: true);
      if (!mounted) return;
      stories = ref.read(socialControllerProvider).stories;
    }

    for (final group in stories) {
      if (group.userId == profile.id && group.stories.isNotEmpty) {
        await showSocialStoryQuickViewer(
          context: context,
          group: group,
          api: _api,
          onStoryArchiveChanged: () {
            unawaited(Future.wait([_loadHighlights(), _loadProfile()]));
          },
          onStoryViewed: (storyId) => ref
              .read(socialControllerProvider.notifier)
              .markStoryViewed(storyId),
        );
        if (!mounted) return;
        return;
      }
    }

    final avatarUrl = (profile.imageUrl ?? '').trim();
    if (avatarUrl.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileMediaViewerPage(
          mediaUrl: avatarUrl,
          isVideo: false,
          title: profile.fullName,
          subtitle: 'الصورة الشخصية',
          caption: profile.bio,
        ),
      ),
    );
  }

  List<_HighlightAlbum> _buildHighlightAlbums() {
    if (_highlights.isEmpty) return const <_HighlightAlbum>[];
    final grouped = <String, List<SocialStoryHighlight>>{};
    for (final item in _highlights) {
      final title = item.title.trim();
      final key = title.isEmpty ? '__single_${item.id}' : title;
      grouped.putIfAbsent(key, () => <SocialStoryHighlight>[]).add(item);
    }

    final albums =
        grouped.entries
            .map((entry) {
              final highlights = List<SocialStoryHighlight>.from(entry.value)
                ..sort((a, b) {
                  final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
                  final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
                  return bTime.compareTo(aTime);
                });
              final cover = highlights.first;
              return _HighlightAlbum(
                id: cover.id,
                title: cover.title.trim().isEmpty
                    ? 'هايلايت'
                    : cover.title.trim(),
                cover: cover,
                stories: highlights.map((h) => h.story).toList(growable: false),
              );
            })
            .toList(growable: false)
          ..sort((a, b) {
            final aTime = a.cover.createdAt?.millisecondsSinceEpoch ?? 0;
            final bTime = b.cover.createdAt?.millisecondsSinceEpoch ?? 0;
            return bTime.compareTo(aTime);
          });
    return albums;
  }

  Future<void> _openHighlightAlbum(_HighlightAlbum album) async {
    final profile = _profile;
    if (profile == null || album.stories.isEmpty) return;
    final group = SocialStoryGroup(
      userId: profile.id,
      author: SocialAuthor(
        id: profile.id,
        fullName: profile.fullName,
        imageUrl: profile.imageUrl,
        phone: profile.phone,
        role: profile.role,
      ),
      latestAt: album.cover.createdAt,
      hasUnviewed: false,
      stories: album.stories,
    );
    await showSocialStoryQuickViewer(
      context: context,
      group: group,
      api: _api,
      onStoryArchiveChanged: () {
        unawaited(Future.wait([_loadHighlights(), _loadProfile()]));
      },
      onStoryViewed: (storyId) =>
          ref.read(socialControllerProvider.notifier).markStoryViewed(storyId),
    );
  }

  Future<void> _removeHighlight(_HighlightAlbum album) async {
    final profile = _profile;
    if (profile == null || !profile.isMe) return;
    try {
      await _api.removeStoryHighlight(album.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حذف الهايلايت')));
      await Future.wait([_loadHighlights(), _loadProfile()]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapAnyError(e, fallback: 'تعذر حذف الهايلايت.')),
        ),
      );
    }
  }

  Future<void> _openAddHighlightSheet() async {
    final profile = _profile;
    if (profile == null || !profile.isMe) return;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddHighlightSheet(api: _api),
    );
    if (result == true) {
      await Future.wait([_loadHighlights(), _loadProfile()]);
    }
  }

  Future<void> _openEditProfileSheet() async {
    final profile = _profile;
    if (profile == null || !profile.isMe) return;
    final next = await showModalBottomSheet<SocialUserProfile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditProfileSheet(api: _api, initialProfile: profile),
    );
    if (next != null && mounted) {
      setState(() => _profile = next);
    }
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '-';
    final d = dateTime.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$y/$m/$day  $h:$min';
  }

  String _friendlyRole(String role) {
    final l10n = context.l10n;
    switch (role.toLowerCase()) {
      case 'admin':
        return l10n.socialProfileRoleAdmin;
      case 'super_admin':
        return l10n.socialProfileRoleSuperAdmin;
      case 'deputy_admin':
        return l10n.socialProfileRoleDeputyAdmin;
      case 'owner':
        return l10n.socialProfileRoleMerchantOwner;
      case 'delivery':
        return l10n.socialProfileRoleDelivery;
      case 'taxi_captain':
        return l10n.socialProfileRoleTaxiCaptain;
      default:
        return l10n.socialProfileRoleUser;
    }
  }

  String _accountPrimaryLabel(SocialUserProfile profile) {
    final l10n = context.l10n;
    if (profile.isCarSeller && profile.isPropertySeller) {
      return l10n.socialProfileAccountCarsAndRealEstate;
    }
    if (profile.isCarSeller) {
      return l10n.socialProfileAccountCarSeller;
    }
    if (profile.isPropertySeller) {
      return l10n.socialProfileAccountPropertyBroker;
    }
    if (profile.accountLabelKey == 'premium_member' ||
        profile.isPremiumMember) {
      return l10n.socialProfileAccountPremiumMember;
    }
    if (profile.role == 'owner') {
      return l10n.socialProfileRoleMerchantOwner;
    }
    return _friendlyRole(profile.role);
  }

  List<String> _profileBadgeLabels(SocialUserProfile profile) {
    final l10n = context.l10n;
    final labels = <String>[];
    if (profile.isMerchantVerified && profile.role == 'owner') {
      labels.add(l10n.socialProfileBadgeVerifiedMerchant);
    }
    if (profile.isCarSeller) {
      labels.add(l10n.socialProfileBadgeVerifiedSeller);
    }
    if (profile.isPropertySeller) {
      labels.add(l10n.socialProfileBadgeVerifiedBroker);
    }
    if (labels.isEmpty && profile.isPremiumMember) {
      labels.add(l10n.socialProfileBadgeVerifiedUser);
    }
    return labels.toSet().toList(growable: false);
  }

  Future<void> _shareProfile() async {
    final profile = _profile;
    if (profile == null) return;
    final l10n = context.l10n;
    final badgeLabels = _profileBadgeLabels(profile);
    final lines = <String>[
      profile.fullName,
      _accountPrimaryLabel(profile),
      if (badgeLabels.isNotEmpty) badgeLabels.join(' • '),
      if (profile.bio.trim().isNotEmpty) profile.bio.trim(),
      l10n.socialProfileShareLine,
    ];
    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  int _tabCountValue(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    return int.tryParse('$value') ?? 0;
  }

  String _tabLabel(_ProfileContentTab tab) {
    final l10n = context.l10n;
    switch (tab) {
      case _ProfileContentTab.posts:
        return l10n.socialProfileTabPosts;
      case _ProfileContentTab.reels:
        return l10n.socialProfileTabReels;
      case _ProfileContentTab.saved:
        return l10n.socialProfileTabSaved;
      case _ProfileContentTab.reviews:
        return l10n.socialProfileTabReviews;
      case _ProfileContentTab.tagged:
        return l10n.socialProfileTabTagged;
    }
  }

  int _tabCountValueFor(_ProfileContentTab tab, SocialUserProfile profile) {
    switch (tab) {
      case _ProfileContentTab.posts:
        return profile.stats.totalPosts;
      case _ProfileContentTab.reels:
        return profile.stats.videoPosts;
      case _ProfileContentTab.saved:
        return _tabCountValue(profile.tabs['saved']);
      case _ProfileContentTab.reviews:
        return math.max(
          profile.stats.reviewPosts,
          _tabCountValue(profile.tabs['reviews']),
        );
      case _ProfileContentTab.tagged:
        return _tabCountValue(profile.tabs['tagged']);
    }
  }

  bool _canOpenInsights(SocialUserProfile profile) {
    return profile.isMe ||
        profile.viewerIsSuperAdmin ||
        _tabCountValue(profile.tabs['insights']) > 0 ||
        profile.role == 'owner';
  }

  List<_ProfileContentTab> _visibleTabsForProfile(SocialUserProfile profile) {
    return <_ProfileContentTab>[
      _ProfileContentTab.posts,
      _ProfileContentTab.reels,
      if (profile.isMe) _ProfileContentTab.saved,
      if (profile.stats.reviewPosts > 0 ||
          _tabCountValue(profile.tabs['reviews']) > 0)
        _ProfileContentTab.reviews,
      if (profile.isMe || _tabCountValue(profile.tabs['tagged']) > 0)
        _ProfileContentTab.tagged,
    ];
  }

  Future<void> _selectContentTab(_ProfileContentTab tab) async {
    setState(() => _selectedTab = tab);
    switch (tab) {
      case _ProfileContentTab.posts:
        if (_postsForKind(null).isEmpty) {
          await _loadPosts(kind: null, refresh: true);
        }
        break;
      case _ProfileContentTab.reels:
        if (_postsForKind('reel').isEmpty) {
          await _loadPosts(kind: 'reel', refresh: true);
        }
        break;
      case _ProfileContentTab.reviews:
        if (_postsForKind('merchant_review').isEmpty) {
          await _loadPosts(kind: 'merchant_review', refresh: true);
        }
        break;
      case _ProfileContentTab.saved:
      case _ProfileContentTab.tagged:
        break;
    }
  }

  Future<void> _openResidenceChangeScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SocialResidenceChangeScreen(),
      ),
    );
    if (!mounted) return;
    await _loadProfile();
  }

  Future<void> _openPaidUpgradesScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PaidUpgradesHomeScreen()),
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(myPaidUpgradesSummaryProvider);
      unawaited(_loadProfile());
    });
  }

  Future<void> _openInsightsScreen() async {
    final l10n = context.l10n;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialInsightsScreen(
          userId: widget.userId,
          title: _profile?.isMe == true
              ? l10n.socialProfileMyInsights
              : l10n.socialProfileInsights,
        ),
      ),
    );
  }

  Future<void> _openSavedScreen() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SocialSavedScreen()));
  }

  Future<void> _openTaggedScreen() async {
    final l10n = context.l10n;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialTaggedPostsScreen(
          userId: widget.userId,
          title: l10n.socialProfileTaggedPosts,
        ),
      ),
    );
  }

  Future<void> _openReportedPosts() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SocialReportedPostsScreen(),
      ),
    );
  }

  Future<void> _openAccountManagementScreen() async {
    final profile = _profile;
    if (profile == null || !profile.isMe) return;
    final paidSummary = ref.read(myPaidUpgradesSummaryProvider).valueOrNull;
    final action = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (pageContext) => SocialProfileAccountManagementScreen(
          profile: profile,
          paidSummary: paidSummary,
          onEditProfile: () async => Navigator.of(pageContext).pop('edit'),
          onOpenRelationRequests: () async {
            await Navigator.of(pageContext).push(
              MaterialPageRoute<void>(
                builder: (_) => const SocialRelationRequestsScreen(),
              ),
            );
            if (!mounted) return;
            await _loadProfile();
          },
          onOpenResidenceChange: _openResidenceChangeScreen,
          onOpenPremiumStatus: () async {
            await Navigator.of(pageContext).push(
              MaterialPageRoute<void>(
                builder: (_) => const SocialPremiumMembershipScreen(),
              ),
            );
            if (!mounted) return;
            ref.invalidate(myPaidUpgradesSummaryProvider);
            await _loadProfile();
          },
          onOpenPaidUpgrades: profile.isPremiumMember
              ? null
              : () async {
                  await Navigator.of(pageContext).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PaidUpgradesHomeScreen(),
                    ),
                  );
                },
          onOpenReportedPosts: _openReportedPosts,
          onOpenInsights: _openInsightsScreen,
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_openEditProfileSheet());
      });
    }
  }

  Future<void> _reportUser() async {
    final profile = _profile;
    if (profile == null || profile.isMe) return;
    final l10n = context.l10n;

    String reason = '';
    String details = '';
    final approved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        return AlertDialog(
          scrollable: true,
          title: Text(
            l10n.socialProfileReportUserTitle,
            textAlign: TextAlign.end,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => reason = value,
                decoration: InputDecoration(
                  labelText: l10n.socialProfileReportReason,
                  hintText: l10n.socialProfileReportReasonHint,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => details = value,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.socialProfileReportAdditionalDetails,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.socialProfileSubmitReport),
            ),
          ],
        );
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 16));
    reason = reason.trim();
    details = details.trim();
    if (approved != true || reason.isEmpty) return;

    try {
      await _api.reportUser(
        userId: widget.userId,
        reason: reason,
        details: details,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.socialProfileReportSubmitted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: l10n.socialProfileReportSubmitFailed),
          ),
        ),
      );
    }
  }

  Future<void> _reportPost(SocialPost post) async {
    final profile = _profile;
    if (profile == null || profile.isMe) return;
    final l10n = context.l10n;
    String reason = '';
    String details = '';
    final approved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        return AlertDialog(
          scrollable: true,
          title: Text(l10n.commonReport, textAlign: TextAlign.end),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => reason = value,
                decoration: const InputDecoration(labelText: 'السبب'),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => details = value,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'تفاصيل إضافية'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonConfirm),
            ),
          ],
        );
      },
    );
    reason = reason.trim();
    details = details.trim();
    if (approved != true || reason.isEmpty) return;

    try {
      await _api.reportPost(postId: post.id, reason: reason, details: details);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إرسال التبليغ بنجاح.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.socialProfileReportSubmitFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openActivityScreen() async {
    final profile = _profile;
    if (profile == null || !profile.isMe) return;
    final l10n = context.l10n;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialProfileActivityScreen(
          profile: profile,
          favoriteMerchants: _favoriteMerchants(),
          savedCount: _tabCountValue(profile.tabs['saved']),
          onOpenImages: () => _openPostsCollectionScreen(
            title: l10n.socialProfileImages,
            mode: SocialProfilePostCollectionMode.userPosts,
            kind: 'image',
            gridLayout: true,
          ),
          onOpenReels: () => _openPostsCollectionScreen(
            title: l10n.socialProfileTabReels,
            mode: SocialProfilePostCollectionMode.userPosts,
            kind: 'reel',
            gridLayout: true,
          ),
          onOpenReviews:
              (profile.stats.reviewPosts > 0 ||
                  _tabCountValue(profile.tabs['reviews']) > 0)
              ? () => _openPostsCollectionScreen(
                  title: l10n.socialProfileTabReviews,
                  mode: SocialProfilePostCollectionMode.userPosts,
                  kind: 'merchant_review',
                )
              : null,
          onOpenHighlights: _openStoryArchiveScreen,
          onOpenFriends: () => _openConnectionsScreen(
            SocialConnectionListMode.friends,
            l10n.socialProfileFriends,
          ),
          onOpenLikedPosts: () => _openPostsCollectionScreen(
            title: l10n.socialProfileLikesMade,
            mode: SocialProfilePostCollectionMode.likedPosts,
          ),
          onOpenCommentedPosts: () => _openPostsCollectionScreen(
            title: l10n.socialProfileCommentsMade,
            mode: SocialProfilePostCollectionMode.commentedPosts,
          ),
          onOpenReceivedLikes: () => _openSocialActivityInbox(
            title: l10n.socialProfileLikesReceived,
            initialFilter: 'likes',
          ),
          onOpenReceivedComments: () => _openSocialActivityInbox(
            title: l10n.socialProfileCommentsReceived,
            initialFilter: 'comments',
          ),
          onOpenSaved: _openSavedScreen,
          onOpenInsights: _openInsightsScreen,
          onOpenTagged: _tabCountValue(profile.tabs['tagged']) > 0
              ? _openTaggedScreen
              : null,
        ),
      ),
    );
  }

  Future<void> _openConnectionsScreen(
    SocialConnectionListMode mode,
    String title,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialUserConnectionsScreen(
          userId: widget.userId,
          mode: mode,
          title: title,
        ),
      ),
    );
  }

  bool _canOpenRelations(SocialUserProfile profile) {
    return profile.isMe ||
        profile.relationsPublic ||
        profile.relation.isAccepted;
  }

  Future<void> _openFollowersFromProfile(SocialUserProfile profile) async {
    if (!_canOpenRelations(profile)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.socialProfileManageRelationsPrivate),
        ),
      );
      return;
    }
    await _openConnectionsScreen(
      SocialConnectionListMode.followers,
      context.l10n.socialProfileStatsFollowers,
    );
  }

  Future<void> _openFollowingFromProfile(SocialUserProfile profile) async {
    if (!_canOpenRelations(profile)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.socialProfileManageRelationsPrivate),
        ),
      );
      return;
    }
    await _openConnectionsScreen(
      SocialConnectionListMode.following,
      context.l10n.socialProfileStatsFollowing,
    );
  }

  Future<void> _openPostsCollectionScreen({
    required String title,
    required SocialProfilePostCollectionMode mode,
    String? kind,
    bool gridLayout = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialProfilePostsScreen(
          userId: widget.userId,
          title: title,
          mode: mode,
          kind: kind,
          gridLayout: gridLayout,
        ),
      ),
    );
  }

  Future<void> _openSocialActivityInbox({
    required String title,
    required String initialFilter,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SocialActivityScreen(title: title, initialFilterKey: initialFilter),
      ),
    );
  }

  Future<void> _openArchiveScreen() async {
    final profile = _profile;
    if (profile == null || !profile.isMe) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SocialProfileArchiveScreen(),
      ),
    );
    if (!mounted) return;
    await Future.wait([_loadProfile(), _loadPosts(kind: null, refresh: true)]);
  }

  Future<void> _openStoryArchiveScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SocialStoryArchiveScreen()),
    );
  }

  Future<void> _togglePostArchive(SocialPost post, bool archived) async {
    final profile = _profile;
    if (profile == null || !profile.isMe) return;
    try {
      if (archived) {
        await _api.archivePost(post.id);
      } else {
        await _api.restorePost(post.id);
      }
      if (!mounted) return;
      setState(() {
        final nextByKey = <String, List<SocialPost>>{};
        for (final entry in _postsByKey.entries) {
          nextByKey[entry.key] = entry.value
              .where((item) => item.id != post.id)
              .toList(growable: false);
        }
        _postsByKey
          ..clear()
          ..addAll(nextByKey);
      });
      await Future.wait([
        _loadProfile(),
        _loadPosts(kind: null, refresh: true),
        if (_postsByKey.containsKey('reel'))
          _loadPosts(kind: 'reel', refresh: true),
        if (_postsByKey.containsKey('merchant_review'))
          _loadPosts(kind: 'merchant_review', refresh: true),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            archived
                ? context.l10n.socialProfileContentArchived
                : context.l10n.socialProfileContentRestored,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: archived
                  ? context.l10n.socialProfileContentArchiveFailed
                  : context.l10n.socialProfileContentRestoreFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _deletePost(SocialPost post) async {
    final profile = _profile;
    if (profile == null || !profile.isMe) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.commonDelete),
        content: Text(context.l10n.socialProfileDeletePostConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final previousByKey = <String, List<SocialPost>>{
      for (final entry in _postsByKey.entries)
        entry.key: List<SocialPost>.from(entry.value),
    };
    if (mounted) {
      setState(() {
        final nextByKey = <String, List<SocialPost>>{};
        for (final entry in _postsByKey.entries) {
          nextByKey[entry.key] = entry.value
              .where((item) => item.id != post.id)
              .toList(growable: false);
        }
        _postsByKey
          ..clear()
          ..addAll(nextByKey);
      });
    }

    try {
      await _api.deletePost(post.id);
      if (!mounted) return;
      await Future.wait([
        _loadProfile(),
        _loadPosts(kind: null, refresh: true),
        if (_postsByKey.containsKey('reel'))
          _loadPosts(kind: 'reel', refresh: true),
        if (_postsByKey.containsKey('merchant_review'))
          _loadPosts(kind: 'merchant_review', refresh: true),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.socialProfileDeletePostSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _postsByKey
          ..clear()
          ..addAll(previousByKey);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.socialProfileDeletePostFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openAdminActionsScreen() async {
    final profile = _profile;
    if (profile == null ||
        !profile.viewerIsSuperAdmin ||
        profile.superAdminControls == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialProfileAdminActionsScreen(
          profileName: profile.fullName,
          subtitle: _friendlyRole(profile.role),
          content: _buildSuperAdminActions(profile),
        ),
      ),
    );
    if (!mounted) return;
    await _loadProfile();
  }

  Future<void> _performPrimaryAction(SocialUserProfile profile) async {
    if (profile.isMe) {
      await _openEditProfileSheet();
      return;
    }
    if (profile.relation.isBlockedByMe) {
      await _unblockRelation();
      return;
    }
    if (profile.relation.isBlockedByOther) return;
    await _onFollowPressed();
  }

  String _primaryActionLabel(SocialUserProfile profile) {
    final l10n = context.l10n;
    if (profile.isMe) return l10n.socialProfileEditProfile;
    if (profile.relation.isBlockedByMe) {
      return l10n.socialProfileUnblock;
    }
    if (profile.relation.isBlockedByOther) {
      return l10n.socialProfileBlocked;
    }
    return _followButtonLabel(profile.relation);
  }

  IconData _primaryActionIcon(SocialUserProfile profile) {
    if (profile.isMe) return Icons.edit_outlined;
    if (profile.relation.isBlockedByMe) return Icons.lock_open_rounded;
    if (profile.relation.isAccepted) return Icons.check_circle_rounded;
    return Icons.person_add_alt_1_rounded;
  }

  List<PopupMenuEntry<String>> _buildMoreEntries(SocialUserProfile profile) {
    final l10n = context.l10n;
    if (profile.isMe) {
      return <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'manage',
          child: Text(l10n.socialProfileManageAccount),
        ),
        PopupMenuItem<String>(
          value: 'activity',
          child: Text(l10n.socialProfileProfileActivity),
        ),
        PopupMenuItem<String>(
          value: 'archive',
          child: Text(l10n.socialProfileArchive),
        ),
        if (_canOpenInsights(profile))
          PopupMenuItem<String>(
            value: 'insights',
            child: Text(l10n.socialProfileInsightsMenu),
          ),
        PopupMenuItem<String>(
          value: 'share',
          child: Text(l10n.socialProfileShareProfile),
        ),
      ];
    }
    final entries = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'share',
        child: Text(l10n.socialProfileShareProfile),
      ),
      PopupMenuItem<String>(
        value: 'notify',
        child: Text(
          (profile.notificationPreference?.enabled ?? true)
              ? l10n.socialProfileMuteNotifications
              : l10n.socialProfileEnableNotifications,
        ),
      ),
      if (profile.relation.canCall && appInAppCallsEnabled)
        PopupMenuItem<String>(value: 'call', child: Text(l10n.commonCall)),
      PopupMenuItem<String>(
        value: profile.relation.isBlockedByMe ? 'unblock' : 'block',
        child: Text(
          profile.relation.isBlockedByMe
              ? l10n.socialProfileUnblock
              : l10n.socialProfileBlock,
        ),
      ),
      PopupMenuItem<String>(value: 'report', child: Text(l10n.commonReport)),
    ];
    if (profile.viewerIsSuperAdmin && profile.superAdminControls != null) {
      entries.add(
        PopupMenuItem<String>(
          value: 'admin',
          child: Text(l10n.socialProfileManageUser),
        ),
      );
    }
    return entries;
  }

  Future<void> _handleMoreAction(String action) async {
    final profile = _profile;
    if (profile == null) return;
    switch (action) {
      case 'manage':
        await _openAccountManagementScreen();
        return;
      case 'activity':
        await _openActivityScreen();
        return;
      case 'archive':
        await _openArchiveScreen();
        return;
      case 'insights':
        await _openInsightsScreen();
        return;
      case 'share':
        await _shareProfile();
        return;
      case 'notify':
        final enabled = profile.notificationPreference?.enabled ?? true;
        await _setNotificationPreference(!enabled);
        return;
      case 'call':
        await _openInAppCall();
        return;
      case 'block':
        await _blockRelation();
        return;
      case 'unblock':
        await _unblockRelation();
        return;
      case 'report':
        await _reportUser();
        return;
      case 'admin':
        await _openAdminActionsScreen();
        return;
    }
  }

  List<String> _favoriteMerchants() {
    final allPosts = _postsForKind(null);
    if (allPosts.isEmpty) return const <String>[];
    final counts = <String, int>{};
    for (final post in allPosts) {
      final name = (post.merchantName ?? '').trim();
      if (name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(6).map((e) => e.key).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = _profile;
    final albums = _buildHighlightAlbums();
    final tabs = profile == null
        ? const <_ProfileContentTab>[_ProfileContentTab.posts]
        : _visibleTabsForProfile(profile);
    if (!tabs.contains(_selectedTab)) {
      _selectedTab = tabs.first;
    }

    return Directionality(
      textDirection: context.appTextDirection,
      child: Scaffold(
        appBar: AppBar(
          title: _ProfileAppBarTitle(
            username: profile?.username,
            fallbackTitle:
                profile?.fullName ??
                widget.initialName ??
                l10n.socialProfileTitle,
            verified: profile?.premiumBadgeVisible == true,
          ),
          actions: [
            if (profile != null)
              PopupMenuButton<String>(
                onSelected: (value) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    Future<void>.delayed(const Duration(milliseconds: 220), () {
                      if (!mounted) return;
                      unawaited(_handleMoreAction(value));
                    });
                  });
                },
                itemBuilder: (_) => _buildMoreEntries(profile),
              ),
          ],
        ),
        body: _loadingProfile && profile == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refreshAll,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (_error != null) _ErrorBanner(message: _error!),
                    if (profile != null) ...[
                      _ProfileHeaderSection(
                        profile: profile,
                        primaryLabel: _accountPrimaryLabel(profile),
                        badgeLabels: _profileBadgeLabels(profile),
                        onAvatarTap: _openAvatarStoryOrImage,
                        onOpenFollowers: () =>
                            _openFollowersFromProfile(profile),
                        onOpenFollowing: () =>
                            _openFollowingFromProfile(profile),
                      ),
                      const SizedBox(height: 14),
                      _ProfileActionRow(
                        profile: profile,
                        primaryLabel: _primaryActionLabel(profile),
                        primaryIcon: _primaryActionIcon(profile),
                        onPrimaryTap: () => _performPrimaryAction(profile),
                        onShareTap: _shareProfile,
                        onMessageTap:
                            !profile.isMe &&
                                profile.relation.canChat &&
                                !profile.relation.isBlocked
                            ? _openChatWithUser
                            : null,
                        onUpgradeTap: profile.isMe && !profile.isPremiumMember
                            ? _openPaidUpgradesScreen
                            : null,
                      ),
                      if (!profile.isMe &&
                          profile.relation.state != 'none') ...[
                        const SizedBox(height: 10),
                        Text(
                          _relationStatusText(profile.relation),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.72),
                              ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 14),
                    _HighlightsSection(
                      loading: _loadingHighlights,
                      albums: albums,
                      isPrivateForViewer: _storiesPrivateForViewer,
                      canManage: profile?.isMe == true,
                      onAdd: _openAddHighlightSheet,
                      onOpen: _openHighlightAlbum,
                      onRemove: _removeHighlight,
                    ),
                    if (profile != null) ...[
                      const SizedBox(height: 18),
                      _ProfileTabsStrip(
                        profile: profile,
                        tabs: tabs,
                        selectedTab: _selectedTab,
                        onSelect: _selectContentTab,
                        labelBuilder: (tab) => _tabLabel(tab),
                        countBuilder: (tab) => _tabCountValueFor(tab, profile),
                      ),
                      const SizedBox(height: 16),
                      _ProfileTabContent(
                        profile: profile,
                        selectedTab: _selectedTab,
                        postsByKey: _postsByKey,
                        nextCursorByKey: _nextCursorByKey,
                        loadingByKey: _loadingByKey,
                        postsPrivateForViewer: _postsPrivateForViewer,
                        onLoadMore: _loadPosts,
                        onOpenMedia: _openProfileContent,
                        onToggleArchive: profile.isMe
                            ? _togglePostArchive
                            : null,
                        onDeletePost: profile.isMe ? _deletePost : null,
                        onReportPost: profile.isMe ? null : _reportPost,
                        formatDateTime: _formatDateTime,
                        userId: widget.userId,
                        profileName: profile.fullName,
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.errorContainer,
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyPostsNotice extends StatelessWidget {
  const _EmptyPostsNotice({this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Center(
        child: Text(
          title ?? context.l10n.socialProfileNoPostsForFilter,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _PrivatePostsNotice extends StatelessWidget {
  final String name;

  const _PrivatePostsNotice({required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded),
              const SizedBox(height: 8),
              Text(
                context.l10n.socialProfilePrivatePostsNotice(name),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeaderSection extends StatelessWidget {
  final SocialUserProfile profile;
  final String primaryLabel;
  final List<String> badgeLabels;
  final VoidCallback onAvatarTap;
  final VoidCallback? onOpenFollowers;
  final VoidCallback? onOpenFollowing;

  const _ProfileHeaderSection({
    required this.profile,
    required this.primaryLabel,
    required this.badgeLabels,
    required this.onAvatarTap,
    this.onOpenFollowers,
    this.onOpenFollowing,
  });

  @override
  Widget build(BuildContext context) {
    final stats = profile.stats;
    final theme = Theme.of(context);
    final hasBio = profile.bio.trim().isNotEmpty;
    final displayName = profile.fullName.trim();
    final username = (profile.username ?? '').trim();
    final headerName = displayName.isNotEmpty
        ? displayName
        : (username.isNotEmpty
              ? '@$username'
              : context.l10n.socialProfileRoleUser);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: onAvatarTap,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.24),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 42,
                  backgroundImage: (profile.imageUrl ?? '').trim().isNotEmpty
                      ? AppCachedImageProvider(profile.imageUrl!)
                      : null,
                  child: (profile.imageUrl ?? '').trim().isEmpty
                      ? const Icon(Icons.person_outline_rounded, size: 32)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ProfileMainStat(
                    value: stats.totalPosts.toString(),
                    label: context.l10n.socialProfileStatsPosts,
                  ),
                  _ProfileMainStat(
                    value: stats.followersCount.toString(),
                    label: context.l10n.socialProfileStatsFollowers,
                    onTap: onOpenFollowers,
                  ),
                  _ProfileMainStat(
                    value: stats.followingCount.toString(),
                    label: context.l10n.socialProfileStatsFollowing,
                    onTap: onOpenFollowing,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _IdentityTextWithBadge(
          label: headerName,
          verified: profile.premiumBadgeVisible,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          primaryLabel,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
        if (hasBio) ...[
          const SizedBox(height: 8),
          Text(
            profile.bio.trim(),
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (badgeLabels.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: badgeLabels
                .take(4)
                .map(
                  (badge) => _ProfileInfoChip(
                    icon: Icons.verified_outlined,
                    label: badge,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}

class _ProfileAppBarTitle extends StatelessWidget {
  final String? username;
  final String fallbackTitle;
  final bool verified;

  const _ProfileAppBarTitle({
    required this.username,
    required this.fallbackTitle,
    required this.verified,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedUsername = (username ?? '').trim();
    if (normalizedUsername.isEmpty) {
      return Text(fallbackTitle);
    }

    return _IdentityTextWithBadge(
      label: '@$normalizedUsername',
      verified: verified,
      forceLtr: true,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

class _IdentityTextWithBadge extends StatelessWidget {
  final String label;
  final bool verified;
  final TextStyle? style;
  final bool forceLtr;

  const _IdentityTextWithBadge({
    required this.label,
    required this.verified,
    this.style,
    this.forceLtr = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: forceLtr
              ? Directionality(textDirection: TextDirection.ltr, child: text)
              : text,
        ),
        if (verified) ...[
          const SizedBox(width: 6),
          Icon(
            Icons.verified_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
        ],
      ],
    );
  }
}

class _ProfileActionRow extends StatelessWidget {
  final SocialUserProfile profile;
  final String primaryLabel;
  final IconData primaryIcon;
  final Future<void> Function() onPrimaryTap;
  final Future<void> Function() onShareTap;
  final Future<void> Function()? onMessageTap;
  final Future<void> Function()? onUpgradeTap;

  const _ProfileActionRow({
    required this.profile,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimaryTap,
    required this.onShareTap,
    this.onMessageTap,
    this.onUpgradeTap,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      Expanded(
        child: FilledButton.icon(
          onPressed: onPrimaryTap,
          icon: Icon(primaryIcon),
          label: Text(primaryLabel),
        ),
      ),
      if (onMessageTap != null) ...[
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onMessageTap,
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: Text(context.l10n.commonMessage),
          ),
        ),
      ],
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: onShareTap,
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(context.l10n.commonShare),
        ),
      ),
      if (profile.isMe && onUpgradeTap != null) ...[
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: onUpgradeTap,
            icon: const Icon(Icons.workspace_premium_outlined),
            label: Text(context.l10n.socialProfileUpgrade),
          ),
        ),
      ],
    ];

    return Row(children: buttons);
  }
}

class _ProfileTabsStrip extends StatelessWidget {
  final SocialUserProfile profile;
  final List<_ProfileContentTab> tabs;
  final _ProfileContentTab selectedTab;
  final Future<void> Function(_ProfileContentTab tab) onSelect;
  final String Function(_ProfileContentTab tab) labelBuilder;
  final int Function(_ProfileContentTab tab) countBuilder;

  const _ProfileTabsStrip({
    required this.profile,
    required this.tabs,
    required this.selectedTab,
    required this.onSelect,
    required this.labelBuilder,
    required this.countBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs
            .map(
              (tab) => Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  selected: selectedTab == tab,
                  label: Text(
                    countBuilder(tab) > 0
                        ? '${labelBuilder(tab)} ${countBuilder(tab)}'
                        : labelBuilder(tab),
                  ),
                  onSelected: (_) => onSelect(tab),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _ProfileTabContent extends ConsumerWidget {
  final SocialUserProfile profile;
  final _ProfileContentTab selectedTab;
  final Map<String, List<SocialPost>> postsByKey;
  final Map<String, int?> nextCursorByKey;
  final Map<String, bool> loadingByKey;
  final bool postsPrivateForViewer;
  final Future<void> Function({required String? kind, bool refresh}) onLoadMore;
  final Future<void> Function(SocialPost post, {List<SocialPost>? contextPosts})
  onOpenMedia;
  final Future<void> Function(SocialPost post, bool archived)? onToggleArchive;
  final Future<void> Function(SocialPost post)? onDeletePost;
  final Future<void> Function(SocialPost post)? onReportPost;
  final String Function(DateTime? value) formatDateTime;
  final int userId;
  final String profileName;

  const _ProfileTabContent({
    required this.profile,
    required this.selectedTab,
    required this.postsByKey,
    required this.nextCursorByKey,
    required this.loadingByKey,
    required this.postsPrivateForViewer,
    required this.onLoadMore,
    required this.onOpenMedia,
    required this.onToggleArchive,
    required this.onDeletePost,
    required this.onReportPost,
    required this.formatDateTime,
    required this.userId,
    required this.profileName,
  });

  String _keyOfKind(String? kind) => kind ?? _allPostsKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selectedTab == _ProfileContentTab.saved) {
      return _ProfileSavedInlineBody(
        onOpenMedia: onOpenMedia,
        onReportPost: onReportPost,
      );
    }
    if (selectedTab == _ProfileContentTab.tagged) {
      return _ProfileTaggedInlineBody(
        userId: userId,
        onOpenMedia: onOpenMedia,
        onReportPost: onReportPost,
        formatDateTime: formatDateTime,
      );
    }

    final kind = switch (selectedTab) {
      _ProfileContentTab.posts => null,
      _ProfileContentTab.reels => 'reel',
      _ProfileContentTab.reviews => 'merchant_review',
      _ProfileContentTab.saved => null,
      _ProfileContentTab.tagged => null,
    };

    final rawPosts = postsByKey[_keyOfKind(kind)] ?? const <SocialPost>[];
    final posts = rawPosts;
    final loading = loadingByKey[_keyOfKind(kind)] == true;
    final nextCursor = nextCursorByKey[_keyOfKind(kind)];

    if (postsPrivateForViewer && !profile.isMe) {
      return _PrivatePostsNotice(name: profileName);
    }
    if (loading && posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (posts.isEmpty) {
      return const _EmptyPostsNotice();
    }

    return Column(
      children: [
        ...posts.map(
          (post) => _ProfilePostCard(
            post: post,
            onOpenMedia: () =>
                unawaited(onOpenMedia(post, contextPosts: posts)),
            onToggleArchive: onToggleArchive == null
                ? null
                : (archived) => onToggleArchive!(post, archived),
            onDeletePost: onDeletePost == null
                ? null
                : () => onDeletePost!(post),
            onReportPost: onReportPost == null
                ? null
                : () => onReportPost!(post),
          ),
        ),
        if (nextCursor != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: loading
                  ? null
                  : () => onLoadMore(kind: kind, refresh: false),
              icon: loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(context.l10n.socialProfileLoadMore),
            ),
          ),
      ],
    );
  }
}

class _ProfileSavedInlineBody extends ConsumerStatefulWidget {
  final Future<void> Function(SocialPost post, {List<SocialPost>? contextPosts})
  onOpenMedia;
  final Future<void> Function(SocialPost post)? onReportPost;

  const _ProfileSavedInlineBody({
    required this.onOpenMedia,
    required this.onReportPost,
  });

  @override
  ConsumerState<_ProfileSavedInlineBody> createState() =>
      _ProfileSavedInlineBodyState();
}

class _ProfileSavedInlineBodyState
    extends ConsumerState<_ProfileSavedInlineBody> {
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
    final state = ref.watch(socialSavedControllerProvider);
    if (state.loading && state.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.items.isEmpty) return const _EmptyPostsNotice();
    final savedPosts = state.items
        .map((item) => item.content)
        .toList(growable: false);
    return Column(
      children: state.items
          .map(
            (item) => _ProfilePostCard(
              post: item.content,
              onOpenMedia: () => unawaited(
                widget.onOpenMedia(item.content, contextPosts: savedPosts),
              ),
              onReportPost: widget.onReportPost == null
                  ? null
                  : () => widget.onReportPost!(item.content),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ProfileTaggedInlineBody extends ConsumerStatefulWidget {
  final int userId;
  final Future<void> Function(SocialPost post, {List<SocialPost>? contextPosts})
  onOpenMedia;
  final Future<void> Function(SocialPost post)? onReportPost;
  final String Function(DateTime? value) formatDateTime;

  const _ProfileTaggedInlineBody({
    required this.userId,
    required this.onOpenMedia,
    required this.onReportPost,
    required this.formatDateTime,
  });

  @override
  ConsumerState<_ProfileTaggedInlineBody> createState() =>
      _ProfileTaggedInlineBodyState();
}

class _ProfileTaggedInlineBodyState
    extends ConsumerState<_ProfileTaggedInlineBody> {
  bool _loading = true;
  String? _error;
  List<SocialPost> _posts = const <SocialPost>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final out = await ref
          .read(socialApiProvider)
          .listProfileTagged(userId: widget.userId);
      final rows = List<dynamic>.from(
        out['posts'] ??
            out['items'] ??
            out['taggedPosts'] ??
            out['tagged_posts'] ??
            const [],
      );
      if (!mounted) return;
      setState(() {
        _posts = rows
            .map(
              (e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialTaggedPostsLoadFailedFriendly,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _ErrorBanner(message: _error!);
    }
    if (_posts.isEmpty) {
      return _EmptyPostsNotice(title: context.l10n.socialTaggedPostsEmpty);
    }
    return Column(
      children: _posts
          .map(
            (post) => _ProfilePostCard(
              post: post,
              onOpenMedia: () =>
                  unawaited(widget.onOpenMedia(post, contextPosts: _posts)),
              onReportPost: widget.onReportPost == null
                  ? null
                  : () => widget.onReportPost!(post),
            ),
          )
          .toList(growable: false),
    );
  }
}

// ignore: unused_element
class _ProfileHeaderCard extends StatelessWidget {
  final SocialUserProfile profile;
  final String roleLabel;
  final String joinedAt;
  final List<String> favorites;
  final VoidCallback onAvatarTap;
  final String relationStatus;
  final Widget? relationActions;
  final VoidCallback? onRequestsTap;
  final VoidCallback? onEditTap;

  const _ProfileHeaderCard({
    required this.profile,
    required this.roleLabel,
    required this.joinedAt,
    required this.favorites,
    required this.onAvatarTap,
    required this.relationStatus,
    required this.relationActions,
    required this.onRequestsTap,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = profile.stats;
    final phone = (profile.phone ?? '').trim();
    final hasPhone = phone.isNotEmpty;

    final secondaryStats = <_StatChip>[
      _StatChip(label: 'أصدقاء', value: stats.friendsCount.toString()),
      _StatChip(label: 'صور', value: stats.imagePosts.toString()),
      _StatChip(label: 'ريلز', value: stats.videoPosts.toString()),
      _StatChip(label: 'تقييمات', value: stats.reviewPosts.toString()),
      _StatChip(label: 'إعجابات', value: stats.likesReceived.toString()),
      _StatChip(label: 'تعليقات', value: stats.commentsReceived.toString()),
      _StatChip(label: 'ستوري نشطة', value: stats.activeStories.toString()),
    ];

    if (stats.pendingIncomingCount > 0) {
      secondaryStats.add(
        _StatChip(
          label: 'طلبات واردة',
          value: stats.pendingIncomingCount.toString(),
        ),
      );
    }

    if (stats.pendingOutgoingCount > 0) {
      secondaryStats.add(
        _StatChip(
          label: 'طلبات صادرة',
          value: stats.pendingOutgoingCount.toString(),
        ),
      );
    }

    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              theme.colorScheme.primaryContainer.withValues(alpha: 0.42),
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: onAvatarTap,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.65,
                          ),
                          width: 2.2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundImage:
                            (profile.imageUrl ?? '').trim().isNotEmpty
                            ? AppCachedImageProvider(profile.imageUrl!)
                            : null,
                        child: (profile.imageUrl ?? '').trim().isEmpty
                            ? const Icon(Icons.person_outline, size: 30)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _ProfileMainStat(
                          value: stats.totalPosts.toString(),
                          label: 'منشورات',
                        ),
                        _ProfileMainStat(
                          value: stats.followersCount.toString(),
                          label: 'متابعون',
                        ),
                        _ProfileMainStat(
                          value: stats.followingCount.toString(),
                          label: 'يتابع',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  profile.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ProfileInfoChip(
                    icon: Icons.badge_outlined,
                    label: roleLabel,
                  ),
                  _ProfileInfoChip(
                    icon: Icons.calendar_month_outlined,
                    label: 'عضو منذ $joinedAt',
                  ),
                  if (profile.age != null)
                    _ProfileInfoChip(
                      icon: Icons.cake_outlined,
                      label: 'العمر ${profile.age} سنة',
                    ),
                  if (hasPhone)
                    _ProfileInfoChip(icon: Icons.call_outlined, label: phone),
                ],
              ),
              if (profile.bio.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  profile.bio.trim(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.92),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (!profile.isMe) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.7,
                    ),
                  ),
                  child: Text(
                    relationStatus,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (relationActions != null) ...[
                  const SizedBox(height: 8),
                  relationActions!,
                ],
              ],
              if (profile.isMe && onRequestsTap != null) ...[
                Row(
                  children: [
                    if (onEditTap != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onEditTap,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('تعديل الملف'),
                        ),
                      ),
                    if (onEditTap != null) const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onRequestsTap,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('طلبات المتابعة'),
                      ),
                    ),
                  ],
                ),
              ] else if (onEditTap != null) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: onEditTap,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل الملف الشخصي'),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PrivacyPill(
                    icon: Icons.phone_enabled_outlined,
                    label: profile.showPhone ? 'الهاتف ظاهر' : 'الهاتف مخفي',
                    active: profile.showPhone,
                  ),
                  _PrivacyPill(
                    icon: Icons.public_rounded,
                    label: profile.postsPublic
                        ? 'المنشورات عامة'
                        : 'المنشورات خاصة',
                    active: profile.postsPublic,
                  ),
                  _PrivacyPill(
                    icon: Icons.auto_stories_rounded,
                    label: profile.storiesPublic
                        ? 'الستوريات عامة'
                        : 'الستوريات خاصة',
                    active: profile.storiesPublic,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'إحصائيات إضافية',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: secondaryStats),
              if (favorites.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'المتاجر المفضلة',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: favorites
                      .map(
                        (name) => Chip(
                          label: Text(name, textDirection: TextDirection.rtl),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMainStat extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _ProfileMainStat({
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.76),
          ),
        ),
      ],
    );
    if (onTap == null) {
      return content;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: content,
      ),
    );
  }
}

class _ProfileInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ProfileInfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.82),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _PrivacyPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _PrivacyPill({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? Theme.of(context).colorScheme.secondaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final fg = active
        ? Theme.of(context).colorScheme.onSecondaryContainer
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: bg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightsSection extends StatelessWidget {
  final bool loading;
  final List<_HighlightAlbum> albums;
  final bool isPrivateForViewer;
  final bool canManage;
  final VoidCallback onAdd;
  final ValueChanged<_HighlightAlbum> onOpen;
  final ValueChanged<_HighlightAlbum> onRemove;

  const _HighlightsSection({
    required this.loading,
    required this.albums,
    required this.isPrivateForViewer,
    required this.canManage,
    required this.onAdd,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (canManage)
                  IconButton(
                    tooltip: 'تثبيت ستوري',
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                const Spacer(),
                const Text(
                  'الهايلايت',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ],
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (isPrivateForViewer)
              Text(
                'الستوريات مخفية من صاحب الحساب.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              )
            else if (albums.isEmpty)
              Text(
                canManage
                    ? 'لا توجد هايلايت بعد. ثبّت ستوري من الأرشيف.'
                    : 'لا توجد هايلايت لهذا المستخدم.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              )
            else
              SizedBox(
                height: 94,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: albums.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    final coverUrl = (album.cover.story.mediaUrl ?? '').trim();
                    return GestureDetector(
                      onTap: () => onOpen(album),
                      onLongPress: canManage ? () => onRemove(album) : null,
                      child: SizedBox(
                        width: 74,
                        child: Column(
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 1.8,
                                ),
                                image:
                                    coverUrl.isNotEmpty &&
                                        album.cover.story.mediaKind == 'image'
                                    ? DecorationImage(
                                        image: AppCachedImageProvider(coverUrl),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                                gradient:
                                    coverUrl.isEmpty ||
                                        album.cover.story.mediaKind != 'image'
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF163A6B),
                                          Color(0xFF2D78B7),
                                        ],
                                      )
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child:
                                  (coverUrl.isEmpty ||
                                      album.cover.story.mediaKind != 'image')
                                  ? const Icon(
                                      Icons.auto_stories_rounded,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              album.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _FiltersSection extends StatelessWidget {
  final String? selectedKind;
  final ValueChanged<String?> onSelect;

  const _FiltersSection({required this.selectedKind, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _profileFilters
              .map(
                (filter) => FilterChip(
                  selected: selectedKind == filter.kind,
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(filter.label),
                      const SizedBox(width: 6),
                      Icon(filter.icon, size: 16),
                    ],
                  ),
                  onSelected: (_) => onSelect(filter.kind),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _ProfilePostCard extends StatelessWidget {
  final SocialPost post;
  final VoidCallback onOpenMedia;
  final Future<void> Function(bool archived)? onToggleArchive;
  final Future<void> Function()? onDeletePost;
  final Future<void> Function()? onReportPost;

  const _ProfilePostCard({
    required this.post,
    required this.onOpenMedia,
    this.onToggleArchive,
    this.onDeletePost,
    this.onReportPost,
  });

  @override
  Widget build(BuildContext context) {
    final showMenu =
        onToggleArchive != null || onDeletePost != null || onReportPost != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Stack(
        children: [
          SocialPostCardV2(
            post: post,
            onOpenDetails: onOpenMedia,
            onOpenComments: onOpenMedia,
            onOpenMerchantLink: onOpenMedia,
            autoPlayVideoPreview: post.postKind == 'reel',
          ),
          if (showMenu)
            PositionedDirectional(
              top: 10,
              end: 10,
              child: Material(
                color: Colors.black.withValues(alpha: 0.36),
                shape: const CircleBorder(),
                child: PopupMenuButton<String>(
                  onSelected: (value) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!context.mounted) return;
                      Future<void>.delayed(
                        const Duration(milliseconds: 220),
                        () {
                          if (!context.mounted) return;
                          if (value == 'archive') {
                            if (onToggleArchive != null) {
                              unawaited(onToggleArchive!(true));
                            }
                          } else if (value == 'report') {
                            if (onReportPost != null) {
                              unawaited(onReportPost!());
                            }
                          } else if (value == 'delete') {
                            if (onDeletePost != null) {
                              unawaited(onDeletePost!());
                            }
                          }
                        },
                      );
                    });
                  },
                  itemBuilder: (_) => [
                    if (onToggleArchive != null)
                      const PopupMenuItem<String>(
                        value: 'archive',
                        child: Text('أرشفة'),
                      ),
                    if (onDeletePost != null)
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text(context.l10n.commonDelete),
                      ),
                    if (onReportPost != null)
                      PopupMenuItem<String>(
                        value: 'report',
                        child: Text(context.l10n.commonReport),
                      ),
                  ],
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddHighlightSheet extends StatefulWidget {
  final SocialApi api;

  const _AddHighlightSheet({required this.api});

  @override
  State<_AddHighlightSheet> createState() => _AddHighlightSheetState();
}

class _AddHighlightSheetState extends State<_AddHighlightSheet> {
  final TextEditingController _titleCtrl = TextEditingController();
  List<SocialStory> _stories = <SocialStory>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadArchive);
  }

  Future<void> _loadArchive() async {
    try {
      final archiveOut = await widget.api.listMyStoryArchive(limit: 80);
      final archiveRaw = List<dynamic>.from(
        archiveOut['stories'] as List? ?? const [],
      );
      final archiveStories = archiveRaw
          .map((e) => SocialStory.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);

      List<SocialStory> liveStories = const <SocialStory>[];
      try {
        final liveOut = await widget.api.listStories(
          limitUsers: 60,
          maxPerUser: 20,
        );
        final liveRaw = List<dynamic>.from(
          liveOut['stories'] as List? ?? const [],
        );
        liveStories = liveRaw
            .map(
              (e) => SocialStoryGroup.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .expand((group) => group.stories.where((story) => story.isMine))
            .toList(growable: false);
      } catch (_) {
        // Keep archive flow functional even if live stories endpoint fails.
      }

      final mergedById = <int, SocialStory>{};
      for (final story in liveStories) {
        mergedById[story.id] = story;
      }
      for (final story in archiveStories) {
        mergedById.putIfAbsent(story.id, () => story);
      }
      final stories = mergedById.values.toList(growable: false)
        ..sort((a, b) {
          final aTime = a.createdAt?.millisecondsSinceEpoch ?? a.id;
          final bTime = b.createdAt?.millisecondsSinceEpoch ?? b.id;
          return bTime.compareTo(aTime);
        });

      if (!mounted) return;
      setState(() {
        _stories = stories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(e, fallback: 'تعذر تحميل أرشيف الستوري.');
      });
    }
  }

  Future<void> _pinStory(SocialStory story) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.api.addStoryHighlight(
        story.id,
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _stories = _stories
            .where((item) => item.id != story.id)
            .toList(growable: false);
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تثبيت الستوري في الهايلايت.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = mapAnyError(e, fallback: 'تعذر تثبيت الستوري.');
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.86,
        child: Column(
          children: [
            const ListTile(
              title: Text(
                'تثبيت ستوري في الهايلايت',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.end,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: TextField(
                controller: _titleCtrl,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'عنوان الهايلايت (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  _error!,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _stories.isEmpty
                  ? const Center(
                      child: Text(
                        'لا توجد ستوريات بالأرشيف حالياً.',
                        textDirection: TextDirection.rtl,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: _stories.length,
                      itemBuilder: (context, index) {
                        final story = _stories[index];
                        final mediaUrl = (story.mediaUrl ?? '').trim();
                        final isImage =
                            story.mediaKind == 'image' && mediaUrl.isNotEmpty;
                        return Card(
                          child: ListTile(
                            leading: isImage
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedAppImage(
                                      imageUrl: mediaUrl,
                                      width: 46,
                                      height: 46,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const CircleAvatar(
                                    child: Icon(Icons.auto_stories_rounded),
                                  ),
                            title: Text(
                              story.caption.trim().isEmpty
                                  ? 'ستوري بدون نص'
                                  : story.caption.trim(),
                              textDirection: TextDirection.rtl,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: FilledButton(
                              onPressed: _saving
                                  ? null
                                  : () => _pinStory(story),
                              child: const Text('تثبيت'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('إنهاء'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  final SocialApi api;
  final SocialUserProfile initialProfile;

  const _EditProfileSheet({required this.api, required this.initialProfile});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _ageCtrl;
  late bool _showPhone;
  late bool _postsPublic;
  late bool _storiesPublic;
  late bool _relationsPublic;
  late bool _accountPrivate;
  late String _onlineStatusVisibility;
  late String _lastSeenVisibility;
  late bool _readReceiptsEnabled;
  late bool _typingIndicatorsEnabled;

  LocalMediaFile? _pickedImage;
  bool _saving = false;
  bool _checkingUsername = false;
  String? _error;
  String? _usernameError;
  Timer? _usernameDebounce;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialProfile.fullName);
    _usernameCtrl = TextEditingController(
      text: widget.initialProfile.username ?? '',
    );
    _bioCtrl = TextEditingController(text: widget.initialProfile.bio);
    _ageCtrl = TextEditingController(
      text: widget.initialProfile.age?.toString() ?? '',
    );
    _showPhone = widget.initialProfile.showPhone;
    _postsPublic = widget.initialProfile.postsPublic;
    _storiesPublic = widget.initialProfile.storiesPublic;
    _relationsPublic = widget.initialProfile.relationsPublic;
    _accountPrivate = widget.initialProfile.accountPrivate;
    _onlineStatusVisibility = widget.initialProfile.onlineStatusVisibility;
    _lastSeenVisibility = widget.initialProfile.lastSeenVisibility;
    _readReceiptsEnabled = widget.initialProfile.readReceiptsEnabled;
    _typingIndicatorsEnabled = widget.initialProfile.typingIndicatorsEnabled;
    _usernameCtrl.addListener(_scheduleUsernameCheck);
  }

  List<DropdownMenuItem<String>> _buildVisibilityItems() {
    const values = <String>['connections', 'everyone', 'nobody'];
    return values
        .map(
          (value) => DropdownMenuItem<String>(
            value: value,
            child: Text(
              value == 'everyone'
                  ? 'الجميع'
                  : value == 'nobody'
                  ? 'لا أحد'
                  : 'العلاقات فقط',
            ),
          ),
        )
        .toList(growable: false);
  }

  String? _validateUsernameLocally(String value) {
    final username = value.trim().toLowerCase();
    if (username.isEmpty) {
      return 'اسم المستخدم مطلوب.';
    }
    final ok =
        username.length >= 4 &&
        username.length <= 24 &&
        !username.contains('..') &&
        RegExp(r'^[a-z0-9](?:[a-z0-9._]{2,22})[a-z0-9]$').hasMatch(username);
    if (!ok) {
      return 'استخدم 4-24 حرفًا إنكليزيًا أو رقمًا مع _ أو .';
    }
    return null;
  }

  void _scheduleUsernameCheck() {
    _usernameDebounce?.cancel();
    if (mounted) {
      setState(() {});
    }
    final localError = _validateUsernameLocally(_usernameCtrl.text);
    if (localError != null) {
      setState(() => _usernameError = localError);
      return;
    }
    final initialUsername = (widget.initialProfile.username ?? '')
        .trim()
        .toLowerCase();
    final nextUsername = _usernameCtrl.text.trim().toLowerCase();
    if (nextUsername == initialUsername) {
      setState(() => _usernameError = null);
      return;
    }
    _usernameDebounce = Timer(
      const Duration(milliseconds: 350),
      _checkUsernameAvailability,
    );
  }

  Future<bool> _checkUsernameAvailability() async {
    final username = _usernameCtrl.text.trim().toLowerCase();
    final localError = _validateUsernameLocally(username);
    if (localError != null) {
      if (mounted) setState(() => _usernameError = localError);
      return false;
    }
    final initialUsername = (widget.initialProfile.username ?? '')
        .trim()
        .toLowerCase();
    if (username == initialUsername) {
      if (mounted) {
        setState(() {
          _checkingUsername = false;
          _usernameError = null;
        });
      }
      return true;
    }
    if (mounted) {
      setState(() {
        _checkingUsername = true;
        _usernameError = null;
      });
    }
    try {
      final out = await widget.api.checkUsernameAvailability(username);
      final available = out['available'] == true;
      if (!mounted) return available;
      setState(() {
        _checkingUsername = false;
        _usernameError = available ? null : 'اسم المستخدم مستخدم بالفعل.';
      });
      return available;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _checkingUsername = false;
        _usernameError = 'تعذر التحقق من اسم المستخدم الآن.';
      });
      return false;
    }
  }

  Future<void> _pickImage() async {
    final media = await pickPostMediaFromDevice();
    if (media == null) return;
    final mime = (media.mimeType ?? '').toLowerCase();
    if (!mime.startsWith('image/')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر صورة فقط لتحديث الملف الشخصي.')),
      );
      return;
    }
    setState(() {
      _pickedImage = media;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final fullName = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim().toLowerCase();
    final bio = _bioCtrl.text.trim();
    final ageText = _ageCtrl.text.trim();
    int? age;
    if (fullName.isEmpty) {
      setState(() => _error = 'الاسم مطلوب.');
      return;
    }
    final usernameOk = await _checkUsernameAvailability();
    if (!mounted || !usernameOk || _usernameError != null) {
      return;
    }
    if (ageText.isNotEmpty) {
      age = int.tryParse(ageText);
      if (age == null || age < 13 || age > 100) {
        setState(() => _error = 'يرجى إدخال عمر صحيح بين 13 و100.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final out = await widget.api.updateMyProfile(
        fullName: fullName,
        username: username,
        bio: bio,
        age: age,
        showPhone: _showPhone,
        postsPublic: _postsPublic,
        storiesPublic: _storiesPublic,
        relationsPublic: _relationsPublic,
        accountPrivate: _accountPrivate,
        onlineStatusVisibility: _onlineStatusVisibility,
        lastSeenVisibility: _lastSeenVisibility,
        readReceiptsEnabled: _readReceiptsEnabled,
        typingIndicatorsEnabled: _typingIndicatorsEnabled,
        imageFile: _pickedImage,
      );
      final raw = out['profile'];
      final hasCoreChangeRequest =
          out['coreProfileChangeRequest'] is Map ||
          (raw is Map && raw['coreProfileChangeRequest'] is Map);
      if (!mounted) return;
      if (raw is! Map) {
        setState(() {
          _saving = false;
          _error = 'تعذر حفظ التعديلات.';
        });
        return;
      }
      final profile = SocialUserProfile.fromJson(
        Map<String, dynamic>.from(raw),
      );
      if (hasCoreChangeRequest) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم إرسال طلب تعديل الاسم/اسم المستخدم إلى الإدارة للمراجعة.',
            ),
          ),
        );
      }
      Navigator.of(context).pop(profile);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = mapAnyError(e, fallback: 'تعذر حفظ التعديلات.');
      });
    }
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = (widget.initialProfile.imageUrl ?? '').trim();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'تعديل الملف الشخصي',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 10),
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundImage:
                          _pickedImage == null && avatarUrl.isNotEmpty
                          ? AppCachedImageProvider(avatarUrl)
                          : null,
                      child: _pickedImage != null
                          ? const Icon(Icons.image_rounded, size: 30)
                          : (avatarUrl.isEmpty
                                ? const Icon(Icons.person_outline, size: 30)
                                : null),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: IconButton.filled(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.camera_alt_outlined),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameCtrl,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _usernameCtrl,
                keyboardType: TextInputType.text,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'اسم المستخدم',
                  helperText: _checkingUsername
                      ? 'جارٍ التحقق من التوفر...'
                      : '@${_usernameCtrl.text.trim().toLowerCase()}',
                  errorText: _usernameError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'العمر (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bioCtrl,
                textDirection: TextDirection.rtl,
                minLines: 3,
                maxLines: 6,
                maxLength: 280,
                decoration: const InputDecoration(
                  labelText: 'نبذة تعريفية',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                value: _accountPrivate,
                onChanged: (value) => setState(() => _accountPrivate = value),
                title: const Text(
                  'جعل الحساب خاصًا',
                  textDirection: TextDirection.rtl,
                ),
                subtitle: const Text(
                  'لا يرى المحتوى إلا من لديهم علاقة مقبولة معك.',
                  textDirection: TextDirection.rtl,
                ),
              ),
              SwitchListTile.adaptive(
                value: _showPhone,
                onChanged: (value) => setState(() => _showPhone = value),
                title: const Text(
                  'إظهار رقم الهاتف في الصفحة الشخصية',
                  textDirection: TextDirection.rtl,
                ),
              ),
              SwitchListTile.adaptive(
                value: _postsPublic,
                onChanged: (value) => setState(() => _postsPublic = value),
                title: const Text(
                  'السماح للجميع برؤية منشوراتي',
                  textDirection: TextDirection.rtl,
                ),
              ),
              SwitchListTile.adaptive(
                value: _storiesPublic,
                onChanged: (value) => setState(() => _storiesPublic = value),
                title: const Text(
                  'السماح للجميع برؤية ستورياتي',
                  textDirection: TextDirection.rtl,
                ),
              ),
              SwitchListTile.adaptive(
                value: _relationsPublic,
                onChanged: (value) => setState(() => _relationsPublic = value),
                title: const Text(
                  'السماح للآخرين برؤية المتابعين والمتابَعين',
                  textDirection: TextDirection.rtl,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _onlineStatusVisibility,
                decoration: const InputDecoration(
                  labelText: 'من يرى حالة الاتصال',
                  border: OutlineInputBorder(),
                ),
                items: _buildVisibilityItems(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _onlineStatusVisibility = value);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _lastSeenVisibility,
                decoration: const InputDecoration(
                  labelText: 'من يرى آخر ظهور',
                  border: OutlineInputBorder(),
                ),
                items: _buildVisibilityItems(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _lastSeenVisibility = value);
                },
              ),
              SwitchListTile.adaptive(
                value: _readReceiptsEnabled,
                onChanged: (value) =>
                    setState(() => _readReceiptsEnabled = value),
                title: const Text(
                  'إظهار حالة قراءة الرسائل',
                  textDirection: TextDirection.rtl,
                ),
                subtitle: Text(
                  _readReceiptsEnabled
                      ? 'يرى الطرف الآخر أنك قرأت الرسائل.'
                      : 'سيتم إخفاء حالة القراءة من الطرف الآخر.',
                  textDirection: TextDirection.rtl,
                ),
              ),
              SwitchListTile.adaptive(
                value: _typingIndicatorsEnabled,
                onChanged: (value) =>
                    setState(() => _typingIndicatorsEnabled = value),
                title: const Text(
                  'إظهار مؤشر الكتابة',
                  textDirection: TextDirection.rtl,
                ),
                subtitle: const Text(
                  'إخفاء هذا الخيار يمنع ظهور "يكتب الآن" للطرف الآخر.',
                  textDirection: TextDirection.rtl,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('حفظ التعديلات'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMediaViewerPage extends StatefulWidget {
  final String mediaUrl;
  final bool isVideo;
  final String title;
  final String subtitle;
  final String? caption;

  const _ProfileMediaViewerPage({
    required this.mediaUrl,
    required this.isVideo,
    required this.title,
    required this.subtitle,
    this.caption,
  });

  @override
  State<_ProfileMediaViewerPage> createState() =>
      _ProfileMediaViewerPageState();
}

class _ProfileMediaViewerPageState extends State<_ProfileMediaViewerPage> {
  VideoPlayerController? _video;
  bool _videoReady = false;
  String? _videoError;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      if (!appSupportsInlineVideoPlayback) {
        _videoError = 'تشغيل الفيديو غير مدعوم على هذه المنصة.';
      } else {
        _initVideo();
      }
    }
  }

  Future<void> _initVideo() async {
    try {
      final mediaUrl = widget.mediaUrl.trim();
      if (mediaUrl.isEmpty) {
        setState(() => _videoError = 'رابط الفيديو غير صالح.');
        return;
      }
      final source = await MediaCacheService.instance.resolveVideoSource(
        url: mediaUrl,
      );
      final controller = source.isLocalFile
          ? VideoPlayerController.file(source.file!)
          : VideoPlayerController.networkUrl(source.uri);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _video = controller;
        _videoReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _videoError = 'تعذر تشغيل الفيديو.');
    }
  }

  Future<void> _togglePlayPause() async {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    if (video.value.isPlaying) {
      await video.pause();
    } else {
      await video.play();
    }
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            Text(widget.subtitle, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!widget.isVideo)
            InteractiveViewer(
              minScale: 0.7,
              maxScale: 4,
              child: Center(
                child: CachedAppImage(
                  imageUrl: widget.mediaUrl,
                  fit: BoxFit.contain,
                  errorWidget: (context, error, stackTrace) =>
                      const _MediaError(message: 'تعذر تحميل الصورة.'),
                ),
              ),
            )
          else if (_videoError != null)
            Center(child: _MediaError(message: _videoError!))
          else if (!_videoReady)
            const Center(child: CircularProgressIndicator())
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlayPause,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _video!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_video!),
                      AnimatedOpacity(
                        opacity: _video!.value.isPlaying ? 0 : 1,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.play_circle_fill_rounded,
                          size: 72,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if ((widget.caption ?? '').trim().isNotEmpty)
            Positioned(
              right: 12,
              left: 12,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  widget.caption!.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaError extends StatelessWidget {
  final String message;

  const _MediaError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF14243E),
      alignment: Alignment.center,
      child: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProfileFilterOption {
  final String label;
  final String? kind;
  final IconData icon;

  const _ProfileFilterOption(this.label, this.kind, this.icon);
}

class _HighlightAlbum {
  final int id;
  final String title;
  final SocialStoryHighlight cover;
  final List<SocialStory> stories;

  const _HighlightAlbum({
    required this.id,
    required this.title,
    required this.cover,
    required this.stories,
  });
}

const String _allPostsKey = '__all__';

const List<_ProfileFilterOption> _profileFilters = <_ProfileFilterOption>[
  _ProfileFilterOption('الكل', null, Icons.grid_view_rounded),
  _ProfileFilterOption('صور', 'image', Icons.image_outlined),
  _ProfileFilterOption('ريلز', 'video', Icons.ondemand_video_rounded),
  _ProfileFilterOption(
    'تقييمات',
    'merchant_review',
    Icons.rate_review_outlined,
  ),
  _ProfileFilterOption('نصوص', 'text', Icons.text_fields_rounded),
];

int? _parseInt(dynamic value) {
  if (value == null) return null;
  return int.tryParse('$value');
}

bool _parseBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value.toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return fallback;
}
