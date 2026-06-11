import 'package:flutter/material.dart';

import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../models/job_models.dart';

class JobApplyDraft {
  final String phone;
  final String? email;
  final double? expectedSalary;
  final String? message;
  final LocalMediaFile? attachmentFile;

  const JobApplyDraft({
    required this.phone,
    required this.email,
    required this.expectedSalary,
    required this.message,
    required this.attachmentFile,
  });
}

class JobApplyScreen extends StatefulWidget {
  final JobPostModel job;
  final String defaultPhone;

  const JobApplyScreen({
    super.key,
    required this.job,
    required this.defaultPhone,
  });

  @override
  State<JobApplyScreen> createState() => _JobApplyScreenState();
}

class _JobApplyScreenState extends State<JobApplyScreen> {
  late final TextEditingController _phoneCtrl = TextEditingController(
    text: widget.defaultPhone,
  );
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _expectedSalaryCtrl = TextEditingController();
  final TextEditingController _messageCtrl = TextEditingController();
  final FormScrollCoordinator _scrollCoordinator = FormScrollCoordinator();

  final Map<String, String> _fieldErrors = <String, String>{};
  String? _formError;
  LocalMediaFile? _attachment;
  bool _submitting = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _expectedSalaryCtrl.dispose();
    _messageCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  String _salaryText() {
    final min = widget.job.salaryMin;
    final max = widget.job.salaryMax;
    if (min == null && max == null) {
      return widget.job.salaryIsNegotiable
          ? context.l10n.realEstateNegotiable
          : context.l10n.companyBranchRequestNoOwner;
    }
    if (min != null && max != null) {
      return '${formatIqd(min, withCode: false)} - ${formatIqd(max, withCode: false)} ${widget.job.salaryCurrency}';
    }
    return '${formatIqd(min ?? max ?? 0, withCode: false)} ${widget.job.salaryCurrency}';
  }

  String? _fieldLabel(String field) {
    final l10n = context.l10n;
    switch (field) {
      case 'phone':
        return l10n.jobApplyApplicantPhone;
      case 'email':
        return l10n.jobApplyEmailOptional;
      case 'expectedSalary':
        return l10n.jobApplyExpectedSalaryOptional;
      case 'message':
        return l10n.jobApplyCoverMessage;
      default:
        return null;
    }
  }

  void _clearFieldError(String field) {
    if (!_fieldErrors.containsKey(field) && _formError == null) return;
    setState(() {
      _fieldErrors.remove(field);
      if (_fieldErrors.isEmpty) {
        _formError = null;
      }
    });
  }

  Future<void> _focusFirstError(Iterable<String> fields) {
    const ordered = <String>['phone', 'email', 'expectedSalary', 'message'];
    final wanted = fields.toSet();
    return _scrollCoordinator.focusFirstError(ordered.where(wanted.contains));
  }

  Future<void> _pickAttachment() async {
    final picked = await pickJobApplicationAttachmentFromDevice();
    if (!mounted || picked == null) return;
    setState(() => _attachment = picked);
  }

