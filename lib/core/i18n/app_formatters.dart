import 'package:intl/intl.dart';

String formatCurrencyIqd(
  num amount, {
  required String localeCode,
  bool withCode = true,
}) {
  final locale = localeCode.toLowerCase().startsWith('en') ? 'en' : 'ar';
  final symbol = withCode ? 'IQD' : '';
  final formatter = NumberFormat.currency(
    locale: locale,
    name: 'IQD',
    symbol: symbol,
    decimalDigits: 0,
    customPattern: withCode ? null : '#,##0',
  );
  final text = formatter.format(amount);
  return withCode ? text.trim() : text.replaceAll('\u00A0', '').trim();
}

String formatNumberLocalized(num value, {required String localeCode}) {
  final locale = localeCode.toLowerCase().startsWith('en') ? 'en' : 'ar';
  return NumberFormat.decimalPattern(locale).format(value);
}

String formatShortDateLocalized(
  DateTime value, {
  required String localeCode,
}) {
  final locale = localeCode.toLowerCase().startsWith('en') ? 'en' : 'ar';
  return DateFormat.yMd(locale).format(value.toLocal());
}

String formatDateTimeLocalized(
  DateTime value, {
  required String localeCode,
}) {
  final locale = localeCode.toLowerCase().startsWith('en') ? 'en' : 'ar';
  return DateFormat.yMd(locale).add_jm().format(value.toLocal());
}
