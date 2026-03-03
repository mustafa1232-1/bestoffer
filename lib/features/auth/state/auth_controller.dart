import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../../../core/files/local_image_file.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/auth_api.dart';
import '../data/auth_repo_impl.dart';
import '../domain/auth_repo.dart';
import '../models/user_model.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

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
  final String? error;

  const AuthState({this.loading = false, this.user, this.token, this.error});

  bool get isAuthed => token != null && token!.isNotEmpty;

  bool get isAdmin => _resolveRole() == 'admin';

  bool get isOwner => _resolveRole() == 'owner';

  bool get isDelivery => _resolveRole() == 'delivery';

  bool get isDeputyAdmin => _resolveRole() == 'deputy_admin';

  bool get isBackoffice => isAdmin || isDeputyAdmin;

  bool get isSuperAdmin {
    if (user?.isSuperAdmin == true) return true;

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

  AuthState copyWith({
    bool? loading,
    UserModel? user,
    String? token,
    String? error,
  }) {
    return AuthState(
      loading: loading ?? this.loading,
      user: user ?? this.user,
      token: token ?? this.token,
      error: error,
    );
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref),
);

class AuthController extends StateNotifier<AuthState> {
  final Ref ref;

  AuthController(this.ref) : super(const AuthState());

  Future<void> bootstrap() async {
    final store = ref.read(secureStoreProvider);
    final token = await store.readToken();
    if (token == null || token.isEmpty) return;

    state = state.copyWith(token: token);

    try {
      final user = await ref.read(authRepoProvider).me();
      state = state.copyWith(user: user);
    } catch (_) {
      await store.clear();
      state = const AuthState();
    }
  }

  Future<void> login(String phone, String pin) async {
    state = state.copyWith(loading: true, error: null);

    try {
      final user = await ref
          .read(authRepoProvider)
          .login(phone: phone, pin: pin);
      final token = await ref.read(secureStoreProvider).readToken();
      state = state.copyWith(loading: false, user: user, token: token);
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapLoginError(e));
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapAnyError(e, fallback: 'Login failed. Please try again.'),
      );
    }
  }

  Future<void> register(
    Map<String, dynamic> dto, {
    LocalImageFile? imageFile,
  }) async {
    state = state.copyWith(loading: true, error: null);

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
      state = state.copyWith(loading: false, user: user, token: token);
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapRegisterError(e));
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapAnyError(e, fallback: 'Account creation failed.'),
      );
    }
  }

  Future<void> registerOwner(
    Map<String, dynamic> dto, {
    LocalImageFile? ownerImageFile,
    LocalImageFile? merchantImageFile,
  }) async {
    state = state.copyWith(loading: true, error: null);

    try {
      final user = await ref
          .read(authRepoProvider)
          .registerOwner(
            fullName: dto['fullName']!.trim(),
            phone: dto['phone']!.trim(),
            pin: dto['pin']!.trim(),
            block: dto['block']!.trim(),
            buildingNumber: dto['buildingNumber']!.trim(),
            apartment: dto['apartment']!.trim(),
            merchantName: dto['merchantName']!.trim(),
            merchantType: dto['merchantType']!.trim(),
            merchantDescription: dto['merchantDescription']!.trim(),
            merchantPhone: dto['merchantPhone']!.trim(),
            merchantImageUrl: dto['merchantImageUrl']!.trim(),
            analyticsConsentAccepted: dto['analyticsConsentAccepted'] == true,
            analyticsConsentVersion:
                '${dto['analyticsConsentVersion'] ?? 'analytics_v1'}',
            ownerImageFile: ownerImageFile,
            merchantImageFile: merchantImageFile,
          );

      final token = await ref.read(secureStoreProvider).readToken();
      state = state.copyWith(loading: false, user: user, token: token);
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapOwnerRegisterError(e));
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapAnyError(e, fallback: 'Owner account creation failed.'),
      );
    }
  }

  Future<bool> registerDelivery(
    Map<String, dynamic> dto, {
    LocalImageFile? profileImageFile,
    LocalImageFile? carImageFile,
  }) async {
    state = state.copyWith(loading: true, error: null);

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
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(
        loading: false,
        error: _mapDeliveryRegisterError(e),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapAnyError(
          e,
          fallback: 'Taxi captain account creation failed.',
        ),
      );
      return false;
    }
  }

  Future<void> logout() async {
    await ref.read(authRepoProvider).logout();
    state = const AuthState();
  }

  Future<bool> updateAccount({
    required String currentPin,
    String? newPhone,
    String? newPin,
  }) async {
    state = state.copyWith(loading: true, error: null);

    try {
      final updated = await ref
          .read(authRepoProvider)
          .updateAccount(
            currentPin: currentPin,
            newPhone: newPhone,
            newPin: newPin,
          );
      state = state.copyWith(loading: false, user: updated, error: null);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapUpdateAccountError(e));
      return false;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: mapAnyError(e, fallback: 'Unable to update account details.'),
      );
      return false;
    }
  }

  String _mapLoginError(DioException e) {
    return mapDioError(
      e,
      fallback: 'Login failed. Please check your phone and PIN.',
      customMessages: const {
        'DELIVERY_ACCOUNT_PENDING_APPROVAL':
            'Your account is pending admin approval.',
      },
      appendRequestId: true,
    );
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
