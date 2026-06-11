import 'package:intl/intl.dart';

String formatIqd(num amount, {bool withCode = true}) {
  final locale = Intl.getCurrentLocale().toLowerCase().startsWith('en')
      ? 'en'
      : 'ar';
  final formatter = NumberFormat.currency(
    locale: locale,
    name: 'IQD',
    symbol: withCode ? 'IQD' : '',
    decimalDigits: 0,
    customPattern: withCode ? null : '#,##0',
  );
  final text = formatter.format(amount);
  return withCode ? text.trim() : text.replaceAll('\u00A0', '').trim();
}
