// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/platform/app_platform_capabilities.dart';
import '../../../core/settings/app_settings_controller.dart';
import '../../../core/widgets/maslaki_brand_mark.dart';
import '../../../core/widgets/maslaki_wordmark.dart';
import '../../settings/ui/settings_screen.dart';
import '../domain/auth_input_normalizer.dart';
import '../state/auth_controller.dart';
import 'mandatory_pin_change_screen.dart';
import 'register_screen.dart';
import 'widgets/mimo_character.dart';

// Palette of the "ميمو بصفحة الدخول" design.
const _ink = Color(0xFF1B2430);
const _navy = Color(0xFF0B2440);
const _green = Color(0xFF2F5E46);
const _goldFocus = Color(0xFFB8893F);
const _goldBorder = Color(0xFFC2AE85);
const _cardBorder = Color(0xFFC9B48A);
const _errorRed = Color(0xFFB42318);

enum _LoginStatus { idle, invalid, loading, error, success }

enum _FocusTarget { none, phone, pin }

/// شاشة الدخول الأساسية للتطبيق مع الشخصية "ميمو" التي تتفاعل مع المستخدم:
/// تنظر للحقل أثناء الكتابة، تغمض عيونها عند إظهار الرمز، تنصدم عند الفشل
/// الأول، تزعل عند الثاني، وترتاح أو تفرح عند النجاح.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.popOnSuccess = false});

  final bool popOnSuccess;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final phoneCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  final _phoneFocus = FocusNode();
  final _pinFocus = FocusNode();
  late final AnimationController _introCtrl;
  late final AnimationController _shakeCtrl;

  String? _phoneError;
  String? _pinError;
  String? _serverError;
  bool _loginInFlight = false;
  bool _pinVisible = false;

  _LoginStatus _status = _LoginStatus.idle;
  _FocusTarget _focus = _FocusTarget.none;
  int _fails = 0;
  int _nudgeTick = 0;
  int _mimoShakeTick = 0;
  bool _sleepy = false;
  bool _petting = false;
  Timer? _sleepTimer;
  Timer? _petTimer;

  bool get _busy => _loginInFlight || ref.read(authControllerProvider).loading;

  bool get _animationsEnabled =>
      ref.read(appSettingsControllerProvider).animationsEnabled;

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _phoneFocus.addListener(_onFocusChanged);
    _pinFocus.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_animationsEnabled) {
        _introCtrl.forward();
      } else {
        _introCtrl.value = 1;
      }
    });
    _serverError = _safeAuthMessage(ref.read(authControllerProvider).error);
    _scheduleSleep();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _petTimer?.cancel();
    _introCtrl.dispose();
    _shakeCtrl.dispose();
    _phoneFocus.dispose();
    _pinFocus.dispose();
    phoneCtrl.dispose();
    pinCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Mimo interaction state
  // ---------------------------------------------------------------------------

  /// Any interaction wakes Mimo up and restarts the "falls asleep" countdown.
  void _poke() {
    if (_sleepy) setState(() => _sleepy = false);
    _scheduleSleep();
  }

  void _scheduleSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(const Duration(seconds: 18), () {
      if (!mounted) return;
      if (_focus == _FocusTarget.none && _status == _LoginStatus.idle) {
        setState(() => _sleepy = true);
      }
    });
  }

  void _onFocusChanged() {
    final next = _phoneFocus.hasFocus
        ? _FocusTarget.phone
        : _pinFocus.hasFocus
        ? _FocusTarget.pin
        : _FocusTarget.none;
    if (next == _focus) return;
    setState(() {
      _focus = next;
      if (next != _FocusTarget.none && _status == _LoginStatus.success) {
        _status = _LoginStatus.idle;
      }
    });
    _poke();
  }

  void _onTyped() {
    _poke();
    setState(() {
      _nudgeTick++;
      if (_status == _LoginStatus.error || _status == _LoginStatus.invalid) {
        _status = _LoginStatus.idle;
      }
      _serverError = null;
    });
  }

  void _petMimo() {
    if (_busy || _status == _LoginStatus.success) return;
    HapticFeedback.selectionClick();
    _poke();
    _petTimer?.cancel();
    setState(() => _petting = true);
    _petTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _petting = false);
    });
  }

  MimoMood _mood() {
    switch (_status) {
      case _LoginStatus.success:
        return _fails >= 2 ? MimoMood.relieved : MimoMood.happy;
      case _LoginStatus.loading:
        return MimoMood.thinking;
      case _LoginStatus.error:
        return _fails >= 2 ? MimoMood.angry : MimoMood.shocked;
      case _LoginStatus.invalid:
        return MimoMood.sad;
      case _LoginStatus.idle:
        break;
    }
    if (_petting) return MimoMood.love;
    if (_focus == _FocusTarget.pin && _pinVisible) return MimoMood.closed;
    if (_focus != _FocusTarget.none) return MimoMood.down;
    if (_sleepy) return MimoMood.sleepy;
    return MimoMood.idle;
  }

  /// Gaze follows the caret: text grows left-to-right in both fields.
  double _lookX() {
    final (len, max) = switch (_focus) {
      _FocusTarget.phone => (phoneCtrl.text.length, 11),
      _FocusTarget.pin => (pinCtrl.text.length, 8),
      _FocusTarget.none => (0, 1),
    };
    return -0.8 + (math.min(len, max) / max) * 1.6;
  }

  _BubbleData? _bubble(BuildContext context) {
    switch (_status) {
      case _LoginStatus.success:
        return _fails >= 2
            ? _BubbleData(context.lt(ar: 'لقد أخفتني!', en: 'You scared me!'))
            : _BubbleData(context.lt(ar: 'هلا بيك!', en: 'Welcome!'));
      case _LoginStatus.error:
        return _fails >= 2
            ? _BubbleData(
                context.lt(ar: 'منو انت؟!', en: 'Who are you?!'),
                background: _errorRed,
                foreground: Colors.white,
              )
            : _BubbleData(context.lt(ar: 'منو انت؟', en: 'Who are you?'));
      case _LoginStatus.invalid:
        return _BubbleData(context.lt(ar: 'كمّل البيانات', en: 'Almost there'));
      case _LoginStatus.loading:
      case _LoginStatus.idle:
        break;
    }
    if (_petting) {
      return _BubbleData(context.lt(ar: 'تدغدغني!', en: 'That tickles!'));
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Validation & submit
  // ---------------------------------------------------------------------------

  /// يتحقق من صحة الهاتف قبل إرسال الطلب إلى الخادم لتقليل round-trips.
  String? _validatePhone(BuildContext context, String value) {
    final normalized = normalizeIraqiPhoneForAuth(value);
    if (normalized.isEmpty) {
      return context.l10n.authPhoneRequired;
    }
    if (!isPlausibleAuthLoginPhone(normalized)) {
      return context.l10n.authPhoneIncomplete;
    }
    return null;
  }

  /// يتحقق من صيغة PIN المتوقعة من النظام قبل login.
  String? _validatePin(BuildContext context, String value) {
    final normalized = normalizeAuthPin(value);
    if (normalized.isEmpty) {
      return context.l10n.authPinRequired;
    }
    if (!RegExp(r'^[0-9]{4,8}$').hasMatch(normalized)) {
      return context.l10n.authPinInvalidFormat;
    }
    return null;
  }

  void _playFailFeedback() {
    if (_animationsEnabled) _shakeCtrl.forward(from: 0);
    _mimoShakeTick++;
    HapticFeedback.mediumImpact();
  }

  /// Runs while the app is about to leave this screen: Mimo cheers first.
  Future<void> _celebrate() async {
    if (!mounted) return;
    setState(() => _status = _LoginStatus.success);
    HapticFeedback.lightImpact();
    if (_animationsEnabled) {
      await Future<void>.delayed(const Duration(milliseconds: 850));
    }
  }

  /// ينفذ login ثم يطبق guard إضافي لمسار owner-only إذا كانت الشاشة مستخدمة
  /// داخل تطبيق أو تدفق مقصور على أصحاب المتاجر.
  Future<void> _submitLogin(BuildContext context) async {
    if (_loginInFlight) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    FocusScope.of(context).unfocus();
    _poke();
    final phoneError = _validatePhone(context, phoneCtrl.text);
    final pinError = _validatePin(context, pinCtrl.text);
    setState(() {
      _phoneError = phoneError;
      _pinError = pinError;
      _serverError = null;
    });
    if (phoneError != null || pinError != null) {
      setState(() => _status = _LoginStatus.invalid);
      _playFailFeedback();
      return;
    }

    setState(() {
      _loginInFlight = true;
      _status = _LoginStatus.loading;
    });
    final notifier = ref.read(authControllerProvider.notifier);
    notifier.beforeLoginCommit = _celebrate;
    try {
      await notifier.login(phoneCtrl.text, pinCtrl.text);
    } finally {
      if (notifier.beforeLoginCommit == _celebrate) {
        notifier.beforeLoginCommit = null;
      }
      if (mounted) setState(() => _loginInFlight = false);
    }

    if (!mounted) return;
    final authAfter = ref.read(authControllerProvider);
    if (!authAfter.isAuthed && authAfter.error != null) {
      setState(() {
        _fails++;
        _status = _LoginStatus.error;
        _serverError =
            _safeAuthMessage(authAfter.error) ??
            context.lt(
              ar: 'رقم الهاتف أو الرمز السري غير صحيح',
              en: 'Wrong phone number or PIN',
            );
      });
      _playFailFeedback();
      return;
    }
    if (authAfter.isCustomer ||
        authAfter.isAdminDashboardUser ||
        authAfter.isServiceProvider) {
      if (_status != _LoginStatus.success) {
        setState(() => _status = _LoginStatus.success);
      }
      if (authAfter.user?.mustChangePin == true) {
        if (!context.mounted) return;
        final navigator = Navigator.of(context);
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => MandatoryPinChangeScreen(initialPin: pinCtrl.text),
          ),
        );
      }
      if (widget.popOnSuccess && context.mounted) {
        Navigator.of(context).pop(true);
      }
      return;
    }

    if (authAfter.isAuthed) {
      await ref.read(authControllerProvider.notifier).logout();
      if (!mounted) return;
      setState(() => _status = _LoginStatus.idle);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.authUserOnlyAppError)),
      );
    } else if (mounted) {
      setState(() => _status = _LoginStatus.idle);
    }
  }

  Future<void> _requestPinReset() async {
    final phone = phoneCtrl.text.trim();
    final error = _validatePhone(context, phone);
    if (error != null) {
      setState(() {
        _phoneError = error;
        _status = _LoginStatus.invalid;
      });
      _playFailFeedback();
      return;
    }
    await ref.read(authControllerProvider.notifier).requestPinReset(phone);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إرسال طلب إعادة التعيين إلى الإدارة')),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  /// يبني shell شاشة الدخول مع دعم layout مكتبي/هاتفي وسلوك اللغة الحالي.
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(appSettingsControllerProvider);
    final useDesktopLayout =
        appIsDesktop && MediaQuery.sizeOf(context).width >= 1180;
    final pad = useDesktopLayout ? 24.0 : 16.0;

    final stage = _LoginStage(
      intro: _introCtrl,
      mimo: MimoCharacter(
        mood: _mood(),
        lookX: _lookX(),
        animate: settings.animationsEnabled,
        nudgeTick: _nudgeTick,
        shakeTick: _mimoShakeTick,
        semanticLabel: context.lt(ar: 'ميمو', en: 'Mimo'),
      ),
      onMimoTap: _petMimo,
      bubble: _bubble(context),
      animate: settings.animationsEnabled,
      card: _buildLoginCard(context, auth: auth, settings: settings),
    );

    return Scaffold(
      // We manage the keyboard inset manually (viewInsets padding + scroll) so
      // the card is never force-shrunk into an overflow.
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFE6E4DC),
      body: Stack(
        children: [
          const _LoginBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewInsetsBottom = MediaQuery.viewInsetsOf(
                  context,
                ).bottom;
                final visibleHeight =
                    (constraints.maxHeight - viewInsetsBottom - pad * 2).clamp(
                      0.0,
                      double.infinity,
                    );
                final content = useDesktopLayout
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Expanded(child: _DesktopLoginShowcase()),
                          const SizedBox(width: 32),
                          SizedBox(width: 440, child: stage),
                        ],
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: stage,
                      );
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    _poke();
                  },
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      pad,
                      pad,
                      pad,
                      pad + viewInsetsBottom,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: visibleHeight),
                      child: Center(child: content),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// يبني بطاقة الدخول: الحقول والإجراءات الثانوية.
  Widget _buildLoginCard(
    BuildContext context, {
    required AuthState auth,
    required AppSettingsState settings,
  }) {
    final l10n = context.l10n;
    final busy = auth.loading || _loginInFlight;
    final success = _status == _LoginStatus.success;
    final hasError = _status == _LoginStatus.error;
    final anim = settings.animationsEnabled;
    final fast = anim ? const Duration(milliseconds: 220) : Duration.zero;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const MaslakiBrandMark(size: 46, borderRadius: 13),
            const SizedBox(width: 10),
            const Expanded(
              child: MaslakiWordmark(
                arabicSize: 24,
                latinSize: 9,
                latinLetterSpacing: 3.4,
                arabicColor: _navy,
                crossAxisAlignment: CrossAxisAlignment.start,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: l10n.commonLanguage,
              icon: const Icon(Icons.translate_rounded, color: _navy),
              onSelected: (code) {
                ref
                    .read(appSettingsControllerProvider.notifier)
                    .setLocale(Locale(code));
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'ar', child: Text(l10n.commonArabic)),
                PopupMenuItem(value: 'en', child: Text(l10n.commonEnglish)),
              ],
            ),
            IconButton(
              tooltip: l10n.commonSettings,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              icon: const Icon(Icons.settings_outlined, color: _navy),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE4EAE6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFB9A57C)),
          ),
          child: Text(
            l10n.authLoginTagline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF2F3845),
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: _shakeCtrl,
          builder: (context, child) {
            final v = _shakeCtrl.value;
            final dx = _shakeCtrl.isAnimating
                ? math.sin(v * math.pi * 6) * (1 - v) * 10
                : 0.0;
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MimoField(
                controller: phoneCtrl,
                focusNode: _phoneFocus,
                hint: l10n.authPhoneLabel,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                maxLength: 16,
                focused: _focus == _FocusTarget.phone,
                hasError: hasError || _phoneError != null,
                errorText: _phoneError,
                animate: anim,
                prefixIcon: Icons.phone_iphone_rounded,
                onSubmitted: (_) => _pinFocus.requestFocus(),
                onChanged: (_) {
                  if (_phoneError != null) _phoneError = null;
                  _onTyped();
                },
              ),
              const SizedBox(height: 12),
              _MimoField(
                controller: pinCtrl,
                focusNode: _pinFocus,
                hint: l10n.authPinLabel,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: 8,
                obscure: !_pinVisible,
                focused: _focus == _FocusTarget.pin,
                hasError: hasError || _pinError != null,
                errorText: _pinError,
                animate: anim,
                prefixIcon: Icons.lock_outline_rounded,
                onSubmitted: (_) {
                  if (!busy) _submitLogin(context);
                },
                onChanged: (_) {
                  if (_pinError != null) _pinError = null;
                  _onTyped();
                },
                trailing: IconButton(
                  tooltip: _pinVisible
                      ? context.lt(ar: 'إخفاء الرمز', en: 'Hide PIN')
                      : context.lt(ar: 'إظهار الرمز', en: 'Show PIN'),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _pinVisible = !_pinVisible);
                    _poke();
                  },
                  icon: AnimatedSwitcher(
                    duration: fast,
                    transitionBuilder: (child, a) =>
                        ScaleTransition(scale: a, child: child),
                    child: Icon(
                      _pinVisible
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      key: ValueKey(_pinVisible),
                      color: _navy.withOpacity(0.7),
                      size: 21,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _SmoothSize(
          animate: anim,
          child: AnimatedSwitcher(
            duration: fast,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, -0.4),
                  end: Offset.zero,
                ).animate(a),
                child: child,
              ),
            ),
            child: _serverError == null
                ? const SizedBox(width: double.infinity, height: 0)
                : Padding(
                    key: ValueKey(_serverError),
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _serverError!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _errorRed,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        _Pressable(
          enabled: !busy && !success,
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: busy || success ? null : () => _submitLogin(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _green.withOpacity(success ? 1 : 0.82),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: AnimatedSwitcher(
                duration: fast,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.7, end: 1.0).animate(a),
                    child: child,
                  ),
                ),
                child: success
                    ? const Icon(
                        Icons.check_rounded,
                        key: ValueKey('ok'),
                        size: 26,
                      )
                    : busy
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.authLogin, key: const ValueKey('label')),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: busy ? null : _requestPinReset,
          style: TextButton.styleFrom(foregroundColor: _ink),
          child: const Text(
            'نسيت الرمز الخاص بي',
            style: TextStyle(fontSize: 15),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
          },
          style: TextButton.styleFrom(foregroundColor: _ink),
          child: Text(
            l10n.authCreateUserAccount,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        const SizedBox(height: 6),
        _Pressable(
          enabled: !busy,
          child: SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      await ref
                          .read(authControllerProvider.notifier)
                          .continueAsGuest();
                    },
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: const Icon(Icons.person_outline_rounded, size: 20),
              label: Text(
                context.lt(ar: 'الدخول كزائر', en: 'Continue as Guest'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Stage: Mimo sitting on the card ledge + speech bubble + card
// -----------------------------------------------------------------------------

class _BubbleData {
  const _BubbleData(
    this.text, {
    this.background = Colors.white,
    this.foreground = _navy,
  });

  final String text;
  final Color background;
  final Color foreground;
}

class _LoginStage extends StatelessWidget {
  const _LoginStage({
    required this.intro,
    required this.mimo,
    required this.onMimoTap,
    required this.bubble,
    required this.animate,
    required this.card,
  });

  final Animation<double> intro;
  final Widget mimo;
  final VoidCallback onMimoTap;
  final _BubbleData? bubble;
  final bool animate;
  final Widget card;

  // Geometry from the design (390pt frame, 354pt card).
  static const double _top = 8;
  static const double _cardTop = _top + 134;
  static const double _mimoW = 130;
  static const double _mimoH = 139;

  @override
  Widget build(BuildContext context) {
    final cardIn = CurvedAnimation(
      parent: intro,
      curve: const Interval(0, 0.7, curve: Curves.easeOutCubic),
    );
    final mimoIn = CurvedAnimation(
      parent: intro,
      curve: const Interval(0.3, 1, curve: Curves.easeOutBack),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // Mimo sits slightly off-centre on the ledge, like the mock.
        final mimoLeft = w / 2 - _mimoW / 2 - 18 * (w / 354);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Card (+ ledge) slides up into place.
            AnimatedBuilder(
              animation: cardIn,
              builder: (context, child) => Opacity(
                opacity: cardIn.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, (1 - cardIn.value) * 28),
                  child: child,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: _cardTop - 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(
                      height: 24,
                      child: CustomPaint(painter: _LedgePainter()),
                    ),
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white, Color(0xFFFBFAF7)],
                          stops: [0, 0.14],
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(6),
                          bottom: Radius.circular(26),
                        ),
                        border: Border.fromBorderSide(
                          BorderSide(color: _cardBorder),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x240B2440),
                            offset: Offset(0, 26),
                            blurRadius: 44,
                          ),
                          BoxShadow(
                            color: _cardBorder,
                            offset: Offset(0, 10),
                            spreadRadius: -1,
                          ),
                          BoxShadow(
                            color: Color(0xFFE3D4B3),
                            offset: Offset(0, 10),
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                        child: card,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Soft contact shadow under Mimo.
            Positioned(
              top: _cardTop - 10,
              left: mimoLeft + 20,
              width: 92,
              height: 12,
              child: FadeTransition(
                opacity: mimoIn,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [Color(0x4D0B2440), Color(0x000B2440)],
                    ),
                    borderRadius: BorderRadius.all(Radius.elliptical(46, 6)),
                  ),
                ),
              ),
            ),
            // Mimo drops onto the ledge.
            Positioned(
              top: _top,
              left: mimoLeft,
              width: _mimoW,
              height: _mimoH,
              child: AnimatedBuilder(
                animation: mimoIn,
                builder: (context, child) {
                  final v = mimoIn.value;
                  return Opacity(
                    opacity: v.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, (1 - v) * -36),
                      child: child,
                    ),
                  );
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onMimoTap,
                  child: mimo,
                ),
              ),
            ),
            // Speech bubble, tail toward Mimo.
            Positioned(
              top: _top,
              right: 0,
              child: _SpeechBubble(data: bubble, animate: animate),
            ),
          ],
        );
      },
    );
  }
}

