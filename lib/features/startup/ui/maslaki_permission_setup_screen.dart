import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/permissions/maslaki_permission_models.dart';
import '../../../core/permissions/maslaki_permission_policy.dart';
import '../../../core/permissions/maslaki_permission_service.dart';

/// Premium first-run "Prepare Maslaki" readiness screen. Policy-driven: it shows
/// only the permissions the [role] needs at first run, requests them one at a
/// time on tap, and never blocks the app — optional permissions can be skipped.
class MaslakiPermissionSetupScreen extends StatefulWidget {
  final MaslakiAppRole role;
  final Future<void> Function() onComplete;
  final MaslakiPermissionService service;

  const MaslakiPermissionSetupScreen({
    super.key,
    required this.role,
    required this.onComplete,
    this.service = const MaslakiPermissionService(),
  });

  @override
  State<MaslakiPermissionSetupScreen> createState() =>
      _MaslakiPermissionSetupScreenState();
}

class _MaslakiPermissionSetupScreenState
    extends State<MaslakiPermissionSetupScreen> {
  final Map<MaslakiPermission, MaslakiPermissionStatus> _status = {};
  MaslakiPermission? _busy;
  bool _finishing = false;

  List<PermissionRequirement> get _requirements =>
      MaslakiPermissionPolicy.firstRunRequirements(widget.role);

  @override
  void initState() {
    super.initState();
    Future.microtask(_refresh);
  }

  Future<void> _refresh() async {
    for (final req in _requirements) {
      final status = await widget.service.getStatus(req.permission);
      if (!mounted) return;
      setState(() => _status[req.permission] = status);
    }
  }

  Future<void> _handle(PermissionRequirement req) async {
    if (_busy != null) return;
    setState(() => _busy = req.permission);
    try {
      final current = _status[req.permission];
      if (current == MaslakiPermissionStatus.permanentlyDenied) {
        await widget.service.openSettings();
      } else {
        // Request foreground location before background location.
        if (req.permission == MaslakiPermission.locationAlways) {
          await widget.service.request(MaslakiPermission.locationWhenInUse);
        }
        await widget.service.request(req.permission);
      }
      final next = await widget.service.getStatus(req.permission);
      if (!mounted) return;
      setState(() => _status[req.permission] = next);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await widget.service.markSetupComplete();
    if (!mounted) return;
    await widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final requirements = _requirements;
    final allRequiredReady = requirements
        .where((r) => r.isRequired)
        .every((r) => (_status[r.permission])?.isGranted ?? false);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0E1C36), Color(0xFF16314D), Color(0xFF231A4A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.lt(
                        ar: 'تهيئة مسلكي لتجربة كاملة',
                        en: 'Prepare Maslaki for the full experience',
                      ),
                      style: const TextStyle(
                        color: Color(0xFFF8F0E2),
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.lt(
                        ar: 'سنطلب الأذونات الضرورية لتشغيل الطلبات والتكسي والدلفري والإشعارات والستوري والريلز بسلاسة.',
                        en: 'We will request the permissions needed to run orders, taxi, delivery, notifications, stories and reels smoothly.',
                      ),
                      style: TextStyle(
                        color: const Color(0xFFE9DEC9).withValues(alpha: 0.82),
                        height: 1.5,
                        fontSize: 14.5,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: requirements.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final req = requirements[index];
                    return _PermissionCard(
                      meta: _metaFor(req.permission),
                      requirement: req,
                      status: _status[req.permission],
                      busy: _busy == req.permission,
                      onTap: () => _handle(req),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                child: SizedBox(
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: const Color(0xFF0D1B2A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _finishing ? null : _finish,
                    child: _finishing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            allRequiredReady
                                ? context.lt(ar: 'متابعة', en: 'Continue')
                                : context.lt(
                                    ar: 'المتابعة الآن',
                                    en: 'Continue for now',
                                  ),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _PermMeta _metaFor(MaslakiPermission permission) {
    switch (permission) {
      case MaslakiPermission.notifications:
        return const _PermMeta(Icons.notifications_active_rounded, 'الإشعارات',
            'Notifications', 'تنبيهات الطلبات والتكسي والدلفري والرسائل');
      case MaslakiPermission.locationWhenInUse:
        return const _PermMeta(Icons.my_location_rounded, 'الموقع',
            'Location', 'لخدمات قريبة منك وتتبّع الطلبات والعناوين');
      case MaslakiPermission.locationAlways:
        return const _PermMeta(Icons.location_on_rounded,
            'الموقع في الخلفية', 'Background location',
            'لتتبّع الرحلات والتوصيل أثناء عمل التطبيق في الخلفية');
      case MaslakiPermission.camera:
        return const _PermMeta(Icons.photo_camera_rounded, 'الكاميرا',
            'Camera', 'للستوري والريلز والصور وإثبات التسليم');
      case MaslakiPermission.microphone:
        return const _PermMeta(Icons.mic_rounded, 'المايكروفون',
            'Microphone', 'لصوت الفيديو والرسائل الصوتية والمكالمات');
      case MaslakiPermission.photos:
        return const _PermMeta(Icons.photo_library_rounded, 'الصور والوسائط',
            'Photos & media', 'لاختيار الصور والفيديو من المعرض');
    }
  }
}

class _PermMeta {
  final IconData icon;
  final String ar;
  final String en;
  final String rationaleAr;
  const _PermMeta(this.icon, this.ar, this.en, this.rationaleAr);
}

class _PermissionCard extends StatelessWidget {
  final _PermMeta meta;
  final PermissionRequirement requirement;
  final MaslakiPermissionStatus? status;
  final bool busy;
  final VoidCallback onTap;

  const _PermissionCard({
    required this.meta,
    required this.requirement,
    required this.status,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final granted = status?.isGranted ?? false;
    final permanentlyDenied =
        status == MaslakiPermissionStatus.permanentlyDenied;
    const gold = Color(0xFFD4AF37);
    final accent = granted
        ? const Color(0xFF71DF89)
        : (permanentlyDenied ? const Color(0xFFFF8A80) : gold);

    final statusLabel = granted
        ? context.lt(ar: 'جاهز', en: 'Ready')
        : permanentlyDenied
            ? context.lt(ar: 'مرفوض', en: 'Denied')
            : requirement.isOptional
                ? context.lt(ar: 'اختياري', en: 'Optional')
                : context.lt(ar: 'يحتاج تفعيل', en: 'Needs enabling');

    final ctaLabel = granted
        ? null
        : permanentlyDenied
            ? context.lt(ar: 'فتح الإعدادات', en: 'Open settings')
            : context.lt(ar: 'تفعيل', en: 'Enable');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(meta.icon, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.isEnglishLocale ? meta.en : meta.ar,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta.rationaleAr.isNotEmpty && !context.isEnglishLocale
                            ? meta.rationaleAr
                            : meta.en,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(label: statusLabel, color: accent, granted: granted),
              ],
            ),
            if (ctaLabel != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: busy ? null : onTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: accent.withValues(alpha: 0.8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(ctaLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool granted;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.granted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            granted ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
