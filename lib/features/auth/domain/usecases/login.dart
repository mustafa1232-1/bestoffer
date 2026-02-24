import '../auth_repo.dart';
import '../../models/user_model.dart';

class LoginUseCase {
  final AuthRepo repo;
  LoginUseCase(this.repo);

  Future<UserModel> call({required String phone, required String pin}) {
    return repo.login(phone: phone, pin: pin);
  }
}
