const Map<String, int> realEstateBuildingCounts = <String, int>{
  'A1': 12,
  'A2': 14,
  'A3': 14,
  'A4': 12,
  'A5': 12,
  'A6': 12,
  'A7': 13,
  'A8': 15,
  'A9': 15,
  'B1': 12,
  'B2': 18,
  'B3': 18,
  'B4': 12,
  'B5': 18,
  'B6': 21,
  'B7': 16,
  'B8': 12,
};

const List<String> realEstateBlocks = <String>[
  'A1',
  'A2',
  'A3',
  'A4',
  'A5',
  'A6',
  'A7',
  'A8',
  'A9',
  'B1',
  'B2',
  'B3',
  'B4',
  'B5',
  'B6',
  'B7',
  'B8',
];

const int realEstateApartmentsPerBuilding = 120;

List<String> realEstateBuildingOptions(String? block, {String? existing}) {
  final count = realEstateBuildingCounts[block?.trim().toUpperCase()];
  final options = <String>[
    if (existing != null && existing.trim().isNotEmpty) existing.trim(),
  ];
  if (count != null) {
    final normalizedBlock = block!.trim().toUpperCase();
    options.addAll(
      List<String>.generate(
        count,
        (index) => '$normalizedBlock${(index + 1).toString().padLeft(2, '0')}',
      ),
    );
  }
  return options.toSet().toList();
}

List<String> realEstateApartmentOptions({String? existing}) {
  final options = <String>[
    if (existing != null && existing.trim().isNotEmpty) existing.trim(),
  ];
  options.addAll(
    List<String>.generate(
      12,
      (index) => 'G${(index + 1).toString().padLeft(2, '0')}',
    ),
  );
  options.addAll(
    List<String>.generate(9 * 12, (index) {
      final floor = (index ~/ 12) + 1;
      final unit = (index % 12) + 1;
      return '$floor${unit.toString().padLeft(2, '0')}';
    }),
  );
  return options.toSet().toList();
}
