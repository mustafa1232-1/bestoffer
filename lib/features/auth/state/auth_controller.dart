import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../../../core/forms/backend_field_error_parser.dart'
    show ParsedBackendFieldErrors;
import '../../../core/files/local_image_file.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/session_invalidation.dart';
import '../../../core/media/media_cache_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/settings/app_settings_controller.dart';
import '../../../core/platform/app_flavor.dart';
import '../data/auth_api.dart';
import '../data/auth_repo_impl.dart';
import '../domain/auth_repo.dart';
import '../domain/login_error_mapper.dart';
import '../models/user_model.dart';

final secureStoreProvider = Provider<SecureStore>((ref) {
  return SecureStore(flavor: ref.watch(appFlavorProvider));
});

final dioClientProvider = Provider<DioClient>(
  (ref) => DioClient(ref.read(secureStoreProvider)),
);

final authRepoProvider = Provider<AuthRepo>((ref) {
  final client = ref.read(dioClientProvider);
  return AuthRepoImpl(api: AuthApi(client.dio), store: client.store);
});

class AuthState {
  final bool loading;
  final UserModel? user;
  final String? token;
  final bool guestMode;
  final String? error;
  final ParsedBackendFieldErrors? validationError;
  final String? errorCode;
  final bool sessionRecoveryPending;
  final SessionRestoreStatus? sessionRestoreStatus;

  const AuthState({
    this.loading = false,
    this.user,
    this.token,
    this.guestMode = false,
    this.error,
    this.validationError,
    this.errorCode,
    this.sessionRecoveryPending = false,
    this.sessionRestoreStatus,
  });

  bool get isAuthed => token != null && token!.isNotEmpty;
  bool get isGuest => guestMode && !isAuthed;

  bool get isAdmin => _resolveRole() == 'admin';

  bool get isOwner => _resolveRole() == 'owner';

  bool get isCustomer {
    final role = _resolveRole();
    return role == 'user' || role == 'customer';
  }

  bool get isTaxiCaptain {
    final role = _resolveRole();
    if (role == 'delivery') return false;
    if (role == 'taxi_captain') return true;
    if (user?.isTaxiCaptain == true) return true;
    return _resolveTaxiCaptainClaim();
  }

  bool get isDelivery => _resolveRole() == 'delivery' && !isTaxiCaptain;

  bool get isAccountant => _resolveRole() == 'accountant';

  bool get isHr => _resolveRole() == 'hr';

  bool get isDeputyAdmin => _resolveRole() == 'deputy_admin';

  bool get isCompanyPortal => _resolveRole() == 'company_portal';

  bool get isServiceProvider => _resolveRole() == 'service_provider';

  bool get isBackoffice => isAdmin || isDeputyAdmin || isSuperAdmin;

  bool get isCompanyBackoffice =>
      isBackoffice || isAccountant || isHr || isCompanyPortal;

  bool get isSuperAdmin {
    if (user?.isSuperAdmin == true) return true;
    if (_resolveRole() == 'super_admin') return true;

    final currentToken = token;
    if (currentToken == null || currentToken.isEmpty) return false;
    try {
      final claims = JwtDecoder.decode(currentToken);
      return claims['sa'] == true;
    } catch (_) {
      return false;
    }
  }

  String _resolveRole() {
    final roleFromUser = user?.role.toLowerCase();
    if (roleFromUser != null && roleFromUser.isNotEmpty) return roleFromUser;

    final currentToken = token;
    if (currentToken == null || currentToken.isEmpty) return '';

    try {
      final claims = JwtDecoder.decode(currentToken);
      return '${claims['role'] ?? ''}'.toLowerCase();
    } catch (_) {
      return '';
    }
  }

