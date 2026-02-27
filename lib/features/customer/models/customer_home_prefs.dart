import '../../../core/utils/parsers.dart';

class CustomerHomePrefs {
  final bool completed;
  final String audience;
  final String priority;
  final List<String> interests;
  final DateTime? updatedAt;

  const CustomerHomePrefs({
    required this.completed,
    required this.audience,
    required this.priority,
    required this.interests,
    required this.updatedAt,
  });

  static const empty = CustomerHomePrefs(
    completed: false,
    audience: 'any',
    priority: 'balanced',
    interests: <String>[],
    updatedAt: null,
  );

  CustomerHomePrefs copyWith({
    bool? completed,
    String? audience,
    String? priority,
    List<String>? interests,
    DateTime? updatedAt,
  }) {
    return CustomerHomePrefs(
      completed: completed ?? this.completed,
      audience: audience ?? this.audience,
      priority: priority ?? this.priority,
      interests: interests ?? this.interests,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory CustomerHomePrefs.fromJson(Map<String, dynamic> json) {
    final rawInterests = json['interests'];
    return CustomerHomePrefs(
      completed: parseBool(json['completed'], fallback: false),
      audience: parseString(json['audience'], fallback: 'any'),
      priority: parseString(json['priority'], fallback: 'balanced'),
      interests: rawInterests is List
          ? rawInterests
                .map((e) => parseString(e).trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList()
          : const <String>[],
      updatedAt: parseNullableDateTime(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completed': completed,
      'audience': audience,
      'priority': priority,
      'interests': interests,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