class _LedgePainter extends CustomPainter {
  const _LedgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final inset = 18.0;
    final ledge = Path()
      ..moveTo(inset, 0)
      ..lineTo(w - inset, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      ledge,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE9DFC9), Color(0xFFF6F0E3)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawLine(
      Offset(inset * 2, 1),
      Offset(w - inset, 1),
      Paint()
        ..color = _cardBorder.withOpacity(0.7)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Pops in with a spring, then "types" its text letter by letter.
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.data, required this.animate});

  final _BubbleData? data;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final d = data;
    // The bubble sits right of Mimo; its sharp corner (the tail) points at him.
    const tailAlign = Alignment.bottomLeft;
    return AnimatedSwitcher(
      duration: animate ? const Duration(milliseconds: 320) : Duration.zero,
      reverseDuration: animate
          ? const Duration(milliseconds: 160)
          : Duration.zero,
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a.drive(CurveTween(curve: const Interval(0, 0.6))),
        child: ScaleTransition(alignment: tailAlign, scale: a, child: child),
      ),
      child: d == null
          ? const SizedBox(key: ValueKey('none'))
          : Container(
              key: ValueKey('${d.text}|${d.background.value}'),
              constraints: const BoxConstraints(maxWidth: 132),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: d.background,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24000000),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: _TypewriterText(
                text: d.text,
                animate: animate,
                style: TextStyle(
                  color: d.foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
            ),
    );
  }
}