  bool _resolveTaxiCaptainClaim() {
    final currentToken = token;
    if (currentToken == null || currentToken.isEmpty) return false;
    try {
      final claims = JwtDecoder.decode(currentToken);
      final raw =
          claims['is_taxi_captain'] ??
          claims['isTaxiCaptain'] ??
          claims['taxi_captain'] ??
          claims['tc'];
      if (raw is bool) return raw;
      if (raw is num) return raw != 0;
      final normalized = '${raw ?? ''}'.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    } catch (_) {
      return false;
    }
  }

  AuthState copyWith({
    bool? loading,
    UserModel? user,
    String? token,
    bool? guestMode,
    String? error,
    ParsedBackendFieldErrors? validationError,
    String? errorCode,
    bool? sessionRecoveryPending,
    SessionRestoreStatus? sessionRestoreStatus,
    bool clearValidationError = false,
    bool clearErrorCode = false,
    bool clearSessionRestoreStatus = false,
  }) {
    return AuthState(
      loading: loading ?? this.loading,
      user: user ?? this.user,
      token: token ?? this.token,
      guestMode: guestMode ?? this.guestMode,
      error: error,
      validationError: clearValidationError
          ? null
          : (validationError ?? this.validationError),
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
      sessionRecoveryPending:
          sessionRecoveryPending ?? this.sessionRecoveryPending,
      sessionRestoreStatus: clearSessionRestoreStatus
          ? null
          : (sessionRestoreStatus ?? this.sessionRestoreStatus),
    );
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref),
);

const Duration kAuthSessionVerifyTimeout = Duration(seconds: 20);
const Duration kAuthStorageReadTimeout = Duration(seconds: 3);

class AuthController extends StateNotifier<AuthState> {
  final Ref ref;

  AuthController(this.ref) : super(const AuthState());

