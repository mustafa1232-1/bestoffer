import 'package:flutter/material.dart';

import '../../../../core/forms/form_error_banner.dart';
import '../../../../core/forms/form_field_error_resolver.dart';
import '../../../../core/forms/form_scroll_coordinator.dart';
import '../../../../core/i18n/app_localizations_context.dart';
import '../../models/admin_financial_request_model.dart';

enum AdminFinancialActionType {
  approve,
  reject,
  assign,
  markPaid,
  returnForRevision,
}

class AdminFinancialActionResult {
  final AdminFinancialActionType action;
  final Map<String, dynamic> payload;

  const AdminFinancialActionResult({
    required this.action,
    required this.payload,
  });
}

class AdminFinancialRequestActionsSheet extends StatefulWidget {
  final AdminFinancialRequestModel request;

  const AdminFinancialRequestActionsSheet({super.key, required this.request});

  @override
  State<AdminFinancialRequestActionsSheet> createState() =>
      _AdminFinancialRequestActionsSheetState();
}

class _AdminFinancialRequestActionsSheetState
    extends State<AdminFinancialRequestActionsSheet> {
  final _noteCtrl = TextEditingController();
  final _internalCtrl = TextEditingController();
  final _assignedNameCtrl = TextEditingController();
  final _paidAmountCtrl = TextEditingController();
  final _methodCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _actorCtrl = TextEditingController();
  final _scrollCoordinator = FormScrollCoordinator();

  Map<String, String?> _fieldErrors = <String, String?>{};
  String? _formError;

  @override
  void dispose() {
    _noteCtrl.dispose();
    _internalCtrl.dispose();
    _assignedNameCtrl.dispose();
    _paidAmountCtrl.dispose();
    _methodCtrl.dispose();
    _dateCtrl.dispose();
    _referenceCtrl.dispose();
    _actorCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
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

  String? _fieldError(String field, String fieldLabel) {
    if (!_fieldErrors.containsKey(field)) {
      return null;
    }
    return resolveFormFieldError(
      l10n: context.l10n,
      field: field,
      code: _fieldErrors[field],
      fieldLabel: fieldLabel,
    );
  }

  Future<void> _focusErrors() {
    return _scrollCoordinator.focusFirstError(
      const [
        'reviewNote',
        'assignedToName',
        'paidAmount',
        'paymentMethod',
        'paymentDate',
        'referenceCode',
        'paymentActorName',
      ].where(_fieldErrors.containsKey),
    );
  }

  bool _validate(AdminFinancialActionType action) {
    final nextErrors = <String, String?>{};
    final isAppPaysStore = widget.request.requestType == 'app_pays_store';
    final reviewNote = _noteCtrl.text.trim();
    final assignedName = _assignedNameCtrl.text.trim();
    final paidAmountText = _paidAmountCtrl.text.trim();
    final paidAmount = double.tryParse(paidAmountText);
    final paymentMethod = _methodCtrl.text.trim();
    final paymentDate = _dateCtrl.text.trim();
    final referenceCode = _referenceCtrl.text.trim();
    final paymentActor = _actorCtrl.text.trim();

    if (action == AdminFinancialActionType.reject ||
        action == AdminFinancialActionType.returnForRevision) {
      if (reviewNote.isEmpty) {
        nextErrors['reviewNote'] = 'REQUIRED';
      }
    }

    if (isAppPaysStore && action == AdminFinancialActionType.assign) {
      if (assignedName.isEmpty) {
        nextErrors['assignedToName'] = 'REQUIRED';
      }
    }

    if (isAppPaysStore && action == AdminFinancialActionType.markPaid) {
      if (paidAmountText.isEmpty) {
        nextErrors['paidAmount'] = 'REQUIRED';
      } else if (paidAmount == null || paidAmount <= 0) {
        nextErrors['paidAmount'] = 'INVALID_NUMBER';
      }
      if (paymentMethod.isEmpty) {
        nextErrors['paymentMethod'] = 'REQUIRED';
      }
      if (paymentDate.isEmpty) {
        nextErrors['paymentDate'] = 'REQUIRED';
      }
      if (referenceCode.isEmpty) {
        nextErrors['referenceCode'] = 'REQUIRED';
      }
      if (paymentActor.isEmpty) {
        nextErrors['paymentActorName'] = 'REQUIRED';
      }
    }

    setState(() {
      _fieldErrors = nextErrors;
      _formError = nextErrors.isEmpty
          ? null
          : context.l10n.validationReviewRequiredFields;
    });
    return nextErrors.isEmpty;
  }

  void _submit(AdminFinancialActionType action) {
    if (!_validate(action)) {
      _focusErrors();
      return;
    }

    final payload = <String, dynamic>{
      'reviewNote': _noteCtrl.text.trim().isEmpty
          ? null
          : _noteCtrl.text.trim(),
      'internalAdminNote': _internalCtrl.text.trim().isEmpty
          ? null
          : _internalCtrl.text.trim(),
      'assignedToName': _assignedNameCtrl.text.trim().isEmpty
          ? null
          : _assignedNameCtrl.text.trim(),
      'paidAmount': _paidAmountCtrl.text.trim().isEmpty
          ? null
          : double.tryParse(_paidAmountCtrl.text.trim()),
      'paymentMethod': _methodCtrl.text.trim().isEmpty
          ? null
          : _methodCtrl.text.trim(),
      'paymentDate': _dateCtrl.text.trim().isEmpty
          ? null
          : _dateCtrl.text.trim(),
      'referenceCode': _referenceCtrl.text.trim().isEmpty
          ? null
          : _referenceCtrl.text.trim(),
      'paymentActorName': _actorCtrl.text.trim().isEmpty
          ? null
          : _actorCtrl.text.trim(),
    }..removeWhere((_, value) => value == null);

    Navigator.of(
      context,
    ).pop(AdminFinancialActionResult(action: action, payload: payload));
  }

  @override
  Widget build(BuildContext context) {
    final isAppPaysStore = widget.request.requestType == 'app_pays_store';
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormErrorBanner(message: _formError),
              Text(
                '#${widget.request.id} • ${widget.request.status}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _scrollCoordinator.anchor(
                'reviewNote',
                TextField(
                  controller: _noteCtrl,
                  focusNode: _scrollCoordinator.focusNodeFor('reviewNote'),
                  onChanged: (_) => _clearFieldError('reviewNote'),
                  decoration: InputDecoration(
                    labelText: l10n.adminFinancialActionReviewNote,
                    errorText: _fieldError(
                      'reviewNote',
                      l10n.adminFinancialActionReviewNote,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _internalCtrl,
                onChanged: (_) => _clearFieldError('internalAdminNote'),
                decoration: InputDecoration(
                  labelText: l10n.adminFinancialActionInternalNote,
                ),
              ),
              if (isAppPaysStore) ...[
                const SizedBox(height: 8),
                _scrollCoordinator.anchor(
                  'assignedToName',
                  TextField(
                    controller: _assignedNameCtrl,
                    focusNode: _scrollCoordinator.focusNodeFor(
                      'assignedToName',
                    ),
                    onChanged: (_) => _clearFieldError('assignedToName'),
                    decoration: InputDecoration(
                      labelText: l10n.adminFinancialActionAssigneeName,
                      errorText: _fieldError(
                        'assignedToName',
                        l10n.adminFinancialActionAssigneeName,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _scrollCoordinator.anchor(
                  'paidAmount',
                  TextField(
                    controller: _paidAmountCtrl,
                    focusNode: _scrollCoordinator.focusNodeFor('paidAmount'),
                    onChanged: (_) => _clearFieldError('paidAmount'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.adminFinancialActionPaidAmount,
                      errorText: _fieldError(
                        'paidAmount',
                        l10n.adminFinancialActionPaidAmount,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _scrollCoordinator.anchor(
                  'paymentMethod',
                  TextField(
                    controller: _methodCtrl,
                    focusNode: _scrollCoordinator.focusNodeFor('paymentMethod'),
                    onChanged: (_) => _clearFieldError('paymentMethod'),
                    decoration: InputDecoration(
                      labelText: l10n.adminFinancialActionPaymentMethod,
                      errorText: _fieldError(
                        'paymentMethod',
                        l10n.adminFinancialActionPaymentMethod,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _scrollCoordinator.anchor(
                  'paymentDate',
                  TextField(
                    controller: _dateCtrl,
                    focusNode: _scrollCoordinator.focusNodeFor('paymentDate'),
                    onChanged: (_) => _clearFieldError('paymentDate'),
                    decoration: InputDecoration(
                      labelText: l10n.adminFinancialActionPaymentDate,
                      errorText: _fieldError(
                        'paymentDate',
                        l10n.adminFinancialActionPaymentDate,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _scrollCoordinator.anchor(
                  'referenceCode',
                  TextField(
                    controller: _referenceCtrl,
                    focusNode: _scrollCoordinator.focusNodeFor('referenceCode'),
                    onChanged: (_) => _clearFieldError('referenceCode'),
                    decoration: InputDecoration(
                      labelText: l10n.adminFinancialActionReference,
                      errorText: _fieldError(
                        'referenceCode',
                        l10n.adminFinancialActionReference,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _scrollCoordinator.anchor(
                  'paymentActorName',
                  TextField(
                    controller: _actorCtrl,
                    focusNode: _scrollCoordinator.focusNodeFor(
                      'paymentActorName',
                    ),
                    onChanged: (_) => _clearFieldError('paymentActorName'),
                    decoration: InputDecoration(
                      labelText: l10n.adminFinancialActionPaymentActor,
                      errorText: _fieldError(
                        'paymentActorName',
                        l10n.adminFinancialActionPaymentActor,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () => _submit(AdminFinancialActionType.approve),
                    child: Text(l10n.commonApprove),
                  ),
                  OutlinedButton(
                    onPressed: () => _submit(AdminFinancialActionType.reject),
                    child: Text(l10n.commonReject),
                  ),
                  if (isAppPaysStore)
                    OutlinedButton(
                      onPressed: () => _submit(AdminFinancialActionType.assign),
                      child: Text(l10n.adminFinancialActionAssign),
                    ),
                  if (isAppPaysStore)
                    ElevatedButton(
                      onPressed: () =>
                          _submit(AdminFinancialActionType.markPaid),
                      child: Text(l10n.adminFinancialActionMarkPaid),
                    ),
                  OutlinedButton(
                    onPressed: () =>
                        _submit(AdminFinancialActionType.returnForRevision),
                    child: Text(l10n.adminFinancialActionReturnForRevision),
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