class _TypewriterText extends StatefulWidget {
  const _TypewriterText({
    required this.text,
    required this.style,
    required this.animate,
  });

  final String text;
  final TextStyle style;
  final bool animate;

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 40 * widget.text.characters.length + 60),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.characters;
    return Semantics(
      liveRegion: true,
      label: widget.text,
      child: ExcludeSemantics(
        child: Stack(
          children: [
            // Reserves the final size so the bubble never jitters.
            Opacity(
              opacity: 0,
              child: Text(
                widget.text,
                style: widget.style,
                textAlign: TextAlign.center,
              ),
            ),
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final count = (chars.length * _ctrl.value).ceil();
                final shown = chars.take(count).toString();
                final cursor = _ctrl.value < 1 ? '▍' : '';
                return Text.rich(
                  TextSpan(
                    text: shown,
                    children: [
                      TextSpan(
                        text: cursor,
                        style: TextStyle(
                          color: widget.style.color?.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                  style: widget.style,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Fields & buttons
// -----------------------------------------------------------------------------

class _MimoField extends StatelessWidget {
  const _MimoField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.keyboardType,
    required this.textInputAction,
    required this.maxLength,
    required this.focused,
    required this.hasError,
    required this.animate,
    required this.prefixIcon,
    this.errorText,
    this.obscure = false,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final int maxLength;
  final bool focused;
  final bool hasError;
  final bool animate;
  final IconData prefixIcon;
  final String? errorText;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final duration = animate
        ? const Duration(milliseconds: 200)
        : Duration.zero;
    final borderColor = hasError
        ? _errorRed
        : focused
        ? _goldFocus
        : _goldBorder;
    final strong = hasError || focused;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          height: 50,
          padding: EdgeInsetsDirectional.only(
            start: 14,
            end: trailing == null ? 14 : 2,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: strong ? 2 : 1),
            boxShadow: [
              BoxShadow(
                color: (hasError ? _errorRed : _goldFocus).withOpacity(
                  strong ? 0.16 : 0,
                ),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: duration,
                child: Icon(
                  prefixIcon,
                  key: ValueKey(borderColor),
                  size: 20,
                  color: strong ? borderColor : _navy.withOpacity(0.45),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    keyboardType: keyboardType,
                    textInputAction: textInputAction,
                    obscureText: obscure,
                    obscuringCharacter: '●',
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    // Hint follows the UI language; typed digits stay LTR.
                    textAlign:
                        controller.text.isEmpty &&
                            Directionality.of(context) == TextDirection.rtl
                        ? TextAlign.right
                        : TextAlign.left,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9٠-٩۰-۹+ ]'),
                      ),
                      LengthLimitingTextInputFormatter(maxLength),
                    ],
                    style: TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: obscure ? 3 : 0.4,
                    ),
                    cursorColor: _goldFocus,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: hint,
                      hintStyle: const TextStyle(
                        color: Color(0xFF6B7380),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        _SmoothSize(
          animate: animate,
          child: errorText == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsetsDirectional.only(top: 6, start: 6),
                  child: Text(
                    errorText!,
                    style: const TextStyle(
                      color: _errorRed,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// AnimatedSize that degrades to a plain child under reduced motion
/// (a zero-duration AnimatedSize re-dirties itself during layout).
class _SmoothSize extends StatelessWidget {
  const _SmoothSize({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

/// Springs down slightly while pressed — makes every tap feel physical.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (widget.enabled) _set(true);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.965 : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Background & desktop showcase
// -----------------------------------------------------------------------------

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFDEDCD6), Color(0xFFECE9DF), Color(0xFFE2E6E0)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

class _DesktopLoginShowcase extends StatelessWidget {
  const _DesktopLoginShowcase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF14365C), Color(0xFF0B2440)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330B2440),
            blurRadius: 40,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              MaslakiBrandMark(size: 56, borderRadius: 18),
              SizedBox(width: 12),
              MaslakiWordmark(
                arabicSize: 30,
                latinSize: 11,
                latinLetterSpacing: 4.2,
                arabicColor: Colors.white,
                latinColor: Color(0xFFE5C38F),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            l10n.authDesktopTitle,
            style: theme.textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.authLoginTagline,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white.withOpacity(0.86),
            ),
          ),
          const SizedBox(height: 24),
          _DesktopFeatureTile(
            icon: Icons.desktop_windows_rounded,
            title: l10n.authDesktopFeatureNavigationTitle,
            subtitle: l10n.authDesktopFeatureNavigationBody,
          ),
          const SizedBox(height: 12),
          _DesktopFeatureTile(
            icon: Icons.dashboard_customize_rounded,
            title: l10n.authDesktopFeatureControlsTitle,
            subtitle: l10n.authDesktopFeatureControlsBody,
          ),
          const SizedBox(height: 12),
          _DesktopFeatureTile(
            icon: Icons.fullscreen_rounded,
            title: l10n.authDesktopFeatureWorkspaceTitle,
            subtitle: l10n.authDesktopFeatureWorkspaceBody,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DesktopStatChip(label: l10n.authDesktopChipCommunity),
              _DesktopStatChip(label: l10n.authDesktopChipOrders),
              _DesktopStatChip(label: l10n.authDesktopChipTaxi),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopFeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DesktopFeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFD4B07A)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withOpacity(0.76)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopStatChip extends StatelessWidget {
  final String label;

  const _DesktopStatChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.10),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Guards the login UI against ever rendering a raw internal error code
/// (e.g. `SESSION_RECOVERY_REQUIRED`, `INVALID_TOKEN`). Returns null when the
/// value is empty or looks like a machine code, so the UI shows nothing rather
/// than leaking developer-facing text to the user.
String? _safeAuthMessage(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final looksLikeCode = RegExp(r'^[A-Z0-9]+(?:_[A-Z0-9]+)+$').hasMatch(text);
  if (looksLikeCode) return null;
  return text;
}
