// ignore_for_file: prefer_const_constructors

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart' as api_error_mapper;
import '../../../core/utils/currency.dart';
import '../../auth/state/auth_controller.dart';
import '../../orders/ui/customer_orders_screen.dart';
import '../../owner/state/owner_controller.dart';
import '../../products/models/product_model.dart';
import '../data/pharmacy_api.dart';
import '../models/pharmacy_models.dart';

final pharmacyApiProvider = Provider<PharmacyApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return PharmacyApi(dio);
});

String _mapPharmacyError(BuildContext context, Object error) {
  if (error is DioException) {
    return api_error_mapper.mapDioError(
      error,
      fallback: context.l10n.commonTryAgainLater,
    );
  }
  return context.l10n.commonTryAgainLater;
}

String _t(BuildContext context, {required String ar, required String en}) =>
    context.lt(ar: ar, en: en);

TextDirection _dir(BuildContext context) => context.appTextDirection;

String _conversationStatusLabel(BuildContext context, String status) {
  switch (status) {
    case 'open':
      return _t(context, ar: 'مفتوحة', en: 'Open');
    case 'awaiting_customer':
      return _t(context, ar: 'بانتظار الزبون', en: 'Awaiting customer');
    case 'awaiting_pharmacy':
      return _t(context, ar: 'بانتظار الصيدلية', en: 'Awaiting pharmacy');
    case 'cart_proposed':
      return _t(context, ar: 'تم اقتراح سلة', en: 'Cart proposed');
    case 'cart_revision_requested':
      return _t(context, ar: 'طلب تعديل', en: 'Revision requested');
    case 'proposed':
      return _t(context, ar: 'مقترحة', en: 'Proposed');
    case 'revision_requested':
      return _t(context, ar: 'بحاجة لتعديل', en: 'Needs revision');
    case 'accepted':
      return _t(context, ar: 'مقبولة', en: 'Accepted');
    case 'rejected':
      return _t(context, ar: 'مرفوضة', en: 'Rejected');
    case 'expired':
      return _t(context, ar: 'منتهية', en: 'Expired');
    case 'order_created':
      return _t(context, ar: 'تم إنشاء الطلب', en: 'Order created');
    case 'in_preparation':
      return _t(context, ar: 'قيد التحضير', en: 'In preparation');
    case 'out_for_delivery':
      return _t(context, ar: 'قيد التوصيل', en: 'Out for delivery');
    case 'completed':
      return _t(context, ar: 'مكتملة', en: 'Completed');
    case 'closed_no_sale':
      return _t(context, ar: 'أغلقت بدون بيع', en: 'Closed without sale');
    case 'cancelled':
      return _t(context, ar: 'ملغاة', en: 'Cancelled');
    case 'unavailable':
      return _t(context, ar: 'غير متاحة', en: 'Unavailable');
    default:
      return status;
  }
}

Color _conversationStatusColor(BuildContext context, String status) {
  switch (status) {
    case 'completed':
    case 'order_created':
    case 'accepted':
      return Colors.green.withValues(alpha: 0.18);
    case 'closed_no_sale':
    case 'cancelled':
    case 'unavailable':
    case 'rejected':
    case 'expired':
      return Colors.red.withValues(alpha: 0.18);
    case 'cart_proposed':
    case 'awaiting_customer':
    case 'proposed':
    case 'revision_requested':
      return Theme.of(context).colorScheme.primary.withValues(alpha: 0.18);
    default:
      return Colors.white.withValues(alpha: 0.08);
  }
}

String _bucketLabel(BuildContext context, String bucket) {
  switch (bucket) {
    case 'active':
      return context.l10n.pharmacyBucketActive;
    case 'completed':
      return context.l10n.pharmacyBucketCompleted;
    case 'closed':
      return context.l10n.pharmacyBucketClosed;
    default:
      return bucket;
  }
}

String _formatDateTime(BuildContext context, DateTime? value) {
  if (value == null) return '-';
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}/${local.month}/${local.day} $hour:$minute';
}

