import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:core_design_system/core_design_system.dart';

import '../../../core/auth/auth_guard.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/parsers.dart';
import '../../../core/widgets/maslaki_user_drawer.dart';
import '../../../pages/map_page.dart';
import '../../assistant/ui/assistant_chat_screen.dart';
import '../../auth/state/auth_controller.dart';
import '../../coupons/ui/customer_coupons_hub_screen.dart';
import '../../customer/state/customer_smart_experience_provider.dart';
import '../../notifications/state/notifications_controller.dart';
import '../../notifications/ui/notifications_screen.dart';
import '../../orders/ui/customer_orders_screen.dart';
import '../../orders/ui/delivery_addresses_screen.dart';
import '../../orders/ui/favorite_products_screen.dart';
import '../../paid_upgrades/ui/paid_upgrades_home_screen.dart';
import '../../pharmacy/ui/pharmacy_conversation_screen.dart';
import '../../services/ui/service_provider_onboarding_screen.dart';
import '../../settings/ui/pages/settings_account_screen.dart';
import '../../settings/ui/settings_screen.dart';
import '../../social/ui/social_profile_screen.dart';

class CustomerAccountHubScreen extends ConsumerWidget {
  const CustomerAccountHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textDirection = context.appTextDirection;
    final auth = ref.watch(authControllerProvider);
    final notifications = ref.watch(notificationsControllerProvider);
    final smartExperienceState = ref.watch(customerSmartExperienceProvider);
    final smartSnapshot = smartExperienceState.valueOrNull;
    final user = auth.user;
    final rawName = (user?.fullName ?? '').trim();
    final profileName = rawName.isNotEmpty ? rawName : context.l10n.appName;
    final phone = (user?.phone ?? '').trim();
    final userId = user?.id;
    final avatarLabel = profileName.isEmpty ? 'M' : profileName.substring(0, 1);

