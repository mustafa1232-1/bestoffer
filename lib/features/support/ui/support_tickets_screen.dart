import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/parsers.dart';
import '../data/customer_support_api.dart';
import '../models/support_context.dart';
import 'support_request_sheet.dart';

class SupportTicketsScreen extends ConsumerStatefulWidget {
  const SupportTicketsScreen({
    super.key,
    this.supportContext = const SupportContext.general(),
  });

  final SupportContext supportContext;

  @override
  ConsumerState<SupportTicketsScreen> createState() =>
      _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends ConsumerState<SupportTicketsScreen> {
  late Future<List<SupportTicketSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SupportTicketSummary>> _load() async {
    final rows = await ref
        .read(customerSupportApiProvider)
        .myTickets(limit: 75);
    return rows.map(SupportTicketSummary.fromJson).toList(growable: false);
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _openCreateTicket() async {
    final created = await showSupportRequestSheet(
      context,
      supportContext: widget.supportContext,
    );
    if (created && mounted) _refresh();
  }

  Future<void> _openTicket(SupportTicketSummary ticket) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportTicketDetailsScreen(ticketId: ticket.id),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'طلبات الدعم', en: 'Support requests')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateTicket,
        icon: const Icon(Icons.add_rounded),
        label: Text(context.lt(ar: 'طلب جديد', en: 'New request')),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<SupportTicketSummary>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _SupportErrorState(
                error: snapshot.error,
                onRetry: _refresh,
              );
            }
            final tickets = snapshot.data ?? const <SupportTicketSummary>[];
            if (tickets.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 96),
                  Icon(
                    Icons.support_agent_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    context.lt(
                      ar: 'لا توجد طلبات دعم.',
                      en: 'No support requests yet.',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _openCreateTicket,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(
                        context.lt(ar: 'فتح طلب دعم', en: 'Open request'),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: tickets.length,
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final ticket = tickets[index];
                return _SupportTicketTile(
                  ticket: ticket,
                  onTap: () => _openTicket(ticket),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class SupportTicketDetailsScreen extends ConsumerStatefulWidget {
  const SupportTicketDetailsScreen({super.key, required this.ticketId});

  final int ticketId;

  @override
  ConsumerState<SupportTicketDetailsScreen> createState() =>
      _SupportTicketDetailsScreenState();
}

class _SupportTicketDetailsScreenState
    extends ConsumerState<SupportTicketDetailsScreen> {
  final _replyController = TextEditingController();
  late Future<SupportTicketDetails> _future;
  bool _sending = false;
  bool _reopening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<SupportTicketDetails> _load() async {
    final data = await ref
        .read(customerSupportApiProvider)
        .ticketDetails(widget.ticketId);
    return SupportTicketDetails.fromJson(data);
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _sendReply() async {
    final body = _replyController.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(customerSupportApiProvider)
          .addMessage(widget.ticketId, body: body);
      _replyController.clear();
      if (!mounted) return;
      _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorText(context, error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reopenTicket() async {
    if (_reopening) return;
    setState(() {
      _reopening = true;
      _error = null;
    });
    try {
      await ref
          .read(customerSupportApiProvider)
          .reopenTicket(
            widget.ticketId,
            reason: context.lt(ar: 'متابعة من التطبيق', en: 'App follow-up'),
          );
      if (!mounted) return;
      _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorText(context, error));
    } finally {
      if (mounted) setState(() => _reopening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SupportTicketDetails>(
      future: _future,
      builder: (context, snapshot) {
        final details = snapshot.data;
        final ticket = details?.ticket;
        final closed = ticket?.isClosed ?? false;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              ticket?.ticketNumber.isNotEmpty == true
                  ? ticket!.ticketNumber
                  : context.lt(ar: 'طلب الدعم', en: 'Support request'),
            ),
          ),
          body: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: Builder(
              builder: (context) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    details == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError && details == null) {
                  return _SupportErrorState(
                    error: snapshot.error,
                    onRetry: _refresh,
                  );
                }
                if (details == null) {
                  return const SizedBox.shrink();
                }
                return ListView(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, closed ? 96 : 132),
                  children: [
                    _SupportTicketHeader(ticket: details.ticket),
                    if (details.links.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _TicketLinksCard(links: details.links),
                    ],
                    const SizedBox(height: 12),
                    if (details.messages.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          context.lt(
                            ar: 'لا توجد رسائل بعد.',
                            en: 'No messages yet.',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      for (final message in details.messages) ...[
                        _SupportMessageBubble(message: message),
                        const SizedBox(height: 8),
                      ],
                  ],
                );
              },
            ),
          ),
          bottomNavigationBar: ticket == null
              ? null
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: closed
                        ? FilledButton.icon(
                            onPressed: _reopening ? null : _reopenTicket,
                            icon: _reopening
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.lock_open_rounded),
                            label: Text(
                              context.lt(
                                ar: 'إعادة فتح الطلب',
                                en: 'Reopen request',
                              ),
                            ),
                          )
                        : _ReplyComposer(
                            controller: _replyController,
                            sending: _sending,
                            error: _error,
                            onSend: _sendReply,
                          ),
                  ),
                ),
        );
      },
    );
  }
}

class SupportTicketSummary {
  const SupportTicketSummary({
    required this.id,
    required this.ticketNumber,
    required this.subject,
    required this.description,
    required this.domain,
    required this.type,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String ticketNumber;
  final String subject;
  final String description;
  final String domain;
  final String type;
  final String priority;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isClosed {
    final value = status.toUpperCase();
    return value == 'RESOLVED' || value == 'CLOSED';
  }

  factory SupportTicketSummary.fromJson(Map<String, dynamic> json) {
    return SupportTicketSummary(
      id: parseInt(json['id']),
      ticketNumber: parseString(json['ticket_number'] ?? json['ticketNumber']),
      subject: parseString(json['subject'], fallback: '-'),
      description: parseString(json['description']),
      domain: parseString(json['domain']),
      type: parseString(json['type']),
      priority: parseString(json['priority']),
      status: parseString(json['status']),
      createdAt: parseNullableDateTime(json['created_at'] ?? json['createdAt']),
      updatedAt: parseNullableDateTime(json['updated_at'] ?? json['updatedAt']),
    );
  }
}

class SupportTicketDetails {
  const SupportTicketDetails({
    required this.ticket,
    required this.messages,
    required this.links,
  });

  final SupportTicketSummary ticket;
  final List<SupportTicketMessage> messages;
  final List<Map<String, dynamic>> links;

  factory SupportTicketDetails.fromJson(Map<String, dynamic> json) {
    final ticketMap = _map(json['ticket']);
    return SupportTicketDetails(
      ticket: SupportTicketSummary.fromJson(ticketMap),
      messages: _list(
        json['messages'],
      ).map(SupportTicketMessage.fromJson).toList(growable: false),
      links: _list(json['links']),
    );
  }
}

class SupportTicketMessage {
  const SupportTicketMessage({
    required this.id,
    required this.authorRole,
    required this.body,
    required this.createdAt,
    required this.attachments,
  });

  final int id;
  final String authorRole;
  final String body;
  final DateTime? createdAt;
  final List<Map<String, dynamic>> attachments;

  bool get isMine {
    final role = authorRole.trim().toLowerCase();
    return role == 'customer' || role == 'user';
  }

  factory SupportTicketMessage.fromJson(Map<String, dynamic> json) {
    return SupportTicketMessage(
      id: parseInt(json['id']),
      authorRole: parseString(json['author_role'] ?? json['authorRole']),
      body: parseString(json['body']),
      createdAt: parseNullableDateTime(json['created_at'] ?? json['createdAt']),
      attachments: _list(json['attachments_json'] ?? json['attachmentsJson']),
    );
  }
}

class _SupportTicketTile extends StatelessWidget {
  const _SupportTicketTile({required this.ticket, required this.onTap});

  final SupportTicketSummary ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: _statusColor(
            context,
            ticket.status,
          ).withValues(alpha: 0.14),
          child: Icon(
            ticket.isClosed
                ? Icons.check_circle_outline_rounded
                : Icons.support_agent_rounded,
            color: _statusColor(context, ticket.status),
          ),
        ),
        title: Text(
          ticket.subject,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _TinyChip(label: _statusLabel(context, ticket.status)),
                  if (ticket.domain.isNotEmpty)
                    _TinyChip(label: _domainLabel(context, ticket.domain)),
                  if (ticket.priority.toLowerCase() == 'urgent')
                    _TinyChip(
                      label: context.lt(ar: 'عاجل', en: 'Urgent'),
                      color: scheme.error,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _formatDate(context, ticket.updatedAt ?? ticket.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _SupportTicketHeader extends StatelessWidget {
  const _SupportTicketHeader({required this.ticket});

  final SupportTicketSummary ticket;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ticket.subject,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _TinyChip(
                  label: _statusLabel(context, ticket.status),
                  color: _statusColor(context, ticket.status),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (ticket.ticketNumber.isNotEmpty)
                  _TinyChip(label: ticket.ticketNumber),
                if (ticket.domain.isNotEmpty)
                  _TinyChip(label: _domainLabel(context, ticket.domain)),
                if (ticket.type.isNotEmpty)
                  _TinyChip(label: _typeLabel(context, ticket.type)),
              ],
            ),
            if (ticket.description.isNotEmpty) ...[
              const Divider(height: 18),
              Text(ticket.description),
            ],
          ],
        ),
      ),
    );
  }
}

