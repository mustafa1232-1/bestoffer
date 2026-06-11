enum SectionAvailabilityStatus {
  open,
  comingSoon,
  maintenance,
  temporarilyClosed;

  static SectionAvailabilityStatus fromApi(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'coming_soon':
        return SectionAvailabilityStatus.comingSoon;
      case 'maintenance':
        return SectionAvailabilityStatus.maintenance;
      case 'temporarily_closed':
        return SectionAvailabilityStatus.temporarilyClosed;
      default:
        return SectionAvailabilityStatus.open;
    }
  }

  String get apiValue => switch (this) {
    SectionAvailabilityStatus.open => 'open',
    SectionAvailabilityStatus.comingSoon => 'coming_soon',
    SectionAvailabilityStatus.maintenance => 'maintenance',
    SectionAvailabilityStatus.temporarilyClosed => 'temporarily_closed',
  };
}

class AppSectionKeys {
  static const shopping = 'shopping';
  static const services = 'services';
  static const taxi = 'taxi';
  static const community = 'community';
  static const jobs = 'jobs';
  static const realEstate = 'real_estate';
  static const cars = 'cars';
  static const pharmacy = 'pharmacy';
}

class SectionAvailabilityEntry {
  final int id;
  final String sectionKey;
  final String displayName;
  final String? parentSectionKey;
  final String surfaceScope;
  final SectionAvailabilityStatus status;
  final bool isVisible;
  final String? userMessage;
  final int sortOrder;
  final bool allowExistingActiveAccess;
  final Map<String, dynamic> metadata;
  final String? updatedAt;

  const SectionAvailabilityEntry({
    required this.id,
    required this.sectionKey,
    required this.displayName,
    required this.parentSectionKey,
    required this.surfaceScope,
    required this.status,
    required this.isVisible,
    required this.userMessage,
    required this.sortOrder,
    required this.allowExistingActiveAccess,
    required this.metadata,
    required this.updatedAt,
  });

  factory SectionAvailabilityEntry.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['metadata'];
    return SectionAvailabilityEntry(
      id: int.tryParse('${json['id'] ?? ''}') ?? 0,
      sectionKey: '${json['sectionKey'] ?? ''}'.trim().toLowerCase(),
      displayName:
          '${json['displayName'] ?? json['sectionKey'] ?? ''}'.trim(),
      parentSectionKey: '${json['parentSectionKey'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['parentSectionKey']}'.trim().toLowerCase(),
      surfaceScope: '${json['surfaceScope'] ?? 'user'}'.trim().toLowerCase(),
      status: SectionAvailabilityStatus.fromApi('${json['status'] ?? ''}'),
      isVisible: json['isVisible'] != false,
      userMessage: '${json['effectiveMessage'] ?? json['userMessage'] ?? ''}'
              .trim()
              .isEmpty
          ? null
          : '${json['effectiveMessage'] ?? json['userMessage']}'.trim(),
      sortOrder: int.tryParse('${json['sortOrder'] ?? ''}') ?? 0,
      allowExistingActiveAccess: json['allowExistingActiveAccess'] != false,
      metadata: rawMetadata is Map
          ? Map<String, dynamic>.from(rawMetadata)
          : const <String, dynamic>{},
      updatedAt: '${json['updatedAt'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['updatedAt']}'.trim(),
    );
  }

  bool get isOpen => status == SectionAvailabilityStatus.open;

  bool get isBlocked => !isOpen;

  String? get badgeLabel => switch (status) {
    SectionAvailabilityStatus.open => null,
    SectionAvailabilityStatus.comingSoon => 'قريبًا',
    SectionAvailabilityStatus.maintenance => 'تحت الصيانة',
    SectionAvailabilityStatus.temporarilyClosed => 'غير متاح',
  };

  String get effectiveMessage {
    if ((userMessage ?? '').trim().isNotEmpty) {
      return userMessage!.trim();
    }
    return switch (status) {
      SectionAvailabilityStatus.open => 'القسم متاح الآن.',
      SectionAvailabilityStatus.comingSoon => 'هذا القسم سيُتاح قريبًا.',
      SectionAvailabilityStatus.maintenance =>
        'هذا القسم تحت الصيانة حاليًا. حاول لاحقًا.',
      SectionAvailabilityStatus.temporarilyClosed =>
        'هذا القسم غير متاح حاليًا. حاول لاحقًا.',
    };
  }

  SectionAvailabilityEntry copyWith({
    int? id,
    String? sectionKey,
    String? displayName,
    String? parentSectionKey,
    String? surfaceScope,
    SectionAvailabilityStatus? status,
    bool? isVisible,
    String? userMessage,
    bool clearUserMessage = false,
    int? sortOrder,
    bool? allowExistingActiveAccess,
    Map<String, dynamic>? metadata,
    String? updatedAt,
  }) {
    return SectionAvailabilityEntry(
      id: id ?? this.id,
      sectionKey: sectionKey ?? this.sectionKey,
      displayName: displayName ?? this.displayName,
      parentSectionKey: parentSectionKey ?? this.parentSectionKey,
      surfaceScope: surfaceScope ?? this.surfaceScope,
      status: status ?? this.status,
      isVisible: isVisible ?? this.isVisible,
      userMessage: clearUserMessage ? null : (userMessage ?? this.userMessage),
      sortOrder: sortOrder ?? this.sortOrder,
      allowExistingActiveAccess:
          allowExistingActiveAccess ?? this.allowExistingActiveAccess,
      metadata: metadata ?? this.metadata,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

SectionAvailabilityEntry fallbackOpenSectionEntry(
  String sectionKey, {
  String? displayName,
  String surfaceScope = 'user',
}) {
  final key = sectionKey.trim().toLowerCase();
  return SectionAvailabilityEntry(
    id: 0,
    sectionKey: key,
    displayName: displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : key,
    parentSectionKey: null,
    surfaceScope: surfaceScope,
    status: SectionAvailabilityStatus.open,
    isVisible: true,
    userMessage: null,
    sortOrder: 0,
    allowExistingActiveAccess: true,
    metadata: const <String, dynamic>{},
    updatedAt: null,
  );
}
