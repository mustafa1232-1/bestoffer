import 'dart:async';

import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/media/cached_app_image.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/parsers.dart';
import '../../../pages/map_page.dart';
import '../../auth/state/auth_controller.dart';
import '../../auth/ui/merchants_list_screen.dart';
import '../../coupons/ui/customer_coupons_hub_screen.dart';
import '../../customer/ui/customer_cars_hub_screen.dart';
import '../../customer/ui/customer_main_market_screen.dart';
import '../../jobs/ui/jobs_hub_screen.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../../notifications/ui/notifications_screen.dart';
import '../../orders/ui/cart_screen.dart';
import '../../orders/ui/customer_orders_screen.dart';
import '../../orders/ui/delivery_addresses_screen.dart';
import '../../orders/ui/favorite_products_screen.dart';
import '../../real_estate/ui/real_estate_marketplace_screen.dart';
import '../../services/ui/services_marketplace_screen.dart';
import '../../settings/ui/settings_screen.dart';
import '../../social/ui/social_chat_threads_screen.dart';
import '../../social/ui/social_feed_screen.dart';
import '../../support/ui/support_tickets_screen.dart';
import '../data/assistant_api.dart';

final assistantApiProvider = Provider<AssistantApi>((ref) {
  return AssistantApi(ref.read(dioClientProvider).dio);
});

class AssistantChatScreen extends ConsumerStatefulWidget {
  const AssistantChatScreen({super.key});

  @override
  ConsumerState<AssistantChatScreen> createState() =>
      _AssistantChatScreenState();
}

