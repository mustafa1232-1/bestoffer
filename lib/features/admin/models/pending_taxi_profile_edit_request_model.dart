import '../../../core/utils/parsers.dart';

class PendingTaxiProfileEditRequestModel {
  final int id;
  final int captainUserId;
  final String fullName;
  final String phone;
  final String? block;
  final String? buildingNumber;
  final String? apartment;
  final String? captainNote;
  final DateTime? requestedAt;
  final Map<String, dynamic> requestedChanges;
  final Map<String, dynamic> currentProfile;

  const PendingTaxiProfileEditRequestModel({
    required this.id,
    required this.captainUserId,
    required this.fullName,
    required this.phone,
    required this.block,
    required this.buildingNumber,
    required this.apartment,
    required this.captainNote,
    required this.requestedAt,
    required this.requestedChanges,
    required this.currentProfile,
  });

  factory PendingTaxiProfileEditRequestModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawRequested = json['requestedChanges'] ?? json['requested_changes'];
    final requestedChanges = rawRequested is Map
        ? Map<String, dynamic>.from(rawRequested)
        : const <String, dynamic>{};

    final rawCurrent = json['currentProfile'] ?? json['current_profile'];
    final currentProfile = rawCurrent is Map
        ? Map<String, dynamic>.from(rawCurrent)
        : const <String, dynamic>{};

    return PendingTaxiProfileEditRequestModel(
      id: parseInt(json['id']),
      captainUserId: parseInt(json['captainUserId'] ?? json['captain_user_id']),
      fullName: parseString(json['fullName'] ?? json['full_name']),
      phone: parseString(json['phone']),
      block: parseNullableString(json['block']),
      buildingNumber: parseNullableString(
        json['buildingNumber'] ?? json['building_number'],
      ),
      apartment: parseNullableString(json['apartment']),
      captainNote: parseNullableString(
        json['captainNote'] ?? json['captain_note'],
      ),
      requestedAt: parseNullableDateTime(
        json['requestedAt'] ?? json['requested_at'],
      ),
      requestedChanges: requestedChanges,
      currentProfile: currentProfile,
    );
  }
}
