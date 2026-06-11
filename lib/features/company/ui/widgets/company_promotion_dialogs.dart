import 'package:flutter/material.dart';

import '../../../../core/forms/backend_field_error_parser.dart';
import '../../../../core/forms/form_error_banner.dart';
import '../../../../core/forms/form_field_error_resolver.dart';
import '../../../../core/forms/form_scroll_coordinator.dart';
import '../../../../core/forms/inline_field_error_text.dart';
import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/network/api_error_mapper.dart' show mapAnyError;
import '../../data/company_api.dart';
import '../../models/company_models.dart';

class CompanyCreateCouponDialog extends StatefulWidget {
  final CompanyApi api;
  final int companyId;
  final List<CompanyBranch> branches;

  const CompanyCreateCouponDialog({
    super.key,
    required this.api,
    required this.companyId,
    required this.branches,
  });

  @override
  State<CompanyCreateCouponDialog> createState() =>
      _CompanyCreateCouponDialogState();
}

class _CompanyCreateCouponDialogState extends State<CompanyCreateCouponDialog> {
  final _codeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _valueController = TextEditingController();
  final _maxUsesController = TextEditingController();
  final _scrollCoordinator = FormScrollCoordinator();
  final Set<int> _selectedBranches = <int>{};

  Map<String, String?> _fieldErrors = <String, String?>{};
  String? _formError;
  bool _submitting = false;
  String _discountType = 'percent';
  bool _appliesToAllBranches = true;

