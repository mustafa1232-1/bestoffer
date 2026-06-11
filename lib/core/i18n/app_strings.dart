import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../settings/app_settings_controller.dart';

class AppStrings {
  final Locale locale;
  final AppLocalizations l10n;

  const AppStrings._(this.locale, this.l10n);

  factory AppStrings(Locale locale) {
    final normalized = locale.languageCode.toLowerCase().startsWith('en')
        ? const Locale('en')
        : const Locale('ar');
    return AppStrings._(normalized, lookupAppLocalizations(normalized));
  }

  bool get isEnglish => locale.languageCode.toLowerCase() == 'en';

  String t(String key) {
    switch (key) {
      case 'settings':
        return l10n.commonSettings;
      case 'logout':
        return l10n.commonLogout;
      case 'myOrders':
        return l10n.customerDiscoveryOrders;
      case 'customerHomeTitle':
        return l10n.customerHomeTitle;
      case 'backofficeMerchantsTitle':
        return l10n.adminBackofficeMerchantsTitle;
      case 'ownerDashboard':
        return l10n.ownerDashboardTitle;
      case 'deliveryDashboard':
        return l10n.deliveryDashboardTitle;
      case 'drawerWorkspace':
        return l10n.drawerWorkspace;
      case 'drawerHome':
        return l10n.drawerHome;
      case 'drawerRefresh':
        return l10n.drawerRefresh;
      case 'drawerCart':
        return l10n.drawerCart;
      case 'drawerAddresses':
        return l10n.drawerAddresses;
      case 'drawerCreateMerchant':
        return l10n.drawerCreateMerchant;
      case 'drawerAddProduct':
        return l10n.drawerAddProduct;
      case 'drawerMerchantsSub':
        return l10n.drawerMerchantsSub;
      case 'drawerOwnerSub':
        return l10n.drawerOwnerSub;
      case 'drawerOwnerPendingSub':
        return l10n.drawerOwnerPendingSub;
      case 'drawerOwnerPendingStatus':
        return l10n.drawerOwnerPendingStatus;
      case 'drawerDeliverySub':
        return l10n.drawerDeliverySub;
      case 'ownerApprovalPendingTitle':
        return l10n.ownerApprovalPendingTitle;
      case 'language':
        return l10n.commonLanguage;
      case 'currentLanguage':
        return l10n.settingsCurrentLanguage;
      case 'arabic':
        return l10n.commonArabic;
      case 'english':
        return l10n.commonEnglish;
      case 'login':
        return l10n.authLogin;
      case 'createUserAccount':
        return l10n.authCreateUserAccount;
      case 'createOwnerAccount':
        return l10n.authCreateOwnerAccount;
      case 'phoneLabel':
        return l10n.authPhoneLabel;
      case 'pinLabel':
        return l10n.authPinLabel;
      case 'loginTagline':
        return l10n.authLoginTagline;
      case 'accountSecurity':
        return l10n.settingsAccountSecurity;
      case 'accountSecurityHintAuthed':
        return l10n.settingsAccountSecurityHintAuthed;
      case 'loginRequiredAccount':
        return l10n.settingsLoginRequiredAccount;
      case 'currentPin':
        return l10n.settingsCurrentPin;
      case 'newPhone':
        return l10n.settingsNewPhone;
      case 'newPin':
        return l10n.settingsNewPin;
      case 'confirmNewPin':
        return l10n.settingsConfirmNewPin;
      case 'changePhone':
        return l10n.settingsChangePhone;
      case 'changePin':
        return l10n.settingsChangePin;
      case 'savePhone':
        return l10n.settingsSavePhone;
      case 'savePin':
        return l10n.settingsSavePin;
      case 'phoneUpdated':
        return l10n.settingsPhoneUpdated;
      case 'pinUpdated':
        return l10n.settingsPinUpdated;
      case 'enterCurrentPin':
        return l10n.settingsEnterCurrentPin;
      case 'enterPhone':
        return l10n.settingsEnterPhone;
      case 'pinMinDigits':
        return l10n.settingsPinMinDigits;
      case 'pinMismatch':
        return l10n.settingsPinMismatch;
      default:
        return key;
    }
  }
}

final appStringsProvider = Provider<AppStrings>((ref) {
  final locale = ref.watch(
    appSettingsControllerProvider.select((s) => s.locale),
  );
  return AppStrings(locale);
});
