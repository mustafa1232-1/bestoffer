import 'package:core_networking/core_networking.dart';
import 'package:core_localization/core_localization.dart';
import 'package:core_storage/core_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AuthRoleScope { user, owner, delivery, taxiCaptain, company }

extension AuthRoleScopeStorage on AuthRoleScope {
  String get storageValue => switch (this) {
    AuthRoleScope.user => 'user',
    AuthRoleScope.owner => 'owner',
    AuthRoleScope.delivery => 'delivery',
    AuthRoleScope.taxiCaptain => 'taxi_captain',
    AuthRoleScope.company => 'company',
  };

  static AuthRoleScope? fromStorageValue(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    for (final value in AuthRoleScope.values) {
      if (value.storageValue == normalized) return value;
    }
    return null;
  }
}

class RuntimeAuthUser {
  final int id;
  final String fullName;
  final String phone;
  final String role;
  final bool isSuperAdmin;
  final bool isTaxiCaptain;

  const RuntimeAuthUser({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.isSuperAdmin,
    required this.isTaxiCaptain,
  });

  factory RuntimeAuthUser.fromJson(Map<String, dynamic> json) {
    return RuntimeAuthUser(
      id: _parseInt(json['id']),
      fullName: _parseString(json['full_name'] ?? json['fullName']),
      phone: _parseString(json['phone']),
      role: _parseString(json['role'], fallback: 'user'),
      isSuperAdmin: _parseBool(
        json['is_super_admin'] ?? json['isSuperAdmin'] ?? json['sa'],
      ),
      isTaxiCaptain: _parseBool(
        json['is_taxi_captain'] ?? json['isTaxiCaptain'],
      ),
    );
  }
}

class AuthState {
  final bool loading;
  final RuntimeAuthUser? user;
  final String? token;
  final String? error;
  final AuthRoleScope? localRole;

  const AuthState({
    this.loading = false,
    this.user,
    this.token,
    this.error,
    this.localRole,
  });

  const AuthState.guest() : this();

  const AuthState.authenticated(AuthRoleScope role)
    : this(localRole: role, token: 'runtime-local-auth');

  bool get isAuthed =>
      (token != null && token!.trim().isNotEmpty) || localRole != null;

  AuthRoleScope? get role {
    if (localRole != null) return localRole;
    if (user == null) return null;
    final normalized = user!.role.trim().toLowerCase();
    if (user!.isTaxiCaptain || normalized == 'taxi_captain') {
      return AuthRoleScope.taxiCaptain;
    }
    return switch (normalized) {
      'owner' => AuthRoleScope.owner,
      'delivery' => AuthRoleScope.delivery,
      'company_portal' => AuthRoleScope.company,
      _ => AuthRoleScope.user,
    };
  }

  bool get isUser => role == AuthRoleScope.user;
  bool get isOwner => role == AuthRoleScope.owner;
  bool get isDelivery => role == AuthRoleScope.delivery;
  bool get isTaxiCaptain => role == AuthRoleScope.taxiCaptain;
  bool get isCompany => role == AuthRoleScope.company;

  AuthState copyWith({
    bool? loading,
    RuntimeAuthUser? user,
    String? token,
    String? error,
    AuthRoleScope? localRole,
    bool clearUser = false,
    bool clearToken = false,
    bool clearError = false,
    bool clearLocalRole = false,
  }) {
    return AuthState(
      loading: loading ?? this.loading,
      user: clearUser ? null : (user ?? this.user),
      token: clearToken ? null : (token ?? this.token),
      error: clearError ? null : error,
      localRole: clearLocalRole ? null : (localRole ?? this.localRole),
    );
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(
      ref: ref,
      store: ref.watch(appScopedSecureStoreProvider),
      preferencesStore: ref.watch(appScopedPreferencesStoreProvider),
      dio: ref.watch(runtimeDioProvider),
    );
  },
);

class AuthController extends StateNotifier<AuthState> {
  static const _authRoleKey = 'auth.role';

  final Ref? _ref;
  final AppScopedSecureStore _store;
  final AppScopedPreferencesStore _preferencesStore;
  final Dio? _dio;
  bool _bootstrapped = false;

  AuthController({
    Ref? ref,
    AppScopedSecureStore? store,
    AppScopedPreferencesStore? preferencesStore,
    Dio? dio,
  }) : _ref = ref,
       _store =
           store ??
           AppScopedSecureStore(
             const AppScopedPreferencesStore(scope: 'runtime_test'),
             inMemoryOnly: true,
           ),
       _preferencesStore =
           preferencesStore ??
           const AppScopedPreferencesStore(scope: 'runtime_test'),
       _dio = dio,
       super(const AuthState.guest());

  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    final token = await _store.readToken();
    if (token != null && token.trim().isNotEmpty) {
      state = state.copyWith(
        token: token.trim(),
        loading: true,
        clearError: true,
        clearLocalRole: true,
      );
      final loaded = await _loadMe();
      if (loaded) return;
    }

