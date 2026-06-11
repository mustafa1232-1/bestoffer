// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/platform/ipos_printer_bridge.dart';
import '../../../core/utils/store_printer_settings.dart';
import '../printing/receipt_printer_service.dart';
import '../printing/ui/receipt_preview_dialog.dart';

class StorePrinterSettingsScreen extends StatefulWidget {
  const StorePrinterSettingsScreen({super.key});

  @override
  State<StorePrinterSettingsScreen> createState() =>
      _StorePrinterSettingsScreenState();
}

class _StorePrinterSettingsScreenState
    extends State<StorePrinterSettingsScreen> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _testing = false;

  PrintingInfo? _printingInfo;
  IposPrinterStatus? _iposStatus;
  List<Printer> _printers = const [];

  StorePrinterMode _mode = StorePrinterMode.system;
  String? _selectedSystemPrinterUrl;
  String? _savedSystemPrinterUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  bool get _useArabicLabels =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cfg = await StorePrinterSettings.readConfig();
      final info = await Printing.info();
      final printers = await Printing.listPrinters();
      final ipos = Platform.isAndroid
          ? await IposPrinterBridge.getStatus()
          : null;

      _mode = cfg.mode;
      _selectedSystemPrinterUrl = cfg.systemPrinter?.url;
      _savedSystemPrinterUrl = cfg.systemPrinter?.url;
      _hostController.text = cfg.networkHost;
      _portController.text = '${cfg.networkPort}';

      if (_mode == StorePrinterMode.system &&
          !info.canListPrinters &&
          cfg.systemPrinter == null &&
          ipos?.bondedIposFound == true) {
        _mode = StorePrinterMode.iposBluetooth;
      } else if (_mode == StorePrinterMode.system &&
          !info.canListPrinters &&
          cfg.systemPrinter == null) {
        _mode = StorePrinterMode.networkEscPos;
      }

      if (!mounted) return;
      setState(() {
        _printingInfo = info;
        _iposStatus = ipos;
        _printers = printers;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _printingInfo = null;
        _iposStatus = null;
        _printers = const [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _sanitizePort() {
    final parsed = int.tryParse(_portController.text.trim()) ?? 9100;
    if (parsed < 1 || parsed > 65535) return 9100;
    return parsed;
  }

  String _printerStatusText({
    required bool value,
    required String enabledText,
    required String disabledText,
  }) {
    return value ? enabledText : disabledText;
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      StorePrinterSelection? selected;
      if (_selectedSystemPrinterUrl != null) {
        final printer = _printers.cast<Printer?>().firstWhere(
          (p) => p?.url == _selectedSystemPrinterUrl,
          orElse: () => null,
        );
        if (printer != null) {
          selected = StorePrinterSelection(
            url: printer.url,
            name: printer.name,
          );
        } else {
          selected = StorePrinterSelection(
            url: _selectedSystemPrinterUrl!,
            name: _selectedSystemPrinterUrl!,
          );
        }
      }

      final config = StorePrinterConfig(
        mode: _mode,
        systemPrinter: selected,
        networkHost: _hostController.text.trim(),
        networkPort: _sanitizePort(),
      );
      await StorePrinterSettings.saveConfig(config);

      if (!mounted) return;
      setState(() => _savedSystemPrinterUrl = _selectedSystemPrinterUrl);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.ownerPrinterSettingsSaved)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testPrint() async {
    final l10n = context.l10n;
    setState(() => _testing = true);
    try {
      await _save();
      if (!mounted) return;
      final result = await ReceiptPrinterService.instance.printTest(
        useArabicLabels: _useArabicLabels,
        appTitle: 'MASLAKI',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? l10n.ownerPrinterTestReceiptSent
                : l10n.ownerPrinterTestFailed(result.message),
          ),
        ),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _printSampleInvoice() async {
    final l10n = context.l10n;
    setState(() => _testing = true);
    try {
      await _save();
      if (!mounted) return;
      final result = await ReceiptPrinterService.instance.printSampleInvoice(
        useArabicLabels: _useArabicLabels,
        appTitle: 'MASLAKI',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? l10n.ownerPrinterSampleSent
                : l10n.ownerPrinterSampleFailed(result.message),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _previewSampleInvoice() async {
    final document = await ReceiptPrinterService.instance.buildSampleDocument(
      useArabicLabels: _useArabicLabels,
      appTitle: 'MASLAKI',
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ReceiptPreviewDialog(
        title: context.l10n.ownerPrinterSamplePreviewTitle,
        document: document,
      ),
    );
  }

  Future<void> _showLogs() async {
    final jobs = ReceiptPrinterService.instance.history;
    final l10n = context.l10n;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: jobs.isEmpty
              ? Center(child: Text(l10n.ownerPrinterNoLogs))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: jobs.length,
                  itemBuilder: (_, index) {
                    final job = jobs[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${job.adapterId} • ${job.createdAt.toLocal()}',
                            ),
                            const SizedBox(height: 4),
                            Text(job.message),
                            const SizedBox(height: 6),
                            ...job.logs
                                .take(8)
                                .map(
                                  (e) => Text(
                                    '${e.ok ? '✓' : '✕'} ${e.stage}: ${e.message}',
                                  ),
                                ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _clearSystemSelection() async {
    setState(() {
      _selectedSystemPrinterUrl = null;
      _savedSystemPrinterUrl = null;
    });
    await _save();
  }

  Future<void> _requestPrinterPermissions() async {
    if (!Platform.isAndroid) return;

    final permissions = <Permission>[
      Permission.locationWhenInUse,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ];

    final result = await permissions.request();
    if (!mounted) return;

    final denied = result.entries
        .where((e) => !(e.value.isGranted || e.value.isLimited))
        .map((e) => e.key.toString())
        .toList();

    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          denied.isEmpty
              ? l10n.ownerPrinterPermissionsGranted
              : l10n.ownerPrinterPermissionsDenied(denied.join(', ')),
        ),
      ),
    );
    await _load();
  }

  Future<void> _openAndroidSettings(String action) async {
    if (!Platform.isAndroid) return;
    try {
      final intent = AndroidIntent(action: action);
      await intent.launch();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabledText = l10n.ownerPrinterStatusEnabled;
    final disabledText = l10n.ownerPrinterStatusDisabled;
    final foundText = l10n.ownerPrinterStatusFound;
    final notFoundText = l10n.ownerPrinterStatusNotFound;
    final installedText = l10n.ownerPrinterStatusInstalled;
    final notInstalledText = l10n.ownerPrinterStatusNotInstalled;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ownerPrinterSettingsTitle),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              children: [
                _SectionCard(
                  title: l10n.ownerPrinterSectionMode,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RadioListTile<StorePrinterMode>(
                        value: StorePrinterMode.system,
                        groupValue: _mode,
                        title: Text(l10n.ownerPrinterModeSystem),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _mode = v);
                        },
                      ),
                      RadioListTile<StorePrinterMode>(
                        value: StorePrinterMode.networkEscPos,
                        groupValue: _mode,
                        title: Text(l10n.ownerPrinterModeNetwork),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _mode = v);
                        },
                      ),
                      if (Platform.isAndroid)
                        RadioListTile<StorePrinterMode>(
                          value: StorePrinterMode.iposBluetooth,
                          groupValue: _mode,
                          title: Text(l10n.ownerPrinterModeIpos),
                          subtitle: Text(l10n.ownerPrinterModeIposSubtitle),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _mode = v);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (_printingInfo != null)
                  _SectionCard(
                    title: l10n.ownerPrinterSectionDeviceCapabilities,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'directPrint: ${_printingInfo!.directPrint} | canListPrinters: ${_printingInfo!.canListPrinters}',
                        ),
                        if (Platform.isAndroid) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _requestPrinterPermissions,
                                icon: const Icon(Icons.verified_user_outlined),
                                label: Text(
                                  l10n.ownerPrinterRequestPermissions,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _openAndroidSettings(
                                  'android.settings.BLUETOOTH_SETTINGS',
                                ),
                                icon: const Icon(Icons.bluetooth),
                                label: Text(l10n.ownerPrinterBluetoothSettings),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _openAndroidSettings(
                                  'android.settings.PRINT_SETTINGS',
                                ),
                                icon: const Icon(Icons.print),
                                label: Text(l10n.ownerPrinterPrintSettings),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_mode == StorePrinterMode.system) ...[
                  const SizedBox(height: 10),
                  _SectionCard(
                    title: l10n.ownerPrinterSectionSystemSelection,
                    child: _buildSystemPrinters(context),
                  ),
                ],
                if (_mode == StorePrinterMode.networkEscPos) ...[
                  const SizedBox(height: 10),
                  _SectionCard(
                    title: l10n.ownerPrinterSectionNetworkSetup,
                    child: Column(
                      children: [
                        TextField(
                          controller: _hostController,
                          decoration: InputDecoration(
                            labelText: l10n.ownerPrinterNetworkIpLabel,
                            hintText: '192.168.1.50',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.ownerPrinterPortLabel,
                            hintText: '9100',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            l10n.ownerPrinterCommonPortHint,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_mode == StorePrinterMode.iposBluetooth) ...[
                  const SizedBox(height: 10),
                  _SectionCard(
                    title: l10n.ownerPrinterSectionIposStatus,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.ownerPrinterBluetoothLine(
                            _printerStatusText(
                              value: _iposStatus?.bluetoothEnabled == true,
                              enabledText: enabledText,
                              disabledText: disabledText,
                            ),
                          ),
                        ),
                        Text(
                          l10n.ownerPrinterBondedLine(
                            _printerStatusText(
                              value: _iposStatus?.bondedIposFound == true,
                              enabledText: foundText,
                              disabledText: notFoundText,
                            ),
                          ),
                        ),
                        if ((_iposStatus?.deviceName ?? '').isNotEmpty)
                          Text(
                            l10n.ownerPrinterDeviceName(
                              _iposStatus!.deviceName!,
                            ),
                          ),
                        if ((_iposStatus?.deviceAddress ?? '').isNotEmpty)
                          Text(
                            l10n.ownerPrinterDeviceAddress(
                              _iposStatus!.deviceAddress!,
                            ),
                          ),
                        Text(
                          l10n.ownerPrinterServiceLine(
                            _printerStatusText(
                              value: _iposStatus?.iposServiceInstalled == true,
                              enabledText: installedText,
                              disabledText: notInstalledText,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(l10n.ownerPrinterIposPairingHint),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving || _testing ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(l10n.commonSave),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saving || _testing ? null : _testPrint,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.print_rounded),
                        label: Text(
                          _testing
                              ? l10n.ownerPrinterTesting
                              : l10n.ownerPrinterTestPrint,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving || _testing
                            ? null
                            : _previewSampleInvoice,
                        icon: const Icon(Icons.visibility_outlined),
                        label: Text(l10n.ownerPrinterPreviewSample),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving || _testing
                            ? null
                            : _printSampleInvoice,
                        icon: const Icon(Icons.description_outlined),
                        label: Text(l10n.ownerPrinterPrintSample),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _showLogs,
                    icon: const Icon(Icons.bug_report_outlined),
                    label: Text(l10n.ownerPrinterLogs),
                  ),
                ),
                if (_mode == StorePrinterMode.system) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _saving || _testing
                          ? null
                          : _clearSystemSelection,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l10n.ownerPrinterClearSystemPrinter),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildSystemPrinters(BuildContext context) {
    final l10n = context.l10n;
    if (_printers.isEmpty) {
      return Text(l10n.ownerPrinterNoSystemPrinters);
    }

    return Column(
      children: _printers.map((printer) {
        final selected = printer.url == _selectedSystemPrinterUrl;
        final saved = printer.url == _savedSystemPrinterUrl;
        return RadioListTile<String>(
          value: printer.url,
          groupValue: _selectedSystemPrinterUrl,
          onChanged: (v) => setState(() => _selectedSystemPrinterUrl = v),
          title: Text(printer.name),
          subtitle: Text(
            [
              if ((printer.model ?? '').isNotEmpty) printer.model!,
              if ((printer.location ?? '').isNotEmpty) printer.location!,
              if (saved) l10n.ownerPrinterSaved,
            ].join(' • '),
          ),
          selected: selected,
        );
      }).toList(),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