  Future<String?> _readStoredTokenOrNull(SecureStore store) async {
    try {
      final token = await store.readToken().timeout(kAuthStorageReadTimeout);
      final text = token?.trim();
      return text == null || text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _readGuestModeOrFalse(SecureStore store) async {
    try {
      return await store.readGuestMode().timeout(
        kAuthStorageReadTimeout,
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> bootstrap() async {
    final store = ref.read(secureStoreProvider);
    state = state.copyWith(
      loading: true,
      clearValidationError: true,
      clearErrorCode: true,
    );
    var token = await _readStoredTokenOrNull(store);
    if (token == null || token.isEmpty) {
      late final SessionRestoreResult restore;
      try {
        restore = await ref
            .read(dioClientProvider)
            .restoreStoredSession()
            .timeout(kAuthSessionVerifyTimeout);
      } catch (_) {
        // Timeout / unexpected failure while restoring. This is NOT a terminal
        // auth error: never surface an internal code and never clear a
        // potentially-valid stored session. Stay silent and pending; a later
        // launch (or silent retry) can still recover it.
        state = state.copyWith(
          loading: false,
          guestMode: false,
          sessionRecoveryPending: true,
          sessionRestoreStatus: SessionRestoreStatus.pending,
          error: null,
          clearValidationError: true,
          clearErrorCode: true,
        );
        return;
      }

      switch (restore.status) {
        case SessionRestoreStatus.recovered:
          token = restore.token;
          break;
        case SessionRestoreStatus.noStoredSession:
          // Fresh install / no stored session. A normal state, never an error
          // and never a session-recovery attempt.
          state = state.copyWith(
            loading: false,
            guestMode: await _readGuestModeOrFalse(store),
            sessionRecoveryPending: false,
            sessionRestoreStatus: SessionRestoreStatus.noStoredSession,
            error: null,
            clearValidationError: true,
            clearErrorCode: true,
          );
          return;
        case SessionRestoreStatus.pending:
          // Recoverable / temporary failure (network, 5xx). Keep the stored
          // session untouched and stay silent — no error, no code. A later
          // launch or silent retry can still recover it.
          state = state.copyWith(
            loading: false,
            guestMode: false,
            sessionRecoveryPending: true,
            sessionRestoreStatus: SessionRestoreStatus.pending,
            error: null,
            clearValidationError: true,
            clearErrorCode: true,
          );
          return;
        case SessionRestoreStatus.accountDisabled:
          // A legitimate terminal reason. The device recovery bundle is kept for
          // the re-verification flow, but the user-facing text is a CLEAN
          // localized message — never the raw backend code.
          state = state.copyWith(
            loading: false,
            guestMode: false,
            sessionRestoreStatus: SessionRestoreStatus.accountDisabled,
            error: _accountDisabledMessage(),
            errorCode: restore.code,
            clearValidationError: true,
          );
          return;
        case SessionRestoreStatus.reVerificationRequired:
        case SessionRestoreStatus.surfaceMismatch:
        case SessionRestoreStatus.blocked:
          // Non-recoverable stored session — this is where an invalid refresh
          // surfaces as SESSION_RECOVERY_REQUIRED. The internal status/code are
          // retained for the recovery flow, but NEVER shown: `error` is null so
          // the login screen renders no developer-facing text and there is no
          // retry loop (restore runs once per launch).
          state = state.copyWith(
            loading: false,
            guestMode: false,
            sessionRecoveryPending: false,
            sessionRestoreStatus: restore.status,
            error: null,
            errorCode: restore.code,
            clearValidationError: true,
          );
          return;
      }
    }

    state = state.copyWith(
      token: token,
      clearValidationError: true,
      clearErrorCode: true,
      clearSessionRestoreStatus: true,
    );

    try {
      final user = await ref
          .read(authRepoProvider)
          .me()
          .timeout(kAuthSessionVerifyTimeout);
      final latestToken = await _readStoredTokenOrNull(store) ?? token;
      await _applyPreferredLocale(user);
      await store.saveGuestMode(false);
      SessionRecoveryCoordinator.instance.reset();
      state = state.copyWith(
        user: user,
        token: latestToken,
        guestMode: false,
        error: null,
        sessionRecoveryPending: false,
        clearSessionRestoreStatus: true,
        clearValidationError: true,
        clearErrorCode: true,
      );
    } catch (e) {
      if (e is DioException) {
        final decision = SessionRecoveryCoordinator.instance.classify(e);
        if (decision == SessionRecoveryDecision.staleFailure ||
            decision == SessionRecoveryDecision.recoverable ||
            decision == SessionRecoveryDecision.needsRecovery) {
          final latestToken = await _readStoredTokenOrNull(store) ?? token;
          state = state.copyWith(
            loading: false,
            token: latestToken,
            guestMode: false,
            sessionRecoveryPending:
                decision == SessionRecoveryDecision.needsRecovery,
            sessionRestoreStatus:
                decision == SessionRecoveryDecision.needsRecovery
                ? SessionRestoreStatus.pending
                : state.sessionRestoreStatus,
            clearValidationError: true,
            clearErrorCode: true,
          );
          return;
        }
      }
      // Non-auth failure (network / timeout) while verifying an existing token.
      // Keep the stored session — a temporary outage must never clear it — and
      // stay silent; recovery is retried on the next resume/launch.
      state = state.copyWith(
        loading: false,
        token: await _readStoredTokenOrNull(store) ?? token,
        guestMode: false,
        sessionRecoveryPending: true,
        error: null,
        clearValidationError: true,
        clearErrorCode: true,
      );
      return;
    }
    state = state.copyWith(
      loading: false,
      sessionRecoveryPending: false,
      clearSessionRestoreStatus: true,
      clearValidationError: true,
      clearErrorCode: true,
    );
  }

  Future<void> login(String phone, String pin) async {
    state = state.copyWith(
      loading: true,
      error: null,
      clearValidationError: true,
      clearErrorCode: true,
    );

    try {
      final user = await ref
          .read(authRepoProvider)
          .login(phone: phone, pin: pin);
      final token = await ref.read(secureStoreProvider).readToken();
      await _applyPreferredLocale(user);
      await ref.read(secureStoreProvider).saveGuestMode(false);
      SessionRecoveryCoordinator.instance.reset();
      state = state.copyWith(
        loading: false,
        user: user,
        token: token,
        guestMode: false,
        error: null,
        clearValidationError: true,
        clearErrorCode: true,
      );
    } on DioException catch (e) {
      final parsed = parseBackendFieldErrors(e);
      state = state.copyWith(
        loading: false,
        error: _mapLoginError(e),
        validationError: parsed,
        errorCode: parsed.messageCode,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapAnyError(e, fallback: 'Login failed. Please try again.'),
        clearValidationError: true,
        clearErrorCode: true,
      );
    }
  }

  Future<void> register(
    Map<String, dynamic> dto, {
    LocalImageFile? imageFile,
  }) async {
    state = state.copyWith(
      loading: true,
      error: null,
      clearValidationError: true,
      clearErrorCode: true,
    );

    try {
      final user = await ref
          .read(authRepoProvider)
          .register(
            fullName: dto['fullName']!.trim(),
            phone: dto['phone']!.trim(),
            pin: dto['pin']!.trim(),
            block: dto['block']!.trim(),
            buildingNumber: dto['buildingNumber']!.trim(),
            apartment: dto['apartment']!.trim(),
            analyticsConsentAccepted: dto['analyticsConsentAccepted'] == true,
            analyticsConsentVersion:
                '${dto['analyticsConsentVersion'] ?? 'analytics_v1'}',
            imageFile: imageFile,
          );

      final token = await ref.read(secureStoreProvider).readToken();
      await _applyPreferredLocale(user);
      await ref.read(secureStoreProvider).saveGuestMode(false);
      SessionRecoveryCoordinator.instance.reset();
      state = state.copyWith(
        loading: false,
        user: user,
        token: token,
        guestMode: false,
        error: null,
        clearValidationError: true,
        clearErrorCode: true,
      );
    } on DioException catch (e) {
      final parsed = parseBackendFieldErrors(e);
      state = state.copyWith(
        loading: false,
        error: _mapRegisterError(e),
        validationError: parsed,
        errorCode: parsed.messageCode,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapAnyError(e, fallback: 'Account creation failed.'),
        clearValidationError: true,
        clearErrorCode: true,
      );
    }
  }

  Future<void> registerOwner(
    Map<String, dynamic> dto, {
    LocalImageFile? ownerImageFile,
    LocalImageFile? merchantImageFile,
  }) async {
    state = state.copyWith(
      loading: true,
      error: null,
      clearValidationError: true,
      clearErrorCode: true,
    );

    try {
      String? optionalTrimmed(dynamic value) {
        if (value == null) return null;
        final text = '$value'.trim();
        return text.isEmpty ? null : text;
      }

      String requiredTrimmed(String key) {
        final value = optionalTrimmed(dto[key]);
        if (value == null) {
          throw StateError('MISSING_REQUIRED_FIELD:$key');
        }
        return value;
      }

      final merchantName = requiredTrimmed('merchantName');
      final fullName = optionalTrimmed(dto['fullName']) ?? merchantName;
      final merchantPhone =
          optionalTrimmed(dto['merchantPhone']) ?? requiredTrimmed('phone');
      final merchantType = optionalTrimmed(dto['merchantType']) ?? 'market';
      final merchantActivityType = requiredTrimmed('merchantActivityType');
      final user = await ref
          .read(authRepoProvider)
          .registerOwner(
            fullName: fullName,
            phone: requiredTrimmed('phone'),
            pin: requiredTrimmed('pin'),
            block: optionalTrimmed(dto['block']),
            buildingNumber: optionalTrimmed(dto['buildingNumber']),
            apartment: optionalTrimmed(dto['apartment']),
            merchantName: merchantName,
            merchantType: merchantType,
            merchantActivityType: merchantActivityType,
            merchantDepartment: optionalTrimmed(dto['merchantDepartment']),
            merchantDiscoverySubcategory: optionalTrimmed(
              dto['merchantDiscoverySubcategory'],
            ),
            merchantDiscoverySubcategories:
                dto['merchantDiscoverySubcategories'] is List
                ? List<String>.from(
                    dto['merchantDiscoverySubcategories'] as List,
                  )
                : null,
            merchantDiscoverySelectAll:
                dto['merchantDiscoverySelectAll'] is bool
                ? dto['merchantDiscoverySelectAll'] as bool
                : null,
            merchantDescription:
                optionalTrimmed(dto['merchantDescription']) ?? '',
            merchantPhone: merchantPhone,
            merchantImageUrl: optionalTrimmed(dto['merchantImageUrl']),
            merchantServiceFlags: dto['merchantServiceFlags'] is Map
                ? Map<String, dynamic>.from(dto['merchantServiceFlags'] as Map)
                : null,
            merchantBadges: dto['merchantBadges'] is List
                ? List<String>.from(dto['merchantBadges'] as List)
                : null,
            merchantSupportsChat: dto['merchantSupportsChat'] is bool
                ? dto['merchantSupportsChat'] as bool
                : null,
            merchantSupportsAttachments:
                dto['merchantSupportsAttachments'] is bool
                ? dto['merchantSupportsAttachments'] as bool
                : null,
            merchantSupportsPharmacyWorkflow:
                dto['merchantSupportsPharmacyWorkflow'] is bool
                ? dto['merchantSupportsPharmacyWorkflow'] as bool
                : null,
            analyticsConsentAccepted: dto['analyticsConsentAccepted'] == true,
            analyticsConsentVersion:
                '${dto['analyticsConsentVersion'] ?? 'analytics_v1'}',
            ownerImageFile: ownerImageFile,
            merchantImageFile: merchantImageFile,
          );

      final token = await ref.read(secureStoreProvider).readToken();
      await _applyPreferredLocale(user);
      await ref.read(secureStoreProvider).saveGuestMode(false);
      SessionRecoveryCoordinator.instance.reset();
      state = state.copyWith(
        loading: false,
        user: user,
        token: token,
        guestMode: false,
        error: null,
        clearValidationError: true,
        clearErrorCode: true,
      );
    } on DioException catch (e) {
      final parsed = parseBackendFieldErrors(e);
      state = state.copyWith(
        loading: false,
        error: _mapOwnerRegisterError(e),
        validationError: parsed,
        errorCode: parsed.messageCode,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapAnyError(e, fallback: 'Owner account creation failed.'),
        clearValidationError: true,
        clearErrorCode: true,
      );
    }
  }

  Future<bool> registerDelivery(
    Map<String, dynamic> dto, {
    LocalImageFile? profileImageFile,
    LocalImageFile? carImageFile,
  }) async {
    state = state.copyWith(
      loading: true,
      error: null,
      clearValidationError: true,
      clearErrorCode: true,
    );

    try {
      await ref
          .read(authRepoProvider)
          .registerDelivery(
            fullName: dto['fullName']!.trim(),
            phone: dto['phone']!.trim(),
            pin: dto['pin']!.trim(),
            block: dto['block']!.trim(),
            buildingNumber: dto['buildingNumber']!.trim(),
            apartment: dto['apartment']!.trim(),
            vehicleType: dto['vehicleType']!.trim(),
            carMake: dto['carMake']!.trim(),
            carModel: dto['carModel']!.trim(),
            carYear: int.parse('${dto['carYear']}'),
            plateNumber: dto['plateNumber']!.trim(),
            plateGovernorate: dto['plateGovernorate']?.toString(),
            plateCategory: dto['plateCategory']?.toString(),
            plateLetter: dto['plateLetter']?.toString(),
            plateDigits: dto['plateDigits']?.toString(),
            carColor: dto['carColor']?.toString(),
            analyticsConsentAccepted: dto['analyticsConsentAccepted'] == true,
            analyticsConsentVersion:
                '${dto['analyticsConsentVersion'] ?? 'analytics_v1'}',
            profileImageFile: profileImageFile,
            carImageFile: carImageFile,
          );

      state = state.copyWith(
        loading: false,
        user: null,
        token: null,
        error: null,
        clearValidationError: true,
        clearErrorCode: true,
      );
      return true;
    } on DioException catch (e) {
      final parsed = parseBackendFieldErrors(e);
      state = state.copyWith(
        loading: false,
        error: _mapDeliveryRegisterError(e),
        validationError: parsed,
        errorCode: parsed.messageCode,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapAnyError(
          e,
          fallback: 'Taxi captain account creation failed.',
        ),
        clearValidationError: true,
        clearErrorCode: true,
      );
      return false;
    }
  }

  Future<Map<String, dynamic>?> extractResidenceCard(
    LocalImageFile cardImageFile,
  ) async {
    final out = await ref
        .read(authRepoProvider)
        .extractResidenceCard(cardImageFile: cardImageFile);
    return out;
  }

  Future<void> registerWithCard(
    Map<String, dynamic> payload, {
    LocalImageFile? imageFile,
    required LocalImageFile cardImageFile,
  }) async {
    state = state.copyWith(
      loading: true,
      error: null,
      clearValidationError: true,
      clearErrorCode: true,
    );

    try {
      final user = await ref
          .read(authRepoProvider)
          .registerWithCard(
            payload: payload,
            imageFile: imageFile,
            cardImageFile: cardImageFile,
          );
      final token = await ref.read(secureStoreProvider).readToken();
      await _applyPreferredLocale(user);
      await ref.read(secureStoreProvider).saveGuestMode(false);
      state = state.copyWith(
        loading: false,
        user: user,
        token: token,
        guestMode: false,
        error: null,
        clearValidationError: true,
        clearErrorCode: true,
      );
    } on DioException catch (e) {
      final parsed = parseBackendFieldErrors(e);
      state = state.copyWith(
        loading: false,
        error: _mapRegisterError(e),
        validationError: parsed,
        errorCode: parsed.messageCode,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapAnyError(e, fallback: 'Account creation failed.'),
        clearValidationError: true,
        clearErrorCode: true,
      );
    }
  }

  Future<bool> registerTaxiCaptain(
    Map<String, dynamic> dto, {
    LocalImageFile? profileImageFile,
    LocalImageFile? carImageFile,
  }) {
    return registerDelivery(
      dto,
      profileImageFile: profileImageFile,
      carImageFile: carImageFile,
    );
  }

  Future<void> logout() async {
    final userId = state.user?.id ?? 0;
    if (userId > 0) {
      await ref.read(mediaCacheServiceProvider).clearUserScopedCache(userId);
    }
    await ref.read(authRepoProvider).logout();
    await ref.read(secureStoreProvider).clear();
    state = const AuthState();
  }

  /// Clean, localized "account disabled" message. Deliberately avoids returning
  /// any raw backend code (e.g. ACCOUNT_DISABLED / SESSION_RECOVERY_REQUIRED).
  /// Reads the active locale from [Intl] (plugin-free) rather than a provider so
  /// it is safe to call during early bootstrap.
  String _accountDisabledMessage() {
    final isArabic = Intl.getCurrentLocale().toLowerCase().startsWith('ar');
    return isArabic
        ? 'تم تعطيل هذا الحساب من قبل الإدارة.'
        : 'This account has been disabled by the administration.';
  }

  Future<void> continueAsGuest() async {
    final store = ref.read(secureStoreProvider);
    await store.saveGuestMode(true);
    state = const AuthState(guestMode: true);
  }

  /// Permanently deletes the signed-in account, then clears the local session so
  /// the router redirects to login. Returns true on success.
  Future<bool> deleteAccount({String? reasonCode, String? note}) async {
    state = state.copyWith(
      loading: true,
      error: null,
      clearValidationError: true,
      clearErrorCode: true,
    );
    try {
      final api = AuthApi(ref.read(dioClientProvider).dio);
      await api.deleteMyAccount(reasonCode: reasonCode, note: note);
      await logout();
      return true;
    } on DioException catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapDioError(
          e,
          fallback: 'Unable to delete your account.',
          appendRequestId: true,
        ),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapAnyError(e, fallback: 'Unable to delete your account.'),
      );
      return false;
    }
  }

  Future<bool> updateAccount({
    required String currentPin,
    String? newPhone,
    String? newPin,
  }) async {
    state = state.copyWith(
      loading: true,
      error: null,
      clearValidationError: true,
      clearErrorCode: true,
    );

    try {
      final updated = await ref
          .read(authRepoProvider)
          .updateAccount(
            currentPin: currentPin,
            newPhone: newPhone,
            newPin: newPin,
          );
      state = state.copyWith(
        loading: false,
        user: updated,
        error: null,
        clearValidationError: true,
        clearErrorCode: true,
      );
      return true;
    } on DioException catch (e) {
      final parsed = parseBackendFieldErrors(e);
      state = state.copyWith(
        loading: false,
        error: _mapUpdateAccountError(e),
        validationError: parsed,
        errorCode: parsed.messageCode,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapAnyError(e, fallback: 'Unable to update account details.'),
        clearValidationError: true,
        clearErrorCode: true,
      );
      return false;
    }
  }

  void updateLocalWorkProfile({String? workTitle, String? workCompany}) {
    final user = state.user;
    if (user == null) return;
    state = state.copyWith(
      user: user.copyWith(
        workTitle: workTitle,
        workCompany: workCompany,
        clearWorkTitle: workTitle == null || workTitle.trim().isEmpty,
        clearWorkCompany: workCompany == null || workCompany.trim().isEmpty,
      ),
    );
  }

  Future<void> _applyPreferredLocale(UserModel? user) async {
    final localeCode = switch (user?.preferredLocale?.trim().toLowerCase()) {
      'ar' => 'ar',
      'en' => 'en',
      _ => null,
    };
    if (localeCode == null) return;
    await ref
        .read(appSettingsControllerProvider.notifier)
        .applyRemoteLocale(Locale(localeCode));
  }

  String _mapLoginError(DioException e) {
    return mapLoginDioErrorForUser(e);
  }

  String _mapRegisterError(DioException e) {
    return mapDioError(
      e,
      fallback: 'Account creation failed.',
      appendRequestId: true,
    );
  }

  String _mapOwnerRegisterError(DioException e) {
    return mapDioError(
      e,
      fallback: 'Owner account creation failed.',
      customMessages: {
        'OWNER_ALREADY_HAS_MERCHANT': resolveLocalizedText(
          (l10n) => l10n.addMerchantOwnerAlreadyLinked,
        ),
        'OWNER_CONFLICT': resolveLocalizedText(
          (l10n) => l10n.addMerchantOwnerConflict,
        ),
        'OWNER_NOT_FOUND': resolveLocalizedText(
          (l10n) => l10n.addMerchantOwnerNotFound,
        ),
      },
      appendRequestId: true,
    );
  }

  String _mapDeliveryRegisterError(DioException e) {
    return mapDioError(
      e,
      fallback: 'Taxi captain account creation failed.',
      appendRequestId: true,
    );
  }

  String _mapUpdateAccountError(DioException e) {
    return mapDioError(
      e,
      fallback: 'Unable to update account details.',
      customMessages: const {
        'PIN_UNCHANGED': 'The new PIN must be different from the current one.',
        'NO_CHANGES': 'No changes were detected.',
      },
      appendRequestId: true,
    );
  }
}
