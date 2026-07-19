import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/forms/inline_field_error_text.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../models/product_review_model.dart';
import '../state/orders_controller.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

/// Bottom sheet that shows product reviews + allows submitting one.
class ProductReviewsSheet extends ConsumerStatefulWidget {
  final int productId;
  final String productName;

  const ProductReviewsSheet({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  ConsumerState<ProductReviewsSheet> createState() =>
      _ProductReviewsSheetState();
}

class _ProductReviewsSheetState extends ConsumerState<ProductReviewsSheet> {
  List<ProductReview> _reviews = [];
  ProductRatingSummary? _summary;
  bool _loading = true;
  String? _error;

  // Submit form
  int _selectedRating = 0;
  final _bodyCtrl = TextEditingController();
  final FormScrollCoordinator _scrollCoordinator = FormScrollCoordinator();
  bool _submitting = false;
  String? _submitError;
  final Map<String, String> _fieldErrors = <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadV2();
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  // ignore: unused_element
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(ordersApiProvider);
      final data = await api.listProductReviews(widget.productId);
      final rawReviews = (data['reviews'] as List?) ?? [];
      final rawSummary = data['summary'];
      setState(() {
        _reviews = rawReviews
            .map(
              (e) =>
                  ProductReview.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        _summary = rawSummary is Map
            ? ProductRatingSummary.fromJson(
                Map<String, dynamic>.from(rawSummary),
              )
            : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = mapAnyError(e, fallback: 'تعذر تحميل التقييمات');
        _loading = false;
      });
    }
  }

  // ignore: unused_element
  Future<void> _submit() async {
    if (_selectedRating == 0) {
      setState(() => _submitError = 'اختر تقييماً من 1 إلى 5 نجوم');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final api = ref.read(ordersApiProvider);
      await api.submitProductReview(
        widget.productId,
        rating: _selectedRating,
        body: _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
      );
      _bodyCtrl.clear();
      setState(() {
        _selectedRating = 0;
        _submitting = false;
      });
      await _load();
    } catch (e) {
      setState(() {
        _submitError = mapAnyError(e, fallback: 'تعذر إرسال التقييم');
        _submitting = false;
      });
    }
  }

  Future<void> _loadV2() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(ordersApiProvider);
      final data = await api.listProductReviews(widget.productId);
      final rawReviews = (data['reviews'] as List?) ?? [];
      final rawSummary = data['summary'];
      setState(() {
        _reviews = rawReviews
            .map(
              (e) =>
                  ProductReview.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        _summary = rawSummary is Map
            ? ProductRatingSummary.fromJson(
                Map<String, dynamic>.from(rawSummary),
              )
            : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = mapAnyErrorL10n(
          e,
          fallbackBuilder: (l10n) => l10n.productReviewsLoadFailed,
        );
        _loading = false;
      });
    }
  }

