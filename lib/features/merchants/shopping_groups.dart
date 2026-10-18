/// The shopping category cards ("مطاعم", "سوبرماركت"…) and which stores each
/// one shows. Shared by the market screen's filter and Mimo's guided tour so
/// both always agree on where a store lives.
library;

/// Card order on the market screen.
const List<String> kShoppingGroups = [
  'fashion',
  'food',
  'supermarket',
  'pharmacy',
  'electronics',
  'home',
];

/// Whether a store with this [type]/[activityType] appears under [group].
bool storeInShoppingGroup(
  String group, {
  required String type,
  required String activityType,
  bool supportsPharmacy = false,
}) {
  final t = type.trim().toLowerCase();
  final a = activityType.trim().toLowerCase();
  switch (group) {
    case 'food':
      return t == 'restaurant' ||
          const {
            'restaurant',
            'sweets_bakery',
            'coffee_drinks',
            'bakery',
            'dessert',
          }.contains(a);
    case 'fashion':
      return const {
        'fashion_clothing',
        'kids_clothing',
        'personal_care_beauty',
      }.contains(a);
    case 'supermarket':
      return t == 'market' &&
          const {
            'market',
            'supermarket',
            'fruits_vegetables',
            'meat_poultry',
            'seafood',
            'nuts_snacks',
            'mineral_water',
          }.contains(a);
    case 'pharmacy':
      return a == 'pharmacy' || a == 'dietary_supplements' || supportsPharmacy;
    case 'electronics':
      return const {
        'electronics_mobile',
        'electrical_lighting',
        'phone_maintenance',
        'phones_technology',
        'home_kitchen',
      }.contains(a);
    case 'home':
      return const {
        'furnishings',
        'home_furniture',
        'home_kitchen',
        'kitchens_decor',
        'construction',
      }.contains(a);
    default:
      return true;
  }
}

/// The card a store is found under (null = only under "كل المتاجر").
String? shoppingGroupOf({
  required String type,
  required String activityType,
  bool supportsPharmacy = false,
}) {
  // Pharmacy first: a pharmacy flagged store must be found under صيدليات.
  const order = [
    'pharmacy',
    'food',
    'supermarket',
    'fashion',
    'electronics',
    'home',
  ];
  for (final g in order) {
    if (storeInShoppingGroup(
      g,
      type: type,
      activityType: activityType,
      supportsPharmacy: supportsPharmacy,
    )) {
      return g;
    }
  }
  return null;
}