class _TicketLinksCard extends StatelessWidget {
  const _TicketLinksCard({required this.links});

  final List<Map<String, dynamic>> links;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.lt(ar: 'الربط', en: 'Linked items'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            for (final link in links)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_rounded),
                title: Text(parseString(link['label'], fallback: '-')),
                subtitle: Text(
                  '${parseString(link['entity_type'] ?? link['entityType'])} #${parseInt(link['entity_id'] ?? link['entityId'])}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SupportMessageBubble extends StatelessWidget {
  const _SupportMessageBubble({required this.message});

  final SupportTicketMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final scheme = Theme.of(context).colorScheme;
    final bg = mine ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = mine ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      mine
                          ? Icons.person_outline_rounded
                          : Icons.support_agent_rounded,
                      size: 16,
                      color: fg,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      mine
                          ? context.lt(ar: 'أنت', en: 'You')
                          : context.lt(ar: 'الدعم', en: 'Support'),
                      style: TextStyle(color: fg, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(context, message.createdAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(message.body, style: TextStyle(color: fg)),
                if (message.attachments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.lt(
                      ar: 'مرفقات: ${message.attachments.length}',
                      en: 'Attachments: ${message.attachments.length}',
                    ),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: fg.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.controller,
    required this.sending,
    required this.error,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final String? error;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          Text(error!, style: TextStyle(color: scheme.error)),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: context.lt(
                    ar: 'اكتب ردك...',
                    en: 'Write a reply...',
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              tooltip: context.lt(ar: 'إرسال', en: 'Send'),
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _TinyChip extends StatelessWidget {
  const _TinyChip({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = color ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: base,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SupportErrorState extends StatelessWidget {
  const _SupportErrorState({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 96),
        Icon(
          Icons.wifi_off_rounded,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 12),
        Text(
          _errorText(context, error),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.lt(ar: 'إعادة المحاولة', en: 'Retry')),
          ),
        ),
      ],
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  return value is Map ? Map<String, dynamic>.from(value) : const {};
}

List<Map<String, dynamic>> _list(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

String _formatDate(BuildContext context, DateTime? value) {
  if (value == null) return '-';
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat('yyyy/MM/dd HH:mm', locale).format(value.toLocal());
}

String _errorText(BuildContext context, Object? error) {
  final fallback = context.lt(
    ar: 'تعذر تحميل طلبات الدعم. حاول مرة أخرى.',
    en: 'Could not load support requests. Try again.',
  );
  if (error is DioException) {
    return mapDioError(error, fallback: fallback);
  }
  return fallback;
}

String _statusLabel(BuildContext context, String status) {
  switch (status.trim().toUpperCase()) {
    case 'NEW':
      return context.lt(ar: 'جديد', en: 'New');
    case 'ASSIGNED':
      return context.lt(ar: 'مُسند', en: 'Assigned');
    case 'IN_PROGRESS':
      return context.lt(ar: 'قيد المتابعة', en: 'In progress');
    case 'WAITING_FOR_CUSTOMER':
      return context.lt(ar: 'بانتظار ردك', en: 'Waiting for you');
    case 'WAITING_FOR_MERCHANT':
      return context.lt(ar: 'بانتظار المتجر', en: 'Waiting for merchant');
    case 'WAITING_FOR_CAPTAIN':
      return context.lt(ar: 'بانتظار الكابتن', en: 'Waiting for captain');
    case 'WAITING_FOR_DELIVERY':
      return context.lt(ar: 'بانتظار الدلفري', en: 'Waiting for delivery');
    case 'RESOLVED':
      return context.lt(ar: 'محلول', en: 'Resolved');
    case 'CLOSED':
      return context.lt(ar: 'مغلق', en: 'Closed');
    default:
      return status.isEmpty ? '-' : status;
  }
}

Color _statusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status.trim().toUpperCase()) {
    case 'RESOLVED':
    case 'CLOSED':
      return Colors.green.shade700;
    case 'WAITING_FOR_CUSTOMER':
      return Colors.orange.shade800;
    case 'NEW':
    case 'ASSIGNED':
    case 'IN_PROGRESS':
      return scheme.primary;
    default:
      return scheme.outline;
  }
}

String _domainLabel(BuildContext context, String domain) {
  switch (domain.trim().toUpperCase()) {
    case 'SHOPPING':
      return context.lt(ar: 'التسوق', en: 'Shopping');
    case 'DELIVERY':
      return context.lt(ar: 'التوصيل', en: 'Delivery');
    case 'TAXI':
      return context.lt(ar: 'التكسي', en: 'Taxi');
    case 'SERVICES':
      return context.lt(ar: 'الخدمات', en: 'Services');
    case 'REAL_ESTATE':
      return context.lt(ar: 'العقارات', en: 'Real estate');
    case 'CARS':
      return context.lt(ar: 'السيارات', en: 'Cars');
    case 'JOBS':
      return context.lt(ar: 'الوظائف', en: 'Jobs');
    case 'COMMUNITY':
      return context.lt(ar: 'المجتمع', en: 'Community');
    case 'ACCOUNT':
      return context.lt(ar: 'الحساب', en: 'Account');
    case 'PAYMENTS':
      return context.lt(ar: 'المدفوعات', en: 'Payments');
    default:
      return domain.isEmpty ? '-' : domain;
  }
}

String _typeLabel(BuildContext context, String type) {
  switch (type.trim().toUpperCase()) {
    case 'PROBLEM':
      return context.lt(ar: 'مشكلة', en: 'Problem');
    case 'COMPLAINT':
      return context.lt(ar: 'شكوى', en: 'Complaint');
    case 'QUESTION':
      return context.lt(ar: 'استفسار', en: 'Question');
    case 'SUGGESTION':
      return context.lt(ar: 'اقتراح', en: 'Suggestion');
    case 'SAFETY':
      return context.lt(ar: 'سلامة', en: 'Safety');
    case 'REFUND':
      return context.lt(ar: 'استرجاع', en: 'Refund');
    default:
      return type.isEmpty ? '-' : type;
  }
}
