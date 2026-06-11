import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../models/customer_home_prefs.dart';

final customerHomePrefsProvider =
    StateNotifierProvider<
      CustomerHomePrefsController,
      AsyncValue<CustomerHomePrefs>
    >((ref) => CustomerHomePrefsController(ref));

class CustomerHomePrefsController
    extends StateNotifier<AsyncValue<CustomerHomePrefs>> {
  static const _keyPrefix = 'customer_home_prefs';

  final Ref ref;

  CustomerHomePrefsController(this.ref)
    : super(const AsyncValue.data(CustomerHomePrefs.empty));

  Future<void> bootstrap({required int userId}) async {
    final local = await _readLocal(userId);
    state = AsyncValue.data(local ?? CustomerHomePrefs.empty);
  }

  Future<void> completeOnboarding({
    required int userId,
    required String audience,
    required String priority,
    required List<String> interests,
  }) async {
    final next = CustomerHomePrefs(
      completed: true,
      audience: audience,
      priority: priority,
      interests: interests.toSet().toList(),
      updatedAt: DateTime.now(),
    );

    state = AsyncValue.data(next);
    await _writeLocal(userId, next);
  }

  Future<void> reset({required int userId}) async {
    state = const AsyncValue.data(CustomerHomePrefs.empty);
    final store = ref.read(secureStoreProvider);
    await store.delete(_key(userId));
  }

  Future<void> _writeLocal(int userId, CustomerHomePrefs prefs) async {
    final store = ref.read(secureStoreProvider);
    await store.writeString(_key(userId), jsonEncode(prefs.toJson()));
  }

  Future<CustomerHomePrefs?> _readLocal(int userId) async {
    final store = ref.read(secureStoreProvider);
    final raw = await store.readString(_key(userId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return CustomerHomePrefs.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  String _key(int userId) => '$_keyPrefix:$userId';
}
