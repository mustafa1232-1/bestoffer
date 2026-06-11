import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/forms/inline_field_error_text.dart';
import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../l10n/app_localizations.dart';

class BasmayaAddressCatalog {
  static const List<String> groupOptions = <String>['A', 'B'];

  static final List<String> blockOptions = <String>[
    ...List<String>.generate(9, (i) => 'A${i + 1}'),
    ...List<String>.generate(8, (i) => 'B${i + 1}'),
  ];

  static final List<String> apartmentOptions = <String>[
    ...List<String>.generate(
      12,
      (i) => 'G${(i + 1).toString().padLeft(2, '0')}',
    ),
    ...List<String>.generate(9 * 12, (i) {
      final floor = (i ~/ 12) + 1;
      final unit = (i % 12) + 1;
      return '$floor${unit.toString().padLeft(2, '0')}';
    }),
  ];

  static List<String> blockOptionsForGroup(String? group) {
    if (group == 'A') {
      return List<String>.generate(9, (i) => 'A${i + 1}');
    }
    if (group == 'B') {
      return List<String>.generate(8, (i) => 'B${i + 1}');
    }
    return const <String>[];
  }

  static List<String> buildingOptionsForBlock(String? block) {
    final parsed = _parseBlock(block);
    if (parsed == null) return const <String>[];
    final count = parsed.letter == 'A' ? 12 : 22;
    return List<String>.generate(
      count,
      (index) =>
          '${parsed.letter}${parsed.sector}${(index + 1).toString().padLeft(2, '0')}',
    );
  }

  static String? validateSelection({
    required String? block,
    required String? buildingNumber,
    required String? apartment,
    AppLocalizations? l10n,
  }) {
    final strings = l10n ?? _lookupCurrentL10n();
    final normalizedBlock = _normalizeCode(block);
    if (!blockOptions.contains(normalizedBlock)) {
      return strings.basmayaValidationSectorInvalid;
    }

    final buildings = buildingOptionsForBlock(normalizedBlock);
    final normalizedBuilding = _normalizeCode(buildingNumber);
    if (!buildings.contains(normalizedBuilding)) {
      return strings.basmayaValidationBuildingInvalid(normalizedBlock);
    }

    final normalizedApartment = _normalizeCode(apartment);
    if (!apartmentOptions.contains(normalizedApartment)) {
      return strings.basmayaValidationApartmentInvalid;
    }

    return null;
  }

  static String _normalizeCode(String? value) {
    return (value ?? '').trim().toUpperCase();
  }

  static _ParsedBlock? _parseBlock(String? value) {
    final normalized = _normalizeCode(value);
    final match = RegExp(r'^([AB])([1-9])$').firstMatch(normalized);
    if (match == null) return null;
    final letter = match.group(1)!;
    final sector = int.parse(match.group(2)!);
    if (letter == 'B' && sector > 8) return null;
    return _ParsedBlock(letter: letter, sector: sector);
  }

  static AppLocalizations _lookupCurrentL10n() {
    final localeCode = Intl.getCurrentLocale().toLowerCase();
    final locale = localeCode.startsWith('en')
        ? const Locale('en')
        : const Locale('ar');
    return lookupAppLocalizations(locale);
  }
}

class BasmayaAddressSelector extends StatelessWidget {
  final String? selectedBlock;
  final String? selectedBuilding;
  final String? selectedApartment;
  final ValueChanged<String?> onBlockChanged;
  final ValueChanged<String?> onBuildingChanged;
  final ValueChanged<String?> onApartmentChanged;
  final bool enabled;
  final String? blockError;
  final String? buildingError;
  final String? apartmentError;
  final String? generalError;

  const BasmayaAddressSelector({
    super.key,
    required this.selectedBlock,
    required this.selectedBuilding,
    required this.selectedApartment,
    required this.onBlockChanged,
    required this.onBuildingChanged,
    required this.onApartmentChanged,
    this.enabled = true,
    this.blockError,
    this.buildingError,
    this.apartmentError,
    this.generalError,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selectedGroup = (selectedBlock ?? '').startsWith('B')
        ? 'B'
        : (selectedBlock ?? '').startsWith('A')
            ? 'A'
            : null;
    final sectors = BasmayaAddressCatalog.blockOptionsForGroup(selectedGroup);
    final buildings = BasmayaAddressCatalog.buildingOptionsForBlock(
      selectedBlock,
    );
    final apartments = BasmayaAddressCatalog.apartmentOptions;

    Widget buildGroupField() {
      return _dropdownField(
        value: selectedGroup,
        label: l10n.basmayaGroupLabel,
        hint: l10n.basmayaGroupHint,
        items: BasmayaAddressCatalog.groupOptions,
        onChanged: enabled
            ? (value) {
                if (value == null) return;
                onBlockChanged(value == 'A' ? 'A1' : 'B1');
              }
            : null,
      );
    }

    Widget buildSectorField() {
      return _dropdownField(
        value: sectors.contains(selectedBlock) ? selectedBlock : null,
        label: l10n.basmayaSectorLabel,
        hint: l10n.basmayaSectorHint,
        items: sectors,
        onChanged: (enabled && selectedGroup != null) ? onBlockChanged : null,
        errorText: blockError,
      );
    }

    Widget buildBuildingField() {
      return _dropdownField(
        value: buildings.contains(selectedBuilding) ? selectedBuilding : null,
        label: l10n.basmayaBuildingLabel,
        hint: l10n.basmayaBuildingHint,
        items: buildings,
        onChanged: (enabled && buildings.isNotEmpty) ? onBuildingChanged : null,
        errorText: buildingError,
      );
    }

    Widget buildApartmentField() {
      return _dropdownField(
        value: apartments.contains(selectedApartment) ? selectedApartment : null,
        label: l10n.basmayaApartmentLabel,
        hint: l10n.basmayaApartmentHint,
        items: apartments,
        onChanged: (enabled && selectedBuilding != null)
            ? onApartmentChanged
            : null,
        errorText: apartmentError,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 640;
            if (compact) {
              return Column(
                children: [
                  buildGroupField(),
                  const SizedBox(height: 10),
                  buildSectorField(),
                  const SizedBox(height: 10),
                  buildBuildingField(),
                  const SizedBox(height: 10),
                  buildApartmentField(),
                ],
              );
            }
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: buildGroupField()),
                    const SizedBox(width: 10),
                    Expanded(child: buildSectorField()),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: buildBuildingField()),
                    const SizedBox(width: 10),
                    Expanded(child: buildApartmentField()),
                  ],
                ),
              ],
            );
          },
        ),
        InlineFieldErrorText(text: generalError),
      ],
    );
  }

  Widget _dropdownField({
    required String? value,
    required String label,
    required String hint,
    required List<String> items,
    required ValueChanged<String?>? onChanged,
    String? errorText,
  }) {
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('${label}_${value}_${items.length}'),
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 360,
      items: items
          .map(
            (item) => DropdownMenuItem<String>(value: item, child: Text(item)),
          )
          .toList(growable: false),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
      ),
    );
  }
}

class _ParsedBlock {
  final String letter;
  final int sector;

  const _ParsedBlock({required this.letter, required this.sector});
}
