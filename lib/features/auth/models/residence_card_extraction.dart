class ResidenceCardExtraction {
  final bool success;
  final String documentType;
  final double confidence;
  final ResidenceCardData extractedData;
  final List<String> missingFields;
  final List<String> warnings;

  const ResidenceCardExtraction({
    required this.success,
    required this.documentType,
    required this.confidence,
    required this.extractedData,
    required this.missingFields,
    required this.warnings,
  });

  factory ResidenceCardExtraction.fromJson(Map<String, dynamic> json) {
    final extractedRaw = json['extracted_data'];
    final extractedMap = extractedRaw is Map
        ? Map<String, dynamic>.from(extractedRaw)
        : <String, dynamic>{};

    return ResidenceCardExtraction(
      success: json['success'] == true,
      documentType: '${json['document_type'] ?? 'residence_card'}',
      confidence: (json['confidence'] is num)
          ? (json['confidence'] as num).toDouble()
          : double.tryParse('${json['confidence'] ?? 0}') ?? 0,
      extractedData: ResidenceCardData.fromJson(extractedMap),
      missingFields: (json['missing_fields'] as List? ?? const <dynamic>[])
          .map((e) => '$e')
          .toList(growable: false),
      warnings: (json['warnings'] as List? ?? const <dynamic>[])
          .map((e) => '$e')
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'document_type': documentType,
      'confidence': confidence,
      'extracted_data': extractedData.toJson(),
      'missing_fields': missingFields,
      'warnings': warnings,
    };
  }
}

class ResidenceCardData {
  final String? fullName;
  final String? town;
  final String? buildingNumber;
  final String? issueDate;
  final String? contractNumber;
  final String? floorNumber;
  final String? apartmentNumber;
  final String? visibleIdNumber;

  const ResidenceCardData({
    required this.fullName,
    required this.town,
    required this.buildingNumber,
    required this.issueDate,
    required this.contractNumber,
    required this.floorNumber,
    required this.apartmentNumber,
    required this.visibleIdNumber,
  });

  factory ResidenceCardData.fromJson(Map<String, dynamic> json) {
    String? str(dynamic value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    return ResidenceCardData(
      fullName: str(json['full_name']),
      town: str(json['town']),
      buildingNumber: str(json['building_number']),
      issueDate: str(json['issue_date']),
      contractNumber: str(json['contract_number']),
      floorNumber: str(json['floor_number']),
      apartmentNumber: str(json['apartment_number']),
      visibleIdNumber: str(json['visible_id_number']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'full_name': fullName,
      'town': town,
      'building_number': buildingNumber,
      'issue_date': issueDate,
      'contract_number': contractNumber,
      'floor_number': floorNumber,
      'apartment_number': apartmentNumber,
      'visible_id_number': visibleIdNumber,
    };
  }
}
