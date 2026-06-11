import 'section_availability_models.dart';

class SectionAvailabilityRegistry {
  static Map<String, SectionAvailabilityEntry> _entries =
      <String, SectionAvailabilityEntry>{};

  static void replaceAll(Iterable<SectionAvailabilityEntry> entries) {
    _entries = {
      for (final entry in entries) entry.sectionKey.trim().toLowerCase(): entry,
    };
  }

  static SectionAvailabilityEntry? get(String sectionKey) {
    return _entries[sectionKey.trim().toLowerCase()];
  }

  static SectionAvailabilityEntry getOrDefault(
    String sectionKey, {
    String? displayName,
  }) {
    return get(sectionKey) ??
        fallbackOpenSectionEntry(sectionKey, displayName: displayName);
  }

  static bool isOpen(String sectionKey) => get(sectionKey)?.isOpen ?? true;

  static Map<String, SectionAvailabilityEntry> snapshot() =>
      Map<String, SectionAvailabilityEntry>.unmodifiable(_entries);
}
