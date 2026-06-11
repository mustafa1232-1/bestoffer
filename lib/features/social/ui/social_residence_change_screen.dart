import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/presentation/widgets/basmaya_address_selector.dart';
import '../data/social_api.dart';
import '../state/social_controller.dart';

class SocialResidenceChangeScreen extends ConsumerStatefulWidget {
  const SocialResidenceChangeScreen({super.key});

  @override
  ConsumerState<SocialResidenceChangeScreen> createState() =>
      _SocialResidenceChangeScreenState();
}

class _SocialResidenceChangeScreenState
    extends ConsumerState<SocialResidenceChangeScreen> {
  Map<String, dynamic>? _currentSnapshot;
  Map<String, dynamic>? _request;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String? _selectedBlock;
  String? _selectedBuilding;
  String? _selectedApartment;
  final _noteCtrl = TextEditingController();
  LocalMediaFile? _documentImage;

  SocialApi get _api => ref.read(socialApiProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await _api.getMyResidenceChangeRequest();
      if (!mounted) return;
      final current = Map<String, dynamic>.from(
        out['currentSnapshot'] as Map? ?? const {},
      );
      final request = out['request'] is Map
          ? Map<String, dynamic>.from(out['request'] as Map)
          : null;
      final effective = request == null
          ? current
          : Map<String, dynamic>.from(
              request['requestedSnapshot'] as Map? ?? current,
            );
      _noteCtrl.text = '';
      setState(() {
        _currentSnapshot = current;
        _request = request;
        _selectedBlock = '${effective['block'] ?? effective['town'] ?? ''}'
            .trim()
            .toUpperCase();
        _selectedBuilding =
            '${effective['buildingNumber'] ?? effective['building_number'] ?? ''}'
                .trim()
                .toUpperCase();
        _selectedApartment =
            '${effective['apartmentNumber'] ?? effective['apartment'] ?? effective['apartment_number'] ?? ''}'
                .trim()
                .toUpperCase();
        _documentImage = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialResidenceChangeLoadFailed,
        );
      });
    }
  }

  bool get _hasPendingRequest =>
      (_request?['status']?.toString().trim().toLowerCase() ?? '') == 'pending';

  Future<void> _pickDocumentImage() async {
    final picked = await pickPostMediaFromDevice();
    if (picked == null) return;
    final mime = (picked.mimeType ?? '').toLowerCase();
    if (!mime.startsWith('image/')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.socialResidenceChangeImageOnly)),
      );
      return;
    }
    setState(() => _documentImage = picked);
  }

  Future<void> _submit() async {
    if (_saving || _hasPendingRequest) return;
    final validation = BasmayaAddressCatalog.validateSelection(
      block: _selectedBlock,
      buildingNumber: _selectedBuilding,
      apartment: _selectedApartment,
    );
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.submitResidenceChangeRequest(
        block: _selectedBlock!,
        buildingNumber: _selectedBuilding!,
        apartmentNumber: _selectedApartment!,
        note: _noteCtrl.text.trim(),
        documentImageFile: _documentImage,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.socialResidenceChangeSubmitted)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialResidenceChangeSubmitFailed,
        );
      });
      return;
    }
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Future<void> _cancelPending() async {
    final requestId = int.tryParse('${_request?['id'] ?? ''}');
    if (_saving || requestId == null || requestId <= 0) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.cancelResidenceChangeRequest(requestId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.socialResidenceChangeCancelled)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialResidenceChangeCancelFailed,
        );
      });
      return;
    }
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Widget _snapshotCard({
    required String title,
    required Map<String, dynamic>? snapshot,
    Color? accent,
  }) {
    final block = '${snapshot?['block'] ?? snapshot?['town'] ?? '-'}';
    final building =
        '${snapshot?['buildingNumber'] ?? snapshot?['building_number'] ?? '-'}';
    final apartment =
        '${snapshot?['apartmentNumber'] ?? snapshot?['apartment'] ?? snapshot?['apartment_number'] ?? '-'}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: (accent ?? Theme.of(context).colorScheme.surfaceContainerHighest)
            .withValues(alpha: 0.4),
        border: Border.all(
          color: (accent ?? Theme.of(context).colorScheme.outline).withValues(
            alpha: 0.28,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            textDirection: context.appTextDirection,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 10),
          _infoRow(context.l10n.socialResidenceChangeBlockLabel, block),
          _infoRow(context.l10n.socialResidenceChangeBuildingLabel, building),
          _infoRow(context.l10n.socialResidenceChangeApartmentLabel, apartment),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        textDirection: context.appTextDirection,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
            textDirection: context.appTextDirection,
          ),
          Expanded(
            child: Text(
              value,
              textDirection: context.appTextDirection,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentPreview() {
    final image = _documentImage;
    if (image == null) return const SizedBox.shrink();
    final Uint8List? bytes = image.hasBytes ? image.bytes : null;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        textDirection: context.appTextDirection,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: bytes == null
                ? Container(
                    width: 54,
                    height: 54,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_outlined),
                  )
                : Image.memory(bytes, width: 54, height: 54, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              image.name,
              textDirection: context.appTextDirection,
              textAlign: TextAlign.right,
            ),
          ),
          IconButton(
            onPressed: _saving
                ? null
                : () => setState(() => _documentImage = null),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final request = _request;
    final requestedSnapshot = request == null
        ? null
        : Map<String, dynamic>.from(
            request['requestedSnapshot'] as Map? ?? const {},
          );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.socialResidenceChangeTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _snapshotCard(
                    title: l10n.socialResidenceChangeCurrentResidenceTitle,
                    snapshot: _currentSnapshot,
                  ),
                  const SizedBox(height: 14),
                  if (request != null) ...[
                    _snapshotCard(
                      title: _hasPendingRequest
                          ? l10n.socialResidenceChangePendingRequestTitle
                          : l10n.socialResidenceChangeLastReviewedTitle,
                      snapshot: requestedSnapshot,
                      accent: _hasPendingRequest
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.socialResidenceChangeStatusLine(
                        '${request['status']}',
                      ),
                      textDirection: context.appTextDirection,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if ((request['reviewNote'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          l10n.socialResidenceChangeReviewNoteLine(
                            '${request['reviewNote']}',
                          ),
                          textDirection: context.appTextDirection,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    if (_hasPendingRequest) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _cancelPending,
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text(l10n.socialResidenceChangeCancelRequest),
                      ),
                    ],
                  ],
                  const SizedBox(height: 18),
                  Text(
                    l10n.socialResidenceChangeNewRequestTitle,
                    textDirection: context.appTextDirection,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  IgnorePointer(
                    ignoring: _hasPendingRequest,
                    child: Opacity(
                      opacity: _hasPendingRequest ? 0.55 : 1,
                      child: Column(
                        children: [
                          BasmayaAddressSelector(
                            selectedBlock: _selectedBlock,
                            selectedBuilding: _selectedBuilding,
                            selectedApartment: _selectedApartment,
                            onBlockChanged: (value) {
                              setState(() {
                                _selectedBlock = value;
                                _selectedBuilding = null;
                                _selectedApartment = null;
                              });
                            },
                            onBuildingChanged: (value) {
                              setState(() {
                                _selectedBuilding = value;
                                _selectedApartment = null;
                              });
                            },
                            onApartmentChanged: (value) {
                              setState(() => _selectedApartment = value);
                            },
                            enabled: !_saving && !_hasPendingRequest,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _noteCtrl,
                            minLines: 2,
                            maxLines: 4,
                            textDirection: context.appTextDirection,
                            decoration: InputDecoration(
                              labelText:
                                  l10n.socialResidenceChangeAdditionalNote,
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: (_saving || _hasPendingRequest)
                                ? null
                                : _pickDocumentImage,
                            icon: const Icon(Icons.upload_file_rounded),
                            label: Text(
                              l10n.socialResidenceChangeAttachDocument,
                            ),
                          ),
                          _buildDocumentPreview(),
                          if ((_error ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              textDirection: context.appTextDirection,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: (_saving || _hasPendingRequest)
                                ? null
                                : _submit,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                            label: Text(l10n.socialResidenceChangeSubmitAction),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_hasPendingRequest) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.socialResidenceChangePendingLockMessage,
                      textDirection: context.appTextDirection,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
