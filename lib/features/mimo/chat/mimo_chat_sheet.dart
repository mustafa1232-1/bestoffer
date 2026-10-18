import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/files/local_image_file.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/media/cached_app_image.dart';
import '../../../core/media/media_url.dart';
import '../../../core/settings/app_settings_controller.dart';
import '../../auth/state/auth_controller.dart';
import '../../orders/state/cart_controller.dart';
import '../../products/models/product_model.dart';
import '../mimo_character.dart';
import '../mimo_navigation.dart';
import '../mimo_voice.dart';
import 'mimo_chat_api.dart';
import 'mimo_chat_controller.dart';
import 'mimo_speech.dart';

const _cream = Color(0xFFFBFAF7);
const _navy = Color(0xFF0B2440);
const _ink = Color(0xFF1B2430);
const _green = Color(0xFF2F5E46);
const _gold = Color(0xFFB8893F);
const _goldLine = Color(0xFFD9C291);
const _muted = Color(0xFF5B6470);

/// Opens Mimo's half-screen chat.
Future<void> showMimoChat(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x590B2440),
    builder: (_) => const MimoChatSheet(),
  );
}

class MimoChatSheet extends ConsumerStatefulWidget {
  const MimoChatSheet({super.key});

  @override
  ConsumerState<MimoChatSheet> createState() => _MimoChatSheetState();
}

