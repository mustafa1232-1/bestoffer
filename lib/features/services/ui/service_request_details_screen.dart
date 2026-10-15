import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../../core/media/media_url.dart';
import '../../auth/state/auth_controller.dart';
import '../data/services_api.dart';
import '../models/service_models.dart';
import 'emergency_request_tracking_screen.dart';
import 'service_my_requests_screen.dart';

const double _servicePlatformCommissionRate = 0.10;

String _serviceRequestLifecycleStatus(ServiceRequestModel request) {
  final bookingStatus = (request.bookingStatus ?? '').trim();
  return bookingStatus.isNotEmpty ? bookingStatus : request.status.trim();
}

String _normalizedServiceRequestLifecycleStatus(ServiceRequestModel request) {
  return _serviceRequestLifecycleStatus(request).toLowerCase();
}

bool _isV2ServiceBooking(ServiceRequestModel request) {
  return (request.bookingFlowKind ?? '').trim().toUpperCase() == 'V2';
}

String? _serviceTransitionIdempotencyKey(
  ServiceRequestModel request,
  String status,
) {
  final version = request.bookingVersion;
  if (version == null) return null;
  return 'service-request:${request.id}:$version:$status';
}

double _serviceRequestGrossAmount(ServiceRequestModel request) {
  final candidates = <double?>[
    request.bookingTotalIqd,
    request.finalPrice,
    request.bookingSubtotalIqd,
    if (request.quotes.isNotEmpty) request.quotes.first.amount,
    if (request.quotes.isNotEmpty) request.quotes.first.minAmount,
  ];
  for (final value in candidates) {
    if (value != null && value > 0) return value;
  }
  return 0;
}

double _servicePlatformCommission(double amount) {
  if (amount <= 0) return 0;
  return amount * _servicePlatformCommissionRate;
}

