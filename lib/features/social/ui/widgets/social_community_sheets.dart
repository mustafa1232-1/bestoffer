import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/forms/backend_field_error_parser.dart';
import '../../../../core/files/local_media_file.dart';
import '../../../../core/files/media_picker_service.dart';
import '../../../../core/forms/form_error_banner.dart';
import '../../../../core/forms/form_field_error_resolver.dart';
import '../../../../core/forms/form_scroll_coordinator.dart';
import '../../../../core/forms/inline_field_error_text.dart';
import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/network/api_error_mapper.dart'
    show mapAnyError, mapDioError;
import '../../../../core/i18n/locale_text.dart';
import '../../../auth/state/auth_controller.dart';
import '../../data/social_api.dart';
import '../../state/social_controller.dart';
import '../../models/social_models.dart';
import '../widgets/social_community_support.dart';

class ScopedCommunityPostSheet extends ConsumerStatefulWidget {
  final String scopeType;
  final String scopeCode;

  const ScopedCommunityPostSheet({
    super.key,
    required this.scopeType,
    required this.scopeCode,
  });

  @override
  ConsumerState<ScopedCommunityPostSheet> createState() =>
      _ScopedCommunityPostSheetState();
}

class _ScopedCommunityPostSheetState
    extends ConsumerState<ScopedCommunityPostSheet> {
  final TextEditingController _captionCtrl = TextEditingController();
  final _scrollCoordinator = FormScrollCoordinator();
  LocalMediaFile? _mediaFile;
  String _postKind = 'text';
  bool _submitting = false;
  Map<String, String?> _fieldErrors = <String, String?>{};
  String? _formError;

  String _t(String ar, String en) => safeCommunityLt(context, ar: ar, en: en);

  @override
  void dispose() {
    _captionCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  String? _fieldError(String field, String label) {
    if (!_fieldErrors.containsKey(field)) {
      return null;
    }
    return resolveFormFieldError(
      l10n: context.l10n,
      field: field,
      code: _fieldErrors[field],
      fieldLabel: label,
    );
  }

  void _clearFieldError(String field) {
    if (!_fieldErrors.containsKey(field) && _formError == null) {
      return;
    }
    setState(() {
      _fieldErrors = Map<String, String?>.from(_fieldErrors)..remove(field);
      if (_fieldErrors.isEmpty) {
        _formError = null;
      }
    });
  }

  Future<void> _pickMedia() async {
    final media = await pickPostMediaFromDevice();
    if (media == null || !mounted) return;
    setState(() {
      _mediaFile = media;
      _postKind = media.isVideo ? 'video' : 'image';
      _fieldErrors = Map<String, String?>.from(_fieldErrors)
        ..remove('mediaFile');
      if (_fieldErrors.isEmpty) {
        _formError = null;
      }
    });
  }

  Future<void> _submit() async {
    final caption = _captionCtrl.text.trim();
    final nextErrors = <String, String?>{};
    if (_postKind == 'text' && caption.isEmpty) {
      nextErrors['caption'] = 'REQUIRED';
    }
    if (_postKind != 'text' && _mediaFile == null) {
      nextErrors['mediaFile'] = 'SELECT_IMAGE';
    }
    if (nextErrors.isNotEmpty) {
      setState(() {
        _fieldErrors = nextErrors;
        _formError = _t(
          'راجع الحقول المظللة ثم أعد المحاولة.',
          'Review the highlighted fields and try again.',
        );
      });
      await _scrollCoordinator.focusFirstError(
        const ['caption', 'mediaFile'].where(nextErrors.containsKey),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _fieldErrors = <String, String?>{};
      _formError = null;
    });
    try {
      await ref
          .read(socialControllerProvider.notifier)
          .createPost(
            caption: caption,
            postKind: _postKind,
            mediaFile: _mediaFile,
            audienceScopeType: widget.scopeType,
            audienceScopeCode: widget.scopeCode,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final parsed = parseBackendFieldErrors(e);
      setState(() {
        _fieldErrors = Map<String, String?>.from(parsed.fieldCodes);
        _formError = parsed.hasAnyErrors
            ? resolveFormLevelError(
                context.l10n,
                code: parsed.formCode ?? parsed.messageCode,
                fallback: mapAnyError(
                  e,
                  fallback: _t(
                    'تعذر نشر المنشور حاليًا.',
                    'Unable to publish post right now.',
                  ),
                ),
              )
            : mapAnyError(
                e,
                fallback: _t(
                  'تعذر نشر المنشور حاليًا.',
                  'Unable to publish post right now.',
                ),
              );
        _submitting = false;
      });
      if (parsed.hasFieldErrors) {
        await _scrollCoordinator.focusFirstError(
          const ['caption', 'mediaFile'].where(parsed.fieldCodes.containsKey),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 8, 14, insets + 14),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FormErrorBanner(message: _formError),
            Text(
              '${_t('منشور جديد في', 'New post in')} ${widget.scopeType.toUpperCase()} ${widget.scopeCode.toUpperCase()}',
              textDirection: context.appTextDirection,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(_t('نص', 'Text')),
                  selected: _postKind == 'text',
                  onSelected: (_) => setState(() {
                    _postKind = 'text';
                    _fieldErrors = Map<String, String?>.from(_fieldErrors)
                      ..remove('caption')
                      ..remove('mediaFile');
                    if (_fieldErrors.isEmpty) {
                      _formError = null;
                    }
                  }),
                ),
                ChoiceChip(
                  label: Text(_t('صورة', 'Image')),
                  selected: _postKind == 'image',
                  onSelected: (_) => setState(() {
                    _postKind = 'image';
                    _fieldErrors = Map<String, String?>.from(_fieldErrors)
                      ..remove('caption')
                      ..remove('mediaFile');
                    if (_fieldErrors.isEmpty) {
                      _formError = null;
                    }
                  }),
                ),
                ChoiceChip(
                  label: Text(_t('فيديو', 'Video')),
                  selected: _postKind == 'video',
                  onSelected: (_) => setState(() {
                    _postKind = 'video';
                    _fieldErrors = Map<String, String?>.from(_fieldErrors)
                      ..remove('caption')
                      ..remove('mediaFile');
                    if (_fieldErrors.isEmpty) {
                      _formError = null;
                    }
                  }),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _scrollCoordinator.anchor(
              'caption',
              TextField(
                controller: _captionCtrl,
                focusNode: _scrollCoordinator.focusNodeFor('caption'),
                onChanged: (_) => _clearFieldError('caption'),
                textDirection: context.appTextDirection,
                minLines: 3,
                maxLines: 7,
                decoration: InputDecoration(
                  hintText: _t('اكتب منشورك هنا...', 'Write your post here...'),
                  errorText: _fieldError(
                    'caption',
                    _t('نص المنشور', 'Post text'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickMedia,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(
                    _mediaFile == null
                        ? _t('اختيار ملف', 'Choose file')
                        : _t('تبديل الملف', 'Change file'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _mediaFile?.name ??
                        _t('لا يوجد ملف مرفق', 'No file attached'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: context.appTextDirection,
                  ),
                ),
              ],
            ),
            _scrollCoordinator.anchor('mediaFile', const SizedBox.shrink()),
            InlineFieldErrorText(
              text: _fieldError('mediaFile', _t('الوسائط', 'Media')),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_t('نشر', 'Publish')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScopedCommunityStorySheet extends ConsumerStatefulWidget {
  const ScopedCommunityStorySheet({super.key});

  @override
  ConsumerState<ScopedCommunityStorySheet> createState() =>
      _ScopedCommunityStorySheetState();
}

class _ScopedCommunityStorySheetState
    extends ConsumerState<ScopedCommunityStorySheet> {
  final TextEditingController _captionCtrl = TextEditingController();
  final _scrollCoordinator = FormScrollCoordinator();
  LocalMediaFile? _mediaFile;
  bool _submitting = false;
  Map<String, String?> _fieldErrors = <String, String?>{};
  String? _formError;

  String _t(String ar, String en) => safeCommunityLt(context, ar: ar, en: en);

  @override
  void dispose() {
    _captionCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  String? _fieldError(String field, String label) {
    if (!_fieldErrors.containsKey(field)) {
      return null;
    }
    return resolveFormFieldError(
      l10n: context.l10n,
      field: field,
      code: _fieldErrors[field],
      fieldLabel: label,
    );
  }

  void _clearFieldError(String field) {
    if (!_fieldErrors.containsKey(field) && _formError == null) {
      return;
    }
    setState(() {
      _fieldErrors = Map<String, String?>.from(_fieldErrors)..remove(field);
      if (_fieldErrors.isEmpty) {
        _formError = null;
      }
    });
  }

  Future<void> _pickMedia() async {
    final media = await pickPostMediaFromDevice();
    if (media == null || !mounted) return;
    setState(() {
      _mediaFile = media;
      _fieldErrors = Map<String, String?>.from(_fieldErrors)
        ..remove('mediaFile');
      if (_fieldErrors.isEmpty) {
        _formError = null;
      }
    });
  }

  Future<void> _submit() async {
    final caption = _captionCtrl.text.trim();
    if (caption.isEmpty && _mediaFile == null) {
      setState(() {
        _formError = _t(
          'أضف نصًا أو صورة/فيديو قبل نشر الستوري.',
          'Add text or media before publishing the story.',
        );
        _fieldErrors = <String, String?>{};
      });
      await _scrollCoordinator.focusFirstError(const ['caption', 'mediaFile']);
      return;
    }

    setState(() {
      _submitting = true;
      _fieldErrors = <String, String?>{};
      _formError = null;
    });

    try {
      await ref
          .read(socialControllerProvider.notifier)
          .createStory(caption: caption, mediaFile: _mediaFile);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final parsed = parseBackendFieldErrors(e);
      setState(() {
        _fieldErrors = Map<String, String?>.from(parsed.fieldCodes);
        _formError = parsed.hasAnyErrors
            ? resolveFormLevelError(
                context.l10n,
                code: parsed.formCode ?? parsed.messageCode,
                fallback: mapAnyError(
                  e,
                  fallback: _t(
                    'تعذر نشر الستوري حاليًا.',
                    'Unable to publish story right now.',
                  ),
                ),
              )
            : mapAnyError(
                e,
                fallback: _t(
                  'تعذر نشر الستوري حاليًا.',
                  'Unable to publish story right now.',
                ),
              );
        _submitting = false;
      });
      if (parsed.hasFieldErrors) {
        await _scrollCoordinator.focusFirstError(
          const ['caption', 'mediaFile'].where(parsed.fieldCodes.containsKey),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 8, 14, insets + 14),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FormErrorBanner(message: _formError),
            Text(
              _t('إضافة ستوري', 'Add story'),
              textDirection: context.appTextDirection,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 10),
            _scrollCoordinator.anchor(
              'caption',
              TextField(
                controller: _captionCtrl,
                focusNode: _scrollCoordinator.focusNodeFor('caption'),
                onChanged: (_) => _clearFieldError('caption'),
                textDirection: context.appTextDirection,
                minLines: 3,
                maxLines: 7,
                decoration: InputDecoration(
                  hintText: _t(
                    'اكتب نص الستوري (اختياري)...',
                    'Write story text (optional)...',
                  ),
                  errorText: _fieldError(
                    'caption',
                    _t('نص الستوري', 'Story text'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickMedia,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(
                    _mediaFile == null
                        ? _t('اختيار صورة/فيديو', 'Pick image/video')
                        : _t('تبديل الملف', 'Change file'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _mediaFile?.name ??
                        _t('لا يوجد ملف مرفق', 'No file attached'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: context.appTextDirection,
                  ),
                ),
              ],
            ),
            _scrollCoordinator.anchor('mediaFile', const SizedBox.shrink()),
            InlineFieldErrorText(
              text: _fieldError('mediaFile', _t('الوسائط', 'Media')),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _submitting
                      ? _t('جاري النشر...', 'Publishing...')
                      : _t('نشر الستوري', 'Publish story'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CommunityManagerSearchSheet extends ConsumerStatefulWidget {
  final String scopeType;
  final String scopeCode;

  const CommunityManagerSearchSheet({
    super.key,
    required this.scopeType,
    required this.scopeCode,
  });

  @override
  ConsumerState<CommunityManagerSearchSheet> createState() =>
      _CommunityManagerSearchSheetState();
}

class _CommunityManagerSearchSheetState
    extends ConsumerState<CommunityManagerSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loading = false;
  String _activeQuery = '';
  String? _error;
  List<SocialCommunityManagerCandidate> _results = const [];

  SocialApi get _api => ref.read(socialApiProvider);
  String _t(String ar, String en) => safeCommunityLt(context, ar: ar, en: en);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    Future<void>.microtask(() => _load(force: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _load();
    });
  }

  Future<void> _load({bool force = false}) async {
    final query = _searchCtrl.text.trim();
    if (!force && query == _activeQuery) return;

    setState(() {
      _loading = true;
      _activeQuery = query;
      _error = null;
    });

    try {
      final out = await _api.searchCommunityUsersForManagers(
        scopeType: widget.scopeType,
        scopeCode: widget.scopeCode,
        search: query,
        limit: 100,
      );
      final users = List<dynamic>.from(out['users'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        _results = users
            .map(
              (row) => SocialCommunityManagerCandidate.fromJson(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList(growable: false);
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapDioError(
          e,
          fallback: _t(
            'تعذر البحث عن المستخدمين حاليًا.',
            'Unable to search users right now.',
          ),
          customMessages: communityApiMessages(context),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: _t(
            'تعذر البحث عن المستخدمين حاليًا.',
            'Unable to search users right now.',
          ),
        );
      });
    }
  }

  void _selectCandidate(SocialCommunityManagerCandidate candidate) {
    if (candidate.isManager) return;
    Navigator.of(context).pop(candidate.user.id);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.82;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: maxHeight,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(
              _t('إدارة المدراء', 'Managers control'),
              textDirection: context.appTextDirection,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchCtrl,
                textDirection: context.appTextDirection,
                decoration: InputDecoration(
                  hintText: _t(
                    'ابحث بالاسم أو الهاتف',
                    'Search by name or phone',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        textDirection: context.appTextDirection,
                      ),
                    )
                  : _results.isEmpty
                  ? Center(
                      child: Text(
                        query.isEmpty
                            ? _t(
                                'لا يوجد مستخدمون متاحون حاليًا.',
                                'No users available right now.',
                              )
                            : _t('لا توجد نتائج.', 'No results found.'),
                        textDirection: context.appTextDirection,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _results[index];
                        final user = item.user;
                        return ListTile(
                          title: Text(
                            user.fullName,
                            textDirection: context.appTextDirection,
                          ),
                          subtitle: Text(
                            [
                              if ((user.phone ?? '').trim().isNotEmpty)
                                user.phone!.trim(),
                              if (user.role.trim().isNotEmpty) user.role.trim(),
                              if (item.isManager)
                                _t('مدير حالي', 'Current manager'),
                            ].join(' • '),
                            textDirection: context.appTextDirection,
                          ),
                          trailing: FilledButton(
                            onPressed: item.isManager
                                ? null
                                : () => _selectCandidate(item),
                            child: Text(
                              item.isManager
                                  ? _t('مُعيَّن', 'Assigned')
                                  : _t('تعيين', 'Assign'),
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

class CommunityChatModerationSheet extends ConsumerStatefulWidget {
  final String scopeType;
  final String scopeCode;

  const CommunityChatModerationSheet({
    super.key,
    required this.scopeType,
    required this.scopeCode,
  });

  @override
  ConsumerState<CommunityChatModerationSheet> createState() =>
      _CommunityChatModerationSheetState();
}

class _CommunityChatModerationSheetState
    extends ConsumerState<CommunityChatModerationSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String _activeQuery = '';
  String? _error;
  List<SocialCommunityChatMemberCandidate> _results = const [];
  final Set<int> _busyUserIds = <int>{};

  SocialApi get _api => ref.read(socialApiProvider);
  String _t(String ar, String en) => safeCommunityLt(context, ar: ar, en: en);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    Future<void>.microtask(() => _load(force: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _load();
    });
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: context.appTextDirection),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _load({bool force = false}) async {
    final query = _searchCtrl.text.trim();
    if (!force && query == _activeQuery) return;
    setState(() {
      _loading = true;
      _activeQuery = query;
      _error = null;
    });
    try {
      final out = await _api.listCommunityChatUsers(
        scopeType: widget.scopeType,
        scopeCode: widget.scopeCode,
        search: query,
        limit: 120,
      );
      final raw = List<dynamic>.from(out['users'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        _results = raw
            .map(
              (row) => SocialCommunityChatMemberCandidate.fromJson(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList(growable: false);
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapDioError(
          e,
          fallback: _t(
            'تعذر تحميل قائمة أعضاء المحادثة حاليًا.',
            'Unable to load chat members right now.',
          ),
          customMessages: communityApiMessages(context),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: _t(
            'تعذر تحميل قائمة أعضاء المحادثة حاليًا.',
            'Unable to load chat members right now.',
          ),
        );
      });
    }
  }

  Future<void> _toggleRestriction(
    SocialCommunityChatMemberCandidate item,
  ) async {
    final targetUserId = item.user.id;
    final currentUserId = ref.read(authControllerProvider).user?.id;
    if (targetUserId == currentUserId) {
      _snack(
        _t('لا يمكنك كتم حسابك.', 'You cannot mute your own account.'),
        error: true,
      );
      return;
    }
    if (_busyUserIds.contains(targetUserId)) return;
    if (item.isScopeRemoved) {
      _snack(
        _t(
          'هذا العضو مُزال من المجتمع. استعده أولًا قبل تغيير حالة الكتم.',
          'This member is removed from this community. Restore first to change mute state.',
        ),
        error: true,
      );
      return;
    }
    setState(() => _busyUserIds.add(targetUserId));
    try {
      if (item.isChatRestricted) {
        await _api.unbanCommunityChatUser(
          scopeType: widget.scopeType,
          scopeCode: widget.scopeCode,
          userId: targetUserId,
        );
        _snack(_t('تم إلغاء كتم العضو.', 'Member unmuted.'));
      } else {
        await _api.banCommunityChatUser(
          scopeType: widget.scopeType,
          scopeCode: widget.scopeCode,
          userId: targetUserId,
          reason: _t(
            'تم كتم العضو من مدير المجتمع.',
            'Member muted by community manager.',
          ),
        );
        _snack(_t('تم كتم العضو.', 'Member muted.'));
      }
      if (!mounted) return;
      setState(() {
        _results = _results
            .map(
              (entry) => entry.user.id == targetUserId
                  ? SocialCommunityChatMemberCandidate(
                      user: entry.user,
                      isManager: entry.isManager,
                      isChatRestricted: !entry.isChatRestricted,
                      isScopeRemoved: entry.isScopeRemoved,
                    )
                  : entry,
            )
            .toList(growable: false);
      });
    } on DioException catch (e) {
      _snack(
        mapDioError(
          e,
          fallback: _t(
            'تعذر تحديث حالة الكتم.',
            'Unable to update mute state.',
          ),
          customMessages: communityApiMessages(context),
        ),
        error: true,
      );
    } catch (e) {
      _snack(
        mapAnyError(
          e,
          fallback: _t(
            'تعذر تحديث حالة الكتم.',
            'Unable to update mute state.',
          ),
        ),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _busyUserIds.remove(targetUserId));
      }
    }
  }

  Future<void> _toggleScopeRemoval(
    SocialCommunityChatMemberCandidate item,
  ) async {
    final targetUserId = item.user.id;
    final currentUserId = ref.read(authControllerProvider).user?.id;
    if (targetUserId == currentUserId) {
      _snack(
        _t('لا يمكنك إزالة حسابك.', 'You cannot remove your own account.'),
        error: true,
      );
      return;
    }
    if (_busyUserIds.contains(targetUserId)) return;
    setState(() => _busyUserIds.add(targetUserId));
    try {
      if (item.isScopeRemoved) {
        await _api.restoreCommunityMember(
          scopeType: widget.scopeType,
          scopeCode: widget.scopeCode,
          userId: targetUserId,
        );
        _snack(
          _t('تمت استعادة العضو إلى المجتمع.', 'Member restored to community.'),
        );
      } else {
        await _api.removeCommunityMember(
          scopeType: widget.scopeType,
          scopeCode: widget.scopeCode,
          userId: targetUserId,
          reason: _t(
            'تمت إزالته من المجتمع بواسطة مدير العمارة.',
            'Removed from this community by building manager.',
          ),
        );
        _snack(
          _t('تمت إزالة العضو من المجتمع.', 'Member removed from community.'),
        );
      }
      if (!mounted) return;
      setState(() {
        _results = _results
            .map(
              (entry) => entry.user.id == targetUserId
                  ? SocialCommunityChatMemberCandidate(
                      user: entry.user,
                      isManager: entry.isManager,
                      isChatRestricted: item.isScopeRemoved
                          ? entry.isChatRestricted
                          : false,
                      isScopeRemoved: !entry.isScopeRemoved,
                    )
                  : entry,
            )
            .toList(growable: false);
      });
    } on DioException catch (e) {
      _snack(
        mapDioError(
          e,
          fallback: _t(
            'تعذر تحديث حالة العضو.',
            'Unable to update member state.',
          ),
          customMessages: communityApiMessages(context),
        ),
        error: true,
      );
    } catch (e) {
      _snack(
        mapAnyError(
          e,
          fallback: _t(
            'تعذر تحديث حالة العضو.',
            'Unable to update member state.',
          ),
        ),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _busyUserIds.remove(targetUserId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.84;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: maxHeight,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(
              _t('إدارة أعضاء المحادثة', 'Manage chat members'),
              textDirection: context.appTextDirection,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              widget.scopeType.trim().toLowerCase() == 'building'
                  ? _t(
                      'يظهر هنا فقط سكان نفس العمارة.',
                      'Only users in this building are shown here.',
                    )
                  : _t(
                      'تظهر هنا فقط حسابات نفس نطاق المجتمع.',
                      'Only users in this community scope are shown here.',
                    ),
              textDirection: context.appTextDirection,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.74),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchCtrl,
                textDirection: context.appTextDirection,
                decoration: InputDecoration(
                  hintText: _t(
                    'ابحث بالاسم أو الهاتف',
                    'Search by name or phone',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        textDirection: context.appTextDirection,
                      ),
                    )
                  : _results.isEmpty
                  ? Center(
                      child: Text(
                        query.isEmpty
                            ? _t(
                                'لا يوجد أعضاء متاحون الآن.',
                                'No members available right now.',
                              )
                            : _t('لا توجد نتائج.', 'No results found.'),
                        textDirection: context.appTextDirection,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _results[index];
                        final user = item.user;
                        final busy = _busyUserIds.contains(user.id);
                        final isSelf =
                            user.id ==
                            ref.read(authControllerProvider).user?.id;
                        return ListTile(
                          title: Text(
                            user.fullName,
                            textDirection: context.appTextDirection,
                          ),
                          subtitle: Text(
                            [
                              if ((user.phone ?? '').trim().isNotEmpty)
                                user.phone!.trim(),
                              if (user.role.trim().isNotEmpty) user.role.trim(),
                              if (item.isManager)
                                _t('مدير حالي', 'Current manager'),
                              if (item.isChatRestricted) _t('مكتوم', 'Muted'),
                              if (item.isScopeRemoved)
                                _t('مزال من المجتمع', 'Removed from community'),
                            ].join(' • '),
                            textDirection: context.appTextDirection,
                          ),
                          trailing: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton.tonal(
                                      onPressed: isSelf
                                          ? null
                                          : () => _toggleScopeRemoval(item),
                                      child: Text(
                                        item.isScopeRemoved
                                            ? _t('استعادة', 'Restore')
                                            : _t('إزالة', 'Remove'),
                                      ),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: isSelf || item.isScopeRemoved
                                          ? null
                                          : () => _toggleRestriction(item),
                                      child: Text(
                                        item.isChatRestricted
                                            ? _t('إلغاء الكتم', 'Unmute')
                                            : _t('كتم', 'Mute'),
                                      ),
                                    ),
                                  ],
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