  Future<void> _submitV2() async {
    final l10n = context.l10n;
    final nextErrors = <String, String>{};
    if (_selectedRating == 0) {
      nextErrors['rating'] = l10n.productReviewsSelectRating;
    }

    if (nextErrors.isNotEmpty) {
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(nextErrors);
        _submitError = l10n.validationReviewRequiredFields;
      });
      await _scrollCoordinator.focusFirstError(nextErrors.keys);
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
      _fieldErrors.clear();
    });
    try {
      final api = ref.read(ordersApiProvider);
      await api.submitProductReview(
        widget.productId,
        rating: _selectedRating,
        body: _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
      );
      _bodyCtrl.clear();
      setState(() {
        _selectedRating = 0;
        _submitting = false;
      });
      await _loadV2();
    } on DioException catch (e) {
      final parsed = parseBackendFieldErrors(e);
      setState(() {
        _fieldErrors.clear();
        if (parsed.fieldCodes.containsKey('rating')) {
          _fieldErrors['rating'] = resolveFormFieldError(
            l10n: l10n,
            field: 'rating',
            code: parsed.codeFor('rating'),
            fieldLabel: l10n.productReviewsRatingLabel,
          );
        }
        if (parsed.fieldCodes.containsKey('body')) {
          _fieldErrors['body'] = resolveFormFieldError(
            l10n: l10n,
            field: 'body',
            code: parsed.codeFor('body'),
            fieldLabel: l10n.productReviewsCommentLabel,
          );
        }
        _submitError = _fieldErrors.isNotEmpty
            ? resolveFormLevelError(
                l10n,
                code: parsed.formCode ?? parsed.messageCode,
                fallback: l10n.validationReviewRequiredFields,
              )
            : mapAnyErrorL10n(
                e,
                fallbackBuilder: (l10n) => l10n.productReviewsSubmitFailed,
              );
        _submitting = false;
      });
      if (_fieldErrors.isNotEmpty) {
        await _scrollCoordinator.focusFirstError(_fieldErrors.keys);
      }
    } catch (e) {
      setState(() {
        _submitError = mapAnyErrorL10n(
          e,
          fallbackBuilder: (l10n) => l10n.productReviewsSubmitFailed,
        );
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final canReview = auth.isAuthed && !auth.isBackoffice && !auth.isOwner;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) => Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title + summary
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'تقييمات ${widget.productName}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_summary != null && _summary!.reviewCount > 0) ...[
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '${_summary!.avgRating?.toStringAsFixed(1) ?? '-'}'
                    ' (${_summary!.reviewCount})',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          // Submit form
          if (canReview)
            _SubmitReviewFormV2(
              rating: _selectedRating,
              bodyCtrl: _bodyCtrl,
              submitting: _submitting,
              error: _submitError,
              scrollCoordinator: _scrollCoordinator,
              fieldErrors: _fieldErrors,
              onRatingChanged: (r) {
                setState(() {
                  _selectedRating = r;
                  _fieldErrors.remove('rating');
                  if (_fieldErrors.isEmpty) _submitError = null;
                });
              },
              onBodyChanged: (_) {
                if (_fieldErrors.remove('body') != null && mounted) {
                  setState(() {
                    if (_fieldErrors.isEmpty) _submitError = null;
                  });
                }
              },
              onSubmit: _submitV2,
            ),
          // Reviews list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : _reviews.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد تقييمات بعد',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _reviews.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 24),
                    itemBuilder: (context, index) =>
                        _ReviewTile(review: _reviews[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _SubmitReviewForm extends StatelessWidget {
  final int rating;
  final TextEditingController bodyCtrl;
  final bool submitting;
  final String? error;
  final ValueChanged<int> onRatingChanged;
  final VoidCallback onSubmit;

  const _SubmitReviewForm({
    required this.rating,
    required this.bodyCtrl,
    required this.submitting,
    required this.error,
    required this.onRatingChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('أضف تقييمك', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          // Star selector
          Row(
            children: List.generate(5, (i) {
              final star = i + 1;
              return GestureDetector(
                onTap: () => onRatingChanged(star),
                child: Icon(
                  star <= rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: Colors.amber,
                  size: 32,
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: bodyCtrl,
            maxLines: 2,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              hintText: 'تعليق اختياري...',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.all(10),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: submitting ? null : onSubmit,
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('إرسال التقييم'),
            ),
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}

class _SubmitReviewFormV2 extends StatelessWidget {
  final int rating;
  final TextEditingController bodyCtrl;
  final bool submitting;
  final String? error;
  final FormScrollCoordinator scrollCoordinator;
  final Map<String, String> fieldErrors;
  final ValueChanged<int> onRatingChanged;
  final ValueChanged<String> onBodyChanged;
  final VoidCallback onSubmit;

  const _SubmitReviewFormV2({
    required this.rating,
    required this.bodyCtrl,
    required this.submitting,
    required this.error,
    required this.scrollCoordinator,
    required this.fieldErrors,
    required this.onRatingChanged,
    required this.onBodyChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormErrorBanner(message: error),
          Text(l10n.productReviewsAddTitle, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          scrollCoordinator.anchor(
            'rating',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return GestureDetector(
                      onTap: () => onRatingChanged(star),
                      child: Icon(
                        star <= rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: Colors.amber,
                        size: 32,
                      ),
                    );
                  }),
                ),
                InlineFieldErrorText(text: fieldErrors['rating']),
              ],
            ),
          ),
          const SizedBox(height: 6),
          scrollCoordinator.anchor(
            'body',
            TextField(
              controller: bodyCtrl,
              focusNode: scrollCoordinator.focusNodeFor('body'),
              maxLines: 2,
              textDirection: TextDirection.rtl,
              onChanged: onBodyChanged,
              decoration: InputDecoration(
                labelText: l10n.productReviewsCommentLabel,
                hintText: l10n.productReviewsCommentHint,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
                errorText: fieldErrors['body'],
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: submitting ? null : onSubmit,
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.productReviewsSubmit),
            ),
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final ProductReview review;

  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundImage: review.customerImageUrl != null
              ? AppCachedImageProvider(review.customerImageUrl!)
              : null,
          child: review.customerImageUrl == null
              ? Text(
                  review.customerName.isNotEmpty ? review.customerName[0] : '?',
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    review.customerName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < review.rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: Colors.amber,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
              if (review.body != null && review.body!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    review.body!,
                    style: theme.textTheme.bodySmall,
                    textDirection: TextDirection.rtl,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