    final storedRole = AuthRoleScopeStorage.fromStorageValue(
      await _preferencesStore.readString(_authRoleKey),
    );
    state = storedRole == null
        ? const AuthState.guest()
        : AuthState.authenticated(storedRole);
  }

  Future<void> login(AuthRoleScope role) async {
    state = AuthState.authenticated(role);
    await _preferencesStore.writeString(_authRoleKey, role.storageValue);
    await _store.clearToken();
  }

  Future<bool> loginWithPhonePin({
    required String phone,
    required String pin,
    required AuthRoleScope expectedRole,
  }) async {
    final dio = _dio ?? _readRuntimeDio();
    final l10n = await _resolveLocalizations();
    if (dio == null) {
      state = state.copyWith(
        error: l10n.runtimeAuthUnavailableError,
        loading: false,
        clearUser: true,
        clearToken: true,
        clearLocalRole: true,
      );
      return false;
    }

    state = state.copyWith(
      loading: true,
      clearError: true,
      clearLocalRole: true,
    );
    try {
      final response = await dio.post(
        '/api/auth/login',
        data: {'phone': _normalizeInput(phone), 'pin': _normalizeInput(pin)},
      );
      final payload = response.data;
      if (payload is! Map) {
        throw const FormatException('INVALID_LOGIN_PAYLOAD');
      }
      final json = Map<String, dynamic>.from(payload);
      final token = _parseString(json['token']);
      final rawUser = json['user'];
      if (token.trim().isEmpty || rawUser is! Map) {
        throw const FormatException('INVALID_LOGIN_PAYLOAD');
      }
      final user = RuntimeAuthUser.fromJson(Map<String, dynamic>.from(rawUser));
      if (!_roleMatches(user, expectedRole)) {
        await _store.clearToken();
        state = state.copyWith(
          loading: false,
          error: l10n.runtimeAuthRoleMismatchError,
          clearToken: true,
          clearUser: true,
          clearLocalRole: true,
        );
        return false;
      }
      await _store.saveToken(token.trim());
      await _preferencesStore.remove(_authRoleKey);
      state = AuthState(
        loading: false,
        user: user,
        token: token.trim(),
        error: null,
      );
      return true;
    } on DioException catch (error) {
      final message =
          _extractApiErrorMessage(error) ?? l10n.runtimeAuthSignInFailedError;
      state = state.copyWith(
        loading: false,
        error: message,
        clearToken: true,
        clearUser: true,
        clearLocalRole: true,
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: l10n.runtimeAuthSignInFailedError,
        clearToken: true,
        clearUser: true,
        clearLocalRole: true,
      );
      return false;
    }
  }

  Future<void> logout() async {
    final dio = _dio ?? _readRuntimeDio();
    if (dio != null && state.token != null && state.token!.isNotEmpty) {
      try {
        await dio.post('/api/auth/logout');
      } catch (_) {
        // Keep logout best-effort.
      }
    }
    await _store.clearToken();
    await _preferencesStore.remove(_authRoleKey);
    state = const AuthState.guest();
  }

  Future<bool> _loadMe() async {
    final dio = _dio ?? _readRuntimeDio();
    if (dio == null) return false;
    try {
      final response = await dio.get('/api/me');
      final payload = response.data;
      if (payload is! Map || payload['user'] is! Map) {
        throw const FormatException('INVALID_ME_PAYLOAD');
      }
      final user = RuntimeAuthUser.fromJson(
        Map<String, dynamic>.from(payload['user'] as Map),
      );
      state = state.copyWith(
        loading: false,
        user: user,
        clearError: true,
        clearLocalRole: true,
      );
      return true;
    } catch (_) {
      await _store.clearToken();
      state = const AuthState.guest();
      return false;
    }
  }

  Dio? _readRuntimeDio() => _ref?.read(runtimeDioProvider);

  Future<CoreAppLocalizations> _resolveLocalizations() async {
    final localeCode =
        (await _preferencesStore.readString('settings.locale'))
            ?.trim()
            .toLowerCase();
    return CoreAppLocalizations(Locale(localeCode == 'en' ? 'en' : 'ar'));
  }

  bool _roleMatches(RuntimeAuthUser user, AuthRoleScope expectedRole) {
    final normalizedRole = user.role.trim().toLowerCase();
    return switch (expectedRole) {
      AuthRoleScope.user =>
        normalizedRole != 'owner' &&
            normalizedRole != 'delivery' &&
            normalizedRole != 'admin' &&
            normalizedRole != 'deputy_admin' &&
            normalizedRole != 'company_portal' &&
            normalizedRole != 'company_owner' &&
            normalizedRole != 'company_manager' &&
            normalizedRole != 'finance_viewer' &&
            normalizedRole != 'operations_viewer' &&
            normalizedRole != 'company' &&
            !user.isTaxiCaptain,
      AuthRoleScope.owner => normalizedRole == 'owner',
      AuthRoleScope.delivery =>
        normalizedRole == 'delivery' && !user.isTaxiCaptain,
      AuthRoleScope.taxiCaptain =>
        user.isTaxiCaptain || normalizedRole == 'taxi_captain',
      AuthRoleScope.company => normalizedRole == 'company_portal',
    };
  }
}

String? _extractApiErrorMessage(DioException error) {
  final data = error.response?.data;
  if (data is Map) {
    final message = data['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
  }
  return null;
}

String _normalizeInput(String value) => _normalizeArabicDigits(value).trim();

String _normalizeArabicDigits(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + (rune - 0x0660));
      continue;
    }
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      out.writeCharCode(0x30 + (rune - 0x06F0));
      continue;
    }
    out.writeCharCode(rune);
  }
  return out.toString();
}

int _parseInt(dynamic value) {
  final parsed = int.tryParse('${value ?? 0}'.trim());
  return parsed ?? 0;
}

String _parseString(dynamic value, {String fallback = ''}) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? fallback : text;
}

bool _parseBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = '${value ?? ''}'.trim().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return fallback;
}
