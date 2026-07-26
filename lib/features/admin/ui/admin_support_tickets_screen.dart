import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
