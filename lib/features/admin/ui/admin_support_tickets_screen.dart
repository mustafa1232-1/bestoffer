import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/parsers.dart';
import '../../orders/models/order_revision_model.dart';
import '../../orders/ui/widgets/order_revision_widgets.dart';
import '../state/admin_controller.dart';

class AdminSupportTicketsScreen extends ConsumerStatefulWidget {
  const AdminSupportTicketsScreen({super.key});

  @override
  ConsumerState<AdminSupportTicketsScreen> createState() =>
      _AdminSupportTicketsScreenState();
}

class _AdminSupportTicketsScreenState
    extends ConsumerState<AdminSupportTicketsScreen> {
  late Future<Map<String, dynamic>> _future;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() {
    return ref.read(adminApiProvider).supportTickets(search: _search.text);
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تذاكر الدعم')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(error: snapshot.error, onRetry: _refresh);
            }
            final data = snapshot.data ?? const {};
            final items = List<dynamic>.from(
              data['items'] as List? ?? const [],
            );
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _refresh(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    labelText: 'بحث في التذاكر',
                  ),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Center(child: Text('لا توجد تذاكر دعم مطابقة.'))
                else
                  for (final raw in items)
                    _TicketTile(
                      ticket: _map(raw),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AdminSupportTicketDetailsScreen(
                            ticketId: parseInt(_map(raw)['id']),
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AdminSupportTicketDetailsScreen extends ConsumerStatefulWidget {
  final int ticketId;

  const AdminSupportTicketDetailsScreen({super.key, required this.ticketId});

  @override
  ConsumerState<AdminSupportTicketDetailsScreen> createState() =>
      _AdminSupportTicketDetailsScreenState();
}

class _AdminSupportTicketDetailsScreenState
    extends ConsumerState<AdminSupportTicketDetailsScreen> {
  late Future<_TicketDetailsData> _future;
  Set<String> _permissions = const {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_TicketDetailsData> _load() async {
    final api = ref.read(adminApiProvider);
    final results = await Future.wait<Map<String, dynamic>>([
      api.supportTicketDetails(widget.ticketId),
      api.supportTicketOrderContext(widget.ticketId),
      api.myPermissions(),
    ]);
    _permissions = _extractPermissions(results[2]);
    return _TicketDetailsData(ticket: results[0], orderContext: results[1]);
  }

  void _refresh() => setState(() => _future = _load());

  bool _can(String key) =>
      _permissions.contains('*') || _permissions.contains(key);

  Future<void> _createDraft(_TicketDetailsData data) async {
    final order = _map(data.orderContext['order']);
    final items = _list(data.orderContext['items']);
    final orderId = parseInt(order['id']);
    if (orderId <= 0 || items.isEmpty) return;
    final draftItems = items
        .map(
          (item) => _DraftRevisionItem(
            orderItemId: parseNullableInt(item['id']),
            productId: parseInt(item['product_id'] ?? item['productId']),
            productName: parseString(
              item['product_name'] ?? item['productName'],
            ),
            quantity: parseInt(item['quantity'], fallback: 1),
          ),
        )
        .toList();
    final products = await _loadMerchantProducts(
      parseInt(order['merchant_id']),
    );
    if (!mounted) return;
    final result = await showModalBottomSheet<_RevisionDraftResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RevisionDraftSheet(
        initialItems: draftItems,
        merchantProducts: products,
      ),
    );
    if (result == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(adminApiProvider)
          .createOrderRevisionFromTicket(
            ticketId: widget.ticketId,
            orderId: orderId,
            reason: result.reason,
            items: result.items.map((item) => item.toPayload()).toList(),
          );
      if (!mounted) return;
      _refresh();
    } on DioException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapDioError(error, fallback: 'تعذر إنشاء تعديل الطلب.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<List<_MerchantProductOption>> _loadMerchantProducts(
    int merchantId,
  ) async {
    if (merchantId <= 0) return const [];
    final raw = await ref
        .read(adminApiProvider)
        .adBoardMerchantProducts(merchantId);
    return raw
        .whereType<Map>()
        .map((entry) => _MerchantProductOption.fromJson(_map(entry)))
        .where((entry) => entry.productId > 0)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('تذكرة #${widget.ticketId}')),
      body: FutureBuilder<_TicketDetailsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error, onRetry: _refresh);
          }
          final data = snapshot.data!;
          final order = _map(data.orderContext['order']);
          final revisions = _list(
            data.orderContext['revisions'],
          ).map(OrderRevisionModel.fromJson).toList(growable: false);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _TicketSummary(ticket: _map(data.ticket['ticket'])),
              const SizedBox(height: 12),
              _ConversationSection(detail: data.ticket),
              if (_can('support.tickets.reply')) ...[
                const SizedBox(height: 8),
                _SupportComposer(
                  ticketId: widget.ticketId,
                  onSent: () async => _refresh(),
                ),
              ],
              const SizedBox(height: 12),
              if (_can('support.tickets.assign'))
                _LinkSuggestionsSection(
                  ticketId: widget.ticketId,
                  onLinked: () async => _refresh(),
                ),
              const SizedBox(height: 12),
              _LinkedOrderSection(contextData: data.orderContext),
              const SizedBox(height: 12),
              OrderRevisionPanel(
                title: 'مراجعات الطلب',
                emptyText: 'لا توجد مراجعات على الطلب المرتبط.',
                loadRevisions: () async => revisions,
                canSubmit: (revision) =>
                    _can('orders.revisions.submit') &&
                    revision.status == 'DRAFT',
                canApply: (revision) =>
                    _can('orders.revisions.apply') && revision.canApply,
                onSubmit: (revision) async {
                  await ref
                      .read(adminApiProvider)
                      .submitOrderRevision(
                        orderId: parseInt(order['id']),
                        revisionId: revision.id,
                      );
                  _refresh();
                },
                onApply: (revision) async {
                  await ref
                      .read(adminApiProvider)
                      .applyOrderRevision(
                        orderId: parseInt(order['id']),
                        revisionId: revision.id,
                      );
                  _refresh();
                },
              ),
              const SizedBox(height: 12),
              if (_can('orders.revisions.create'))
                FilledButton.icon(
                  onPressed: _saving ? null : () => _createDraft(data),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_note_rounded),
                  label: const Text('اقتراح تعديل على الطلب'),
                ),
              if (!_can('orders.revisions.create'))
                const Text('لا تملك صلاحية اقتراح تعديل على الطلب.'),
            ],
          );
        },
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onTap;

  const _TicketTile({required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.confirmation_number_outlined),
        title: Text(
          parseString(ticket['ticket_number'] ?? ticket['ticketNumber']),
        ),
        subtitle: Text(parseString(ticket['subject'])),
        trailing: Text(parseString(ticket['status'])),
        onTap: onTap,
      ),
    );
  }
}

