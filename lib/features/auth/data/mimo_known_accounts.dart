import 'dart:convert';

import '../../../core/storage/secure_storage.dart';
import '../domain/auth_input_normalizer.dart';

/// Phones that already signed in on THIS device, mapped to the account's
/// first name, so Mimo can greet a returning user who mistyped their PIN.
///
/// The backend deliberately answers "unknown phone" and "wrong PIN" with the
/// same error (no account enumeration), so names come only from this local,
/// secure-storage-backed list: typing a stranger's number reveals nothing.
/// Survives logout on purpose (the secure-store `clear()` only wipes session
/// keys).
class MimoKnownAccounts {
  MimoKnownAccounts(this._store);

  final SecureStore _store;

  static const _key = 'mimo_known_accounts_v1';
  static const _maxEntries = 5;

  Future<Map<String, String>> _readAll() async {
    try {
      final raw = await _store.readString(_key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is String) e.key.toString(): e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  /// First name remembered for [phone], or null.
  Future<String?> nameFor(String phone) async {
    final key = normalizeIraqiPhoneForAuth(phone);
    if (key.isEmpty) return null;
    final name = (await _readAll())[key]?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<void> remember(String phone, String fullName) async {
    final key = normalizeIraqiPhoneForAuth(phone);
    final first = firstName(fullName);
    if (key.isEmpty || first.isEmpty) return;
    final all = await _readAll();
    all.remove(key);
    all[key] = first;
    while (all.length > _maxEntries) {
      all.remove(all.keys.first);
    }
    try {
      await _store.writeString(_key, jsonEncode(all));
    } catch (_) {
      // Cosmetic feature; never fail sign-in over it.
    }
  }

  static String firstName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.first;
  }
}
