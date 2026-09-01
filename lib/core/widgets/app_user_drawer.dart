import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/app_permission_matrix.dart';
import '../../features/auth/state/auth_controller.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../../features/social/models/social_models.dart';
import '../../features/social/state/social_controller.dart';
import '../../features/social/ui/social_community_screen.dart';
import '../../features/social/ui/social_profile_screen.dart';
import '../i18n/app_strings.dart';

const Map<String, String> _drawerAutoEnglishMap = {
  'الواجهة الرئيسية': 'Home',
  'تحديث البيانات': 'Refresh Data',
  'المحادثات': 'Chats',
  'إضافة منشور': 'New Post',
  'إضافة ستوري': 'New Story',
  'الملف الشخصي': 'Profile',
  'تسجيل الخروج': 'Logout',
  'لوحة التحكم': 'Dashboard',
  'الطلبات الحالية': 'Current Orders',
  'السجل المؤرشف': 'Archive',
  'طلباتي': 'My Orders',
  'السلة': 'Cart',
  'الخريطة': 'Map',
  'المساعد الذكي': 'AI Assistant',
  'إنهاء اليوم': 'End Day',
  'لوحة التكسي': 'Taxi Board',
  'إدارة المتجر': 'Store Management',
  'إدارة الطلبات': 'Orders Management',
  'الأصناف والمنتجات': 'Categories & Products',
  'كوبونات المتجر': 'Store Coupons',
  'صندوق الموافقات': 'Approvals Inbox',
  'سجل التدقيق': 'Audit Log',
  'إدارة كوبونات الأدمن': 'Admin Coupons',
  'مراقبة المحادثات': 'Chat Monitor',
  'شديصير بسماية': 'Shdysir Basmaya',
  'دخول أي مجتمع': 'Open Any Community',
  'لوحة الإعلانات': 'Ads Board',
};

String _drawerAutoTranslate(AppStrings strings, String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty || !strings.isEnglish) return value ?? '';
  return _drawerAutoEnglishMap[text] ?? (value ?? '');
}