  @override
  void dispose() {
    _codeController.dispose();
    _descriptionController.dispose();
    _valueController.dispose();
    _maxUsesController.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  void _clearFieldError(String field) {
    if (!_fieldErrors.containsKey(field) && _formError == null) return;
    setState(() {
      _fieldErrors = Map<String, String?>.from(_fieldErrors)..remove(field);
      if (_fieldErrors.isEmpty) {
        _formError = null;
      }
    });
  }

  String? _errorText(String field, String label) {
    if (!_fieldErrors.containsKey(field)) return null;
    return resolveFormFieldError(
      l10n: context.l10n,
      field: field,
      code: _fieldErrors[field],
      fieldLabel: label,
    );
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final nextErrors = <String, String?>{};
    final discountValue = double.tryParse(_valueController.text.trim());
    final maxUses = int.tryParse(_maxUsesController.text.trim());

    if (_codeController.text.trim().isEmpty) {
      nextErrors['code'] = 'REQUIRED';
    }
    if (_valueController.text.trim().isEmpty) {
      nextErrors['discountValue'] = 'REQUIRED';
    } else if (discountValue == null || discountValue <= 0) {
      nextErrors['discountValue'] = 'INVALID_NUMBER';
    }
    if (_maxUsesController.text.trim().isNotEmpty &&
        (maxUses == null || maxUses <= 0)) {
      nextErrors['maxUses'] = 'INVALID_NUMBER';
    }
    if (!_appliesToAllBranches && _selectedBranches.isEmpty) {
      nextErrors['targetMerchantIds'] = 'SELECT_OPTION';
    }

    if (nextErrors.isNotEmpty) {
      setState(() {
        _fieldErrors = nextErrors;
        _formError = l10n.validationReviewRequiredFields;
      });
      await _scrollCoordinator.focusFirstError(
        const [
          'code',
          'discountValue',
          'maxUses',
          'targetMerchantIds',
        ].where(nextErrors.containsKey),
      );
      return;
    }

    setState(() {
      _fieldErrors = <String, String?>{};
      _formError = null;
      _submitting = true;
    });

    try {
      await widget.api.createCoupon(widget.companyId, {
        'code': _codeController.text.trim(),
        'description': _descriptionController.text.trim(),
        'discountType': _discountType,
        'discountValue': discountValue,
        'maxUses': maxUses,
        'appliesToAllBranches': _appliesToAllBranches,
        'targetMerchantIds': _appliesToAllBranches
            ? null
            : _selectedBranches.toList(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final parsed = parseBackendFieldErrors(error);
      setState(() {
        _fieldErrors = Map<String, String?>.from(parsed.fieldCodes);
        _formError = parsed.hasAnyErrors
            ? resolveFormLevelError(
                l10n,
                code: parsed.formCode ?? parsed.messageCode,
                fallback: mapAnyError(
                  error,
                  fallback: l10n.companyPromotionsCreateCouponFailed,
                ),
              )
            : mapAnyError(
                error,
                fallback: l10n.companyPromotionsCreateCouponFailed,
              );
      });
      if (parsed.hasFieldErrors) {
        await _scrollCoordinator.focusFirstError(
          const [
            'code',
            'discountValue',
            'maxUses',
            'targetMerchantIds',
          ].where(parsed.fieldCodes.containsKey),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.companyPromotionsCreateCouponTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormErrorBanner(message: _formError),
              _scrollCoordinator.anchor(
                'code',
                TextField(
                  controller: _codeController,
                  focusNode: _scrollCoordinator.focusNodeFor('code'),
                  onChanged: (_) => _clearFieldError('code'),
                  decoration: InputDecoration(
                    labelText: l10n.companyPromotionsCouponCode,
                    errorText: _errorText(
                      'code',
                      l10n.companyPromotionsCouponCode,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('coupon_discount_type_$_discountType'),
                initialValue: _discountType,
                decoration: InputDecoration(
                  labelText: l10n.companyPromotionsDiscountType,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'percent',
                    child: Text(l10n.companyPromotionsDiscountPercent),
                  ),
                  DropdownMenuItem(
                    value: 'fixed',
                    child: Text(l10n.companyPromotionsDiscountFixed),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(
                        () => _discountType = value ?? _discountType,
                      ),
              ),
              const SizedBox(height: 12),
              _scrollCoordinator.anchor(
                'discountValue',
                TextField(
                  controller: _valueController,
                  focusNode: _scrollCoordinator.focusNodeFor('discountValue'),
                  onChanged: (_) => _clearFieldError('discountValue'),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.companyPromotionsDiscountValue,
                    errorText: _errorText(
                      'discountValue',
                      l10n.companyPromotionsDiscountValue,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _scrollCoordinator.anchor(
                'maxUses',
                TextField(
                  controller: _maxUsesController,
                  focusNode: _scrollCoordinator.focusNodeFor('maxUses'),
                  onChanged: (_) => _clearFieldError('maxUses'),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.companyPromotionsMaxUses,
                    errorText: _errorText(
                      'maxUses',
                      l10n.companyPromotionsMaxUses,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.companyPromotionsDescription,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _appliesToAllBranches,
                onChanged: _submitting
                    ? null
                    : (value) {
                        setState(() {
                          _appliesToAllBranches = value;
                          if (value) {
                            _fieldErrors = Map<String, String?>.from(
                              _fieldErrors,
                            )..remove('targetMerchantIds');
                            if (_fieldErrors.isEmpty) {
                              _formError = null;
                            }
                          }
                        });
                      },
                title: Text(l10n.companyPromotionsApplyAllBranches),
              ),
              if (!_appliesToAllBranches) ...[
                _scrollCoordinator.anchor(
                  'targetMerchantIds',
                  const SizedBox.shrink(),
                ),
                ...widget.branches.map(
                  (branch) => CheckboxListTile.adaptive(
                    value: _selectedBranches.contains(branch.id),
                    onChanged: _submitting
                        ? null
                        : (value) {
                            setState(() {
                              if (value == true) {
                                _selectedBranches.add(branch.id);
                              } else {
                                _selectedBranches.remove(branch.id);
                              }
                            });
                            _clearFieldError('targetMerchantIds');
                          },
                    title: Text(branch.name),
                  ),
                ),
                InlineFieldErrorText(
                  text: _errorText(
                    'targetMerchantIds',
                    l10n.companyBranchesTitle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(l10n.companyPromotionsCreateCoupon),
        ),
      ],
    );
  }
}

class CompanyCreateCampaignDialog extends StatefulWidget {
  final CompanyApi api;
  final int companyId;
  final List<CompanyBranch> branches;

  const CompanyCreateCampaignDialog({
    super.key,
    required this.api,
    required this.companyId,
    required this.branches,
  });

  @override
  State<CompanyCreateCampaignDialog> createState() =>
      _CompanyCreateCampaignDialogState();
}

class _CompanyCreateCampaignDialogState
    extends State<CompanyCreateCampaignDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _valueController = TextEditingController();
  final _buyController = TextEditingController();
  final _getController = TextEditingController();
  final _scrollCoordinator = FormScrollCoordinator();
  final Set<int> _selectedBranches = <int>{};

  Map<String, String?> _fieldErrors = <String, String?>{};
  String? _formError;
  bool _submitting = false;
  String _offerType = 'percentage';
  bool _appliesToAllBranches = true;
  String _status = 'draft';

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _valueController.dispose();
    _buyController.dispose();
    _getController.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  void _clearFieldError(String field) {
    if (!_fieldErrors.containsKey(field) && _formError == null) return;
    setState(() {
      _fieldErrors = Map<String, String?>.from(_fieldErrors)..remove(field);
      if (_fieldErrors.isEmpty) {
        _formError = null;
      }
    });
  }

  String? _errorText(String field, String label) {
    if (!_fieldErrors.containsKey(field)) return null;
    return resolveFormFieldError(
      l10n: context.l10n,
      field: field,
      code: _fieldErrors[field],
      fieldLabel: label,
    );
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final nextErrors = <String, String?>{};
    final discountValue = double.tryParse(_valueController.text.trim());
    final buyQuantity = int.tryParse(_buyController.text.trim());
    final getQuantity = int.tryParse(_getController.text.trim());

    if (_titleController.text.trim().isEmpty) {
      nextErrors['title'] = 'REQUIRED';
    }
    if (_offerType == 'buy_x_get_y') {
      if (_buyController.text.trim().isEmpty) {
        nextErrors['buyQuantity'] = 'REQUIRED';
      } else if (buyQuantity == null || buyQuantity <= 0) {
        nextErrors['buyQuantity'] = 'INVALID_NUMBER';
      }
      if (_getController.text.trim().isEmpty) {
        nextErrors['getQuantity'] = 'REQUIRED';
      } else if (getQuantity == null || getQuantity <= 0) {
        nextErrors['getQuantity'] = 'INVALID_NUMBER';
      }
    } else {
      if (_valueController.text.trim().isEmpty) {
        nextErrors['discountValue'] = 'REQUIRED';
      } else if (discountValue == null || discountValue <= 0) {
        nextErrors['discountValue'] = 'INVALID_NUMBER';
      }
    }
    if (!_appliesToAllBranches && _selectedBranches.isEmpty) {
      nextErrors['targetMerchantIds'] = 'SELECT_OPTION';
    }

    if (nextErrors.isNotEmpty) {
      setState(() {
        _fieldErrors = nextErrors;
        _formError = l10n.validationReviewRequiredFields;
      });
      await _scrollCoordinator.focusFirstError(
        const [
          'title',
          'discountValue',
          'buyQuantity',
          'getQuantity',
          'targetMerchantIds',
        ].where(nextErrors.containsKey),
      );
      return;
    }

    setState(() {
      _fieldErrors = <String, String?>{};
      _formError = null;
      _submitting = true;
    });

    try {
      await widget.api.createCampaign(widget.companyId, {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'offerType': _offerType,
        'discountValue': _offerType == 'buy_x_get_y' ? null : discountValue,
        'buyQuantity': _offerType == 'buy_x_get_y' ? buyQuantity : null,
        'getQuantity': _offerType == 'buy_x_get_y' ? getQuantity : null,
        'status': _status,
        'appliesToAllBranches': _appliesToAllBranches,
        'targetMerchantIds': _appliesToAllBranches
            ? null
            : _selectedBranches.toList(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final parsed = parseBackendFieldErrors(error);
      setState(() {
        _fieldErrors = Map<String, String?>.from(parsed.fieldCodes);
        _formError = parsed.hasAnyErrors
            ? resolveFormLevelError(
                l10n,
                code: parsed.formCode ?? parsed.messageCode,
                fallback: mapAnyError(
                  error,
                  fallback: l10n.companyPromotionsCreateCampaignFailed,
                ),
              )
            : mapAnyError(
                error,
                fallback: l10n.companyPromotionsCreateCampaignFailed,
              );
      });
      if (parsed.hasFieldErrors) {
        await _scrollCoordinator.focusFirstError(
          const [
            'title',
            'discountValue',
            'buyQuantity',
            'getQuantity',
            'targetMerchantIds',
          ].where(parsed.fieldCodes.containsKey),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.companyPromotionsCreateCampaignTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormErrorBanner(message: _formError),
              _scrollCoordinator.anchor(
                'title',
                TextField(
                  controller: _titleController,
                  focusNode: _scrollCoordinator.focusNodeFor('title'),
                  onChanged: (_) => _clearFieldError('title'),
                  decoration: InputDecoration(
                    labelText: l10n.companyPromotionsCampaignTitle,
                    errorText: _errorText(
                      'title',
                      l10n.companyPromotionsCampaignTitle,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('campaign_offer_type_$_offerType'),
                initialValue: _offerType,
                decoration: InputDecoration(
                  labelText: l10n.companyPromotionsCampaignType,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'percentage',
                    child: Text(l10n.companyPromotionsCampaignPercentage),
                  ),
                  DropdownMenuItem(
                    value: 'fixed_amount',
                    child: Text(l10n.companyPromotionsCampaignFixedAmount),
                  ),
                  DropdownMenuItem(
                    value: 'buy_x_get_y',
                    child: Text(l10n.companyPromotionsCampaignBuyXGetY),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) {
                        setState(() {
                          _offerType = value ?? _offerType;
                          _fieldErrors = Map<String, String?>.from(_fieldErrors)
                            ..remove('discountValue')
                            ..remove('buyQuantity')
                            ..remove('getQuantity');
                          if (_fieldErrors.isEmpty) {
                            _formError = null;
                          }
                        });
                      },
              ),
              const SizedBox(height: 12),
              if (_offerType == 'buy_x_get_y') ...[
                _scrollCoordinator.anchor(
                  'buyQuantity',
                  TextField(
                    controller: _buyController,
                    focusNode: _scrollCoordinator.focusNodeFor('buyQuantity'),
                    onChanged: (_) => _clearFieldError('buyQuantity'),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.companyPromotionsCampaignBuyQuantity,
                      errorText: _errorText(
                        'buyQuantity',
                        l10n.companyPromotionsCampaignBuyQuantity,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _scrollCoordinator.anchor(
                  'getQuantity',
                  TextField(
                    controller: _getController,
                    focusNode: _scrollCoordinator.focusNodeFor('getQuantity'),
                    onChanged: (_) => _clearFieldError('getQuantity'),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.companyPromotionsCampaignGetQuantity,
                      errorText: _errorText(
                        'getQuantity',
                        l10n.companyPromotionsCampaignGetQuantity,
                      ),
                    ),
                  ),
                ),
              ] else
                _scrollCoordinator.anchor(
                  'discountValue',
                  TextField(
                    controller: _valueController,
                    focusNode: _scrollCoordinator.focusNodeFor('discountValue'),
                    onChanged: (_) => _clearFieldError('discountValue'),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.companyPromotionsDiscountValue,
                      errorText: _errorText(
                        'discountValue',
                        l10n.companyPromotionsDiscountValue,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('campaign_status_$_status'),
                initialValue: _status,
                decoration: InputDecoration(
                  labelText: l10n.companyPromotionsCampaignStatus,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'draft',
                    child: Text(l10n.companyPromotionsStatusDraft),
                  ),
                  DropdownMenuItem(
                    value: 'scheduled',
                    child: Text(l10n.companyPromotionsStatusScheduled),
                  ),
                  DropdownMenuItem(
                    value: 'active',
                    child: Text(l10n.companyPromotionsStatusActive),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _status = value ?? _status),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.companyPromotionsDescription,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _appliesToAllBranches,
                onChanged: _submitting
                    ? null
                    : (value) {
                        setState(() {
                          _appliesToAllBranches = value;
                          if (value) {
                            _fieldErrors = Map<String, String?>.from(
                              _fieldErrors,
                            )..remove('targetMerchantIds');
                            if (_fieldErrors.isEmpty) {
                              _formError = null;
                            }
                          }
                        });
                      },
                title: Text(l10n.companyPromotionsApplyAllBranches),
              ),
              if (!_appliesToAllBranches) ...[
                _scrollCoordinator.anchor(
                  'targetMerchantIds',
                  const SizedBox.shrink(),
                ),
                ...widget.branches.map(
                  (branch) => CheckboxListTile.adaptive(
                    value: _selectedBranches.contains(branch.id),
                    onChanged: _submitting
                        ? null
                        : (value) {
                            setState(() {
                              if (value == true) {
                                _selectedBranches.add(branch.id);
                              } else {
                                _selectedBranches.remove(branch.id);
                              }
                            });
                            _clearFieldError('targetMerchantIds');
                          },
                    title: Text(branch.name),
                  ),
                ),
                InlineFieldErrorText(
                  text: _errorText(
                    'targetMerchantIds',
                    l10n.companyBranchesTitle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(l10n.companyPromotionsCreateCampaign),
        ),
      ],
    );
  }
}
