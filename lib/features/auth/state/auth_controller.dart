import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../../../core/constants/api.dart';
import '../../../core/files/local_image_file.dart';
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
      state = state.copyWith(loading: false, error: 'فشل تسجيل الدخول: $e');
    }
  }

  Future<void> register(
    Map<String, String> dto, {
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
            imageFile: imageFile,
          );

      final token = await ref.read(secureStoreProvider).readToken();
      state = state.copyWith(loading: false, user: user, token: token);
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapRegisterError(e));
    } catch (_) {
      state = state.copyWith(loading: false, error: 'فشل إنشاء الحساب');
    }
  }

  Future<void> registerOwner(
    Map<String, String> dto, {
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
            ownerImageFile: ownerImageFile,
            merchantImageFile: merchantImageFile,
          );

      final token = await ref.read(secureStoreProvider).readToken();
      state = state.copyWith(loading: false, user: user, token: token);
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapOwnerRegisterError(e));
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'فشل إنشاء حساب صاحب المتجر',
      );
    }
  }

  Future<void> registerDelivery(
    Map<String, String> dto, {
    LocalImageFile? imageFile,
  }) async {
    state = state.copyWith(loading: true, error: null);

    try {
      final user = await ref
          .read(authRepoProvider)
          .registerDelivery(
            fullName: dto['fullName']!.trim(),
            phone: dto['phone']!.trim(),
            pin: dto['pin']!.trim(),
            block: dto['block']!.trim(),
            buildingNumber: dto['buildingNumber']!.trim(),
            apartment: dto['apartment']!.trim(),
            imageFile: imageFile,
          );

      final token = await ref.read(secureStoreProvider).readToken();
      state = state.copyWith(loading: false, user: user, token: token);
    } on DioException catch (e) {
      state = state.copyWith(
        loading: false,
        error: _mapDeliveryRegisterError(e),
      );
    } catch (_) {
      state = state.copyWith(loading: false, error: 'فشل إنشاء حساب الدلفري');
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
    } catch (_) {
      state = state.copyWith(loading: false, error: 'تعذر تحديث بيانات الحساب');
      return false;
    }
  }

  String _mapLoginError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final message = map['message'];
      if (message == 'INVALID_CREDENTIALS') return 'رقم الهاتف أو PIN غير صحيح';
      if (message == 'VALIDATION_ERROR') return 'تحقق من صيغة رقم الهاتف وPIN';
      if (message is String && message.isNotEmpty) return message;
    }
    if (data is String) {
      if (data.contains('INVALID_CREDENTIALS')) {
        return 'رقم الهاتف أو PIN غير صحيح';
      }
      if (data.contains('VALIDATION_ERROR')) {
        return 'تحقق من صيغة رقم الهاتف وPIN';
      }
    }

    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      final baseUrl = ref.read(dioClientProvider).dio.options.baseUrl;
      final fallbacks = Api.fallbackBaseUrls.join(' , ');
      return 'تعذر الاتصال بالخادم ($baseUrl). عناوين المحاولة: $fallbacks';
    }

    return 'فشل تسجيل الدخول';
  }

  String _mapRegisterError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final message = map['message'];
      if (message == 'PHONE_EXISTS') return 'رقم الهاتف مسجل مسبقًا';
      if (message == 'VALIDATION_ERROR') return 'تحقق من صيغة رقم الهاتف وPIN';
      if (message is String && message.isNotEmpty) return message;
    }
    if (data is String) {
      if (data.contains('INVALID_CREDENTIALS')) {
        return 'رقم الهاتف أو PIN غير صحيح';
      }
      if (data.contains('VALIDATION_ERROR')) {
        return 'تحقق من صيغة رقم الهاتف وPIN';
      }
    }
    return 'فشل إنشاء الحساب';
  }

  String _mapOwnerRegisterError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final message = map['message'];
      if (message == 'PHONE_EXISTS') return 'رقم الهاتف مسجل مسبقًا';
      if (message == 'VALIDATION_ERROR') return 'تحقق من صيغة رقم الهاتف وPIN';
      if (message is String && message.isNotEmpty) return message;
    }
    if (data is String) {
      if (data.contains('INVALID_CREDENTIALS')) {
        return 'رقم الهاتف أو PIN غير صحيح';
      }
      if (data.contains('VALIDATION_ERROR')) {
        return 'تحقق من صيغة رقم الهاتف وPIN';
      }
    }
    return 'فشل إنشاء حساب صاحب المتجر';
  }

  String _mapDeliveryRegisterError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final message = map['message'];
      if (message == 'PHONE_EXISTS') return 'رقم الهاتف مسجل مسبقًا';
      if (message == 'VALIDATION_ERROR') return 'تحقق من صيغة رقم الهاتف وPIN';
      if (message is String && message.isNotEmpty) return message;
    }
    if (data is String) {
      if (data.contains('INVALID_CREDENTIALS')) {
        return 'رقم الهاتف أو PIN غير صحيح';
      }
      if (data.contains('VALIDATION_ERROR')) {
        return 'تحقق من صيغة رقم الهاتف وPIN';
      }
    }
    return 'فشل إنشاء حساب الدلفري';
  }

  String _mapUpdateAccountError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final message = map['message'];
      if (message == 'INVALID_CURRENT_PIN') {
        return '\u0627\u0644\u0631\u0645\u0632 \u0627\u0644\u062d\u0627\u0644\u064a \u063a\u064a\u0631 \u0635\u062d\u064a\u062d';
      }
      if (message == 'PHONE_EXISTS') {
        return '\u0631\u0642\u0645 \u0627\u0644\u0647\u0627\u062a\u0641 \u0645\u0633\u062a\u062e\u062f\u0645 \u0645\u0633\u0628\u0642\u0627';
      }
      if (message == 'PIN_UNCHANGED') {
        return 'PIN \u0627\u0644\u062c\u062f\u064a\u062f \u064a\u062c\u0628 \u0623\u0646 \u064a\u062e\u062a\u0644\u0641 \u0639\u0646 \u0627\u0644\u062d\u0627\u0644\u064a';
      }
      if (message == 'NO_CHANGES') {
        return '\u064a\u0631\u062c\u0649 \u0625\u062f\u062e\u0627\u0644 \u062a\u0639\u062f\u064a\u0644 \u0648\u0627\u062d\u062f \u0639\u0644\u0649 \u0627\u0644\u0623\u0642\u0644';
      }
      if (message == 'VALIDATION_ERROR') {
        return '\u062a\u062d\u0642\u0642 \u0645\u0646 \u0635\u064a\u063a\u0629 \u0631\u0642\u0645 \u0627\u0644\u0647\u0627\u062a\u0641 \u0648PIN';
      }
      if (message is String && message.isNotEmpty) return message;
    }
    return '\u062a\u0639\u0630\u0631 \u062a\u062d\u062f\u064a\u062b \u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u062d\u0633\u0627\u0628';
  }
}