String _formatIqd(num value) {
  final rounded = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < rounded.length; i++) {
    final remaining = rounded.length - i;
    buffer.write(rounded[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return '${buffer.toString()} IQD';
}

String _whatsAppPhone(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('0')) return '964${digits.substring(1)}';
  return digits;
}

class ServiceRequestDetailsScreen extends ConsumerStatefulWidget {
  final int requestId;

  const ServiceRequestDetailsScreen({super.key, required this.requestId});

  @override
  ConsumerState<ServiceRequestDetailsScreen> createState() =>
      _ServiceRequestDetailsScreenState();
}

class _ServiceRequestDetailsScreenState
    extends ConsumerState<ServiceRequestDetailsScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _reviewSubmitted = false;
  String? _error;
  ServiceRequestModel? _request;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref
          .read(servicesApiProvider)
          .getMyRequest(widget.requestId);
      if (!mounted) return;
      setState(() {
        _request = ServiceRequestModel.fromJson(raw);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _updateCustomerStatus(String status, {String? note}) async {
    if (_busy) return;
    final request = _request;
    if (request == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(servicesApiProvider)
          .updateMyRequestStatus(
            requestId: widget.requestId,
            status: status,
            note: note,
            expectedVersion: request.bookingVersion,
            idempotencyKey: _serviceTransitionIdempotencyKey(request, status),
          );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateProviderStatus(
    String status, {
    String? note,
    DateTime? scheduledStartAt,
    DateTime? scheduledEndAt,
  }) async {
    if (_busy) return;
    final request = _request;
    if (request == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(servicesApiProvider)
          .updateProviderRequestStatus(
            requestId: widget.requestId,
            status: status,
            note: note,
            scheduledStartAt: scheduledStartAt,
            scheduledEndAt: scheduledEndAt,
            expectedVersion: request.bookingVersion,
            idempotencyKey: _serviceTransitionIdempotencyKey(request, status),
          );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respondToQuote(ServiceQuoteModel quote, String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(servicesApiProvider)
          .respondToQuote(
            requestId: widget.requestId,
            quoteId: quote.id,
            action: action,
          );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createReview() async {
    final request = _request;
    if (request == null || _busy) return;
    final payload = await _showReviewDialog(context);
    if (payload == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(servicesApiProvider).createReview({
        'requestId': request.id,
        'rating': payload.rating,
        if ((payload.comment ?? '').trim().isNotEmpty)
          'comment': payload.comment!.trim(),
        'serviceAsDescribed': payload.serviceAsDescribed,
        'onTime': payload.onTime,
        'priceFair': payload.priceFair,
        'recommend': payload.recommend,
      });
      if (!mounted) return;
      setState(() => _reviewSubmitted = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إرسال التقييم بنجاح.')));
    } catch (error) {
      if (!mounted) return;
      final text = '$error';
      if (text.toLowerCase().contains('review_already_exists')) {
        setState(() => _reviewSubmitted = true);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendProviderQuote() async {
    final payload = await _showQuoteDialog(context);
    if (payload == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(servicesApiProvider)
          .createQuote(
            requestId: widget.requestId,
            payload: {
              'pricingModel': payload.pricingModel,
              'pricingUnit': payload.pricingUnit,
              if (payload.amount != null) 'amount': payload.amount,
              if (payload.minAmount != null) 'minAmount': payload.minAmount,
              if (payload.maxAmount != null) 'maxAmount': payload.maxAmount,
              if (payload.visitFee != null) 'visitFee': payload.visitFee,
              'currency': 'IQD',
              if ((payload.note ?? '').trim().isNotEmpty)
                'note': payload.note!.trim(),
            },
          );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _adjustInvoice() async {
    final request = _request;
    if (request == null || _busy) return;
    final priceCtrl = TextEditingController(
      text: (request.finalPrice ?? request.bookingTotalIqd ?? 0)
          .round()
          .toString(),
    );
    final discountCtrl = TextEditingController(
      text: request.invoiceAdminDiscountIqd.round().toString(),
    );
    final noteCtrl = TextEditingController(
      text: request.invoiceAdminDiscountNote ?? '',
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل فاتورة الخدمة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'سعر الخدمة'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: discountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'خصم الإدارة'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'سبب التعديل أو الخصم',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حفظ الفاتورة'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final price = double.tryParse(priceCtrl.text.trim());
    final discount = double.tryParse(discountCtrl.text.trim()) ?? 0;
    if (price == null || price < 0 || discount < 0 || discount > price) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(servicesApiProvider)
          .adjustServiceRequestPrice(
            requestId: request.id,
            totalIqd: price,
            discountIqd: discount,
            note: noteCtrl.text.trim(),
          );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      priceCtrl.dispose();
      discountCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<void> _applyCoupon() async {
    final request = _request;
    if (request == null || _busy) return;
    final codeCtrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استخدام كوبون خصم'),
        content: TextField(
          controller: codeCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'كود الخصم'),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(codeCtrl.text.trim()),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
    if ((code ?? '').isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(servicesApiProvider)
          .applyServiceRequestCoupon(requestId: request.id, code: code!);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      codeCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitPayment() async {
    final request = _request;
    if (request == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(servicesApiProvider)
          .submitServiceRequestPayment(
            requestId: request.id,
            paymentMethod: 'cash',
          );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmPayment() async {
    final request = _request;
    if (request == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(servicesApiProvider)
          .confirmServiceRequestPayment(requestId: request.id);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRequestChat(bool isProvider) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ServiceRequestChatSheet(
        requestId: widget.requestId,
        provider: isProvider,
      ),
    );
  }

  Future<void> _cancelByProvider() async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء حجز الخدمة'),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'سبب الإلغاء',
            hintText: 'سيظهر السبب للزبون بوضوح',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(reasonCtrl.text.trim()),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if ((reason ?? '').trim().isEmpty) return;
    await _updateProviderStatus('CANCELLED_BY_PROVIDER', note: reason);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final servicesSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.services, displayName: 'الخدمات');
    final isProvider = auth.isServiceProvider;
    final request = _request;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || request == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل طلب الخدمة')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'تعذر تحميل الطلب.\n${_error ?? ''}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _load,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_canAccessRequestWithSectionPolicy(request, servicesSection)) {
      return SectionUnavailableScreen(entry: servicesSection);
    }
    final amount = _serviceRequestGrossAmount(request);
    final commission = _servicePlatformCommission(amount);
    final lifecycleStatus = _normalizedServiceRequestLifecycleStatus(request);
    final isV2Booking = _isV2ServiceBooking(request);
    final cancelAvailableAt = DateTime.tryParse(
      request.customerCancelAvailableAt ?? '',
    );
    final canCustomerCancel =
        cancelAvailableAt == null ||
        !DateTime.now().isBefore(cancelAvailableAt.toLocal());
    final invoiceAmount =
        request.invoiceTotalIqd ??
        request.finalPrice ??
        request.bookingTotalIqd ??
        0;

    final allowCustomerReview =
        !isProvider && lifecycleStatus == 'completed' && !_reviewSubmitted;
    final latestQuote = request.quotes.isEmpty ? null : request.quotes.first;
    final pendingCustomerQuote =
        !isProvider &&
            latestQuote != null &&
            latestQuote.quoteStatus.trim().toLowerCase() == 'pending_customer'
        ? latestQuote
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          request.requestCode.trim().isEmpty
              ? 'تفاصيل طلب الخدمة'
              : request.requestCode,
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            if (!isProvider && request.urgency == 'emergency') ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        EmergencyRequestTrackingScreen(requestId: request.id),
                  ),
                ),
                icon: const Icon(Icons.location_searching_rounded),
                label: const Text('فتح الموقع الحي ومحادثة الطوارئ'),
              ),
              const SizedBox(height: 12),
            ],
            if (servicesSection.isBlocked)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        servicesSection.badgeLabel ?? 'غير متاح',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(servicesSection.effectiveMessage),
                      const SizedBox(height: 8),
                      const Text(
                        'تم إبقاء هذا الطلب متاحًا لأنه ما زال ضمن معاملة نشطة.',
                      ),
                    ],
                  ),
                ),
              ),
            if (request.serviceKey != null && !isV2Booking) ...[
              _CentralRoutingCard(request: request),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.serviceTitle ??
                          request.offeringName ??
                          'طلب خدمة',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'الحالة الحالية: ${serviceRequestStatusLabel(_serviceRequestLifecycleStatus(request))}',
                    ),
                    if ((request.providerBusinessName ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          isProvider
                              ? 'العميل رقم #${request.customerUserId}'
                              : 'مقدم الخدمة: ${request.providerBusinessName}',
                        ),
                      ),
                    if ((request.city ?? '').trim().isNotEmpty ||
                        (request.area ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'الموقع: ${request.city ?? ''} ${request.area ?? ''}',
                        ),
                      ),
                    if ((request.addressLine ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('العنوان: ${request.addressLine}'),
                      ),
                    if ((request.requestedDate ?? '').trim().isNotEmpty ||
                        (request.requestedTime ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'الموعد المطلوب: ${request.requestedDate ?? ''} ${request.requestedTime ?? ''}'
                              .trim(),
                        ),
                      ),
                    if ((request.notes ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('ملاحظات: ${request.notes}'),
                      ),
                    if ((request.contactPhone ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'طريقة التواصل: ${request.preferredContact} - ${request.contactPhone}',
                            ),
                            if (isProvider)
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => launchUrl(
                                      Uri.parse('tel:${request.contactPhone}'),
                                    ),
                                    icon: const Icon(Icons.call_outlined),
                                    label: const Text('اتصال'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => launchUrl(
                                      Uri.parse(
                                        'https://wa.me/${_whatsAppPhone(request.contactPhone!)}',
                                      ),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                    icon: const Icon(Icons.chat_outlined),
                                    label: const Text('واتساب'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    if (request.medicalInfo.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'المعلومات الطبية الاختيارية: ${request.medicalInfo.values.where((value) => '$value'.trim().isNotEmpty).join('، ')}',
                        ),
                      ),
                    if (request.finalPrice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'السعر النهائي: ${request.finalPrice} ${request.finalCurrency ?? 'IQD'}',
                        ),
                      ),
                    if (amount > 0) ...[
                      const SizedBox(height: 10),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.black.withValues(alpha: 0.04),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('قيمة الحجز: ${_formatIqd(amount)}'),
                              Text(
                                'استقطاع مسلكي 10%: ${_formatIqd(commission)}',
                              ),
                              Text(
                                'صافي مقدم الخدمة: ${_formatIqd(amount - commission)}',
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'الدفع نقداً عبر المكتب، ويتم تسليم الصافي لصاحب الخدمة بعد انتهاء الخدمة.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (<String>{
              'accepted',
              'confirmed',
              'in_progress',
              'provider_completed',
              'completed',
            }.contains(lifecycleStatus)) ...[
              const SizedBox(height: 12),
              _ServiceInvoiceCard(
                request: request,
                invoiceAmount: invoiceAmount,
                isProvider: isProvider,
                busy: _busy,
                onApplyCoupon: _applyCoupon,
                onAdjust: _adjustInvoice,
                onSubmitPayment: _submitPayment,
                onConfirmPayment: _confirmPayment,
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openRequestChat(isProvider),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('محادثة طلب الخدمة'),
            ),
            if (request.attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'المرفقات',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: request.attachments.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final attachment = request.attachments[index];
                    final mediaUrl = resolveMediaUrl(
                      '${attachment['mediaUrl'] ?? ''}'.trim(),
                    );
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 140,
                        color: Colors.black12,
                        child: mediaUrl == null || mediaUrl.isEmpty
                            ? const Icon(Icons.image_not_supported_outlined)
                            : Image.network(
                                mediaUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'عروض السعر',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                if (isProvider)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _sendProviderQuote,
                    icon: const Icon(Icons.price_change_outlined),
                    label: const Text('إرسال عرض'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (request.quotes.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('لا توجد عروض سعر على هذا الطلب حتى الآن.'),
                ),
              ),
            ...request.quotes.map(
              (quote) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الجولة ${quote.roundNo}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'الحالة: ${serviceQuoteStatusLabel(quote.quoteStatus)}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'التسعير: ${quote.amount ?? quote.minAmount ?? '-'} ${quote.currency} / ${quote.pricingUnit}',
                      ),
                      if ((quote.note ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('ملاحظة: ${quote.note}'),
                      ],
                      if (pendingCustomerQuote?.id == quote.id) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _respondToQuote(quote, 'accepted'),
                              child: const Text('قبول العرض'),
                            ),
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _respondToQuote(quote, 'rejected'),
                              child: const Text('رفض العرض'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'الخط الزمني',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (request.history.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('لا توجد تحديثات مسجلة بعد.'),
                ),
              ),
            ...request.history.map(
              (item) => Card(
                child: ListTile(
                  title: Text(
                    '${item['toStatus'] ?? item['status'] ?? 'تحديث'}',
                  ),
                  subtitle: Text('${item['note'] ?? item['createdAt'] ?? ''}'),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (allowCustomerReview)
              FilledButton.icon(
                onPressed: _busy ? null : _createReview,
                icon: const Icon(Icons.star_outline_rounded),
                label: const Text('إرسال تقييم للخدمة'),
              ),
            if (!isProvider) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (<String>{
                    'pending',
                    'awaiting_provider',
                    'pending_provider_confirmation',
                    'accepted',
                    'confirmed',
                    'scheduled',
                    'in_progress',
                  }.contains(lifecycleStatus))
                    OutlinedButton.icon(
                      onPressed: _busy || !canCustomerCancel
                          ? null
                          : () => _updateCustomerStatus('cancelled'),
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(
                        canCustomerCancel
                            ? 'إلغاء الطلب'
                            : 'الإلغاء متاح بعد 15 دقيقة',
                      ),
                    ),
                ],
              ),
            ],
            if (isProvider) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (<String>{
                    'pending',
                    'awaiting_provider',
                    'pending_provider_confirmation',
                  }.contains(lifecycleStatus))
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _updateProviderStatus('CONFIRMED'),
                      child: const Text('تأكيد الحجز بالسعر الظاهر'),
                    ),
                  if (<String>{
                    'accepted',
                    'awaiting_provider',
                    'confirmed',
                  }.contains(lifecycleStatus))
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _showScheduleDialog(
                              context,
                              _updateProviderStatus,
                            ),
                      child: const Text('جدولة'),
                    ),
                  if (<String>{
                    'accepted',
                    'scheduled',
                    'confirmed',
                  }.contains(lifecycleStatus))
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _updateProviderStatus('IN_PROGRESS'),
                      child: const Text('التوجه إلى الزبون'),
                    ),
                  if (lifecycleStatus == 'in_progress')
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _updateProviderStatus(
                              isV2Booking ? 'PROVIDER_COMPLETED' : 'completed',
                            ),
                      child: const Text('إتمام الخدمة وإظهار الفاتورة'),
                    ),
                  if (<String>{
                    'pending',
                    'awaiting_provider',
                    'pending_provider_confirmation',
                  }.contains(lifecycleStatus))
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _updateProviderStatus('rejected'),
                      child: const Text('رفض'),
                    ),
                  if (<String>{
                    'accepted',
                    'confirmed',
                    'scheduled',
                    'in_progress',
                  }.contains(lifecycleStatus))
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _cancelByProvider,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('إلغاء الحجز'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ServiceInvoiceCard extends StatelessWidget {
  final ServiceRequestModel request;
  final double invoiceAmount;
  final bool isProvider;
  final bool busy;
  final VoidCallback onApplyCoupon;
  final VoidCallback onAdjust;
  final VoidCallback onSubmitPayment;
  final VoidCallback onConfirmPayment;

  const _ServiceInvoiceCard({
    required this.request,
    required this.invoiceAmount,
    required this.isProvider,
    required this.busy,
    required this.onApplyCoupon,
    required this.onAdjust,
    required this.onSubmitPayment,
    required this.onConfirmPayment,
  });

  @override
  Widget build(BuildContext context) {
    final paymentSubmitted = request.paymentSubmittedAt != null;
    final paymentConfirmed = request.paymentConfirmedAt != null;
    final serviceCompleted =
        (request.bookingStatus ?? request.status).toLowerCase() ==
            'provider_completed' ||
        paymentSubmitted ||
        paymentConfirmed;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_outlined),
              SizedBox(width: 8),
              Text(
                'فاتورة الخدمة',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _invoiceRow(
            'سعر الخدمة',
            _formatIqd(request.finalPrice ?? request.bookingTotalIqd ?? 0),
          ),
          if (request.invoiceAdminDiscountIqd > 0)
            _invoiceRow(
              'خصم الإدارة',
              '- ${_formatIqd(request.invoiceAdminDiscountIqd)}',
            ),
          if (request.invoiceCouponDiscountIqd > 0)
            _invoiceRow(
              'كوبون ${request.invoiceCouponCode ?? ''}',
              '- ${_formatIqd(request.invoiceCouponDiscountIqd)}',
            ),
          const Divider(),
          _invoiceRow('المبلغ المطلوب', _formatIqd(invoiceAmount), bold: true),
          const SizedBox(height: 10),
          if (paymentConfirmed)
            const Text(
              'تم تأكيد الدفع وأرشفة الخدمة ضمن الخدمات المكتملة.',
              style: TextStyle(fontWeight: FontWeight.w800),
            )
          else if (paymentSubmitted)
            const Text(
              'أكد العميل الدفع. الطلب بانتظار تأكيد الاستلام من الإدارة.',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isProvider && !paymentConfirmed)
                OutlinedButton.icon(
                  onPressed: busy ? null : onAdjust,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('تعديل السعر أو الخصم'),
                ),
              if (!isProvider && !paymentSubmitted && !paymentConfirmed)
                OutlinedButton.icon(
                  onPressed: busy ? null : onApplyCoupon,
                  icon: const Icon(Icons.local_offer_outlined),
                  label: const Text('إضافة كوبون'),
                ),
              if (!isProvider &&
                  serviceCompleted &&
                  !paymentSubmitted &&
                  !paymentConfirmed)
                FilledButton.icon(
                  onPressed: busy ? null : onSubmitPayment,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('تم الدفع'),
                ),
              if (isProvider && paymentSubmitted && !paymentConfirmed)
                FilledButton.icon(
                  onPressed: busy ? null : onConfirmPayment,
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('تأكيد استلام الدفع'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _invoiceRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: bold ? FontWeight.w900 : null),
          ),
          Text(
            value,
            style: TextStyle(fontWeight: bold ? FontWeight.w900 : null),
          ),
        ],
      ),
    );
  }
}

class _ServiceRequestChatSheet extends ConsumerStatefulWidget {
  final int requestId;
  final bool provider;

  const _ServiceRequestChatSheet({
    required this.requestId,
    required this.provider,
  });

  @override
  ConsumerState<_ServiceRequestChatSheet> createState() =>
      _ServiceRequestChatSheetState();
}

class _ServiceRequestChatSheetState
    extends ConsumerState<_ServiceRequestChatSheet> {
  final _messageCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await ref
          .read(servicesApiProvider)
          .listServiceRequestMessages(
            requestId: widget.requestId,
            provider: widget.provider,
          );
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final message = _messageCtrl.text.trim();
    if (message.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(servicesApiProvider)
          .sendServiceRequestMessage(
            requestId: widget.requestId,
            provider: widget.provider,
            message: message,
          );
      _messageCtrl.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authControllerProvider).user?.id;
    return FractionallySizedBox(
      heightFactor: 0.82,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          10,
          14,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'محادثة طلب الخدمة',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                  ? const Center(
                      child: Text('ابدأ المحادثة لتوضيح تفاصيل الطلب.'),
                    )
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final mine =
                            '${item['senderUserId']}' == '$currentUserId';
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${item['message'] ?? ''}'),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageCtrl,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالتك...',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'إرسال',
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CentralRoutingCard extends StatelessWidget {
  const _CentralRoutingCard({required this.request});

  final ServiceRequestModel request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emergency = request.urgency == 'emergency';
    final color = emergency ? scheme.error : scheme.primary;
    final professional = (request.assignedProfessionalName ?? '').trim();
    final phone = (request.assignedProfessionalPhone ?? '').trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(
                emergency ? Icons.sos_rounded : Icons.route_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  emergency ? 'متابعة نداء المساعدة' : 'متابعة توجيه الطلب',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _centralRoutingDescription(request.routingStatus),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (professional.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'المختص المعيّن: $professional',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
            ),
          ],
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                icon: const Icon(Icons.call_rounded),
                label: Text('اتصال بالمختص: $phone'),
              ),
            ),
          ],
          if ((request.assignmentNote ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'ملاحظة الفريق: ${request.assignmentNote}',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
            ),
          ],
        ],
      ),
    );
  }
}

String _centralRoutingDescription(String? value) => switch (value) {
  'triaged' => 'راجع فريق مسلكي الطلب ويختار المختص المناسب الآن.',
  'assigned' => 'تم تعيين مختص لهذا الطلب وسيتم التواصل معك.',
  'contacted' => 'تم التواصل مع المختص وتأكيد تفاصيل الطلب.',
  'en_route' => 'المختص في الطريق إلى الموقع المحدد.',
  'resolved' => 'تم إنجاز الخدمة وإغلاق التوجيه.',
  'cancelled' => 'تم إلغاء توجيه هذا الطلب. راجع الملاحظة أدناه.',
  _ => 'وصل طلبك إلى فريق خدمات مسلكي وهو بانتظار المراجعة.',
};

bool _canAccessRequestWithSectionPolicy(
  ServiceRequestModel request,
  SectionAvailabilityEntry entry,
) {
  if (entry.isOpen) return true;
  if (!entry.allowExistingActiveAccess) return false;
  return !_isTerminalServiceRequestStatus(request.status);
}

bool _isTerminalServiceRequestStatus(String? value) {
  return <String>{
    'completed',
    'cancelled',
    'rejected',
  }.contains((value ?? '').trim().toLowerCase());
}

class _ServiceReviewPayload {
  final int rating;
  final String? comment;
  final bool serviceAsDescribed;
  final bool onTime;
  final bool priceFair;
  final bool recommend;

  const _ServiceReviewPayload({
    required this.rating,
    required this.comment,
    required this.serviceAsDescribed,
    required this.onTime,
    required this.priceFair,
    required this.recommend,
  });
}

class _ServiceQuotePayload {
  final String pricingModel;
  final String pricingUnit;
  final double? amount;
  final double? minAmount;
  final double? maxAmount;
  final double? visitFee;
  final String? note;

  const _ServiceQuotePayload({
    required this.pricingModel,
    required this.pricingUnit,
    required this.amount,
    required this.minAmount,
    required this.maxAmount,
    required this.visitFee,
    required this.note,
  });
}

Future<_ServiceReviewPayload?> _showReviewDialog(BuildContext context) async {
  final commentCtrl = TextEditingController();
  var rating = 5;
  var serviceAsDescribed = true;
  var onTime = true;
  var priceFair = true;
  var recommend = true;
  _ServiceReviewPayload? result;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('تقييم الخدمة'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: rating,
                    decoration: const InputDecoration(labelText: 'التقييم'),
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5 نجوم')),
                      DropdownMenuItem(value: 4, child: Text('4 نجوم')),
                      DropdownMenuItem(value: 3, child: Text('3 نجوم')),
                      DropdownMenuItem(value: 2, child: Text('نجمتان')),
                      DropdownMenuItem(value: 1, child: Text('نجمة واحدة')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => rating = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'تعليقك',
                      hintText: 'اكتب ملاحظتك عن التنفيذ والسعر والالتزام...',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    value: serviceAsDescribed,
                    onChanged: (value) =>
                        setDialogState(() => serviceAsDescribed = value),
                    title: const Text('الخدمة مطابقة للوصف'),
                  ),
                  SwitchListTile(
                    value: onTime,
                    onChanged: (value) => setDialogState(() => onTime = value),
                    title: const Text('الالتزام بالموعد'),
                  ),
                  SwitchListTile(
                    value: priceFair,
                    onChanged: (value) =>
                        setDialogState(() => priceFair = value),
                    title: const Text('السعر مناسب'),
                  ),
                  SwitchListTile(
                    value: recommend,
                    onChanged: (value) =>
                        setDialogState(() => recommend = value),
                    title: const Text('أوصي بمقدم الخدمة'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                result = _ServiceReviewPayload(
                  rating: rating,
                  comment: commentCtrl.text.trim().isEmpty
                      ? null
                      : commentCtrl.text.trim(),
                  serviceAsDescribed: serviceAsDescribed,
                  onTime: onTime,
                  priceFair: priceFair,
                  recommend: recommend,
                );
                Navigator.of(context).pop();
              },
              child: const Text('إرسال'),
            ),
          ],
        );
      },
    ),
  );
  commentCtrl.dispose();
  return result;
}

Future<_ServiceQuotePayload?> _showQuoteDialog(BuildContext context) async {
  final amountCtrl = TextEditingController();
  final minCtrl = TextEditingController();
  final maxCtrl = TextEditingController();
  final feeCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  var pricingModel = 'custom_quote';
  var pricingUnit = 'job';
  _ServiceQuotePayload? result;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('إرسال عرض سعر'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: pricingModel,
                decoration: const InputDecoration(labelText: 'نوع التسعير'),
                items: const [
                  DropdownMenuItem(
                    value: 'custom_quote',
                    child: Text('تسعير مخصص'),
                  ),
                  DropdownMenuItem(
                    value: 'inspection_required',
                    child: Text('حسب المعاينة'),
                  ),
                  DropdownMenuItem(
                    value: 'starting_from',
                    child: Text('يبدأ من'),
                  ),
                  DropdownMenuItem(
                    value: 'fixed_package',
                    child: Text('باقة ثابتة'),
                  ),
                  DropdownMenuItem(value: 'per_hour', child: Text('لكل ساعة')),
                  DropdownMenuItem(
                    value: 'per_visit',
                    child: Text('لكل زيارة'),
                  ),
                ],
                onChanged: (value) => pricingModel = value ?? 'custom_quote',
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: pricingUnit,
                decoration: const InputDecoration(labelText: 'الوحدة'),
                items: const [
                  DropdownMenuItem(value: 'job', child: Text('خدمة')),
                  DropdownMenuItem(value: 'hour', child: Text('ساعة')),
                  DropdownMenuItem(value: 'visit', child: Text('زيارة')),
                  DropdownMenuItem(value: 'day', child: Text('يوم')),
                  DropdownMenuItem(value: 'package', child: Text('باقة')),
                ],
                onChanged: (value) => pricingUnit = value ?? 'job',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'السعر'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'أدنى سعر'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: maxCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'أعلى سعر'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: feeCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'رسوم الزيارة'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            result = _ServiceQuotePayload(
              pricingModel: pricingModel,
              pricingUnit: pricingUnit,
              amount: double.tryParse(amountCtrl.text.trim()),
              minAmount: double.tryParse(minCtrl.text.trim()),
              maxAmount: double.tryParse(maxCtrl.text.trim()),
              visitFee: double.tryParse(feeCtrl.text.trim()),
              note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
            );
            Navigator.of(context).pop();
          },
          child: const Text('إرسال'),
        ),
      ],
    ),
  );
  amountCtrl.dispose();
  minCtrl.dispose();
  maxCtrl.dispose();
  feeCtrl.dispose();
  noteCtrl.dispose();
  return result;
}