class _TicketSummary extends StatelessWidget {
  final Map<String, dynamic> ticket;

  const _TicketSummary({required this.ticket});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'ملخص التذكرة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'الرقم: ${parseString(ticket['ticket_number'] ?? ticket['ticketNumber'])}',
          ),
          Text('الحالة: ${parseString(ticket['status'])}'),
          Text('الموضوع: ${parseString(ticket['subject'])}'),
        ],
      ),
    );
  }
}

class _LinkedOrderSection extends StatelessWidget {
  final Map<String, dynamic> contextData;

  const _LinkedOrderSection({required this.contextData});

  @override
  Widget build(BuildContext context) {
    final order = _map(contextData['order']);
    if (order.isEmpty) {
      return const _Panel(
        title: 'الطلب المرتبط',
        child: Text('لا توجد فاتورة/طلب مرتبط بهذه التذكرة.'),
      );
    }
    final items = _list(contextData['items']);
    final invoice = _map(contextData['invoice']);
    return _Panel(
      title: 'الطلب المرتبط',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('رقم الطلب: ${parseInt(order['id'])}'),
          Text(
            'المتجر: ${parseString(order['merchant_name'] ?? order['merchantName'])}',
          ),
          Text(
            'المستخدم: ${parseString(order['customer_name'] ?? order['customer_full_name'])}',
          ),
          Text(
            'الدلفري: ${parseString(order['delivery_name'] ?? order['delivery_full_name'], fallback: 'غير معيّن')}',
          ),
          Text(
            'الحالة: ${parseString(order['status_text'] ?? order['status'])}',
          ),
          Text(
            'الفاتورة: ${formatIqd(parseDouble(invoice['outstanding_amount'] ?? order['total_amount']))}',
          ),
          const Divider(),
          for (final item in items)
            Text(
              '${parseString(item['product_name'] ?? item['productName'])} × ${parseInt(item['quantity'])} - ${formatIqd(parseDouble(item['line_total'] ?? item['lineTotal']))}',
            ),
        ],
      ),
    );
  }
}

