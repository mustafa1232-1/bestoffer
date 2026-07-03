import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppFlavor {
  user,
  store,
  delivery,
  taxiCaptain,
  company,
}

extension AppFlavorX on AppFlavor {
  String get key => switch (this) {
    AppFlavor.user => 'user',
    AppFlavor.store => 'store',
    AppFlavor.delivery => 'delivery',
    AppFlavor.taxiCaptain => 'taxi_captain',
    AppFlavor.company => 'company',
  };

  String get storageScope => key;

  String get clientPlatformTag => 'flutter:$key';

  String get displayName => switch (this) {
    AppFlavor.user => 'user',
    AppFlavor.store => 'store',
    AppFlavor.delivery => 'delivery',
    AppFlavor.taxiCaptain => 'taxi_captain',
    AppFlavor.company => 'company',
  };

  bool get isCompanySurface => this == AppFlavor.company;
}

class AppFlavorContext {
  static AppFlavor _current = AppFlavor.user;

  static AppFlavor get current => _current;

  static void setCurrent(AppFlavor flavor) {
    _current = flavor;
  }
}

final appFlavorProvider = Provider<AppFlavor>((ref) => AppFlavorContext.current);