final _drawerCommunityScopesProvider =
    FutureProvider.autoDispose<List<SocialCommunityScopeInfo>>((ref) async {
      final out = await ref.read(socialApiProvider).listCommunityScopes();
      final raw = List<dynamic>.from(out['scopes'] as List? ?? const []);
      return raw
          .map(
            (item) => SocialCommunityScopeInfo.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
    });

class AppUserDrawerItem {
  final IconData icon;
  final String label;
  final String? subtitle;
  final String? section;
  final Future<void> Function(BuildContext context)? onTap;

  const AppUserDrawerItem({
    required this.icon,
    required this.label,
    this.subtitle,
    this.section,
    this.onTap,
  });
}

class AppUserDrawer extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final List<AppUserDrawerItem> items;
  final bool showSettings;
  final bool embedded;
  final bool showProfileButton;
  final bool showCommunitySection;

  const AppUserDrawer({
    super.key,
    required this.title,
    this.subtitle,
    this.items = const [],
    this.showSettings = true,
    this.embedded = false,
    this.showProfileButton = true,
    this.showCommunitySection = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final currentUserId = auth.user?.id;
    final permissions = ref.watch(appPermissionMatrixProvider);
    final strings = ref.watch(appStringsProvider);
    final textDirection = strings.isEnglish
        ? TextDirection.ltr
        : TextDirection.rtl;
    final userName = auth.user?.fullName.trim();
    final userPhone = auth.user?.phone.trim();
    final canUseCommunityScopes = permissions.can(
      AppCapability.socialCommunityScopes,
    );
    final communityScopesAsync = canUseCommunityScopes
        ? ref.watch(_drawerCommunityScopesProvider)
        : const AsyncValue<List<SocialCommunityScopeInfo>>.data(
            <SocialCommunityScopeInfo>[],
          );

    String normalizedCode(String? value) => (value ?? '').trim().toUpperCase();

    String? resolveBlockScopeCode() {
      final user = auth.user;
      if (user == null) return null;
      final block = normalizedCode(user.block);
      final building = normalizedCode(user.buildingNumber);
      if (RegExp(r'^[AB]$').hasMatch(block)) return block;
      if (RegExp(r'^[AB][1-9]$').hasMatch(block)) return block.substring(0, 1);
      if (RegExp(r'^[AB][1-9](0[1-9]|1[0-9]|2[0-2])$').hasMatch(building)) {
        return building.substring(0, 1);
      }
      return null;
    }

    String? resolveCompoundScopeCode() {
      final user = auth.user;
      if (user == null) return null;
      final block = normalizedCode(user.block);
      final building = normalizedCode(user.buildingNumber);
      if (RegExp(r'^[AB][1-9]$').hasMatch(block)) return block;
      if (RegExp(r'^[AB][1-9](0[1-9]|1[0-9]|2[0-2])$').hasMatch(building)) {
        return building.substring(0, 2);
      }
      return null;
    }

    String? resolveBuildingScopeCode() {
      final user = auth.user;
      if (user == null) return null;
      final building = normalizedCode(user.buildingNumber);
      if (RegExp(r'^[AB][1-9](0[1-9]|1[0-9]|2[0-2])$').hasMatch(building)) {
        return building;
      }
      return null;
    }

    final remoteScopes = communityScopesAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <SocialCommunityScopeInfo>[],
    );
    SocialCommunityScopeInfo? remoteScopeByType(String scopeType) {
      for (final scope in remoteScopes) {
        if (scope.scopeType.trim().toLowerCase() == scopeType) return scope;
      }
      return null;
    }

    final blockScope = remoteScopeByType('block');
    final compoundScope = remoteScopeByType('compound');
    final buildingScope = remoteScopeByType('building');

    final blockScopeCode = canUseCommunityScopes
        ? (blockScope?.scopeCode ?? resolveBlockScopeCode())
        : null;
    final compoundScopeCode = canUseCommunityScopes
        ? (compoundScope?.scopeCode ?? resolveCompoundScopeCode())
        : null;
    final buildingScopeCode = canUseCommunityScopes
        ? (buildingScope?.scopeCode ?? resolveBuildingScopeCode())
        : null;
    final allowManualCommunityScopeSelection = auth.isBackoffice;
    final isCommunityCatalogMode = auth.isBackoffice && remoteScopes.length > 6;
    final shouldShowCommunitySection =
        showCommunitySection &&
        (allowManualCommunityScopeSelection ||
            isCommunityCatalogMode ||
            blockScopeCode != null ||
            compoundScopeCode != null ||
            buildingScopeCode != null);

    Future<void> openProfile() async {
      final userId = currentUserId;
      if (userId == null) return;
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => SocialProfileScreen(
            userId: userId,
            initialName: auth.user?.fullName,
          ),
        ),
      );
    }

    Future<void> openSettings() async {
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
    }

    Future<void> runItem(AppUserDrawerItem item) async {
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await item.onTap?.call(navigator.context);
    }

    Future<void> openCommunityScope({
      required String scopeType,
      required String scopeCode,
      required String title,
    }) async {
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => SocialCommunityScreen(
            scopeType: scopeType,
            scopeCode: scopeCode,
            title: title,
          ),
        ),
      );
    }

    Future<void> openCommunityScopePrompt({
      required String scopeType,
      required String titleLabel,
      required String hintText,
    }) async {
      final codeCtrl = TextEditingController();
      final navigator = Navigator.of(context);
      final approved = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(titleLabel, textDirection: textDirection),
          content: TextField(
            controller: codeCtrl,
            textDirection: textDirection,
            decoration: InputDecoration(
              hintText: hintText,
              hintTextDirection: textDirection,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.t('drawerCancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(strings.t('drawerEnter')),
            ),
          ],
        ),
      );
      final scopeCode = codeCtrl.text.trim().toUpperCase();
      codeCtrl.dispose();
      if (approved != true || scopeCode.isEmpty) return;
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute(
          builder: (_) =>
              SocialCommunityScreen(scopeType: scopeType, scopeCode: scopeCode),
        ),
      );
    }

    final content = SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _drawerAutoTranslate(strings, title),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (subtitle?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(_drawerAutoTranslate(strings, subtitle!)),
                ],
                if (userName?.isNotEmpty == true ||
                    userPhone?.isNotEmpty == true)
                  const SizedBox(height: 8),
                if (userName?.isNotEmpty == true) Text(userName!),
                if (userPhone?.isNotEmpty == true) Text(userPhone!),
                if (showProfileButton && currentUserId != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: openProfile,
                      icon: const Icon(Icons.person_outline_rounded),
                      label: Text(strings.t('drawerProfile')),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  if (items[index].section != null &&
                      (index == 0 ||
                          items[index - 1].section != items[index].section))
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        14,
                        16,
                        4,
                      ),
                      child: Text(
                        _drawerAutoTranslate(strings, items[index].section),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ListTile(
                    dense: true,
                    leading: Icon(items[index].icon),
                    title: Text(
                      _drawerAutoTranslate(strings, items[index].label),
                    ),
                    subtitle: items[index].subtitle == null
                        ? null
                        : Text(
                            _drawerAutoTranslate(
                              strings,
                              items[index].subtitle!,
                            ),
                          ),
                    onTap: items[index].onTap == null
                        ? null
                        : () => runItem(items[index]),
                  ),
                ],
                if (shouldShowCommunitySection) const Divider(height: 1),
                if (shouldShowCommunitySection &&
                    (blockScopeCode != null ||
                        allowManualCommunityScopeSelection))
                  ListTile(
                    leading: const Icon(Icons.account_tree_outlined),
                    title: Text(strings.t('drawerBlockCommunity')),
                    subtitle: Text(
                      (isCommunityCatalogMode || blockScopeCode == null)
                          ? strings.t('drawerManualSelection')
                          : blockScopeCode,
                    ),
                    onTap: () =>
                        (isCommunityCatalogMode || blockScopeCode == null)
                        ? openCommunityScopePrompt(
                            scopeType: 'block',
                            titleLabel: strings.t('drawerEnterBlockCode'),
                            hintText: strings.t('drawerBlockCodeHint'),
                          )
                        : openCommunityScope(
                            scopeType: 'block',
                            scopeCode: blockScopeCode,
                            title:
                                '${strings.t('drawerBlockCommunity')} $blockScopeCode',
                          ),
                  ),
                if (shouldShowCommunitySection &&
                    (compoundScopeCode != null ||
                        allowManualCommunityScopeSelection))
                  ListTile(
                    leading: const Icon(Icons.groups_2_outlined),
                    title: Text(strings.t('drawerCompoundCommunity')),
                    subtitle: Text(
                      (isCommunityCatalogMode || compoundScopeCode == null)
                          ? strings.t('drawerManualSelection')
                          : compoundScopeCode,
                    ),
                    onTap: () =>
                        (isCommunityCatalogMode || compoundScopeCode == null)
                        ? openCommunityScopePrompt(
                            scopeType: 'compound',
                            titleLabel: strings.t('drawerEnterCompoundCode'),
                            hintText: strings.t('drawerCompoundCodeHint'),
                          )
                        : openCommunityScope(
                            scopeType: 'compound',
                            scopeCode: compoundScopeCode,
                            title:
                                '${strings.t('drawerCompoundCommunity')} $compoundScopeCode',
                          ),
                  ),
                if (shouldShowCommunitySection &&
                    (buildingScopeCode != null ||
                        allowManualCommunityScopeSelection))
                  ListTile(
                    leading: const Icon(Icons.apartment_rounded),
                    title: Text(strings.t('drawerBuildingCommunity')),
                    subtitle: Text(
                      (isCommunityCatalogMode || buildingScopeCode == null)
                          ? strings.t('drawerManualSelection')
                          : buildingScopeCode,
                    ),
                    onTap: () =>
                        (isCommunityCatalogMode || buildingScopeCode == null)
                        ? openCommunityScopePrompt(
                            scopeType: 'building',
                            titleLabel: strings.t('drawerEnterBuildingCode'),
                            hintText: strings.t('drawerBuildingCodeHint'),
                          )
                        : openCommunityScope(
                            scopeType: 'building',
                            scopeCode: buildingScopeCode,
                            title:
                                '${strings.t('drawerBuildingCommunity')} $buildingScopeCode',
                          ),
                  ),
                if (showSettings)
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: Text(strings.t('settings')),
                    onTap: openSettings,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(strings.t('logout')),
            onTap: () async {
              if (!embedded) {
                Navigator.of(context).pop();
              }
              await ref.read(authControllerProvider.notifier).logout();
            },
          ),
        ],
      ),
    );

    if (embedded) {
      return Material(
        color: Theme.of(context).drawerTheme.backgroundColor,
        child: content,
      );
    }

    return Drawer(child: content);
  }
}
