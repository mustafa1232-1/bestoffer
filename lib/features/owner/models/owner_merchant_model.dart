import '../../../core/utils/parsers.dart';

class OwnerMerchantModel {
  final int id;
  final String name;
  final String type;
  final String activityType;
  final String? discoverySubcategory;
  final List<String> discoverySubcategories;
  final bool discoverySelectAll;
  final String? description;
  final String? phone;
  final String? imageUrl;
  final String? tagline;
  final String? workingHours;
  final String? serviceAreaNote;
  final bool isOpen;
  final bool supportsChat;
  final bool supportsAttachments;
  final bool supportsPharmacyWorkflow;
  final Map<String, dynamic> serviceFlags;
  final List<String> badges;
  final bool isApproved;
  final String approvalStatus;
  final DateTime? financialTermsSentAt;
  final DateTime? financialTermsAcceptedAt;
  final DateTime? financialTermsRejectedAt;
  final String? financialTermsRejectionNote;
  final Map<String, dynamic>? financialTermsSnapshot;
  final DateTime? createdAt;

  const OwnerMerchantModel({
    required this.id,
    required this.name,
    required this.type,
    required this.activityType,
    this.discoverySubcategory,
    this.discoverySubcategories = const <String>[],
    this.discoverySelectAll = false,
    this.description,
    this.phone,
    this.imageUrl,
    this.tagline,
    this.workingHours,
    this.serviceAreaNote,
    required this.isOpen,
    required this.supportsChat,
    required this.supportsAttachments,
    required this.supportsPharmacyWorkflow,
    required this.serviceFlags,
    required this.badges,
    required this.isApproved,
    required this.approvalStatus,
    this.financialTermsSentAt,
    this.financialTermsAcceptedAt,
    this.financialTermsRejectedAt,
    this.financialTermsRejectionNote,
    this.financialTermsSnapshot,
    required this.createdAt,
  });

  factory OwnerMerchantModel.fromJson(Map<String, dynamic> j) {
    return OwnerMerchantModel(
      id: parseInt(j['id']),
      name: parseString(j['name']),
      type: parseString(j['type']),
      activityType: parseString(
        j['activity_type'] ?? j['activityType'],
        fallback: parseString(j['type'], fallback: 'market'),
      ),
      discoverySubcategory: parseNullableString(
        j['discovery_subcategory'] ?? j['discoverySubcategory'],
      ),
      discoverySubcategories:
          (j['discovery_subcategories'] ?? j['discoverySubcategories']) is List
          ? List<dynamic>.from(
                  (j['discovery_subcategories'] ?? j['discoverySubcategories'])
                      as List,
                )
                .map(
                  (item) =>
                      parseString(item, fallback: '').trim().toLowerCase(),
                )
                .where((item) => item.isNotEmpty)
                .toList()
          : const <String>[],
      discoverySelectAll: parseBool(
        j['discovery_select_all'] ?? j['discoverySelectAll'],
      ),
      description: parseNullableString(j['description']),
      phone: parseNullableString(j['phone']),
      imageUrl: parseNullableString(j['image_url'] ?? j['imageUrl']),
      tagline: parseNullableString(j['tagline']),
      workingHours: parseNullableString(
        j['working_hours'] ?? j['workingHours'],
      ),
      serviceAreaNote: parseNullableString(
        j['service_area_note'] ?? j['serviceAreaNote'],
      ),
      isOpen: j['is_open'] ?? j['isOpen'] ?? true,
      supportsChat: parseBool(j['supports_chat'] ?? j['supportsChat']),
      supportsAttachments: parseBool(
        j['supports_attachments'] ?? j['supportsAttachments'],
      ),
      supportsPharmacyWorkflow: parseBool(
        j['supports_pharmacy_workflow'] ?? j['supportsPharmacyWorkflow'],
      ),
      serviceFlags: (j['service_flags_json'] ?? j['serviceFlags']) is Map
          ? Map<String, dynamic>.from(
              (j['service_flags_json'] ?? j['serviceFlags']) as Map,
            )
          : const <String, dynamic>{},
      badges: (j['badges_json'] ?? j['badges']) is List
          ? List<dynamic>.from((j['badges_json'] ?? j['badges']) as List)
                .map((item) => parseString(item, fallback: ''))
                .where((item) => item.isNotEmpty)
                .toList()
          : const <String>[],
      isApproved: j['is_approved'] ?? j['isApproved'] ?? false,
      approvalStatus: parseString(
        j['approval_status'] ?? j['approvalStatus'] ?? 'pending_admin_review',
      ),
      financialTermsSentAt: _parseDate(
        j['financial_terms_sent_at'] ?? j['financialTermsSentAt'],
      ),
      financialTermsAcceptedAt: _parseDate(
        j['financial_terms_accepted_at'] ?? j['financialTermsAcceptedAt'],
      ),
      financialTermsRejectedAt: _parseDate(
        j['financial_terms_rejected_at'] ?? j['financialTermsRejectedAt'],
      ),
      financialTermsRejectionNote: parseNullableString(
        j['financial_terms_rejection_note'] ?? j['financialTermsRejectionNote'],
      ),
      financialTermsSnapshot:
          (j['financial_terms_snapshot_json'] ?? j['financialTermsSnapshot'])
              is Map
          ? Map<String, dynamic>.from(
              (j['financial_terms_snapshot_json'] ??
                      j['financialTermsSnapshot'])
                  as Map,
            )
          : null,
      createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final s = value.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