Future<void> _showScheduleDialog(
  BuildContext context,
  Future<void> Function(
    String status, {
    String? note,
    DateTime? scheduledStartAt,
    DateTime? scheduledEndAt,
  })
  onSubmit,
) async {
  final noteCtrl = TextEditingController();
  DateTime? start;
  DateTime? end;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('جدولة التنفيذ'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  start == null
                      ? 'اختر وقت البداية'
                      : 'البداية: ${start!.toLocal()}',
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final now = DateTime.now();
                  final date = await showDatePicker(
                    context: context,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 180)),
                    initialDate: start ?? now,
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(start ?? now),
                  );
                  if (time == null) return;
                  setDialogState(() {
                    start = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                  });
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  end == null
                      ? 'اختر وقت النهاية'
                      : 'النهاية: ${end!.toLocal()}',
                ),
                trailing: const Icon(Icons.event_available_outlined),
                onTap: () async {
                  final base = start ?? DateTime.now();
                  final date = await showDatePicker(
                    context: context,
                    firstDate: base,
                    lastDate: base.add(const Duration(days: 180)),
                    initialDate: end ?? base,
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(end ?? base),
                  );
                  if (time == null) return;
                  setDialogState(() {
                    end = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                  });
                },
              ),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظة'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: start == null
                ? null
                : () async {
                    await onSubmit(
                      'scheduled',
                      note: noteCtrl.text.trim().isEmpty
                          ? null
                          : noteCtrl.text.trim(),
                      scheduledStartAt: start,
                      scheduledEndAt: end,
                    );
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                  },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
  noteCtrl.dispose();
}

String serviceQuoteStatusLabel(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'pending_customer':
      return 'بانتظار العميل';
    case 'accepted':
      return 'مقبول';
    case 'rejected':
      return 'مرفوض';
    case 'expired':
      return 'منتهي';
    case 'cancelled':
      return 'ملغي';
    default:
      return value == null || value.trim().isEmpty ? 'غير محدد' : value;
  }
}