  void _submit() {
    if (_submitting) return;
    final l10n = context.l10n;
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    final expectedSalaryText = _expectedSalaryCtrl.text.trim();
    final expectedSalary = expectedSalaryText.isEmpty
        ? null
        : double.tryParse(expectedSalaryText);
    final nextErrors = <String, String>{};

    if (phone.isEmpty) {
      nextErrors['phone'] = resolveFormFieldError(
        l10n: l10n,
        field: 'phone',
        fieldLabel: _fieldLabel('phone'),
      );
    }
    if (email.isNotEmpty && !email.contains('@')) {
      nextErrors['email'] = resolveFormFieldError(
        l10n: l10n,
        field: 'email',
        code: 'INVALID_EMAIL',
        fieldLabel: _fieldLabel('email'),
      );
    }
    if (expectedSalaryText.isNotEmpty && expectedSalary == null) {
      nextErrors['expectedSalary'] = resolveFormFieldError(
        l10n: l10n,
        field: 'expectedSalary',
        code: 'INVALID_NUMBER',
        fieldLabel: _fieldLabel('expectedSalary'),
      );
    }

    if (nextErrors.isNotEmpty) {
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(nextErrors);
        _formError = l10n.validationReviewRequiredFields;
      });
      _focusFirstError(nextErrors.keys);
      return;
    }

    setState(() {
      _submitting = true;
      _fieldErrors.clear();
      _formError = null;
    });
    Navigator.of(context).pop(
      JobApplyDraft(
        phone: phone,
        email: email.isEmpty ? null : email,
        expectedSalary: expectedSalary,
        message: message.isEmpty ? null : message,
        attachmentFile: _attachment,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location =
        '${widget.job.city}${widget.job.area == null ? '' : ' - ${widget.job.area}'}';
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.jobApplyApplyForJob),
        actions: [
          TextButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: const Icon(Icons.send_rounded),
            label: Text(context.l10n.ownerFinancialRequestSend),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: const Icon(Icons.send_rounded),
            label: Text(context.l10n.jobApplySubmitApplication),
          ),
        ),
      ),
      body: Directionality(
        textDirection: context.appTextDirection,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _JobSummaryCard(
              title: widget.job.title,
              companyName: widget.job.companyName,
              location: location,
              salary: _salaryText(),
              description: widget.job.description,
              requirements: widget.job.requirements,
              responsibilities: widget.job.responsibilities,
              benefits: widget.job.benefits,
              skills: widget.job.skills,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: const Icon(Icons.send_rounded),
              label: Text(context.l10n.jobApplySendApplication),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormErrorBanner(message: _formError),
                    Text(
                      context.l10n.jobApplyApplicationDetails,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _scrollCoordinator.anchor(
                      'phone',
                      TextField(
                        controller: _phoneCtrl,
                        focusNode: _scrollCoordinator.focusNodeFor('phone'),
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => _clearFieldError('phone'),
                        decoration: InputDecoration(
                          labelText: context.l10n.jobApplyApplicantPhone,
                          errorText: _fieldErrors['phone'],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _scrollCoordinator.anchor(
                      'email',
                      TextField(
                        controller: _emailCtrl,
                        focusNode: _scrollCoordinator.focusNodeFor('email'),
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) => _clearFieldError('email'),
                        decoration: InputDecoration(
                          labelText: context.l10n.jobApplyEmailOptional,
                          errorText: _fieldErrors['email'],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _scrollCoordinator.anchor(
                      'expectedSalary',
                      TextField(
                        controller: _expectedSalaryCtrl,
                        focusNode: _scrollCoordinator.focusNodeFor(
                          'expectedSalary',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => _clearFieldError('expectedSalary'),
                        decoration: InputDecoration(
                          labelText:
                              context.l10n.jobApplyExpectedSalaryOptional,
                          errorText: _fieldErrors['expectedSalary'],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _scrollCoordinator.anchor(
                      'message',
                      TextField(
                        controller: _messageCtrl,
                        focusNode: _scrollCoordinator.focusNodeFor('message'),
                        minLines: 3,
                        maxLines: 5,
                        onChanged: (_) => _clearFieldError('message'),
                        decoration: InputDecoration(
                          labelText: context.l10n.jobApplyCoverMessage,
                          errorText: _fieldErrors['message'],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickAttachment,
                            icon: const Icon(Icons.attach_file_rounded),
                            label: Text(context.l10n.jobApplyUploadPdfImage),
                          ),
                        ),
                        if (_attachment != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: context.l10n.jobApplyRemoveAttachment,
                            onPressed: () => setState(() => _attachment = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ],
                    ),
                    if (_attachment != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${context.l10n.jobApplyAttachment}: ${_attachment!.name}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9EE4FF),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _JobSummaryCard extends StatelessWidget {
  final String title;
  final String companyName;
  final String location;
  final String salary;
  final String description;
  final String? requirements;
  final String? responsibilities;
  final String? benefits;
  final List<String> skills;

  const _JobSummaryCard({
    required this.title,
    required this.companyName,
    required this.location,
    required this.salary,
    required this.description,
    required this.requirements,
    required this.responsibilities,
    required this.benefits,
    required this.skills,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF194A7A), Color(0xFF0F2746)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              '$companyName - $location',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${context.l10n.commonSalary}: $salary',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF86FFD1),
              ),
            ),
            const SizedBox(height: 10),
            _section(context.l10n.jobsHubJobDescription, description),
            if (requirements?.trim().isNotEmpty == true)
              _section(context.l10n.jobsHubRequirements, requirements!),
            if (responsibilities?.trim().isNotEmpty == true)
              _section(context.l10n.jobsHubResponsibilities, responsibilities!),
            if (benefits?.trim().isNotEmpty == true)
              _section(context.l10n.jobsHubBenefits, benefits!),
            if (skills.isNotEmpty)
              _section(context.l10n.jobsHubSkills, skills.join(' - ')),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            textAlign: TextAlign.right,
            style: const TextStyle(height: 1.4),
          ),
        ],
      ),
    );
  }
}
