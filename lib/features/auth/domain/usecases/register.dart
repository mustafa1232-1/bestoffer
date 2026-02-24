import '../auth_repo.dart';
import '../../models/user_model.dart';

class RegisterUseCase {
  final AuthRepo repo;
  RegisterUseCase(this.repo);

  Future<UserModel> call({
    required String fullName,
    required String phone,
    required String pin,
    required String block,
    required String buildingNumber,
    required String apartment,
  }) {
    return repo.register(
      fullName: fullName,
      phone: phone,
      pin: pin,
      block: block,
      buildingNumber: buildingNumber,
      apartment: apartment,
    );
  }
}
