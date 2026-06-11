import 'package:printing/printing.dart';

import '../storage/secure_storage.dart';

enum StorePrinterMode { system, networkEscPos, iposBluetooth }

class StorePrinterSelection {
  final String url;
  final String name;

  const StorePrinterSelection({required this.url, required this.name});
}

class StorePrinterConfig {
  final StorePrinterMode mode;
  final StorePrinterSelection? systemPrinter;
  final String networkHost;
  final int networkPort;

  const StorePrinterConfig({
    required this.mode,
    required this.systemPrinter,
    required this.networkHost,
    required this.networkPort,
  });

  const StorePrinterConfig.defaults()
    : mode = StorePrinterMode.system,
      systemPrinter = null,
      networkHost = '',
      networkPort = 9100;
}

class StorePrinterSettings {
  static const _modeKey = 'owner_printer_mode';
  static const _printerUrlKey = 'owner_selected_printer_url';
  static const _printerNameKey = 'owner_selected_printer_name';
  static const _networkHostKey = 'owner_network_printer_host';
  static const _networkPortKey = 'owner_network_printer_port';

  static final SecureStore _store = SecureStore();

  static Future<StorePrinterConfig> readConfig() async {
    final modeRaw = (await _store.readString(_modeKey))?.trim();
    final mode = modeRaw == 'network'
        ? StorePrinterMode.networkEscPos
        : modeRaw == 'ipos'
        ? StorePrinterMode.iposBluetooth
        : StorePrinterMode.system;

    final url = (await _store.readString(_printerUrlKey))?.trim() ?? '';
    final name = (await _store.readString(_printerNameKey))?.trim() ?? '';
    final systemPrinter = url.isEmpty
        ? null
        : StorePrinterSelection(url: url, name: name.isEmpty ? url : name);

    final networkHost =
        (await _store.readString(_networkHostKey))?.trim() ?? '';
    final networkPortRaw =
        (await _store.readString(_networkPortKey))?.trim() ?? '';
    final networkPort = int.tryParse(networkPortRaw) ?? 9100;

    return StorePrinterConfig(
      mode: mode,
      systemPrinter: systemPrinter,
      networkHost: networkHost,
      networkPort: networkPort,
    );
  }

  static Future<void> saveConfig(StorePrinterConfig config) async {
    await _store.writeString(
      _modeKey,
      config.mode == StorePrinterMode.networkEscPos
          ? 'network'
          : config.mode == StorePrinterMode.iposBluetooth
          ? 'ipos'
          : 'system',
    );

    if (config.systemPrinter == null) {
      await _store.delete(_printerUrlKey);
      await _store.delete(_printerNameKey);
    } else {
      await _store.writeString(_printerUrlKey, config.systemPrinter!.url);
      await _store.writeString(_printerNameKey, config.systemPrinter!.name);
    }

    await _store.writeString(_networkHostKey, config.networkHost.trim());
    await _store.writeString(_networkPortKey, '${config.networkPort}');
  }

  static Future<StorePrinterSelection?> readSelection() async {
    final cfg = await readConfig();
    return cfg.systemPrinter;
  }

  static Future<void> saveSelection(Printer printer) async {
    final cfg = await readConfig();
    await saveConfig(
      StorePrinterConfig(
        mode: cfg.mode,
        systemPrinter: StorePrinterSelection(
          url: printer.url,
          name: printer.name,
        ),
        networkHost: cfg.networkHost,
        networkPort: cfg.networkPort,
      ),
    );
  }

  static Future<void> clearSelection() async {
    final cfg = await readConfig();
    await saveConfig(
      StorePrinterConfig(
        mode: cfg.mode,
        systemPrinter: null,
        networkHost: cfg.networkHost,
        networkPort: cfg.networkPort,
      ),
    );
  }
}