class _RevisionDraftSheet extends StatefulWidget {
  final List<_DraftRevisionItem> initialItems;
  final List<_MerchantProductOption> merchantProducts;

  const _RevisionDraftSheet({
    required this.initialItems,
    required this.merchantProducts,
  });

  @override
  State<_RevisionDraftSheet> createState() => _RevisionDraftSheetState();
}

class _RevisionDraftSheetState extends State<_RevisionDraftSheet> {
  late final List<_DraftRevisionItem> _items;
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = widget.initialItems.map((item) => item.copy()).toList();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _addProduct(_MerchantProductOption product) {
    setState(() {
      final existing = _items.indexWhere(
        (item) => item.productId == product.productId,
      );
      if (existing >= 0) {
        _items[existing].quantity += 1;
      } else {
        _items.add(
          _DraftRevisionItem(
            productId: product.productId,
            productName: product.name,
            quantity: 1,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'اقتراح تعديل على الطلب',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'سبب التعديل'),
            ),
            const SizedBox(height: 12),
            for (final item in _items)
              _DraftItemRow(
                item: item,
                onChanged: () => setState(() {}),
                onRemove: () => setState(() => _items.remove(item)),
              ),
            if (widget.merchantProducts.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<_MerchantProductOption>(
                items: widget.merchantProducts
                    .map(
                      (product) => DropdownMenuItem(
                        value: product,
                        child: Text(product.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (product) {
                  if (product != null) _addProduct(product);
                },
                decoration: const InputDecoration(
                  labelText: 'إضافة مادة من نفس المتجر',
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final reason = _reason.text.trim();
                if (reason.isEmpty ||
                    _items.where((i) => i.quantity > 0).isEmpty) {
                  return;
                }
                Navigator.of(context).pop(
                  _RevisionDraftResult(
                    reason: reason,
                    items: _items.where((i) => i.quantity > 0).toList(),
                  ),
                );
              },
              child: const Text('حفظ Draft'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftItemRow extends StatelessWidget {
  final _DraftRevisionItem item;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _DraftItemRow({
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(item.productName)),
        IconButton(
          onPressed: item.quantity <= 0
              ? null
              : () {
                  item.quantity -= 1;
                  onChanged();
                },
          icon: const Icon(Icons.remove_rounded),
        ),
        Text('${item.quantity}'),
        IconButton(
          onPressed: () {
            item.quantity += 1;
            onChanged();
          },
          icon: const Icon(Icons.add_rounded),
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final message = error is DioException
        ? mapDioError(error as DioException, fallback: 'تعذر تحميل البيانات.')
        : 'تعذر تحميل البيانات.';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('إعادة المحاولة'),
        ),
      ],
    );
  }
}

/// عرض محادثة التذكرة: الرسائل الظاهرة + الملاحظات الداخلية + المرفقات (صور).
class _ConversationSection extends StatelessWidget {
  final Map<String, dynamic> detail;
  const _ConversationSection({required this.detail});

  List<Map<String, dynamic>> _rows(String key) {
    final raw = detail[key];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    }
    return const [];
  }

  List<Map<String, dynamic>> _attachmentsFor(int? id, bool internal) {
    return _rows('attachments').where((a) {
      final key = internal ? 'internal_note_id' : 'message_id';
      final ref = int.tryParse('${a[key] ?? ''}');
      return id != null && ref != null && ref == id;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final messages = _rows('messages');
    final internalNotes = _rows('internalNotes');
    if (messages.isEmpty && internalNotes.isEmpty) {
      return const _Panel(title: 'المحادثة', child: Text('لا توجد رسائل بعد.'));
    }
    return _Panel(
      title: 'المحادثة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in messages)
            _MessageBubble(
              body: '${m['body'] ?? ''}',
              author: '${m['author_role'] ?? ''}',
              internal: false,
              attachments: _attachmentsFor(int.tryParse('${m['id']}'), false),
            ),
          for (final n in internalNotes)
            _MessageBubble(
              body: '${n['body'] ?? ''}',
              author: '${n['author_role'] ?? ''}',
              internal: true,
              attachments: _attachmentsFor(int.tryParse('${n['id']}'), true),
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String body;
  final String author;
  final bool internal;
  final List<Map<String, dynamic>> attachments;
  const _MessageBubble({
    required this.body,
    required this.author,
    required this.internal,
    required this.attachments,
  });

  bool _isImage(Map<String, dynamic> a) =>
      '${a['mime_type'] ?? ''}'.startsWith('image/');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            internal ? scheme.errorContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(author, style: Theme.of(context).textTheme.labelSmall),
              if (internal) ...[
                const SizedBox(width: 6),
                Text(
                  'ملاحظة داخلية',
                  style: TextStyle(
                    color: scheme.error,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(body),
          ],
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in attachments)
                  _isImage(a)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            '${a['file_url'] ?? ''}',
                            width: 84,
                            height: 84,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image_outlined),
                          ),
                        )
                      : Chip(
                          avatar:
                              const Icon(Icons.attach_file_rounded, size: 16),
                          label: Text('${a['file_name'] ?? 'ملف'}'),
                        ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// مُنشئ الرد: نص + إرفاق صورة + خيار ملاحظة داخلية + إرسال. يحفظ في الخادم.
class _SupportComposer extends ConsumerStatefulWidget {
  final int ticketId;
  final Future<void> Function() onSent;
  const _SupportComposer({required this.ticketId, required this.onSent});

  @override
  ConsumerState<_SupportComposer> createState() => _SupportComposerState();
}

class _SupportComposerState extends ConsumerState<_SupportComposer> {
  final _controller = TextEditingController();
  final List<Map<String, dynamic>> _attachments = [];
  bool _internal = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final LocalImageFile? file = await pickImageFromDevice();
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final att = await ref.read(adminApiProvider).uploadSupportAttachment(
            file,
            visibility: _internal ? 'internal' : 'customer',
          );
      setState(() => _attachments.add(att));
    } catch (e) {
      setState(() => _error = e is DioException
          ? mapDioError(e, fallback: 'تعذّر رفع الصورة.')
          : 'تعذّر رفع الصورة.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty && _attachments.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminApiProvider).replySupportTicket(
            widget.ticketId,
            body: body,
            isInternal: _internal,
            attachments: List<Map<String, dynamic>>.from(_attachments),
          );
      _controller.clear();
      _attachments.clear();
      await widget.onSent();
    } catch (e) {
      setState(() => _error = e is DioException
          ? mapDioError(e, fallback: 'تعذّر إرسال الرسالة.')
          : 'تعذّر إرسال الرسالة.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'الرد على التذكرة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'اكتب ردك للمستخدم…',
            ),
          ),
          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < _attachments.length; i++)
                    Chip(
                      label: Text('${_attachments[i]['fileName'] ?? 'صورة'}'),
                      onDeleted: () => setState(() => _attachments.removeAt(i)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: _busy ? null : _attach,
                icon: const Icon(Icons.image_outlined),
                tooltip: 'إرفاق صورة',
              ),
              Switch(
                value: _internal,
                onChanged: _busy ? null : (v) => setState(() => _internal = v),
              ),
              const Text('داخلية'),
              const Spacer(),
              FilledButton.icon(
                onPressed: _busy ? null : _send,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('إرسال'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// اقتراح ربط: أحدث طلبات/رحلات صاحب التذكرة، مع زر ربط بعد التأكد.
class _LinkSuggestionsSection extends ConsumerStatefulWidget {
  final int ticketId;
  final Future<void> Function() onLinked;
  const _LinkSuggestionsSection({required this.ticketId, required this.onLinked});

  @override
  ConsumerState<_LinkSuggestionsSection> createState() =>
      _LinkSuggestionsSectionState();
}

class _LinkSuggestionsSectionState
    extends ConsumerState<_LinkSuggestionsSection> {
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data =
          await ref.read(adminApiProvider).supportTicketLinkSuggestions(widget.ticketId);
      final orders = ((data['orders'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map));
      final rides = ((data['rides'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map));
      setState(() {
        _items = [...orders, ...rides];
        _loaded = true;
      });
    } catch (e) {
      setState(() => _error = e is DioException
          ? mapDioError(e, fallback: 'تعذّر تحميل الاقتراحات.')
          : 'تعذّر تحميل الاقتراحات.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _link(Map<String, dynamic> item) async {
    setState(() => _loading = true);
    try {
      await ref.read(adminApiProvider).linkSupportTicketEntity(
            widget.ticketId,
            entityType: '${item['entityType']}',
            entityId: parseInt(item['entityId']),
            label: '${item['label'] ?? ''}',
            reason: 'linked from suggestions',
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الربط بنجاح.')),
        );
      }
      await widget.onLinked();
    } catch (e) {
      setState(() => _error = e is DioException
          ? mapDioError(e, fallback: 'تعذّر الربط.')
          : 'تعذّر الربط.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'ربط بطلب/رحلة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!_loaded)
            OutlinedButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.link_rounded),
              label: const Text('اقترح طلبات/رحلات صاحب التذكرة'),
            )
          else if (_items.isEmpty)
            const Text('لا توجد طلبات أو رحلات حديثة لصاحب التذكرة.')
          else
            ..._items.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  item['entityType'] == 'ride'
                      ? Icons.local_taxi_rounded
                      : Icons.receipt_long_rounded,
                ),
                title: Text('${item['label'] ?? ''}'),
                subtitle: Text(
                  '${item['status'] ?? ''} ${item['route'] ?? ''}'.trim(),
                ),
                trailing: TextButton(
                  onPressed: _loading ? null : () => _link(item),
                  child: const Text('ربط'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TicketDetailsData {
  final Map<String, dynamic> ticket;
  final Map<String, dynamic> orderContext;

  const _TicketDetailsData({required this.ticket, required this.orderContext});
}

class _RevisionDraftResult {
  final String reason;
  final List<_DraftRevisionItem> items;

  const _RevisionDraftResult({required this.reason, required this.items});
}

class _DraftRevisionItem {
  final int? orderItemId;
  final int productId;
  final String productName;
  int quantity;

  _DraftRevisionItem({
    this.orderItemId,
    required this.productId,
    required this.productName,
    required this.quantity,
  });

  _DraftRevisionItem copy() => _DraftRevisionItem(
    orderItemId: orderItemId,
    productId: productId,
    productName: productName,
    quantity: quantity,
  );

  Map<String, dynamic> toPayload() => {
    if (orderItemId != null) 'orderItemId': orderItemId,
    'productId': productId,
    'quantity': quantity,
  };
}

class _MerchantProductOption {
  final int productId;
  final String name;

  const _MerchantProductOption({required this.productId, required this.name});

  factory _MerchantProductOption.fromJson(Map<String, dynamic> json) {
    return _MerchantProductOption(
      productId: parseInt(json['id'] ?? json['productId']),
      name: parseString(json['name'] ?? json['productName']),
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _list(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) => entry.map((key, value) => MapEntry('$key', value)))
      .toList(growable: false);
}

Set<String> _extractPermissions(Map<String, dynamic> payload) {
  final raw =
      payload['permissions'] ?? payload['items'] ?? payload['effective'];
  if (raw is List) {
    return raw
        .map((entry) {
          final mapped = _map(entry);
          return parseString(mapped['key'] ?? mapped['permissionKey'] ?? entry);
        })
        .where((entry) => entry.isNotEmpty)
        .toSet();
  }
  if (raw is Map) {
    return raw.entries
        .where((entry) => entry.value == true)
        .map((entry) => '${entry.key}')
        .toSet();
  }
  return const {};
}
