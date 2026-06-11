/// يمثل حالة أخطاء النموذج بعد دمج أخطاء التحقق المحلية وأخطاء الباكند.
class FormErrorState {
  final Map<String, String> fieldErrors;
  final String? formError;
  final String? firstInvalidField;

  const FormErrorState({
    this.fieldErrors = const <String, String>{},
    this.formError,
    this.firstInvalidField,
  });

  static const empty = FormErrorState();

  bool get hasAnyErrors =>
      fieldErrors.isNotEmpty || (formError != null && formError!.isNotEmpty);

  String? errorFor(String field) => fieldErrors[field];
}