class PharmacyConversationScreen extends ConsumerStatefulWidget {
  final int? merchantId;
  final int? conversationId;
  final bool ownerMode;
  final String? titleOverride;
  final String? pendingProductContextMessage;
  final Map<String, dynamic>? pendingProductContextMetadata;

  const PharmacyConversationScreen({
    super.key,
    this.merchantId,
    this.conversationId,
    this.ownerMode = false,
    this.titleOverride,
    this.pendingProductContextMessage,
    this.pendingProductContextMetadata,
  });

  @override
  ConsumerState<PharmacyConversationScreen> createState() =>
      _PharmacyConversationScreenState();
}

class _PharmacyConversationScreenState
    extends ConsumerState<PharmacyConversationScreen> {
  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  PharmacyConversationDetailsModel? _details;
  int? _conversationId;
  bool _loading = true;
  bool _sending = false;
  bool _uploading = false;
  String? _error;
  bool _pendingContextProcessed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(pharmacyApiProvider);
      final conversationId = await _resolveConversationId(api);
      if (conversationId == null) {
        throw StateError('Pharmacy conversation context is missing.');
      }
      final details = await api.getConversationDetails(conversationId: conversationId);
      if (!mounted) return;
      setState(() {
        _conversationId = conversationId;
        _details = details;
        _loading = false;
      });
      await _maybeSendPendingProductContext();
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _mapPharmacyError(context, error);
        _loading = false;
      });
    }
  }

  Future<int?> _resolveConversationId(PharmacyApi api) async {
    if (widget.conversationId != null) return widget.conversationId;
    if (widget.merchantId == null) return null;

    final existing = await api.listConversations(limit: 80);
    final matches = existing.where((item) => item.merchantId == widget.merchantId).toList();
    if (matches.isNotEmpty) {
      matches.sort((a, b) {
        final aTime = a.updatedAt ?? a.lastMessageAt ?? a.createdAt;
        final bTime = b.updatedAt ?? b.lastMessageAt ?? b.createdAt;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
      return matches.first.id;
    }
    if (widget.ownerMode) return null;
    final created = await api.createConversation(
      merchantId: widget.merchantId!,
      metadata: widget.pendingProductContextMetadata,
    );
    return created.id;
  }

  Future<void> _maybeSendPendingProductContext() async {
    final id = _conversationId;
    final message = widget.pendingProductContextMessage?.trim();
    if (_pendingContextProcessed ||
        widget.ownerMode ||
        id == null ||
        message == null ||
        message.isEmpty) {
      return;
    }
    _pendingContextProcessed = true;
    await ref.read(pharmacyApiProvider).sendMessage(
      conversationId: id,
      message: message,
      metadata: widget.pendingProductContextMetadata,
    );
    await _reload();
  }

  Future<void> _reload() async {
    final id = _conversationId;
    if (id == null) return _bootstrap();
    try {
      final details = await ref
          .read(pharmacyApiProvider)
          .getConversationDetails(conversationId: id);
      if (!mounted) return;
      setState(() {
        _details = details;
        _error = null;
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _mapPharmacyError(context, error));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _sendMessage() async {
    final id = _conversationId;
    if (id == null || _sending) return;
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(pharmacyApiProvider).sendMessage(
            conversationId: id,
            message: text,
          );
      if (!mounted) return;
      _messageCtrl.clear();
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mapPharmacyError(context, error))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _uploadAttachment() async {
    final id = _conversationId;
    if (id == null || _uploading) return;
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const <String>[
        'jpg',
        'jpeg',
        'png',
        'webp',
        'pdf',
        'doc',
        'docx',
      ],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) return;

    setState(() => _uploading = true);
    try {
      await ref.read(pharmacyApiProvider).uploadAttachment(
            conversationId: id,
            file: file,
          );
      if (!mounted) return;
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mapPharmacyError(context, error))),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openAttachment(int attachmentId) async {
    final url = await ref
        .read(pharmacyApiProvider)
        .requestAttachmentAccessUrl(attachmentId);
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<String?> _promptNote({
    required String title,
    String? initialValue,
  }) async {
    final ctrl = TextEditingController(text: initialValue ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, textDirection: _dir(context)),
        content: TextField(
          controller: ctrl,
          textDirection: _dir(context),
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: _t(
              context,
              ar: 'اكتب ملاحظتك هنا',
              en: 'Write your note here',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(ctrl.text.trim()),
            child: Text(context.l10n.commonContinue),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _applyCustomerCartAction(
    String action,
    PharmacyProposedCartModel cart,
  ) async {
    final api = ref.read(pharmacyApiProvider);
    final note = action == 'revision' || action == 'reject'
        ? await _promptNote(
            title: action == 'revision'
                ? _t(
                    context,
                    ar: 'سبب طلب التعديل',
                    en: 'Reason for requesting revision',
                  )
                : _t(
                    context,
                    ar: 'سبب الرفض',
                    en: 'Reason for rejection',
                  ),
          )
        : null;
    if ((action == 'revision' || action == 'reject') && note == null) return;
    try {
      switch (action) {
        case 'accept':
          await api.acceptCart(cart.id);
          break;
        case 'reject':
          await api.rejectCart(cart.id);
          break;
        case 'revision':
          await api.requestCartRevision(cartId: cart.id, note: note);
          break;
      }
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mapPharmacyError(context, error))),
      );
    }
  }

  Future<void> _convertToOrder(PharmacyProposedCartModel cart) async {
    try {
      final orderId = await ref
          .read(pharmacyApiProvider)
          .convertCartToOrder(cartId: cart.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.pharmacyOrderCreated(orderId))),
      );
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CustomerOrdersScreen(initialOrderId: orderId),
        ),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mapPharmacyError(context, error))),
      );
    }
  }

  Future<void> _openCreateCartSheet() async {
    final conversationId = _conversationId;
    if (conversationId == null) return;
    final ownerState = ref.read(ownerControllerProvider);
    final result = await showModalBottomSheet<_CartComposerResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PharmacyCartComposerSheet(
        products: ownerState.products,
      ),
    );
    if (result == null) return;
    try {
      await ref.read(pharmacyApiProvider).createProposedCart(
            conversationId: conversationId,
            items: result.items,
            deliveryFee: result.deliveryFee,
            notes: result.notes,
            expiresAt: result.expiresAt,
          );
      if (!mounted) return;
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mapPharmacyError(context, error))),
      );
    }
  }

  Widget _buildHeaderCard(PharmacyConversationDetailsModel details) {
    final conversation = details.conversation;
    final ownerSubtitle = conversation.customer == null
        ? null
        : '${conversation.customer?.fullName ?? _t(context, ar: 'زبون', en: 'Customer')}'
            '${conversation.customer?.phone?.trim().isNotEmpty == true ? ' • ${conversation.customer!.phone}' : ''}';
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                _StatusPill(
                  label: _conversationStatusLabel(context, conversation.status),
                  color: _conversationStatusColor(context, conversation.status),
                ),
                _StatusPill(
                  label: _bucketLabel(context, conversation.bucket),
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                if (conversation.linkedOrderId != null)
                  _StatusPill(
                    label: _t(
                      context,
                      ar: 'طلب #${conversation.linkedOrderId}',
                      en: 'Order #${conversation.linkedOrderId}',
                    ),
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.18),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (widget.ownerMode && ownerSubtitle != null)
              Text(
                ownerSubtitle,
                textDirection: _dir(context),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              )
            else
              Text(
                conversation.merchantName ?? context.l10n.pharmacyConversationTitle,
                textDirection: _dir(context),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            const SizedBox(height: 6),
            Text(
              _t(
                context,
                ar:
                    'آخر نشاط: ${_formatDateTime(context, conversation.lastMessageAt ?? conversation.updatedAt ?? conversation.createdAt)}',
                en:
                    'Last activity: ${_formatDateTime(context, conversation.lastMessageAt ?? conversation.updatedAt ?? conversation.createdAt)}',
              ),
              textDirection: _dir(context),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (conversation.supportsAttachments)
                  _StatusPill(
                    label: _t(
                      context,
                      ar: 'المرفقات مفعلة',
                      en: 'Attachments enabled',
                    ),
                    color: Color(0x1A4CAF50),
                  ),
                if (conversation.supportsPharmacyWorkflow)
                  _StatusPill(
                    label: _t(
                      context,
                      ar: 'سير عمل صيدلي',
                      en: 'Pharmacy workflow',
                    ),
                    color: Color(0x1A2196F3),
                  ),
                _StatusPill(
                  label: _t(
                    context,
                    ar: '${conversation.messagesCount} رسالة',
                    en: '${conversation.messagesCount} messages',
                  ),
                  color: Colors.white12,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineCard(PharmacyConversationDetailsModel details) {
    final conversation = details.conversation;
    final cart = details.latestProposedCart;
    final timeline = <(String label, DateTime? date)>[
      (_t(context, ar: 'بدء المحادثة', en: 'Conversation started'), conversation.createdAt),
      (_t(context, ar: 'آخر تحديث', en: 'Last update'), conversation.updatedAt ?? conversation.lastMessageAt),
      if (cart != null) (_t(context, ar: 'اقتراح السلة', en: 'Cart proposed'), cart.createdAt),
      if (cart?.revisionRequestedAt != null)
        (_t(context, ar: 'طلب تعديل', en: 'Revision requested'), cart?.revisionRequestedAt),
      if (cart?.confirmedAt != null)
        (_t(context, ar: 'تأكيد السلة', en: 'Cart confirmed'), cart?.confirmedAt),
      if (cart?.rejectedAt != null)
        (_t(context, ar: 'رفض السلة', en: 'Cart rejected'), cart?.rejectedAt),
    ];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t(context, ar: 'حالة المحادثة', en: 'Conversation status'),
              textDirection: _dir(context),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...timeline.where((item) => item.$2 != null).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      textDirection: _dir(context),
                      children: [
                        Expanded(
                          child: Text(
                            item.$1,
                            textDirection: _dir(context),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          _formatDateTime(context, item.$2),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageTile(PharmacyMessageModel message) {
    final isMine = widget.ownerMode
        ? message.senderType == 'pharmacy'
        : message.senderType == 'customer';
    final bubbleColor = isMine
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.06);
    final senderLabel = message.senderFullName?.trim().isNotEmpty == true
        ? message.senderFullName!
        : isMine
        ? context.l10n.commonYou
        : _t(
            context,
            ar: message.senderType == 'pharmacy' ? 'الصيدلية' : 'الزبون',
            en: message.senderType == 'pharmacy' ? 'Pharmacy' : 'Customer',
          );
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              senderLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            if (message.text?.trim().isNotEmpty == true)
              Text(message.text!, textDirection: _dir(context)),
            if (message.attachmentId != null) ...[
              if (message.text?.trim().isNotEmpty == true)
                const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _openAttachment(message.attachmentId!),
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(
                  message.attachmentName?.trim().isNotEmpty == true
                      ? message.attachmentName!
                      : context.l10n.pharmacyOpenAttachmentLabel,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              _formatDateTime(context, message.createdAt),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartCard(PharmacyProposedCartModel cart) {
    final canCustomerAct = !widget.ownerMode &&
        (cart.status == 'proposed' || cart.status == 'revision_requested');
    final canConvert = !widget.ownerMode && cart.status == 'accepted';

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              textDirection: _dir(context),
              children: [
                Expanded(
                  child: Text(
                    context.l10n.pharmacyProposedCartTitle(cart.version),
                    textDirection: _dir(context),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _StatusPill(
                  label: _conversationStatusLabel(context, cart.status),
                  color: _conversationStatusColor(context, cart.status),
                ),
              ],
            ),
            if (cart.notes?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                cart.notes!,
                textDirection: _dir(context),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 10),
            ...cart.items.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      textDirection: _dir(context),
                      children: [
                        Expanded(
                          child: Text(
                            item.productName,
                            textDirection: _dir(context),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(formatIqd(item.lineTotal)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _t(
                        context,
                        ar: 'الكمية: ${item.quantity} • سعر الوحدة: ${formatIqd(item.unitPrice)}',
                        en: 'Quantity: ${item.quantity} • Unit price: ${formatIqd(item.unitPrice)}',
                      ),
                      textDirection: _dir(context),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (item.note?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.note!,
                        textDirection: _dir(context),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (item.requiresPrescription || item.requiresReview) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          if (item.requiresPrescription)
                            _StatusPill(
                              label: _t(
                                context,
                                ar: 'وصفة مطلوبة',
                                en: 'Prescription required',
                              ),
                              color: Color(0x1A9C27B0),
                            ),
                          if (item.requiresReview)
                            _StatusPill(
                              label: _t(
                                context,
                                ar: 'مراجعة صيدلانية',
                                en: 'Pharmacist review',
                              ),
                              color: Color(0x1A03A9F4),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 18),
            _SummaryLine(
              label: context.l10n.commonSubtotal,
              value: formatIqd(cart.subtotal),
            ),
            _SummaryLine(
              label: context.l10n.commonDeliveryFee,
              value: formatIqd(cart.deliveryFee),
            ),
            _SummaryLine(
              label: context.l10n.commonTotal,
              value: formatIqd(cart.total),
              highlight: true,
            ),
            if (cart.expiresAt != null) ...[
              const SizedBox(height: 10),
              Text(
                _t(
                  context,
                  ar: 'تنتهي الصلاحية: ${_formatDateTime(context, cart.expiresAt)}',
                  en: 'Expires at: ${_formatDateTime(context, cart.expiresAt)}',
                ),
                textDirection: _dir(context),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (canCustomerAct) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () => _applyCustomerCartAction('accept', cart),
                    child: Text(context.l10n.commonApprove),
                  ),
                  OutlinedButton(
                    onPressed: () => _applyCustomerCartAction('revision', cart),
                    child: Text(context.l10n.pharmacyRequestRevisionLabel),
                  ),
                  OutlinedButton(
                    onPressed: () => _applyCustomerCartAction('reject', cart),
                    child: Text(context.l10n.commonReject),
                  ),
                ],
              ),
            ],
            if (canConvert) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _convertToOrder(cart),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: Text(context.l10n.pharmacyConvertToOrderLabel),
              ),
            ],
            if (widget.ownerMode) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.pharmacyStoreSettlementHint,
                style: Theme.of(context).textTheme.bodySmall,
                textDirection: _dir(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(PharmacyConversationDetailsModel? details) {
    return Column(
      children: [
        if (details != null) _buildHeaderCard(details),
        if (details != null) _buildTimelineCard(details),
        if (details?.latestProposedCart case final cart?) _buildCartCard(cart),
        Expanded(
          child: details == null || details.messages.isEmpty
              ? Center(
                  child: Text(
                    context.l10n.pharmacyNoMessagesYet,
                    textDirection: _dir(context),
                  ),
                )
              : ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  children: details.messages.map(_buildMessageTile).toList(),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: _uploading ? null : _uploadAttachment,
                  icon: _uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.attach_file_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageCtrl,
                    textDirection: _dir(context),
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: context.l10n.pharmacyMessageInputHint,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending ? null : _sendMessage,
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.l10n.commonSend),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.titleOverride ??
              details?.conversation.merchantName ??
              context.l10n.pharmacyConversationTitle,
        ),
        actions: [
          if (widget.ownerMode)
            IconButton(
              onPressed: _openCreateCartSheet,
              icon: const Icon(Icons.playlist_add_check_circle_outlined),
              tooltip: context.l10n.pharmacyCreateCartTitle,
            ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textDirection: _dir(context)),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _bootstrap,
                        child: Text(context.l10n.commonRetry),
                      ),
                    ],
                  ),
                )
              : _buildBody(details),
    );
  }
}

class CustomerPharmacyConversationsScreen extends StatelessWidget {
  const CustomerPharmacyConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PharmacyConversationsHubScreen(ownerMode: false);
  }
}

class OwnerPharmacyConversationsScreen extends StatelessWidget {
  const OwnerPharmacyConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PharmacyConversationsHubScreen(ownerMode: true);
  }
}

class _PharmacyConversationsHubScreen extends ConsumerStatefulWidget {
  final bool ownerMode;

  const _PharmacyConversationsHubScreen({required this.ownerMode});

  @override
  ConsumerState<_PharmacyConversationsHubScreen> createState() =>
      _PharmacyConversationsHubScreenState();
}

class _PharmacyConversationsHubScreenState
    extends ConsumerState<_PharmacyConversationsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 3, vsync: this);
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  final Map<String, List<PharmacyConversationModel>> _items =
      <String, List<PharmacyConversationModel>>{
        'active': <PharmacyConversationModel>[],
        'completed': <PharmacyConversationModel>[],
        'closed': <PharmacyConversationModel>[],
      };

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(pharmacyApiProvider);
      final query = _searchCtrl.text.trim();
      final result = await Future.wait([
        api.listConversations(bucket: 'active', q: query),
        api.listConversations(bucket: 'completed', q: query),
        api.listConversations(bucket: 'closed', q: query),
      ]);
      if (!mounted) return;
      setState(() {
        _items['active'] = result[0];
        _items['completed'] = result[1];
        _items['closed'] = result[2];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _mapPharmacyError(context, error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <(String key, String label)>[
      ('active', context.l10n.pharmacyBucketActive),
      ('completed', context.l10n.pharmacyBucketCompleted),
      ('closed', context.l10n.pharmacyBucketClosed),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.pharmacyConversationsTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: tabs.map((item) => Tab(text: item.$2)).toList(),
        ),
        actions: [
          IconButton(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              textDirection: _dir(context),
              decoration: InputDecoration(
                hintText: widget.ownerMode
                    ? _t(
                        context,
                        ar: 'ابحث باسم العميل أو رقمه',
                        en: 'Search by customer name or phone',
                      )
                    : _t(
                        context,
                        ar: 'ابحث باسم الصيدلية',
                        en: 'Search by pharmacy name',
                      ),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  onPressed: _loadAll,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
              onSubmitted: (_) => _loadAll(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, textDirection: _dir(context)))
                    : TabBarView(
                        controller: _tabController,
                        children: tabs.map((item) {
                          final list =
                              _items[item.$1] ?? const <PharmacyConversationModel>[];
                          if (list.isEmpty) {
                            return Center(
                              child: Text(
                                context.l10n.pharmacyConversationsEmpty,
                                textDirection: _dir(context),
                              ),
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final itemData = list[index];
                              final title = widget.ownerMode
                                  ? (itemData.customer?.fullName ??
                                      itemData.customer?.phone ??
                                      _t(context, ar: 'زبون', en: 'Customer'))
                                  : (itemData.merchantName ??
                                      context.l10n.pharmacyConversationTitle);
                              final subtitleParts = <String>[
                                _conversationStatusLabel(context, itemData.status),
                                if (widget.ownerMode &&
                                    itemData.customer?.phone?.trim().isNotEmpty ==
                                        true)
                                  itemData.customer!.phone!,
                                _t(
                                  context,
                                  ar:
                                      'آخر نشاط ${_formatDateTime(context, itemData.lastMessageAt ?? itemData.updatedAt ?? itemData.createdAt)}',
                                  en:
                                      'Last activity ${_formatDateTime(context, itemData.lastMessageAt ?? itemData.updatedAt ?? itemData.createdAt)}',
                                ),
                              ];
                              return Card(
                                child: ListTile(
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => PharmacyConversationScreen(
                                          conversationId: itemData.id,
                                          ownerMode: widget.ownerMode,
                                          titleOverride: widget.ownerMode
                                              ? title
                                              : itemData.merchantName,
                                        ),
                                      ),
                                    );
                                    if (!mounted) return;
                                    await _loadAll();
                                  },
                                  title: Text(
                                    title,
                                    textDirection: _dir(context),
                                  ),
                                  subtitle: Text(
                                    subtitleParts.join(' • '),
                                    textDirection: _dir(context),
                                  ),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                ),
                              );
                            },
                          );
                        }).toList(),
                      ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        textDirection: _dir(context),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(value, style: style),
          const Spacer(),
          Text(label, style: style),
        ],
      ),
    );
  }
}

class _CartComposerResult {
  final List<Map<String, dynamic>> items;
  final double deliveryFee;
  final String? notes;
  final DateTime? expiresAt;

  const _CartComposerResult({
    required this.items,
    required this.deliveryFee,
    required this.notes,
    required this.expiresAt,
  });
}

class _CartDraftItem {
  int? productId;
  String? productName;
  bool manual;
  int quantity;
  double unitPrice;
  bool requiresPrescription;
  bool requiresReview;
  String? note;
  String? alternativeGroupId;

  _CartDraftItem({
    required this.productId,
    required this.productName,
    required this.manual,
    required this.quantity,
    required this.unitPrice,
    required this.requiresPrescription,
    required this.requiresReview,
  });

  factory _CartDraftItem.fromProduct(ProductModel product) {
    return _CartDraftItem(
      productId: product.id,
      productName: product.name,
      manual: false,
      quantity: 1,
      unitPrice: product.discountedPrice ?? product.price,
      requiresPrescription: product.requiresPrescription,
      requiresReview: product.requiresReview,
    );
  }

  factory _CartDraftItem.manual() {
    return _CartDraftItem(
      productId: null,
      productName: '',
      manual: true,
      quantity: 1,
      unitPrice: 0,
      requiresPrescription: false,
      requiresReview: false,
    );
  }
}

class _PharmacyCartComposerSheet extends ConsumerStatefulWidget {
  final List<ProductModel> products;

  const _PharmacyCartComposerSheet({required this.products});

  @override
  ConsumerState<_PharmacyCartComposerSheet> createState() =>
      _PharmacyCartComposerSheetState();
}

class _PharmacyCartComposerSheetState
    extends ConsumerState<_PharmacyCartComposerSheet> {
  final TextEditingController _deliveryCtrl = TextEditingController(text: '0');
  final TextEditingController _notesCtrl = TextEditingController();
  final List<_CartDraftItem> _items = <_CartDraftItem>[];
  DateTime? _expiresAt;

  @override
  void dispose() {
    _deliveryCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      initialDate: _expiresAt ?? now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expiresAt ?? now),
    );
    if (time == null || !mounted) return;
    setState(() {
      _expiresAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _addCatalogItem(ProductModel product) {
    setState(() {
      _items.add(_CartDraftItem.fromProduct(product));
    });
  }

  void _addManualItem() {
    setState(() {
      _items.add(_CartDraftItem.manual());
    });
  }

  void _submit() {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              context,
              ar: 'أضف عنصرًا واحدًا على الأقل.',
              en: 'Add at least one item.',
            ),
          ),
        ),
      );
      return;
    }

    final payload = <Map<String, dynamic>>[];
    for (final item in _items) {
      final name = (item.productName ?? '').trim();
      if (name.isEmpty || item.quantity <= 0 || item.unitPrice < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                context,
                ar: 'تحقق من اسم العنصر والكمية والسعر.',
                en: 'Check the item name, quantity, and price.',
              ),
            ),
          ),
        );
        return;
      }
      payload.add({
        if (item.productId != null) 'productId': item.productId,
        'productName': name,
        'quantity': item.quantity,
        'unitPrice': item.unitPrice,
        'requiresPrescription': item.requiresPrescription,
        'requiresReview': item.requiresReview,
        if ((item.note ?? '').trim().isNotEmpty) 'note': item.note!.trim(),
        if ((item.alternativeGroupId ?? '').trim().isNotEmpty)
          'alternativeGroupId': item.alternativeGroupId!.trim(),
      });
    }

    final deliveryFee = double.tryParse(_deliveryCtrl.text.trim()) ?? 0;
    Navigator.of(context).pop(
      _CartComposerResult(
        items: payload,
        deliveryFee: deliveryFee,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        expiresAt: _expiresAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Directionality(
          textDirection: _dir(context),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.pharmacyCreateCartTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _addManualItem,
                      icon: const Icon(Icons.add_circle_outline),
                      label: Text(
                        _t(context, ar: 'عنصر يدوي', en: 'Manual item'),
                      ),
                    ),
                    PopupMenuButton<ProductModel>(
                      onSelected: _addCatalogItem,
                      itemBuilder: (_) => widget.products
                          .map(
                            (product) => PopupMenuItem<ProductModel>(
                              value: product,
                              child: Text(product.name),
                            ),
                          )
                          .toList(),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined),
                            SizedBox(width: 8),
                            Text(
                              _t(
                                context,
                                ar: 'اختيار من منتجات الصيدلية',
                                en: 'Select from pharmacy products',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_items.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    child: Text(
                      _t(context, ar: 'لا توجد عناصر بعد.', en: 'No items yet.'),
                    ),
                  )
                else
                  ...List.generate(_items.length, (index) {
                    final item = _items[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CartDraftItemCard(
                        item: item,
                        onChanged: () => setState(() {}),
                        onDelete: () => setState(() => _items.removeAt(index)),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                TextField(
                  controller: _deliveryCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: context.l10n.pharmacyCartDeliveryFeeLabel,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notesCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: _t(
                      context,
                      ar: 'ملاحظات السلة',
                      en: 'Cart notes',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickExpiry,
                      icon: const Icon(Icons.schedule_outlined),
                      label: Text(
                        _expiresAt == null
                            ? _t(
                                context,
                                ar: 'تحديد صلاحية العرض',
                                en: 'Set offer expiry',
                              )
                            : _formatDateTime(context, _expiresAt),
                      ),
                    ),
                    if (_expiresAt != null)
                      TextButton(
                        onPressed: () => setState(() => _expiresAt = null),
                        child: Text(context.l10n.commonClear),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _submit,
                  child: Text(context.l10n.commonCreate),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CartDraftItemCard extends StatelessWidget {
  final _CartDraftItem item;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  const _CartDraftItemCard({
    required this.item,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final nameCtrl = TextEditingController(text: item.productName ?? '');
    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    final priceCtrl = TextEditingController(text: item.unitPrice.toString());
    final noteCtrl = TextEditingController(text: item.note ?? '');
    final altCtrl = TextEditingController(text: item.alternativeGroupId ?? '');
    return StatefulBuilder(
      builder: (context, setLocalState) {
        void sync() {
          item.productName = nameCtrl.text;
          item.quantity = int.tryParse(qtyCtrl.text.trim()) ?? 1;
          item.unitPrice = double.tryParse(priceCtrl.text.trim()) ?? 0;
          item.note = noteCtrl.text;
          item.alternativeGroupId = altCtrl.text;
          onChanged();
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  textDirection: _dir(context),
                  children: [
                    Expanded(
                      child: Text(
                        item.manual
                            ? _t(context, ar: 'عنصر يدوي', en: 'Manual item')
                            : (item.productName ??
                                _t(context, ar: 'منتج', en: 'Product')),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: _t(context, ar: 'اسم العنصر', en: 'Item name'),
                  ),
                  onChanged: (_) => sync(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _t(
                            context,
                            ar: 'الكمية',
                            en: 'Quantity',
                          ),
                        ),
                        onChanged: (_) => sync(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: priceCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: _t(
                            context,
                            ar: 'سعر الوحدة',
                            en: 'Unit price',
                          ),
                        ),
                        onChanged: (_) => sync(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: _t(
                      context,
                      ar: 'ملاحظة على العنصر',
                      en: 'Item note',
                    ),
                  ),
                  onChanged: (_) => sync(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: altCtrl,
                  decoration: InputDecoration(
                    labelText: _t(
                      context,
                      ar: 'معرّف البدائل (اختياري)',
                      en: 'Alternative group ID (optional)',
                    ),
                  ),
                  onChanged: (_) => sync(),
                ),
                CheckboxListTile(
                  value: item.requiresPrescription,
                  onChanged: (value) {
                    item.requiresPrescription = value == true;
                    setLocalState(() {});
                    onChanged();
                  },
                  title: Text(
                    _t(
                      context,
                      ar: 'يتطلب وصفة',
                      en: 'Requires prescription',
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: item.requiresReview,
                  onChanged: (value) {
                    item.requiresReview = value == true;
                    setLocalState(() {});
                    onChanged();
                  },
                  title: Text(
                    _t(
                      context,
                      ar: 'يتطلب مراجعة',
                      en: 'Requires review',
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