class _MimoChatSheetState extends ConsumerState<MimoChatSheet> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _nudge = 0;
  bool _typing = false;
  final List<LocalImageFile> _photos = [];
  bool _listening = false;
  bool _voiceUsed = false;
  late final MimoSpeech _speech = ref.read(mimoSpeechProvider);

  MimoSpeech get _voice {
    _voiceUsed = true;
    return _speech;
  }

  String get _lang =>
      ref.read(appSettingsControllerProvider).locale.languageCode == 'en'
      ? 'en'
      : 'ar';

  /// Mic: speak instead of typing (on-device recognition, free). The live
  /// transcript fills the input and is sent when the user stops talking.
  Future<void> _toggleMic() async {
    final speech = _voice;
    if (_listening) {
      await speech.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    HapticFeedback.mediumImpact();
    await speech.stopSpeaking();
    final ok = await speech.listen(
      lang: _lang,
      onText: (text, isFinal) {
        if (!mounted) return;
        _input.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        if (isFinal) {
          setState(() => _listening = false);
          if (text.trim().isNotEmpty) _send(text);
        }
      },
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            context.lt(
              ar: 'ما گدرت أسمعك، تأكد من إذن الميكروفون',
              en: "I can't hear you, check the microphone permission",
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _listening = true);
  }

  /// Reads Mimo's finished reply aloud when the speaker is on.
  void _onChatChanged(MimoChatState? prev, MimoChatState next) {
    if (prev == null || !prev.sending || next.sending) return;
    if (!ref.read(mimoSpeakRepliesProvider)) return;
    final last = next.messages.isEmpty ? null : next.messages.last;
    if (last == null || last.sender != MimoSender.mimo || last.failed) return;
    if (last.text.trim().isEmpty) return;
    _voice.speak(mimoLisp(last.text), lang: _lang);
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _input.addListener(() {
      final typing = _input.text.trim().isNotEmpty;
      if (typing != _typing || typing) {
        setState(() {
          _typing = typing;
          _nudge++;
        });
      }
    });
  }

  @override
  void dispose() {
    if (_voiceUsed) {
      _speech.stopListening();
      _speech.stopSpeaking();
    }
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _isEnglish =>
      ref.read(appSettingsControllerProvider).locale.languageCode == 'en';

  Future<void> _pickPhoto() async {
    if (_photos.length >= 4) return;
    final camera = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: _green),
              title: Text(context.lt(ar: 'صوّر هسه', en: 'Take a photo')),
              onTap: () => Navigator.of(context).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: _green),
              title: Text(context.lt(ar: 'من المعرض', en: 'From gallery')),
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
    if (camera == null || !mounted) return;
    final file = await ref.read(mimoPhotoPickerProvider)(camera: camera);
    if (file == null || !mounted) return;
    setState(() => _photos.add(file));
  }

  Future<void> _send(String text) async {
    final clean = text.trim();
    if (clean.isEmpty && _photos.isEmpty) return;
    if (!ref.read(authControllerProvider).isAuthed) {
      ref
          .read(mimoChatControllerProvider.notifier)
          .sayLocally(
            context.lt(
              ar: 'حتى أگدر أساعدك وأدورلك، سجل دخولك أول 😊',
              en: 'Sign in first so I can search for you 😊',
            ),
            mood: MimoMood.wink,
          );
      return;
    }
    _input.clear();
    final photos = List<LocalImageFile>.of(_photos);
    if (_photos.isNotEmpty) setState(_photos.clear);
    HapticFeedback.lightImpact();
    final future = ref
        .read(mimoChatControllerProvider.notifier)
        .send(clean, photos: photos);
    _scrollToEnd();
    await future;
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _open(MimoNavRequest request) {
    Navigator.of(context).maybePop();
    MimoNavigation.open(request);
  }

  Future<void> _addToCart(
    Map<String, dynamic> productJson, {
    required int storeId,
    required String storeName,
    int quantity = 1,
    bool hasOptions = false,
  }) async {
    final product = ProductModel.fromJson(productJson);
    if (hasOptions || product.hasVariants) {
      _open(
        MimoNavRequest.store({
          'id': storeId,
          'name': storeName,
        }, productId: product.id),
      );
      return;
    }
    final status = ref
        .read(cartControllerProvider.notifier)
        .addItem(
          product: product,
          merchantId: storeId,
          merchantName: storeName,
          quantity: quantity,
        );
    HapticFeedback.mediumImpact();
    final chat = ref.read(mimoChatControllerProvider.notifier);
    if (status != CartAddStatus.storeLimitExceeded) {
      chat.reportCartAdded([
        {'productId': product.id, 'quantity': quantity},
      ]);
    }
    if (status == CartAddStatus.storeLimitExceeded) {
      chat.sayLocally(
        context.lt(
          ar: 'السلة بيها 3 محلات، هذا الحد. كمّل طلبك أو شيل محل حتى أضيفه',
          en: 'Your cart already has 3 stores — the limit. Check out or remove one first',
        ),
        mood: MimoMood.sad,
      );
      return;
    }
    chat.sayLocally(
      context.lt(
        ar: 'تم! ضفت ${product.name} للسلة. بالعافية مقدماً 😋',
        en: 'Done! Added ${product.name} to your cart 😋',
      ),
      mood: MimoMood.yummy,
    );
    _scrollToEnd();
  }

  /// "ضيفهم كلهم": adds every item of a bundle with one tap.
  Future<void> _addBundle(List<Map<String, dynamic>> items) async {
    final cart = ref.read(cartControllerProvider.notifier);
    final chat = ref.read(mimoChatControllerProvider.notifier);
    var added = 0;
    var needsOptions = 0;
    var limited = false;
    final accepted = <Map<String, dynamic>>[];
    for (final it in items) {
      final productJson = it['product'] is Map
          ? Map<String, dynamic>.from(it['product'] as Map)
          : const <String, dynamic>{};
      final store = it['store'] is Map
          ? Map<String, dynamic>.from(it['store'] as Map)
          : const <String, dynamic>{};
      if (productJson.isEmpty) continue;
      final product = ProductModel.fromJson(productJson);
      if (it['hasOptions'] == true || product.hasVariants) {
        needsOptions++;
        continue;
      }
      final qty = ((it['quantity'] as num?) ?? 1).toInt().clamp(1, 50);
      final status = cart.addItem(
        product: product,
        merchantId: (store['id'] as num?)?.toInt() ?? product.merchantId,
        merchantName: '${store['name'] ?? ''}',
        quantity: qty,
      );
      if (status == CartAddStatus.storeLimitExceeded) {
        limited = true;
        continue;
      }
      added += qty;
      accepted.add({'productId': product.id, 'quantity': qty});
    }
    HapticFeedback.mediumImpact();
    if (accepted.isNotEmpty) chat.reportCartAdded(accepted);
    final parts = <String>[
      if (added > 0)
        context.lt(
          ar: 'ضفت $added غرض للسلة 😋',
          en: 'Added $added items to your cart 😋',
        ),
      if (needsOptions > 0)
        context.lt(
          ar: '$needsOptions منهم يحتاج تختار الحجم أو اللون من صفحة المنتج',
          en: '$needsOptions need size/color — pick them on the product page',
        ),
      if (limited)
        context.lt(
          ar: 'بعضهم ما انضاف لأن السلة وصلت 3 محلات',
          en: 'Some were skipped: the cart already has 3 stores',
        ),
    ];
    chat.sayLocally(
      parts.join('. '),
      mood: added > 0 ? MimoMood.dancing : MimoMood.sad,
    );
    _scrollToEnd();
  }

  MimoMood _headerMood(MimoChatState chat) {
    if (_typing && _focus.hasFocus) return MimoMood.down;
    if (chat.sending) {
      final last = chat.messages.isEmpty ? null : chat.messages.last;
      if (last != null && last.text.isEmpty) return MimoMood.thinking;
    }
    return chat.mood;
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(mimoChatControllerProvider);
    ref.listen<MimoChatState>(mimoChatControllerProvider, _onChatChanged);
    final animate =
        ref.watch(
          appSettingsControllerProvider.select((s) => s.animationsEnabled),
        ) &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    // Arabic typing grows right→left, English left→right.
    final frac = math.min(_input.text.length, 28) / 28;
    final lookX = _isEnglish ? -0.8 + frac * 1.6 : 0.8 - frac * 1.6;
    final current = chat.messages.isEmpty ? null : chat.messages.last;
    final statusLine = chat.sending && current != null && current.text.isEmpty
        ? (current.status ??
              context.lt(ar: 'ميمو يفكّر...', en: 'Mimo is thinking...'))
        : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.38,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, sheetScroll) {
        return Container(
          decoration: const BoxDecoration(
            color: _cream,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: _goldLine, width: 1.5)),
          ),
          child: Column(
            children: [
              // Drag handle + header (the handle area drags the sheet).
              SingleChildScrollView(
                controller: sheetScroll,
                physics: const ClampingScrollPhysics(),
                child: _Header(
                  mood: _headerMood(chat),
                  lookX: lookX,
                  nudge: _nudge,
                  animate: animate,
                  statusLine: statusLine,
                  onClose: () => Navigator.of(context).maybePop(),
                  speaking: ref.watch(mimoSpeakRepliesProvider),
                  onToggleSpeak: () {
                    final n = ref.read(mimoSpeakRepliesProvider.notifier);
                    n.state = !n.state;
                    if (!n.state) {
                      _voice.stopSpeaking();
                    }
                  },
                  onReset: chat.messages.isEmpty
                      ? null
                      : () => ref
                            .read(mimoChatControllerProvider.notifier)
                            .reset(),
                ),
              ),
              Expanded(
                child: chat.messages.isEmpty
                    ? _Welcome(onPick: _send)
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                        itemCount: chat.messages.length,
                        itemBuilder: (context, i) {
                          final m = chat.messages[chat.messages.length - 1 - i];
                          final isLast = i == 0;
                          return _MessageView(
                            message: m,
                            animate: animate,
                            showReplies: isLast && !chat.sending,
                            onReply: _send,
                            onOpen: _open,
                            onAdd: _addToCart,
                            onAddBundle: _addBundle,
                            onRate: (up) => ref
                                .read(mimoChatControllerProvider.notifier)
                                .rate(m.id, up: up),
                          );
                        },
                      ),
              ),
              _InputBar(
                controller: _input,
                focusNode: _focus,
                sending: chat.sending,
                photos: _photos,
                listening: _listening,
                showMic: _listening || (!_typing && _photos.isEmpty),
                onMic: _toggleMic,
                onAttach: _pickPhoto,
                onRemovePhoto: (i) => setState(() => _photos.removeAt(i)),
                onSend: () => _send(_input.text),
                onStop: () =>
                    ref.read(mimoChatControllerProvider.notifier).stop(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.mood,
    required this.lookX,
    required this.nudge,
    required this.animate,
    required this.statusLine,
    required this.onClose,
    required this.onReset,
    this.speaking = false,
    this.onToggleSpeak,
  });

  final bool speaking;
  final VoidCallback? onToggleSpeak;
  final MimoMood mood;
  final double lookX;
  final int nudge;
  final bool animate;
  final String? statusLine;
  final VoidCallback onClose;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: _goldLine,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 4),
          // Mimo always sits on the left, looking at what the user types.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  height: 76,
                  child: MimoCharacter(
                    mood: mood,
                    lookX: lookX,
                    nudgeTick: nudge,
                    animate: animate,
                    semanticLabel: context.lt(ar: 'ميمو', en: 'Mimo'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Directionality(
                    textDirection: Directionality.of(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.lt(ar: 'ميمو', en: 'Mimo'),
                          style: const TextStyle(
                            color: _navy,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            statusLine != null
                                ? mimoLisp(statusLine!)
                                : context.lt(
                                    ar: 'مساعدك الذكي بمسلكي',
                                    en: 'Your smart Maslaki assistant',
                                  ),
                            key: ValueKey(statusLine),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: statusLine != null ? _gold : _muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (onToggleSpeak != null)
                  IconButton(
                    key: const ValueKey('mimo-speaker'),
                    tooltip: speaking
                        ? context.lt(ar: 'اسكت ميمو', en: 'Mute Mimo')
                        : context.lt(
                            ar: 'خلي ميمو يقرا رده',
                            en: 'Read replies aloud',
                          ),
                    onPressed: onToggleSpeak,
                    icon: Icon(
                      speaking
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      color: speaking ? _green : _muted,
                    ),
                  ),
                if (onReset != null)
                  IconButton(
                    tooltip: context.lt(ar: 'محادثة جديدة', en: 'New chat'),
                    onPressed: onReset,
                    icon: const Icon(Icons.refresh_rounded, color: _muted),
                  ),
                IconButton(
                  tooltip: context.lt(ar: 'إغلاق', en: 'Close'),
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, color: _navy),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0x33B8893F)),
      ],
    );
  }
}

class _Welcome extends ConsumerWidget {
  const _Welcome({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(authControllerProvider).user?.fullName ?? '';
    final first = name.trim().split(RegExp(r'\s+')).first;
    final picks = <(IconData, String, String)>[
      (
        Icons.restaurant_rounded,
        context.lt(ar: 'أكل', en: 'Food'),
        context.lt(ar: 'أريد آكل', en: 'I want to eat'),
      ),
      (
        Icons.storefront_rounded,
        context.lt(ar: 'تسوق', en: 'Shopping'),
        context.lt(ar: 'أريد أتسوق', en: 'I want to shop'),
      ),
      (
        Icons.local_taxi_rounded,
        context.lt(ar: 'تكسي', en: 'Taxi'),
        context.lt(ar: 'أريد تكسي', en: 'I need a taxi'),
      ),
      (
        Icons.handyman_rounded,
        context.lt(ar: 'خدمات', en: 'Services'),
        context.lt(ar: 'أحتاج خدمة', en: 'I need a service'),
      ),
      (
        Icons.local_pharmacy_rounded,
        context.lt(ar: 'صيدلية', en: 'Pharmacy'),
        context.lt(ar: 'أحتاج صيدلية', en: 'I need a pharmacy'),
      ),
      (
        Icons.local_offer_rounded,
        context.lt(ar: 'عروض', en: 'Offers'),
        context.lt(ar: 'شنو العروض اليوم؟', en: "What are today's offers?"),
      ),
      (
        Icons.groups_rounded,
        context.lt(ar: 'مجتمع', en: 'Community'),
        context.lt(ar: 'وديني للمجتمع', en: 'Take me to the community'),
      ),
      (
        Icons.auto_awesome_rounded,
        context.lt(ar: 'اختارلي', en: 'Surprise me'),
        context.lt(ar: 'جوعان، اختارلي انت', en: "I'm hungry, you choose"),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      children: [
        _MimoBubble(
          text: mimoLisp(
            first.isEmpty
                ? context.lt(
                    ar: 'هلا! شتريد تسوي اليوم؟',
                    en: 'Hi! What do you want to do today?',
                  )
                : context.lt(
                    ar: 'هلا $first! شتريد تسوي اليوم؟',
                    en: 'Hi $first! What do you want to do today?',
                  ),
          ),
          animate: true,
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.92,
          children: [
            for (final (i, (icon, label, message)) in picks.indexed)
              _PickCard(
                index: i,
                icon: icon,
                label: label,
                onTap: () => onPick(message),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          context.lt(
            ar: 'أو اكتبلي أي شي… مثلاً «مشتهي تمن ومرق» أو «عندي ضيوف الليلة»',
            en: 'Or just type… e.g. "pizza for 4" or "a gift for my wife"',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.index,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final int index;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + index * 45),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.7 + 0.3 * v, child: child),
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE6D9BD)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF3ECDD),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: _green, size: 22),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef _AddToCart =
    Future<void> Function(
      Map<String, dynamic> productJson, {
      required int storeId,
      required String storeName,
      int quantity,
      bool hasOptions,
    });

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.message,
    required this.animate,
    required this.showReplies,
    required this.onReply,
    required this.onOpen,
    required this.onAdd,
    required this.onAddBundle,
    required this.onRate,
  });

  final Future<void> Function(List<Map<String, dynamic>> items) onAddBundle;
  final ValueChanged<bool> onRate;
  final MimoChatMessage message;
  final bool animate;
  final bool showReplies;
  final ValueChanged<String> onReply;
  final ValueChanged<MimoNavRequest> onOpen;
  final _AddToCart onAdd;

  @override
  Widget build(BuildContext context) {
    if (message.sender == MimoSender.user) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.75,
          ),
          decoration: const BoxDecoration(
            color: _green,
            borderRadius: BorderRadiusDirectional.only(
              topStart: Radius.circular(18),
              topEnd: Radius.circular(18),
              bottomStart: Radius.circular(18),
              bottomEnd: Radius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.photos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final bytes in message.photos)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            bytes,
                            key: const ValueKey('mimo-user-photo'),
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 120,
                              height: 120,
                              child: Icon(
                                Icons.image_rounded,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Text(
                message.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final children = <Widget>[];
    if (message.text.isEmpty && message.streaming) {
      children.add(_ThinkingDots(status: message.status));
    } else if (message.text.isNotEmpty) {
      children.add(
        _MimoBubble(
          text: mimoLisp(message.text),
          streaming: message.streaming,
          failed: message.failed,
        ),
      );
    }
    for (final block in message.blocks) {
      switch (block.type) {
        case 'stores':
          children.add(_StoresRow(block: block, onOpen: onOpen));
        case 'products':
          children.add(
            _ProductsRow(block: block, onOpen: onOpen, onAdd: onAdd),
          );
        case 'cart_proposal':
          children.add(_CartProposal(block: block, onAdd: onAdd));
        case 'cart_bundle':
          children.add(_CartBundle(block: block, onAddAll: onAddBundle));
        case 'quote':
          children.add(_QuoteCard(block: block));
        case 'services':
          children.add(_ServicesRow(block: block, onOpen: onOpen));
        case 'sources':
          children.add(_SourcesRow(block: block));
        case 'ticket':
          children.add(_TicketCard(block: block, onOpen: onOpen));
        case 'open_section':
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: () => onOpen(
                    MimoNavRequest.section('${block.data['section']}'),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    side: const BorderSide(color: _green),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(
                    context.lt(
                      ar: 'افتح ${block.data['label'] ?? ''}',
                      en: 'Open ${block.data['label'] ?? ''}',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          );
        case 'replies':
          if (showReplies) {
            children.add(
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (i, o) in block.options.indexed)
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 220 + i * 60),
                        curve: Curves.easeOutBack,
                        builder: (context, v, child) => Opacity(
                          opacity: v.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.8 + 0.2 * v,
                            child: child,
                          ),
                        ),
                        child: ActionChip(
                          label: Text(o),
                          onPressed: () => onReply(o),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: _goldLine),
                          shape: const StadiumBorder(),
                          labelStyle: const TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }
      }
    }
    // Only real answers from Mimo's brain can be rated (refs is set on done).
    if (!message.streaming && !message.failed && message.refs != null) {
      children.add(_FeedbackRow(value: message.feedback, onRate: onRate));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// 👍/👎 — every rating teaches Mimo which answers help.
class _FeedbackRow extends StatelessWidget {
  const _FeedbackRow({required this.value, required this.onRate});

  final bool? value;
  final ValueChanged<bool> onRate;

  @override
  Widget build(BuildContext context) {
    Widget button(bool up) {
      final selected = value == up;
      final dimmed = value != null && !selected;
      return IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        tooltip: up
            ? context.lt(ar: 'جواب مفيد', en: 'Helpful')
            : context.lt(ar: 'مو مفيد', en: 'Not helpful'),
        onPressed: value == null
            ? () {
                HapticFeedback.selectionClick();
                onRate(up);
              }
            : null,
        icon: AnimatedScale(
          scale: selected ? 1.25 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: Icon(
            up
                ? (selected
                      ? Icons.thumb_up_alt_rounded
                      : Icons.thumb_up_alt_outlined)
                : (selected
                      ? Icons.thumb_down_alt_rounded
                      : Icons.thumb_down_alt_outlined),
            color: dimmed
                ? _muted.withValues(alpha: 0.35)
                : (selected ? (up ? _green : const Color(0xFF9A3B30)) : _muted),
          ),
        ),
      );
    }

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(true),
          button(false),
          if (value != null)
            Text(
              mimoLisp(
                context.lt(
                  ar: value! ? 'شكراً! تعلمت' : 'تعلمت، راح أتحسن',
                  en: value! ? 'Thanks! Noted' : "Noted, I'll do better",
                ),
              ),
              style: const TextStyle(
                color: _muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _MimoBubble extends StatelessWidget {
  const _MimoBubble({
    required this.text,
    this.streaming = false,
    this.failed = false,
    this.animate = false,
  });

  final String text;
  final bool streaming;
  final bool failed;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: failed ? const Color(0xFFFBE4E1) : Colors.white,
          borderRadius: const BorderRadiusDirectional.only(
            topStart: Radius.circular(18),
            topEnd: Radius.circular(18),
            bottomEnd: Radius.circular(18),
            bottomStart: Radius.circular(4),
          ),
          border: Border.all(color: _goldLine),
        ),
        child: Text.rich(
          TextSpan(
            text: text,
            children: [
              if (streaming)
                const TextSpan(
                  text: ' ▍',
                  style: TextStyle(color: _gold),
                ),
            ],
          ),
          style: const TextStyle(
            color: _ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots({this.status});

  final String? status;

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _goldLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Transform.translate(
                      offset: Offset(
                        0,
                        -4 *
                            math.max(
                              0,
                              math.sin((_c.value - i * 0.18) * 2 * math.pi),
                            ),
                      ),
                      child: Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: const BoxDecoration(
                          color: _gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.status != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  mimoLisp(widget.status!),
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _price(num? v, BuildContext context) {
  if (v == null) return '';
  final s = v.round().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return context.lt(ar: '$s د.ع', en: '$s IQD');
}

Widget _image(
  String? raw, {
  double? width,
  double? height,
  IconData fallback = Icons.image_outlined,
}) {
  final url = resolveMediaUrl(raw);
  final placeholder = Container(
    width: width,
    height: height,
    color: const Color(0xFFF3ECDD),
    child: Icon(fallback, color: _gold),
  );
  if (url == null || url.isEmpty) return placeholder;
  return CachedAppImage(
    imageUrl: url,
    width: width,
    height: height,
    fit: BoxFit.cover,
    memCacheWidth: 400,
    placeholder: (_, _) => placeholder,
    errorWidget: (_, _, _) => placeholder,
  );
}

class _CardsTitle extends StatelessWidget {
  const _CardsTitle(this.title);

  final String? title;

  @override
  Widget build(BuildContext context) {
    if (title == null) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(
        mimoLisp(title!),
        style: const TextStyle(
          color: _navy,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _StoresRow extends StatelessWidget {
  const _StoresRow({required this.block, required this.onOpen});

  final MimoUiBlock block;
  final ValueChanged<MimoNavRequest> onOpen;

  @override
  Widget build(BuildContext context) {
    final items = block.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CardsTitle(block.title),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final s = items[i];
              final open = s['isOpen'] != false;
              final rating = (s['rating'] as num?)?.toDouble() ?? 0;
              final count = (s['ratingsCount'] as num?)?.toInt() ?? 0;
              final orders = (s['completedOrders'] as num?)?.toInt() ?? 0;
              return _AppearIn(
                index: i,
                child: _CardShell(
                  width: 214,
                  onTap: () => onOpen(MimoNavRequest.store(s)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 74,
                        width: double.infinity,
                        child: _image(
                          s['coverImageUrl'] ?? s['imageUrl'] ?? s['logoUrl'],
                          fallback: Icons.storefront_rounded,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 7, 10, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s['name'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _navy,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 15,
                                  color: _gold,
                                ),
                                Text(
                                  ' ${rating.toStringAsFixed(1)} ($count)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _ink,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    context.lt(
                                      ar: '• $orders طلب',
                                      en: '• $orders orders',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              children: [
                                _Badge(
                                  open
                                      ? context.lt(ar: 'مفتوح', en: 'Open')
                                      : context.lt(ar: 'مسدود', en: 'Closed'),
                                  color: open
                                      ? _green
                                      : const Color(0xFF9A3B30),
                                ),
                                if (s['isNew'] == true)
                                  _Badge(
                                    context.lt(ar: 'جديد', en: 'New'),
                                    color: _gold,
                                  ),
                                if (s['hasOffer'] == true)
                                  _Badge(
                                    context.lt(ar: 'عرض', en: 'Offer'),
                                    color: const Color(0xFFB4542D),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              mimoLisp('${s['note'] ?? ''}'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _gold,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                              ),
                            ),
                          ],
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
    );
  }
}

class _ProductsRow extends StatelessWidget {
  const _ProductsRow({
    required this.block,
    required this.onOpen,
    required this.onAdd,
  });

  final MimoUiBlock block;
  final ValueChanged<MimoNavRequest> onOpen;
  final _AddToCart onAdd;

  @override
  Widget build(BuildContext context) {
    final items = block.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CardsTitle(block.title),
        SizedBox(
          height: 262,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = items[i];
              final store = p['store'] is Map
                  ? Map<String, dynamic>.from(p['store'] as Map)
                  : const <String, dynamic>{};
              final price = p['price'] as num?;
              final original = p['originalPrice'] as num?;
              final discounted =
                  original != null && price != null && original > price;
              void openProduct() => onOpen(
                MimoNavRequest.store(
                  store,
                  productId: (p['id'] as num?)?.toInt(),
                ),
              );
              return _AppearIn(
                index: i,
                child: _CardShell(
                  width: 178,
                  onTap: openProduct,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 104,
                        width: double.infinity,
                        child: _image(
                          p['imageUrl'] as String?,
                          fallback: Icons.fastfood_rounded,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 7, 10, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${p['name'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _navy,
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                              ),
                            ),
                            Text(
                              '${store['name'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  _price(price, context),
                                  style: const TextStyle(
                                    color: _green,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                  ),
                                ),
                                if (discounted) ...[
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      _price(original, context),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 11,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              mimoLisp('${p['note'] ?? ''}'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: _gold,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: SizedBox(
                          width: double.infinity,
                          height: 34,
                          child: FilledButton.icon(
                            onPressed: openProduct,
                            style: FilledButton.styleFrom(
                              backgroundColor: _green,
                              shape: const StadiumBorder(),
                              padding: EdgeInsets.zero,
                              textStyle: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            icon: const Icon(
                              Icons.visibility_rounded,
                              size: 16,
                            ),
                            label: Text(context.lt(ar: 'شوفه', en: 'View')),
                          ),
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
    );
  }
}

class _CartProposal extends StatefulWidget {
  const _CartProposal({required this.block, required this.onAdd});

  final MimoUiBlock block;
  final _AddToCart onAdd;

  @override
  State<_CartProposal> createState() => _CartProposalState();
}

class _CartProposalState extends State<_CartProposal> {
  late int _qty = ((widget.block.data['quantity'] as num?) ?? 1).toInt().clamp(
    1,
    20,
  );
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.block.data;
    final product = data['product'] is Map
        ? Map<String, dynamic>.from(data['product'] as Map)
        : const <String, dynamic>{};
    final store = data['store'] is Map
        ? Map<String, dynamic>.from(data['store'] as Map)
        : const <String, dynamic>{};
    final unit = num.tryParse(
      '${product['discounted_price'] ?? product['price'] ?? ''}',
    );
    return _AppearIn(
      index: 0,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _gold, width: 1.4),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _image(
                (product['imageUrl'] ?? product['image_url']) as String?,
                width: 62,
                height: 62,
                fallback: Icons.fastfood_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product['name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${store['name'] ?? ''}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  if (unit != null)
                    Text(
                      _price(unit * _qty, context),
                      style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
            ),
            if (!_done) ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              Text(
                '$_qty',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _qty < 20 ? () => setState(() => _qty++) : null,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: _done
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: _green,
                      size: 32,
                      key: ValueKey('ok'),
                    )
                  : FilledButton(
                      key: const ValueKey('add'),
                      onPressed: () async {
                        setState(() => _done = true);
                        await widget.onAdd(
                          product,
                          storeId: (store['id'] as num?)?.toInt() ?? 0,
                          storeName: '${store['name'] ?? ''}',
                          quantity: _qty,
                          hasOptions: data['hasOptions'] == true,
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _green,
                        shape: const StadiumBorder(),
                      ),
                      child: Text(context.lt(ar: 'ضيف', en: 'Add')),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mimo raised the problem to the support team.
class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.block, required this.onOpen});

  final MimoUiBlock block;
  final ValueChanged<MimoNavRequest> onOpen;

  @override
  Widget build(BuildContext context) {
    final d = block.data;
    final id = (d['ticketId'] as num?)?.toInt() ?? 0;
    final urgent = d['priority'] == 'urgent';
    final existing = d['existing'] == true;
    return _AppearIn(
      index: 0,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: urgent ? const Color(0xFFFFF4EC) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: urgent ? const Color(0xFFB4542D) : _gold,
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (urgent ? const Color(0xFFB4542D) : _green).withValues(
                  alpha: 0.12,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                urgent
                    ? Icons.notification_important_rounded
                    : Icons.support_agent_rounded,
                color: urgent ? const Color(0xFFB4542D) : _green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing
                        ? context.lt(
                            ar: 'ضفت التحديث لتذكرتك',
                            en: 'Added to your open ticket',
                          )
                        : context.lt(
                            ar: 'وصلت مشكلتك للإدارة',
                            en: 'Support has your problem',
                          ),
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${d['ticketNumber'] ?? ''}',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    context.lt(
                      ar: 'راح يوصلك إشعار أول ما يردون',
                      en: "You'll get a notification when they reply",
                    ),
                    style: const TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            if (id > 0)
              TextButton(
                onPressed: () => onOpen(MimoNavRequest.ticket(id)),
                child: Text(context.lt(ar: 'تابعها', en: 'Track')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Where Mimo found the answer online (tap to open in the browser).
class _SourcesRow extends StatelessWidget {
  const _SourcesRow({required this.block});

  final MimoUiBlock block;

  @override
  Widget build(BuildContext context) {
    final items = block.items;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final s in items)
            ActionChip(
              avatar: const Icon(Icons.public_rounded, size: 16, color: _gold),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Text(
                  _sourceLabel(s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              backgroundColor: const Color(0xFFF7F1E7),
              side: const BorderSide(color: Color(0xFFE6D9BD)),
              shape: const StadiumBorder(),
              onPressed: () {
                final uri = Uri.tryParse('${s['url'] ?? ''}');
                final web = uri?.scheme == 'https' || uri?.scheme == 'http';
                if (uri == null || !web) return;
                launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
        ],
      ),
    );
  }

  static String _sourceLabel(Map<String, dynamic> s) {
    final title = '${s['title'] ?? ''}'.trim();
    if (title.isNotEmpty) return title;
    final host = Uri.tryParse('${s['url'] ?? ''}')?.host ?? '';
    return host.replaceFirst('www.', '');
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.block});

  final MimoUiBlock block;

  @override
  Widget build(BuildContext context) {
    final d = block.data;
    final exact = d['exact'] == true;
    Widget row(
      String label,
      num? value, {
      bool bold = false,
      Color? color,
      bool minus = false,
    }) {
      if (value == null || (value == 0 && !bold)) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: _ink,
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                  fontSize: bold ? 15 : 13,
                ),
              ),
            ),
            Text(
              '${minus ? '- ' : ''}${_price(value, context)}',
              style: TextStyle(
                color: color ?? (bold ? _green : _ink),
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                fontSize: bold ? 16 : 13,
              ),
            ),
          ],
        ),
      );
    }

    return _AppearIn(
      index: 0,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _goldLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded, color: _gold, size: 18),
                const SizedBox(width: 6),
                Text(
                  exact
                      ? context.lt(ar: 'الفاتورة المتوقعة', en: 'Expected bill')
                      : context.lt(
                          ar: 'تقدير (بدون التوصيل)',
                          en: 'Estimate (without delivery)',
                        ),
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const Divider(height: 14, color: Color(0x33B8893F)),
            row(context.lt(ar: 'المنتجات', en: 'Items'), d['subtotal'] as num?),
            row(
              context.lt(ar: 'الخصم', en: 'Discount'),
              d['discounts'] as num?,
              color: const Color(0xFFB4542D),
              minus: true,
            ),
            row(
              context.lt(ar: 'التوصيل', en: 'Delivery'),
              d['delivery'] as num?,
            ),
            row(
              context.lt(ar: 'رسوم الخدمة', en: 'Service fee'),
              d['serviceFee'] as num?,
            ),
            if (d['total'] != null) ...[
              const Divider(height: 14, color: Color(0x33B8893F)),
              row(
                context.lt(ar: 'المجموع', en: 'Total'),
                d['total'] as num?,
                bold: true,
              ),
            ],
            if (d['multiStoreNotice'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${d['multiStoreNotice']}',
                  style: const TextStyle(color: _muted, fontSize: 11.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CartBundle extends StatefulWidget {
  const _CartBundle({required this.block, required this.onAddAll});

  final MimoUiBlock block;
  final Future<void> Function(List<Map<String, dynamic>> items) onAddAll;

  @override
  State<_CartBundle> createState() => _CartBundleState();
}

class _CartBundleState extends State<_CartBundle> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.block.items;
    num total = 0;
    for (final it in items) {
      final p = it['product'] is Map ? it['product'] as Map : const {};
      final unit =
          num.tryParse('${p['discounted_price'] ?? p['price'] ?? ''}') ?? 0;
      total += unit * (((it['quantity'] as num?) ?? 1));
    }
    return _AppearIn(
      index: 0,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _gold, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final it in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3ECDD),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '×${it['quantity'] ?? 1}',
                        style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${(it['product'] is Map ? (it['product'] as Map)['name'] : '') ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${(it['store'] is Map ? (it['store'] as Map)['name'] : '') ?? ''}',
                      style: const TextStyle(color: _muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.lt(
                      ar: 'المنتجات: ${_price(total, context)}',
                      en: 'Items: ${_price(total, context)}',
                    ),
                    style: const TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: c),
                  child: _done
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: _green,
                          size: 32,
                          key: ValueKey('ok'),
                        )
                      : FilledButton.icon(
                          key: const ValueKey('add'),
                          onPressed: () async {
                            setState(() => _done = true);
                            await widget.onAddAll(items);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: _green,
                            shape: const StadiumBorder(),
                          ),
                          icon: const Icon(
                            Icons.add_shopping_cart_rounded,
                            size: 18,
                          ),
                          label: Text(
                            context.lt(ar: 'ضيفهم كلهم', en: 'Add all'),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicesRow extends StatelessWidget {
  const _ServicesRow({required this.block, required this.onOpen});

  final MimoUiBlock block;
  final ValueChanged<MimoNavRequest> onOpen;

  @override
  Widget build(BuildContext context) {
    final items = block.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CardsTitle(block.title),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final s = items[i];
              final id = (s['id'] as num?)?.toInt() ?? 0;
              final rating = (s['rating'] as num?)?.toDouble() ?? 0;
              return _AppearIn(
                index: i,
                child: _CardShell(
                  width: 220,
                  onTap: () => id > 0
                      ? onOpen(MimoNavRequest.service(id))
                      : onOpen(const MimoNavRequest.section('services')),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF3ECDD),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.handyman_rounded,
                                color: _green,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${s['provider'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _navy,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${s['title'] ?? ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 15,
                              color: _gold,
                            ),
                            Text(
                              ' ${rating.toStringAsFixed(1)} (${s['reviews'] ?? 0})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${s['price'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          mimoLisp('${s['note'] ?? ''}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _gold,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.width,
    required this.child,
    required this.onTap,
  });

  final double width;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE6D9BD)),
        ),
        child: InkWell(onTap: onTap, child: child),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Cards slide in one after another.
class _AppearIn extends StatelessWidget {
  const _AppearIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + index * 80),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: c),
      ),
      child: child,
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.onStop,
    this.photos = const [],
    this.onAttach,
    this.onRemovePhoto,
    this.listening = false,
    this.showMic = false,
    this.onMic,
  });

  final bool listening;
  final bool showMic;
  final VoidCallback? onMic;

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final List<LocalImageFile> photos;
  final VoidCallback? onAttach;
  final ValueChanged<int>? onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0x33B8893F))),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (photos.isNotEmpty)
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: photos[i].hasBytes
                              ? Image.memory(
                                  photos[i].bytes!,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.image_rounded),
                                )
                              : const Icon(Icons.image_rounded, size: 56),
                        ),
                        PositionedDirectional(
                          top: 0,
                          end: 0,
                          child: InkWell(
                            onTap: () => onRemovePhoto?.call(i),
                            child: const CircleAvatar(
                              radius: 10,
                              backgroundColor: Color(0xCC000000),
                              child: Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  if (onAttach != null)
                    IconButton(
                      key: const ValueKey('mimo-attach'),
                      tooltip: context.lt(
                        ar: 'أرفق صورة',
                        en: 'Attach a photo',
                      ),
                      onPressed: sending || photos.length >= 4
                          ? null
                          : onAttach,
                      icon: const Icon(Icons.add_photo_alternate_rounded),
                      color: _green,
                    ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => sending ? null : onSend(),
                      decoration: InputDecoration(
                        hintText: listening
                            ? context.lt(
                                ar: 'أسمعك… تكلم',
                                en: 'Listening… speak',
                              )
                            : context.lt(
                                ar: 'اكتب لميمو…',
                                en: 'Message Mimo…',
                              ),
                        filled: true,
                        fillColor: _cream,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: _goldLine),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: _goldLine),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: _gold,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (c, a) =>
                        ScaleTransition(scale: a, child: c),
                    child: !sending && showMic && onMic != null
                        ? IconButton.filled(
                            key: ValueKey(listening ? 'mic-on' : 'mic'),
                            tooltip: listening
                                ? context.lt(ar: 'خلصت', en: 'Done')
                                : context.lt(ar: 'تكلم', en: 'Speak'),
                            onPressed: onMic,
                            style: IconButton.styleFrom(
                              backgroundColor: listening
                                  ? const Color(0xFF9A3B30)
                                  : _gold,
                            ),
                            icon: Icon(
                              listening
                                  ? Icons.graphic_eq_rounded
                                  : Icons.mic_rounded,
                            ),
                          )
                        : sending
                        ? IconButton.filled(
                            key: const ValueKey('stop'),
                            tooltip: context.lt(ar: 'إيقاف', en: 'Stop'),
                            onPressed: onStop,
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF9A3B30),
                            ),
                            icon: const Icon(Icons.stop_rounded),
                          )
                        : IconButton.filled(
                            key: const ValueKey('send'),
                            tooltip: context.lt(ar: 'إرسال', en: 'Send'),
                            onPressed: onSend,
                            style: IconButton.styleFrom(
                              backgroundColor: _green,
                            ),
                            icon: const Icon(Icons.send_rounded),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