    Future<void> open(Widget page) {
      return Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => page));
    }

    Future<void> openSavedPlace(Map<String, dynamic> place) async {
      if (!auth.isAuthed) {
        await requireAuthBeforeAction(
          context,
          featureArabic: 'العناوين المحفوظة',
          featureEnglish: 'saved places',
        );
        return;
      }
      await open(MapPage(initialDropoffSnapshot: place));
    }

    Future<void> rebookRide(Map<String, dynamic> ride) async {
      if (!auth.isAuthed) {
        await requireAuthBeforeAction(
          context,
          featureArabic: 'إعادة المشوار الأخير',
          featureEnglish: 'rebooking a previous ride',
        );
        return;
      }
      final pickup = (ride['pickup'] as Map?)?.cast<String, dynamic>();
      final dropoff = (ride['dropoff'] as Map?)?.cast<String, dynamic>();
      final fare =
          tryParseLocalizedInt(ride['agreedFareIqd']) ??
          tryParseLocalizedInt(ride['fareAfterDiscountIqd']) ??
          tryParseLocalizedInt(ride['proposedFareIqd']);
      await open(
        MapPage(
          initialPickupSnapshot: pickup,
          initialDropoffSnapshot: dropoff,
          initialFareIqd: fare,
        ),
      );
    }

    Future<void> openProfile() async {
      if (!auth.isAuthed) {
        await requireAuthBeforeAction(
          context,
          featureArabic: 'الملف الشخصي',
          featureEnglish: 'your profile',
        );
        return;
      }
      if (userId == null || userId <= 0) return;
      await open(
        SocialProfileScreen(userId: userId, initialName: user?.fullName),
      );
    }

    Future<void> logout() async {
      await ref.read(authControllerProvider.notifier).logout();
    }

    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      endDrawer: const MaslakiUserDrawer(),
      appBar: MaslakiTopBar(
        title: context.lt(ar: 'حسابي', en: 'My account'),
        subtitle: context.lt(
          ar: 'إدارة الطلبات والعناوين والمفضلة',
          en: 'Manage orders, addresses, and favorites',
        ),
        leading: canPop
            ? IconButton(
                tooltip: context.l10n.commonBack,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : const MaslakiUserDrawerButton(),
        actions: [
          if (canPop) const MaslakiUserDrawerButton(),
          IconButton(
            tooltip: context.l10n.notificationsTitle,
            onPressed: () async {
              if (!auth.isAuthed) {
                await requireAuthBeforeAction(
                  context,
                  featureArabic: 'الإشعارات الشخصية',
                  featureEnglish: 'personal notifications',
                );
                return;
              }
              await open(const NotificationsScreen());
            },
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined),
                if (notifications.unreadCount > 0)
                  PositionedDirectional(
                    top: -6,
                    end: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        notifications.unreadCount > 99
                            ? '99+'
                            : '${notifications.unreadCount}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: MaslakiScreenFrame(
        scrollable: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MaslakiCard(
              padding: const EdgeInsets.all(MaslakiSpacing.lg),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  context.maslakiTokens.surfacePrimary,
                  context.maslakiTokens.cardElevated,
                  context.maslakiTokens.backgroundSecondary,
                ],
              ),
              child: Row(
                textDirection: textDirection,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: openProfile,
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.maslakiTokens.primaryAccent,
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: context.visualTheme.accentGold.withValues(
                              alpha: 0.16,
                            ),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        backgroundColor: context.maslakiTokens.surfaceSecondary,
                        child: Text(
                          avatarLabel,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: MaslakiSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          profileName,
                          textDirection: textDirection,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          phone.isEmpty
                              ? context.lt(
                                  ar: 'مستخدم مسلكي',
                                  en: 'Maslaki user',
                                )
                              : phone,
                          textDirection: textDirection,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            MaslakiStatusPill(
                              label: context.lt(
                                ar: 'عضو فعّال',
                                en: 'Active member',
                              ),
                              icon: Icons.verified_user_outlined,
                            ),
                            if (auth.isServiceProvider)
                              MaslakiStatusPill(
                                label: context.lt(
                                  ar: 'صاحب خدمة',
                                  en: 'Service provider',
                                ),
                                icon: Icons.handyman_outlined,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MaslakiSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: MaslakiMetricCard(
                    label: context.l10n.notificationsTitle,
                    value: '${notifications.unreadCount}',
                    icon: Icons.notifications_active_outlined,
                  ),
                ),
                const SizedBox(width: MaslakiSpacing.sm),
                Expanded(
                  child: MaslakiMetricCard(
                    label: context.lt(ar: 'العناوين', en: 'Addresses'),
                    value: '${smartSnapshot?.savedPlaces.length ?? 0}',
                    icon: Icons.place_outlined,
                  ),
                ),
                const SizedBox(width: MaslakiSpacing.sm),
                Expanded(
                  child: MaslakiMetricCard(
                    label: context.lt(ar: 'المفضلة', en: 'Favorites'),
                    value: '${smartSnapshot?.favoritesCount ?? 0}',
                    icon: Icons.favorite_border_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: MaslakiSpacing.lg),
            smartExperienceState.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (snapshot) {
                final bestForYouTitle = switch (snapshot.bestSectionKey) {
                  'services' => context.lt(
                    ar: 'الأفضل لك الآن في الخدمات',
                    en: 'Best for you now in services',
                  ),
                  'taxi' => context.lt(
                    ar: 'الأفضل لك الآن في التكسي',
                    en: 'Best for you now in taxi',
                  ),
                  _ => context.lt(
                    ar: 'الأفضل لك الآن في المتاجر',
                    en: 'Best for you now in stores',
                  ),
                };
                final bestForYouSubtitle = context.lt(
                  ar: 'اختصارات وعروض مرتبة حسب نشاطك الفعلي وآخر استخداماتك.',
                  en: 'Shortcuts and offers ranked by your actual activity and recent usage.',
                );
                final quickRows = <Widget>[
                  if (snapshot.homePlace != null)
                    MaslakiListRowCard(
                      title: context.lt(ar: 'البيت', en: 'Home'),
                      subtitle: context.lt(
                        ar: 'فتح المشوار مباشرة إلى موقعك المحفوظ',
                        en: 'Open a ride directly to your saved location',
                      ),
                      leadingIcon: Icons.home_work_outlined,
                      onTap: () => openSavedPlace(snapshot.homePlace!),
                    ),
                  if (snapshot.homePlace != null && snapshot.workPlace != null)
                    const SizedBox(height: MaslakiSpacing.sm),
                  if (snapshot.workPlace != null)
                    MaslakiListRowCard(
                      title: context.lt(ar: 'العمل', en: 'Work'),
                      subtitle: context.lt(
                        ar: 'اختصار سريع للوصول إلى وجهة العمل',
                        en: 'Quick shortcut to your work destination',
                      ),
                      leadingIcon: Icons.work_history_outlined,
                      onTap: () => openSavedPlace(snapshot.workPlace!),
                    ),
                  if ((snapshot.homePlace != null ||
                          snapshot.workPlace != null) &&
                      snapshot.lastRide != null)
                    const SizedBox(height: MaslakiSpacing.sm),
                  if (snapshot.lastRide != null)
                    MaslakiListRowCard(
                      title: context.lt(
                        ar: 'إعادة آخر مشوار',
                        en: 'Rebook last ride',
                      ),
                      subtitle: context.lt(
                        ar: 'كرر آخر رحلة بنفس المسار والأجرة المقترحة',
                        en: 'Repeat the last trip with the same route and suggested fare',
                      ),
                      leadingIcon: Icons.local_taxi_outlined,
                      onTap: () => rebookRide(snapshot.lastRide!),
                    ),
                ];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MaslakiSectionHeader(
                      title: context.lt(ar: 'الأفضل لك', en: 'Best for you'),
                      subtitle: context.lt(
                        ar: 'اختصارات مبنية على أماكنك المحفوظة وآخر المشاوير ونشاطك الفعلي',
                        en: 'Shortcuts based on your saved places, last rides, and recent activity',
                      ),
                    ),
                    const SizedBox(height: MaslakiSpacing.md),
                    MaslakiOfferBanner(
                      title: bestForYouTitle,
                      subtitle: bestForYouSubtitle,
                      ctaLabel: context.lt(ar: 'افتح الآن', en: 'Open now'),
                      onTap: () => open(const AssistantChatScreen()),
                    ),
                    if (quickRows.isNotEmpty) ...[
                      const SizedBox(height: MaslakiSpacing.md),
                      MaslakiCard(child: Column(children: quickRows)),
                    ],
                    const SizedBox(height: MaslakiSpacing.lg),
                  ],
                );
              },
            ),
            MaslakiSectionHeader(
              title: context.lt(ar: 'اختصارات الحساب', en: 'Account shortcuts'),
              subtitle: context.lt(
                ar: 'الوصول السريع إلى أكثر المسارات استخدامًا',
                en: 'Quick access to the most used flows',
              ),
            ),
            const SizedBox(height: MaslakiSpacing.md),
            MaslakiCard(
              child: Column(
                children: [
                  MaslakiListRowCard(
                    title: context.lt(ar: 'طلباتي', en: 'My orders'),
                    subtitle: context.lt(
                      ar: 'متابعة الطلبات الحالية والسابقة',
                      en: 'Track current and past orders',
                    ),
                    leadingIcon: Icons.receipt_long_rounded,
                    onTap: () => open(const CustomerOrdersScreen()),
                  ),
                  const SizedBox(height: MaslakiSpacing.sm),
                  MaslakiListRowCard(
                    title: context.lt(ar: 'المفضلة', en: 'Favorites'),
                    subtitle: context.lt(
                      ar: 'المنتجات المحفوظة للعودة السريعة',
                      en: 'Saved products for quick access',
                    ),
                    leadingIcon: Icons.favorite_border_rounded,
                    onTap: () => open(const FavoriteProductsScreen()),
                  ),
                  const SizedBox(height: MaslakiSpacing.sm),
                  MaslakiListRowCard(
                    title: context.lt(ar: 'العناوين', en: 'Addresses'),
                    subtitle: context.lt(
                      ar: 'إدارة نقاط التوصيل المحفوظة',
                      en: 'Manage saved delivery points',
                    ),
                    leadingIcon: Icons.location_on_outlined,
                    onTap: () =>
                        open(const DeliveryAddressesScreen(selectOnTap: false)),
                  ),
                  const SizedBox(height: MaslakiSpacing.sm),
                  MaslakiListRowCard(
                    title: context.lt(
                      ar: 'الأمان والحساب',
                      en: 'Security and account',
                    ),
                    subtitle: context.lt(
                      ar: 'تغيير الهاتف والرمز السري',
                      en: 'Change phone and PIN',
                    ),
                    leadingIcon: Icons.security_outlined,
                    onTap: () => open(const SettingsAccountScreen()),
                  ),
                  const SizedBox(height: MaslakiSpacing.sm),
                  MaslakiListRowCard(
                    title: context.lt(ar: 'الكوبونات', en: 'Coupons'),
                    subtitle: context.lt(
                      ar: 'عرض الكوبونات والخصومات الفعالة',
                      en: 'View active coupons and discounts',
                    ),
                    leadingIcon: Icons.discount_outlined,
                    onTap: () => open(const CustomerCouponsHubScreen()),
                  ),
                  const SizedBox(height: MaslakiSpacing.sm),
                  MaslakiListRowCard(
                    title: context.l10n.pharmacyConversationsTitle,
                    subtitle: context.lt(
                      ar: 'متابعة الوصفات والسلال المقترحة وطلبات المراجعة',
                      en: 'Follow prescriptions, proposed carts, and review requests',
                    ),
                    leadingIcon: Icons.local_pharmacy_outlined,
                    onTap: () =>
                        open(const CustomerPharmacyConversationsScreen()),
                  ),
                  const SizedBox(height: MaslakiSpacing.sm),
                  MaslakiListRowCard(
                    title: context.lt(
                      ar: 'المساعد الذكي',
                      en: 'Smart assistant',
                    ),
                    subtitle: context.lt(
                      ar: 'محادثة وبحث واقتراحات مخصصة داخل مسلكي',
                      en: 'Chat, search, and personalized suggestions inside Maslaki',
                    ),
                    leadingIcon: Icons.auto_awesome_rounded,
                    onTap: () => open(const AssistantChatScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MaslakiSpacing.lg),
            MaslakiOfferBanner(
              title: context.lt(
                ar: 'ترقية تجربتك',
                en: 'Upgrade your experience',
              ),
              subtitle: context.lt(
                ar: 'الوصول إلى الترقيات المدفوعة ومزايا النشاطات الخاصة من مكان واحد.',
                en: 'Access paid upgrades and premium activity benefits from one place.',
              ),
              ctaLabel: context.lt(ar: 'إدارة المزايا', en: 'Manage benefits'),
              onTap: () => open(const PaidUpgradesHomeScreen()),
            ),
            const SizedBox(height: MaslakiSpacing.lg),
            MaslakiCard(
              child: Column(
                children: [
                  if (!auth.isServiceProvider) ...[
                    MaslakiListRowCard(
                      title: context.lt(
                        ar: 'تسجيل مقدم خدمة',
                        en: 'Service provider registration',
                      ),
                      subtitle: context.lt(
                        ar: 'التسجيل والتفعيل مجانيان. أرسل طلبك للمراجعة وابدأ بعد الموافقة.',
                        en: 'Registration and activation are free. Submit for review and start after approval.',
                      ),
                      leadingIcon: Icons.storefront_outlined,
                      onTap: () =>
                          open(const ServiceProviderOnboardingScreen()),
                    ),
                    const SizedBox(height: MaslakiSpacing.sm),
                  ],
                  MaslakiListRowCard(
                    title: context.l10n.commonSettings,
                    subtitle: context.lt(
                      ar: 'اللغة، الواجهة، الدعم، وسجل النشاط',
                      en: 'Language, interface, support, and activity log',
                    ),
                    leadingIcon: Icons.settings_outlined,
                    onTap: () => open(const SettingsScreen()),
                  ),
                  const SizedBox(height: MaslakiSpacing.sm),
                  MaslakiListRowCard(
                    title: context.lt(
                      ar: 'الملف الاجتماعي',
                      en: 'Social profile',
                    ),
                    subtitle: context.lt(
                      ar: 'عرض ملفك العام داخل المجتمع',
                      en: 'Open your public profile inside the community',
                    ),
                    leadingIcon: Icons.person_outline_rounded,
                    onTap: openProfile,
                  ),
                  const SizedBox(height: MaslakiSpacing.sm),
                  MaslakiListRowCard(
                    title: context.l10n.commonLogout,
                    subtitle: context.lt(
                      ar: 'إنهاء الجلسة الحالية بأمان',
                      en: 'End the current session safely',
                    ),
                    leadingIcon: Icons.logout_rounded,
                    onTap: logout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