class _AssistantChatScreenState extends ConsumerState<AssistantChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _guidedQueryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  _AssistantExperience _experience = _AssistantExperience.home;
  String _commerceKind = 'shopping';
  String _commercePriority = 'balanced';
  double? _commerceMaxPrice;
  bool _guidedLoading = false;
  String? _guidedError;
  Map<String, dynamic>? _guidedResult;
  bool _loading = true;
  bool _sending = false;
  bool _refreshingSession = false;
  bool _quickLoading = false;
  bool _memoryEnabled = true;
  int? _sessionId;
  String? _error;
  String? _warning;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _quickResult;
  List<Map<String, dynamic>> _messages = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _topics = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _guidedQueryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  AssistantApi get _assistantApi => ref.read(assistantApiProvider);

  Future<void> _bootstrap({bool forceNewSession = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _warning = null;
    });

    try {
      final sessionPayload = forceNewSession
          ? await _assistantApi.startNewSession()
          : await _assistantApi.getCurrentSession();
      Map<String, dynamic>? profilePayload;
      List<Map<String, dynamic>> topics = const <Map<String, dynamic>>[];
      String? warning;

      try {
        profilePayload = await _assistantApi.getAiUserProfile();
      } catch (error) {
        warning = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) =>
              'المساعد يعمل، لكن تعذر تحميل تفضيلات الذكاء الاصطناعي الآن.',
        );
      }

      try {
        topics = await _assistantApi.listAiTopics();
      } catch (error) {
        warning ??= mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) =>
              'المساعد يعمل، لكن اقتراحات المواضيع غير متاحة حاليًا.',
        );
      }

      if (!mounted) return;
      setState(() {
        _syncSessionPayload(sessionPayload);
        _applyAiProfile(profilePayload);
        _topics = topics;
        _warning = warning;
        _loading = false;
      });
      _jumpToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) => 'تعذر تشغيل المساعد الذكي حاليًا.',
        );
      });
    }
  }

  void _syncSessionPayload(Map<String, dynamic> payload) {
    _sessionId = tryParseLocalizedInt(payload['sessionId']) ?? _sessionId;
    _messages = _readMapList(payload['messages']);
  }

  void _applyAiProfile(Map<String, dynamic>? payload) {
    final profile = payload?['profile'];
    if (profile is! Map) return;
    _profile = Map<String, dynamic>.from(profile);
    final consent = profile['consentFlags'];
    if (consent is Map) {
      _memoryEnabled = consent['memoryEnabled'] != false;
    }
  }

  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _sending = true;
      _warning = null;
    });
    try {
      final payload = await _assistantApi.chat(
        message: text,
        sessionId: _sessionId,
      );
      if (!mounted) return;
      _messageController.clear();
      setState(() {
        _quickResult = null;
        _syncSessionPayload(payload);
        _sending = false;
      });
      _jumpToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _warning = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) =>
              'تعذر إرسال الرسالة الآن. إذا كانت خدمات الذكاء غير متاحة فسيعود النظام للعمل عند توفرها.',
        );
      });
    }
  }

  Future<void> _confirmDraft(String token) async {
    final safeToken = token.trim();
    if (safeToken.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _warning = null;
    });
    try {
      final payload = await _assistantApi.confirmDraft(safeToken);
      if (!mounted) return;
      setState(() {
        _quickResult = null;
        _syncSessionPayload(payload);
        _sending = false;
      });
      final createdOrder = payload['createdOrder'];
      final orderId = createdOrder is Map ? createdOrder['id'] : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            orderId == null
                ? 'تم تأكيد الطلب.'
                : 'تم تأكيد الطلب رقم #$orderId.',
          ),
        ),
      );
      _jumpToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _warning = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) =>
              'تعذر تأكيد الطلب الآن. راجع العنوان أو جرّب مرة أخرى.',
        );
      });
    }
  }

  Future<void> _startFreshSession() async {
    if (_refreshingSession) return;
    setState(() => _refreshingSession = true);
    try {
      await _bootstrap(forceNewSession: true);
    } finally {
      if (mounted) setState(() => _refreshingSession = false);
    }
  }

  Future<void> _toggleMemory(bool enabled) async {
    final previous = _memoryEnabled;
    setState(() {
      _memoryEnabled = enabled;
      _warning = null;
    });
    try {
      final payload = await _assistantApi.setAiMemoryConsent(enabled: enabled);
      if (!mounted) return;
      _applyAiProfile(payload);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _memoryEnabled = previous;
        _warning = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) => 'تعذر تحديث إعدادات ذاكرة المساعد الآن.',
        );
      });
    }
  }

  void _showExperience(_AssistantExperience experience) {
    FocusScope.of(context).unfocus();
    setState(() {
      _experience = experience;
      _guidedError = null;
      if (experience != _AssistantExperience.commerceResults) {
        _guidedResult = null;
      }
    });
  }

  Future<void> _runGuidedCommerce() async {
    if (_guidedLoading) return;
    final query = _guidedQueryController.text.trim();
    if (query.isEmpty) {
      setState(
        () => _guidedError = _commerceKind == 'restaurants'
            ? 'اكتب اسم الوجبة أو نوع الطعام الذي تريده.'
            : 'اكتب اسم المنتج أو الشيء الذي تبحث عنه.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _guidedLoading = true;
      _guidedError = null;
    });
    try {
      final result = await _assistantApi.recommendCommerce(
        query: query,
        kind: _commerceKind,
        priority: _commercePriority,
        maxPrice: _commerceMaxPrice,
        limit: 12,
      );
      if (!mounted) return;
      setState(() {
        _guidedResult = result;
        _guidedLoading = false;
        _experience = _AssistantExperience.commerceResults;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _guidedLoading = false;
        _guidedError = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) =>
              'تعذر تحليل الخيارات الآن. تحقق من الاتصال وحاول مرة أخرى.',
        );
      });
    }
  }

  List<Map<String, dynamic>> _guidedResultItems() {
    final raw = _guidedResult?['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  void _openCommerceRecommendation(Map<String, dynamic> item) {
    final merchantId = tryParseLocalizedInt(item['merchantId']);
    final productId = tryParseLocalizedInt(item['productId']);
    if (merchantId == null || merchantId <= 0) {
      _openAssistantTarget(_AssistantTarget.market);
      return;
    }
    final merchantType = '${item['merchantType'] ?? 'market'}'.trim();
    final merchant = MerchantModel(
      id: merchantId,
      name: '${item['merchantName'] ?? 'متجر'}'.trim(),
      type: merchantType.isEmpty ? 'market' : merchantType,
      activityType: merchantType.isEmpty ? 'market' : merchantType,
      imageUrl: '${item['merchantImageUrl'] ?? ''}'.trim().isEmpty
          ? null
          : '${item['merchantImageUrl']}',
      avgMerchantRating: tryParseLocalizedDouble(item['avgRating']),
      ratingCount: tryParseLocalizedInt(item['ratingCount']) ?? 0,
      isOpen: item['isOpen'] != false,
      hasDiscountOffer:
          (tryParseLocalizedDouble(item['discountedPrice']) ?? 0) > 0,
      hasFreeDeliveryOffer: item['freeDelivery'] == true,
    );
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MerchantProductsScreen(
            merchant: merchant,
            initialCategoryId: tryParseLocalizedInt(item['categoryId']),
            initialProductId: productId,
          ),
        ),
      ),
    );
  }

  Future<void> _runQuickAction(_AssistantQuickAction action) async {
    if (_quickLoading) return;
    final query = await _askForQuery(action);
    if (!mounted || query == null || query.trim().isEmpty) return;
    setState(() {
      _quickLoading = true;
      _warning = null;
    });
    try {
      late final Map<String, dynamic> result;
      switch (action) {
        case _AssistantQuickAction.commerce:
          result = await _assistantApi.recommendCommerce(query: query);
          break;
        case _AssistantQuickAction.jobs:
          result = await _assistantApi.recommendJobs(query: query);
          break;
        case _AssistantQuickAction.appSearch:
          result = await _assistantApi.appSearch(query: query);
          break;
        case _AssistantQuickAction.webSearch:
          result = await _assistantApi.webSearch(query: query);
          break;
      }
      if (!mounted) return;
      setState(() {
        _quickResult = <String, dynamic>{
          'action': action.name,
          'query': query,
          ...result,
        };
        _quickLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _quickLoading = false;
        _warning = mapAnyErrorL10n(
          error,
          fallbackBuilder: (_) => 'تعذر تنفيذ الطلب الذكي الآن.',
        );
      });
    }
  }

  void _openAssistantTarget(_AssistantTarget target) {
    final Widget screen = switch (target) {
      _AssistantTarget.market => const CustomerMainMarketScreen(),
      _AssistantTarget.taxi => const MapPage(),
      _AssistantTarget.services => const ServicesMarketplaceScreen(),
      _AssistantTarget.jobs => const JobsHubScreen(),
      _AssistantTarget.orders => const CustomerOrdersScreen(),
      _AssistantTarget.cart => const CartScreen(),
      _AssistantTarget.community => const SocialFeedScreen(),
      _AssistantTarget.messages => const SocialChatThreadsScreen(),
      _AssistantTarget.notifications => const NotificationsScreen(),
      _AssistantTarget.support => const SupportTicketsScreen(),
      _AssistantTarget.realEstate => const RealEstateMarketplaceScreen(),
      _AssistantTarget.cars => const CustomerCarsHubScreen(),
      _AssistantTarget.pharmacy => const MerchantsListScreen(
        initialType: 'market',
        initialActivityType: 'pharmacy',
        overrideTitle: 'الصيدليات',
        compactCustomerMode: true,
      ),
      _AssistantTarget.coupons => const CustomerCouponsHubScreen(),
      _AssistantTarget.favorites => const FavoriteProductsScreen(),
      _AssistantTarget.addresses => const DeliveryAddressesScreen(
        selectOnTap: true,
      ),
      _AssistantTarget.settings => const SettingsScreen(),
    };
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => screen)),
    );
  }

  Future<String?> _askForQuery(_AssistantQuickAction action) async {
    final controller = TextEditingController();
    final label = switch (action) {
      _AssistantQuickAction.commerce => 'صف ما تريد شراءه أو مطعمًا تبحث عنه',
      _AssistantQuickAction.jobs => 'اكتب نوع الوظيفة أو المهارة أو الموقع',
      _AssistantQuickAction.appSearch => 'ابحث داخل التطبيق عن متجر أو خدمة',
      _AssistantQuickAction.webSearch => 'اكتب سؤالك للبحث على الويب',
    };
    final result = await showMaslakiBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Container(
            margin: const EdgeInsets.all(MaslakiSpacing.md),
            padding: const EdgeInsets.all(MaslakiSpacing.md),
            decoration: BoxDecoration(
              color: context.maslakiTokens.cardPrimary,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: context.maslakiTokens.borderSubtle.withValues(
                  alpha: 0.9,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'نفّذ الآن',
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: MaslakiSpacing.xs),
                Text(
                  label,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: MaslakiSpacing.md),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textDirection: TextDirection.rtl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: label,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: MaslakiSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: MaslakiOutlineButton(
                        onPressed: () =>
                            Navigator.of(sheetContext).pop<String>(null),
                        label: 'إلغاء',
                        icon: Icons.close_rounded,
                      ),
                    ),
                    const SizedBox(width: MaslakiSpacing.sm),
                    Expanded(
                      child: MaslakiPrimaryButton(
                        onPressed: () => Navigator.of(
                          sheetContext,
                        ).pop<String>(controller.text.trim()),
                        label: 'تشغيل',
                        icon: Icons.auto_awesome_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();
    return result;
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _buildGuidedScaffold(BuildContext context) {
    final subtitle = switch (_experience) {
      _AssistantExperience.commerceSetup =>
        _commerceKind == 'restaurants'
            ? 'حدد طلبك وسنرتب أفضل خيارات الطعام'
            : 'حدد ما تحتاجه وسنقارن الخيارات المتاحة',
      _AssistantExperience.commerceResults =>
        'أفضل النتائج وفق السعر والتقييم والسرعة',
      _ => 'اختر ما تريد إنجازه الآن',
    };
    return Scaffold(
      appBar: MaslakiTopBar(
        title: 'مساعد مسلكي',
        subtitle: subtitle,
        actions: [
          if (_experience != _AssistantExperience.home)
            IconButton(
              tooltip: 'العودة إلى خيارات المساعد',
              onPressed: () => _showExperience(_AssistantExperience.home),
              icon: const Icon(Icons.grid_view_rounded),
            ),
        ],
      ),
      body: SafeArea(top: false, child: MaslakiScreenFrame(
        scrollable: true,
        child: switch (_experience) {
          _AssistantExperience.commerceSetup => _buildCommerceSetup(context),
          _AssistantExperience.commerceResults => _buildCommerceResults(
            context,
          ),
          _ => _buildAssistantHome(context),
        },
      )),
    );
  }

  Widget _buildAssistantHome(BuildContext context) {
    final tasks = <_AssistantTaskSpec>[
      _AssistantTaskSpec(
        title: 'تسوق بذكاء',
        subtitle: 'قارن السعر والتقييم والتوصيل',
        icon: Icons.shopping_bag_outlined,
        color: context.maslakiTokens.primaryAccent,
        onTap: () {
          setState(() => _commerceKind = 'shopping');
          _showExperience(_AssistantExperience.commerceSetup);
        },
      ),
      _AssistantTaskSpec(
        title: 'اختر وجبتك',
        subtitle: 'أفضل وجبة حسب ميزانيتك',
        icon: Icons.restaurant_rounded,
        color: context.visualTheme.accentGold,
        onTap: () {
          setState(() => _commerceKind = 'restaurants');
          _showExperience(_AssistantExperience.commerceSetup);
        },
      ),
      _AssistantTaskSpec(
        title: 'احجز تكسي',
        subtitle: 'حدد الوجهة والسعر على الخريطة',
        icon: Icons.local_taxi_rounded,
        color: context.visualTheme.accentBlue,
        onTap: () => _openAssistantTarget(_AssistantTarget.taxi),
      ),
      _AssistantTaskSpec(
        title: 'اطلب خدمة',
        subtitle: 'صيانة وتنظيف وخدمات مهنية',
        icon: Icons.handyman_rounded,
        color: context.visualTheme.accentViolet,
        onTap: () => _openAssistantTarget(_AssistantTarget.services),
      ),
      _AssistantTaskSpec(
        title: 'تابع طلباتك',
        subtitle: 'حالة الطلب والتوصيل بالتفصيل',
        icon: Icons.receipt_long_rounded,
        color: context.visualTheme.accentCyan,
        onTap: () => _openAssistantTarget(_AssistantTarget.orders),
      ),
      _AssistantTaskSpec(
        title: 'اسأل بحرية',
        subtitle: 'محادثة مساعدة داخل مسلكي',
        icon: Icons.chat_bubble_outline_rounded,
        color: context.maslakiTokens.textSecondary,
        onTap: () => _showExperience(_AssistantExperience.chat),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ما الذي تريد إنجازه؟',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: context.maslakiTokens.textPrimary,
          ),
        ),
        const SizedBox(height: MaslakiSpacing.xs),
        Text(
          'اختر مهمة واحدة، وسنطلب منك المعلومات الضرورية فقط.',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: context.maslakiTokens.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: MaslakiSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 520;
            final itemWidth = twoColumns
                ? (constraints.maxWidth - MaslakiSpacing.md) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: MaslakiSpacing.md,
              runSpacing: MaslakiSpacing.md,
              children: tasks
                  .map(
                    (task) => SizedBox(
                      width: itemWidth,
                      child: _AssistantTaskTile(spec: task),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCommerceSetup(BuildContext context) {
    const budgets = <double?>[null, 10000, 25000, 50000, 100000];
    const priorities = <(String, String, IconData)>[
      ('balanced', 'الأفضل', Icons.auto_awesome_rounded),
      ('price', 'الأوفر', Icons.savings_outlined),
      ('rating', 'الأعلى تقييماً', Icons.star_outline_rounded),
      ('speed', 'الأسرع', Icons.bolt_rounded),
      ('offers', 'العروض', Icons.local_offer_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const <ButtonSegment<String>>[
            ButtonSegment<String>(
              value: 'shopping',
              icon: Icon(Icons.shopping_bag_outlined),
              label: Text('منتج'),
            ),
            ButtonSegment<String>(
              value: 'restaurants',
              icon: Icon(Icons.restaurant_rounded),
              label: Text('طعام'),
            ),
          ],
          selected: <String>{_commerceKind},
          onSelectionChanged: (selection) {
            setState(() {
              _commerceKind = selection.first;
              _guidedError = null;
            });
          },
        ),
        const SizedBox(height: MaslakiSpacing.lg),
        Text(
          _commerceKind == 'restaurants'
              ? 'ماذا تريد أن تأكل؟'
              : 'ما الذي تبحث عنه؟',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: MaslakiSpacing.sm),
        TextField(
          controller: _guidedQueryController,
          textDirection: TextDirection.rtl,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _runGuidedCommerce(),
          decoration: InputDecoration(
            hintText: _commerceKind == 'restaurants'
                ? 'مثال: برغر، مشويات، حلويات'
                : 'مثال: سماعة لاسلكية، كرسي مكتب',
            prefixIcon: const Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: MaslakiSpacing.lg),
        const _AssistantSectionLabel(title: 'ميزانيتك'),
        const SizedBox(height: MaslakiSpacing.sm),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: MaslakiSpacing.sm,
          runSpacing: MaslakiSpacing.sm,
          children: budgets
              .map((budget) {
                final label = budget == null
                    ? 'بدون حد'
                    : 'حتى ${formatIqd(budget, withCode: false)}';
                return ChoiceChip(
                  selected: _commerceMaxPrice == budget,
                  label: Text(label, textDirection: TextDirection.rtl),
                  onSelected: (_) => setState(() => _commerceMaxPrice = budget),
                );
              })
              .toList(growable: false),
        ),
        const SizedBox(height: MaslakiSpacing.lg),
        const _AssistantSectionLabel(title: 'ما الأهم لك؟'),
        const SizedBox(height: MaslakiSpacing.sm),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: MaslakiSpacing.sm,
          runSpacing: MaslakiSpacing.sm,
          children: priorities
              .map((option) {
                return ChoiceChip(
                  selected: _commercePriority == option.$1,
                  avatar: Icon(option.$3, size: 18),
                  label: Text(option.$2, textDirection: TextDirection.rtl),
                  onSelected: (_) =>
                      setState(() => _commercePriority = option.$1),
                );
              })
              .toList(growable: false),
        ),
        if (_guidedError != null) ...[
          const SizedBox(height: MaslakiSpacing.md),
          Text(
            _guidedError!,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: MaslakiSpacing.xl),
        MaslakiPrimaryButton(
          label: _guidedLoading ? 'نحلل الخيارات...' : 'اعرض أفضل الخيارات',
          icon: _guidedLoading ? null : Icons.auto_awesome_rounded,
          onPressed: _guidedLoading ? null : _runGuidedCommerce,
        ),
      ],
    );
  }

  Widget _buildCommerceResults(BuildContext context) {
    final items = _guidedResultItems();
    final summary = '${_guidedResult?['summary'] ?? ''}'.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          textDirection: TextDirection.rtl,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'اختيارات مناسبة لك',
                    textDirection: TextDirection.rtl,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (summary.isNotEmpty)
                    Text(
                      summary,
                      textDirection: TextDirection.rtl,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تعديل الاختيارات',
              onPressed: () =>
                  _showExperience(_AssistantExperience.commerceSetup),
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
        const SizedBox(height: MaslakiSpacing.md),
        if (items.isEmpty)
          MaslakiEmptyState(
            icon: Icons.search_off_rounded,
            title: 'لا توجد نتيجة مطابقة',
            body: summary.isEmpty
                ? 'غيّر الميزانية أو استخدم اسماً أبسط للمنتج.'
                : summary,
            action: MaslakiOutlineButton(
              label: 'تعديل البحث',
              icon: Icons.tune_rounded,
              onPressed: () =>
                  _showExperience(_AssistantExperience.commerceSetup),
            ),
          )
        else
          for (final item in items) ...[
            _CommerceRecommendationCard(
              item: item,
              onOpen: () => _openCommerceRecommendation(item),
            ),
            const SizedBox(height: MaslakiSpacing.md),
          ],
      ],
    );
  }

  List<Map<String, dynamic>> _readMapList(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  String _profileName() {
    final profile = _profile;
    if (profile == null) return '';
    const keys = <String>[
      'displayName',
      'display_name',
      'realName',
      'real_name',
      'nickname',
    ];
    for (final key in keys) {
      final value = '${profile[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _profileCity() {
    final city = '${_profile?['city'] ?? ''}'.trim();
    return city;
  }

  List<Map<String, dynamic>> _quickResultItems() {
    final quickResult = _quickResult;
    if (quickResult == null) return const <Map<String, dynamic>>[];
    final items = quickResult['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  String _quickItemTitle(Map<String, dynamic> item) {
    for (final key in const <String>[
      'title',
      'name',
      'merchantName',
      'merchant_name',
      'jobTitle',
      'job_title',
      'label',
    ]) {
      final value = '${item[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return 'عنصر مقترح';
  }

  String _quickItemSubtitle(Map<String, dynamic> item) {
    final parts = <String>[];
    for (final key in const <String>[
      'reason',
      'categoryName',
      'merchantType',
      'city',
      'salaryLabel',
      'priceLabel',
      'summary',
      'snippet',
      'url',
    ]) {
      final value = '${item[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        parts.add(value);
      }
      if (parts.length >= 2) break;
    }
    return parts.join(' • ');
  }

  String _messageText(Map<String, dynamic> message) {
    final text = '${message['text'] ?? ''}'.trim();
    if (text.isNotEmpty) return text;
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    if (_experience != _AssistantExperience.chat) {
      return _buildGuidedScaffold(context);
    }
    final auth = ref.watch(authControllerProvider);
    final rawUserName = auth.user?.fullName.trim() ?? '';
    final displayName = _profileName().isNotEmpty
        ? _profileName()
        : (rawUserName.isNotEmpty ? rawUserName : context.l10n.appName);
    final city = _profileCity();
    final quickItems = _quickResultItems();

    return Scaffold(
      appBar: MaslakiTopBar(
        title: 'المساعد الذكي',
        subtitle: 'اقتراحات، بحث، ومحادثة ذكية داخل مسلكي',
        actions: [
          IconButton(
            tooltip: 'خيارات المساعد',
            onPressed: () => _showExperience(_AssistantExperience.home),
            icon: const Icon(Icons.grid_view_rounded),
          ),
          IconButton(
            tooltip: 'جلسة جديدة',
            onPressed: _refreshingSession ? null : _startFreshSession,
            icon: _refreshingSession
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MaslakiScreenFrame(
              child: Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? _AssistantErrorCard(message: _error!, onRetry: _bootstrap)
                    : ListView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          MaslakiCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  textDirection: TextDirection.rtl,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            displayName,
                                            textDirection: TextDirection.rtl,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                          const SizedBox(
                                            height: MaslakiSpacing.xs,
                                          ),
                                          Text(
                                            city.isEmpty
                                                ? 'المساعد جاهز لترتيب اقتراحاتك وطلباتك.'
                                                : 'مهيأ الآن لمدينة $city',
                                            textDirection: TextDirection.rtl,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: MaslakiSpacing.sm),
                                    const MaslakiStatusPill(
                                      label: 'نشط',
                                      icon: Icons.auto_awesome_rounded,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: MaslakiSpacing.md),
                                Material(
                                  type: MaterialType.transparency,
                                  child: SwitchListTile.adaptive(
                                    value: _memoryEnabled,
                                    onChanged: _toggleMemory,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'تفعيل ذاكرة المساعد',
                                      textDirection: TextDirection.rtl,
                                    ),
                                    subtitle: const Text(
                                      'يحفظ التفضيلات والأنماط لتقديم اقتراحات أدق لاحقًا.',
                                      textDirection: TextDirection.rtl,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_warning != null) ...[
                            const SizedBox(height: MaslakiSpacing.md),
                            MaslakiCard(
                              borderColor: Theme.of(
                                context,
                              ).colorScheme.error.withValues(alpha: 0.4),
                              child: Text(
                                _warning!,
                                textDirection: TextDirection.rtl,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                          const SizedBox(height: MaslakiSpacing.md),
                          MaslakiCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'أوامر سريعة',
                                  textDirection: TextDirection.rtl,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: MaslakiSpacing.md),
                                Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: MaslakiSpacing.sm,
                                  runSpacing: MaslakiSpacing.sm,
                                  children: [
                                    _QuickActionChip(
                                      icon: Icons.storefront_rounded,
                                      label: 'افتح السوق',
                                      onTap: () => _openAssistantTarget(
                                        _AssistantTarget.market,
                                      ),
                                    ),
                                    _QuickActionChip(
                                      icon: Icons.local_taxi_rounded,
                                      label: 'حجز تكسي',
                                      onTap: () => _openAssistantTarget(
                                        _AssistantTarget.taxi,
                                      ),
                                    ),
                                    _QuickActionChip(
                                      icon: Icons.handyman_rounded,
                                      label: 'طلب خدمة',
                                      onTap: () => _openAssistantTarget(
                                        _AssistantTarget.services,
                                      ),
                                    ),
                                    _QuickActionChip(
                                      icon: Icons.shopping_bag_outlined,
                                      label: 'اقتراح متاجر',
                                      onTap: () => _runQuickAction(
                                        _AssistantQuickAction.commerce,
                                      ),
                                    ),
                                    _QuickActionChip(
                                      icon: Icons.work_outline_rounded,
                                      label: 'اقتراح وظائف',
                                      onTap: () => _runQuickAction(
                                        _AssistantQuickAction.jobs,
                                      ),
                                    ),
                                    _QuickActionChip(
                                      icon: Icons.search_rounded,
                                      label: 'بحث داخل التطبيق',
                                      onTap: () => _runQuickAction(
                                        _AssistantQuickAction.appSearch,
                                      ),
                                    ),
                                    _QuickActionChip(
                                      icon: Icons.public_rounded,
                                      label: 'بحث ويب',
                                      onTap: () => _runQuickAction(
                                        _AssistantQuickAction.webSearch,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_topics.isNotEmpty) ...[
                                  const SizedBox(height: MaslakiSpacing.md),
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: MaslakiSpacing.sm,
                                    runSpacing: MaslakiSpacing.sm,
                                    children: _topics.take(6).map((topic) {
                                      final label =
                                          '${topic['topicLabel'] ?? topic['topic'] ?? topic['name'] ?? ''}'
                                              .trim();
                                      if (label.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      return MaslakiChip(
                                        label: label,
                                        icon: Icons.bolt_rounded,
                                        onTap: () {
                                          _messageController.text = label;
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                                if (_quickLoading) ...[
                                  const SizedBox(height: MaslakiSpacing.md),
                                  const LinearProgressIndicator(),
                                ],
                              ],
                            ),
                          ),
                          if (_quickResult != null) ...[
                            const SizedBox(height: MaslakiSpacing.md),
                            MaslakiCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${_quickResult?['summary'] ?? 'نتيجة ذكية'}',
                                    textDirection: TextDirection.rtl,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  if (quickItems.isEmpty) ...[
                                    const SizedBox(height: MaslakiSpacing.sm),
                                    const Text(
                                      'لا توجد عناصر مطابقة الآن، لكن يمكنك تعديل الطلب أو إعادة المحاولة.',
                                      textDirection: TextDirection.rtl,
                                    ),
                                  ],
                                  for (final item in quickItems.take(4)) ...[
                                    const SizedBox(height: MaslakiSpacing.sm),
                                    MaslakiListRowCard(
                                      title: _quickItemTitle(item),
                                      subtitle: _quickItemSubtitle(item),
                                      leadingIcon:
                                          Icons.auto_awesome_motion_rounded,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: MaslakiSpacing.md),
                          if (_messages.isEmpty)
                            const MaslakiEmptyState(
                              icon: Icons.forum_outlined,
                              title: 'ابدأ المحادثة الآن',
                              body:
                                  'اسأل عن متجر، خدمة، عرض، أو اكتب ما تحتاجه وسيرتب لك المساعد الخيارات الأنسب.',
                            )
                          else
                            ..._messages.map(
                              (message) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: MaslakiSpacing.sm,
                                ),
                                child: _AssistantMessageBubble(
                                  role: '${message['role'] ?? ''}',
                                  text: _messageText(message),
                                  metadata: message['metadata'] is Map
                                      ? Map<String, dynamic>.from(
                                          message['metadata'] as Map,
                                        )
                                      : const <String, dynamic>{},
                                  onConfirmDraft: _confirmDraft,
                                  onOpenTarget: _openAssistantTarget,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                MaslakiSpacing.md,
                0,
                MaslakiSpacing.md,
                MaslakiSpacing.md,
              ),
              child: MaslakiCard(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 4,
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                          hintText: 'اكتب سؤالك أو طلبك هنا...',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: MaslakiSpacing.sm),
                    MaslakiPrimaryButton(
                      onPressed: _sending ? null : _sendMessage,
                      icon: _sending ? null : Icons.send_rounded,
                      label: _sending ? 'جارٍ الإرسال' : 'إرسال',
                      expanded: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _AssistantExperience { home, commerceSetup, commerceResults, chat }

class _AssistantTaskSpec {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AssistantTaskSpec({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _AssistantTaskTile extends StatelessWidget {
  final _AssistantTaskSpec spec;

  const _AssistantTaskTile({required this.spec});

  @override
  Widget build(BuildContext context) {
    return MaslakiCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: spec.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Padding(
              padding: const EdgeInsets.all(MaslakiSpacing.md),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: spec.color.withValues(alpha: 0.12),
                      border: Border.all(
                        color: spec.color.withValues(alpha: 0.38),
                      ),
                    ),
                    child: Icon(spec.icon, color: spec.color),
                  ),
                  const SizedBox(width: MaslakiSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          spec.title,
                          textDirection: TextDirection.rtl,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          spec.subtitle,
                          textDirection: TextDirection.rtl,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: context.maslakiTokens.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: MaslakiSpacing.sm),
                  Icon(
                    Icons.chevron_left_rounded,
                    color: context.maslakiTokens.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantSectionLabel extends StatelessWidget {
  final String title;

  const _AssistantSectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

class _CommerceRecommendationCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onOpen;

  const _CommerceRecommendationCard({required this.item, required this.onOpen});

  String get _recommendationKey =>
      '${item['recommendationKey'] ?? 'recommended'}'.trim();

  List<String> get _recommendationTags => (item['recommendationTags'] is List)
      ? List<dynamic>.from(
          item['recommendationTags'] as List,
        ).map((value) => '$value').toList(growable: false)
      : <String>[_recommendationKey];

  String get _badgeLabel {
    final tags = _recommendationTags;
    if (tags.contains('best_match') && tags.contains('best_price')) {
      return 'الأفضل والأوفر';
    }
    return switch (_recommendationKey) {
      'best_match' => 'الأفضل لك',
      'best_rating' => 'الأعلى تقييماً',
      'best_price' => 'الأوفر',
      'fastest' => 'الأسرع',
      _ => 'خيار مناسب',
    };
  }

  IconData get _badgeIcon => switch (_recommendationKey) {
    'best_rating' => Icons.star_rounded,
    'best_price' => Icons.savings_rounded,
    'fastest' => Icons.bolt_rounded,
    _ => Icons.auto_awesome_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final imageUrl = '${item['productImageUrl'] ?? ''}'.trim();
    final productName = '${item['productName'] ?? 'منتج'}'.trim();
    final merchantName = '${item['merchantName'] ?? ''}'.trim();
    final reason = '${item['reason'] ?? ''}'.trim();
    final effectivePrice = tryParseLocalizedDouble(item['effectivePrice']) ?? 0;
    final basePrice = tryParseLocalizedDouble(item['basePrice']) ?? 0;
    final rating = tryParseLocalizedDouble(item['avgRating']) ?? 0;
    final ratingCount = tryParseLocalizedInt(item['ratingCount']) ?? 0;
    final deliveryMinutes =
        tryParseLocalizedDouble(item['avgDeliveryMinutes']) ?? 0;
    final accent = _recommendationKey == 'best_price'
        ? context.visualTheme.accentGold
        : _recommendationKey == 'fastest'
        ? context.visualTheme.accentBlue
        : context.maslakiTokens.primaryAccent;

    return MaslakiCard(
      padding: EdgeInsets.zero,
      borderColor: accent.withValues(alpha: 0.38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 172,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(7),
                  ),
                  child: imageUrl.isEmpty
                      ? ColoredBox(
                          color: context.maslakiTokens.surfaceSecondary,
                          child: Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: context.maslakiTokens.textMuted,
                          ),
                        )
                      : CachedAppImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 172,
                          errorWidget: (_, _, _) => ColoredBox(
                            color: context.maslakiTokens.surfaceSecondary,
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: context.maslakiTokens.textMuted,
                            ),
                          ),
                        ),
                ),
                PositionedDirectional(
                  top: MaslakiSpacing.sm,
                  start: MaslakiSpacing.sm,
                  child: MaslakiStatusPill(
                    label: _badgeLabel,
                    icon: _badgeIcon,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(MaslakiSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  productName,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                if (merchantName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    merchantName,
                    textDirection: TextDirection.rtl,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.maslakiTokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: MaslakiSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: MaslakiSpacing.sm,
                  runSpacing: MaslakiSpacing.xs,
                  children: [
                    if (rating > 0)
                      _RecommendationMetric(
                        icon: Icons.star_rounded,
                        label:
                            '${rating.toStringAsFixed(1)}${ratingCount > 0 ? ' ($ratingCount)' : ''}',
                      ),
                    if (deliveryMinutes > 0)
                      _RecommendationMetric(
                        icon: Icons.schedule_rounded,
                        label: '${deliveryMinutes.round()} دقيقة',
                      ),
                    if (item['freeDelivery'] == true)
                      const _RecommendationMetric(
                        icon: Icons.delivery_dining_rounded,
                        label: 'توصيل مجاني',
                      ),
                  ],
                ),
                const SizedBox(height: MaslakiSpacing.md),
                Row(
                  textDirection: TextDirection.rtl,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatIqd(effectivePrice),
                      textDirection: TextDirection.rtl,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (basePrice > effectivePrice && effectivePrice > 0) ...[
                      const SizedBox(width: MaslakiSpacing.sm),
                      Text(
                        formatIqd(basePrice),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: context.maslakiTokens.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: MaslakiSpacing.sm),
                  Text(
                    reason,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.maslakiTokens.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: MaslakiSpacing.md),
                MaslakiPrimaryButton(
                  label: 'عرض المنتج في المتجر',
                  icon: Icons.storefront_rounded,
                  onPressed: onOpen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationMetric extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RecommendationMetric({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: context.maslakiTokens.primaryAccent),
        const SizedBox(width: 4),
        Text(
          label,
          textDirection: TextDirection.rtl,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

enum _AssistantQuickAction { commerce, jobs, appSearch, webSearch }

enum _AssistantTarget {
  market,
  taxi,
  services,
  jobs,
  orders,
  cart,
  community,
  messages,
  notifications,
  support,
  realEstate,
  cars,
  pharmacy,
  coupons,
  favorites,
  addresses,
  settings,
}

class _AssistantActionSpec {
  final _AssistantTarget target;
  final IconData icon;
  final String label;

  const _AssistantActionSpec({
    required this.target,
    required this.icon,
    required this.label,
  });
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MaslakiChip(label: label, icon: icon, onTap: onTap);
  }
}

class _AssistantMessageBubble extends StatelessWidget {
  final String role;
  final String text;
  final Map<String, dynamic> metadata;
  final ValueChanged<String> onConfirmDraft;
  final ValueChanged<_AssistantTarget> onOpenTarget;

  const _AssistantMessageBubble({
    required this.role,
    required this.text,
    required this.metadata,
    required this.onConfirmDraft,
    required this.onOpenTarget,
  });

  @override
  Widget build(BuildContext context) {
    final isAssistant = role.trim().toLowerCase() == 'assistant';
    final draftToken = '${metadata['draftToken'] ?? ''}'.trim();
    final canConfirmDraft =
        isAssistant &&
        draftToken.isNotEmpty &&
        '${metadata['type'] ?? ''}'.trim() == 'draft_created';
    final actions = isAssistant
        ? _assistantActionSpecs(metadata: metadata, text: text)
        : const <_AssistantActionSpec>[];
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    return Align(
      alignment: isAssistant ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(MaslakiSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isAssistant
              ? tokens.surfacePrimary.withValues(alpha: 0.94)
              : visual.accentBlue.withValues(alpha: 0.16),
          border: Border.all(
            color: isAssistant
                ? tokens.primaryAccent.withValues(alpha: 0.34)
                : visual.accentCyan.withValues(alpha: 0.24),
          ),
        ),
        child: Column(
          crossAxisAlignment: isAssistant
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              isAssistant ? 'المساعد' : 'أنت',
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: isAssistant ? tokens.primaryAccent : visual.accentCyan,
              ),
            ),
            const SizedBox(height: MaslakiSpacing.xs),
            Text(
              text,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (canConfirmDraft) ...[
              const SizedBox(height: MaslakiSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: MaslakiPrimaryButton(
                  onPressed: () => onConfirmDraft(draftToken),
                  icon: Icons.check_circle_outline_rounded,
                  label: 'تأكيد الطلب',
                  expanded: false,
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: MaslakiSpacing.sm),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: MaslakiSpacing.xs,
                runSpacing: MaslakiSpacing.xs,
                textDirection: TextDirection.rtl,
                children: actions
                    .map(
                      (action) => OutlinedButton.icon(
                        onPressed: () => onOpenTarget(action.target),
                        icon: Icon(action.icon, size: 18),
                        label: Text(
                          action.label,
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

List<_AssistantActionSpec> _assistantActionSpecs({
  required Map<String, dynamic> metadata,
  required String text,
}) {
  final domain = '${metadata['assistDomain'] ?? ''}'.trim().toLowerCase();
  final recommendations = '${metadata['domainRecommendationsType'] ?? ''}'
      .trim()
      .toLowerCase();
  final type = '${metadata['type'] ?? ''}'.trim().toLowerCase();
  final haystack = <String>[
    domain,
    recommendations,
    type,
    text,
  ].join(' ').toLowerCase();

  final actions = <_AssistantActionSpec>[];
  final added = <_AssistantTarget>{};

  void add(_AssistantTarget target, IconData icon, String label) {
    if (!added.add(target)) return;
    actions.add(_AssistantActionSpec(target: target, icon: icon, label: label));
  }

  void addTargetName(String targetName) {
    switch (targetName.trim().toLowerCase()) {
      case 'market':
      case 'commerce':
      case 'shopping':
        add(_AssistantTarget.market, Icons.storefront_rounded, 'افتح السوق');
        break;
      case 'taxi':
      case 'ride':
        add(_AssistantTarget.taxi, Icons.local_taxi_rounded, 'افتح التكسي');
        break;
      case 'services':
      case 'service':
        add(_AssistantTarget.services, Icons.handyman_rounded, 'افتح الخدمات');
        break;
      case 'jobs':
      case 'job':
        add(_AssistantTarget.jobs, Icons.work_outline_rounded, 'افتح الوظائف');
        break;
      case 'orders':
      case 'order':
        add(_AssistantTarget.orders, Icons.receipt_long_rounded, 'افتح طلباتي');
        break;
      case 'cart':
      case 'basket':
        add(_AssistantTarget.cart, Icons.shopping_cart_rounded, 'افتح السلة');
        break;
      case 'community':
      case 'social':
        add(_AssistantTarget.community, Icons.groups_rounded, 'افتح المجتمع');
        break;
      case 'messages':
      case 'message':
      case 'chat':
        add(
          _AssistantTarget.messages,
          Icons.chat_bubble_rounded,
          'افتح الرسائل',
        );
        break;
      case 'notifications':
      case 'notification':
        add(
          _AssistantTarget.notifications,
          Icons.notifications_rounded,
          'افتح الإشعارات',
        );
        break;
      case 'support':
      case 'help':
        add(
          _AssistantTarget.support,
          Icons.support_agent_rounded,
          'افتح الدعم',
        );
        break;
      case 'real_estate':
      case 'realestate':
      case 'properties':
        add(
          _AssistantTarget.realEstate,
          Icons.apartment_rounded,
          'افتح العقارات',
        );
        break;
      case 'cars':
      case 'car_market':
        add(
          _AssistantTarget.cars,
          Icons.directions_car_filled_rounded,
          'افتح السيارات',
        );
        break;
      case 'pharmacy':
      case 'pharmacies':
        add(
          _AssistantTarget.pharmacy,
          Icons.local_pharmacy_rounded,
          'افتح الصيدليات',
        );
        break;
      case 'coupons':
      case 'coupon':
        add(_AssistantTarget.coupons, Icons.discount_rounded, 'افتح الكوبونات');
        break;
      case 'favorites':
      case 'saved_items':
        add(_AssistantTarget.favorites, Icons.favorite_rounded, 'افتح المفضلة');
        break;
      case 'addresses':
      case 'saved_addresses':
        add(
          _AssistantTarget.addresses,
          Icons.location_on_rounded,
          'افتح العناوين',
        );
        break;
      case 'settings':
      case 'account':
      case 'profile':
        add(
          _AssistantTarget.settings,
          Icons.settings_rounded,
          'افتح الإعدادات',
        );
        break;
    }
  }

  final uiActions = metadata['uiActions'];
  if (uiActions is List) {
    for (final item in uiActions) {
      if (item is Map) {
        addTargetName('${item['target'] ?? ''}');
      } else {
        addTargetName('$item');
      }
    }
  }

  bool mentionsAny(Iterable<String> words) => words.any(haystack.contains);

  if (mentionsAny(const [
    'taxi',
    'ride',
    'trip',
    'تكسي',
    'تاكسي',
    'رحلة',
    'مشوار',
  ])) {
    add(_AssistantTarget.taxi, Icons.local_taxi_rounded, 'افتح التكسي');
  }

  if (mentionsAny(const [
    'service',
    'services',
    'maintenance',
    'legal',
    'medical',
    'sos',
    'خدمة',
    'خدمات',
    'صيانة',
    'طبية',
    'قانونية',
    'تنظيف',
    'طوارئ',
  ])) {
    add(_AssistantTarget.services, Icons.handyman_rounded, 'افتح الخدمات');
  }

  if (mentionsAny(const [
    'jobs',
    'job',
    'career',
    'cv',
    'وظيفة',
    'وظائف',
    'عمل',
    'سيرة',
  ])) {
    add(_AssistantTarget.jobs, Icons.work_outline_rounded, 'افتح الوظائف');
  }

  if (mentionsAny(const [
    'commerce',
    'shopping',
    'merchant',
    'store',
    'product',
    'restaurant',
    'market',
    'سوق',
    'تسوق',
    'متجر',
    'متاجر',
    'منتج',
    'مطعم',
    'مطاعم',
    'خصم',
    'عروض',
  ])) {
    add(_AssistantTarget.market, Icons.storefront_rounded, 'افتح السوق');
  }

  if (mentionsAny(const [
    'order',
    'orders',
    'draft_created',
    'طلب',
    'طلباتي',
    'طلبات',
  ])) {
    add(_AssistantTarget.orders, Icons.receipt_long_rounded, 'افتح طلباتي');
  }

  if (mentionsAny(const [
    'cart',
    'basket',
    'checkout',
    'سلة',
    'السلة',
    'الدفع',
  ])) {
    add(_AssistantTarget.cart, Icons.shopping_cart_rounded, 'افتح السلة');
  }

  if (mentionsAny(const [
    'community',
    'social',
    'post',
    'reel',
    'story',
    'مجتمع',
    'منشور',
    'ريل',
    'ستوري',
  ])) {
    add(_AssistantTarget.community, Icons.groups_rounded, 'افتح المجتمع');
  }

  if (mentionsAny(const [
    'messages',
    'message',
    'chat',
    'رسائل',
    'رسالة',
    'محادثة',
  ])) {
    add(_AssistantTarget.messages, Icons.chat_bubble_rounded, 'افتح الرسائل');
  }

  if (mentionsAny(const [
    'notifications',
    'notification',
    'إشعارات',
    'إشعار',
    'اشعارات',
    'اشعار',
  ])) {
    add(
      _AssistantTarget.notifications,
      Icons.notifications_rounded,
      'افتح الإشعارات',
    );
  }

  if (mentionsAny(const ['support', 'help ticket', 'دعم', 'شكوى', 'تذكرة'])) {
    add(_AssistantTarget.support, Icons.support_agent_rounded, 'افتح الدعم');
  }

  if (mentionsAny(const [
    'real estate',
    'property',
    'properties',
    'عقار',
    'عقارات',
    'بيت للبيع',
    'بيت للايجار',
  ])) {
    add(_AssistantTarget.realEstate, Icons.apartment_rounded, 'افتح العقارات');
  }
  if (mentionsAny(const ['cars', 'car market', 'سيارة', 'سيارات'])) {
    add(
      _AssistantTarget.cars,
      Icons.directions_car_filled_rounded,
      'افتح السيارات',
    );
  }
  if (mentionsAny(const [
    'pharmacy',
    'medicine',
    'prescription',
    'صيدلية',
    'صيدليات',
    'دواء',
    'وصفة',
  ])) {
    add(
      _AssistantTarget.pharmacy,
      Icons.local_pharmacy_rounded,
      'افتح الصيدليات',
    );
  }
  if (mentionsAny(const ['coupon', 'coupons', 'كوبون', 'كوبونات', 'قسيمة'])) {
    add(_AssistantTarget.coupons, Icons.discount_rounded, 'افتح الكوبونات');
  }
  if (mentionsAny(const ['favorites', 'saved items', 'المفضلة', 'مفضلة'])) {
    add(_AssistantTarget.favorites, Icons.favorite_rounded, 'افتح المفضلة');
  }
  if (mentionsAny(const [
    'addresses',
    'saved address',
    'العناوين',
    'عنوان محفوظ',
  ])) {
    add(_AssistantTarget.addresses, Icons.location_on_rounded, 'افتح العناوين');
  }
  if (mentionsAny(const [
    'settings',
    'profile',
    'account',
    'اعدادات',
    'إعدادات',
    'حساب',
    'ملف شخصي',
    'تعديل اسمي',
    'تغيير اسمي',
  ])) {
    add(_AssistantTarget.settings, Icons.settings_rounded, 'افتح الإعدادات');
  }

  return actions.take(3).toList(growable: false);
}

class _AssistantErrorCard extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _AssistantErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MaslakiCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.assistant_outlined, size: 42),
            const SizedBox(height: MaslakiSpacing.md),
            Text(
              message,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MaslakiSpacing.md),
            MaslakiPrimaryButton(
              onPressed: () => onRetry(),
              icon: Icons.refresh_rounded,
              label: 'إعادة المحاولة',
            ),
          ],
        ),
      ),
    );
  }
}
