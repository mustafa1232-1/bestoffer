import 'dart:math' as math;

import '../mimo_character.dart';
import 'mimo_directory.dart';

/// Mimo's instant brain: plain rules over the app's own directory (no AI, no
/// network). It understands categories, store names, services and sections,
/// ranks by orders → rating (random on a tie) and answers in Iraqi.
///
/// Returns null when it isn't sure — then the AI (if available) answers.
class MimoOfflineReply {
  const MimoOfflineReply({
    required this.text,
    this.mood = MimoMood.happy,
    this.blocks = const [],
    this.topic,
  });

  final String text;
  final MimoMood mood;

  /// UI blocks in the same format the server sends (stores, services,
  /// open_section, replies).
  final List<Map<String, dynamic>> blocks;

  /// What was being browsed, so a follow-up like "أعلى تقييم" applies to it.
  final MimoTopic? topic;
}

/// The last list shown (for follow-ups).
class MimoTopic {
  const MimoTopic({this.category, this.services = false, this.query});

  final MimoCategory? category;
  final bool services;
  final String? query;
}

/// A category of stores and the words people use for it.
class MimoCategory {
  const MimoCategory(
    this.key,
    this.ar,
    this.en,
    this.words, {
    this.groups = const {},
    this.activities = const {},
  });

  final String key;
  final String ar;
  final String en;
  final List<String> words;
  final Set<String> groups;
  final Set<String> activities;

  bool matches(MimoStore s) =>
      activities.contains(s.activityType.toLowerCase()) ||
      (groups.isNotEmpty && groups.contains(s.group));
}

const _categories = <MimoCategory>[
  MimoCategory(
    'sweets',
    'حلويات ومخابز',
    'Sweets & bakeries',
    [
      'حلويات',
      'حلو',
      'كيك',
      'كيكه',
      'معجنات',
      'مخبز',
      'مخابز',
      'صمون',
      'خبز',
      'كعك',
      'بقلاوه',
      'sweets',
      'cake',
      'bakery',
    ],
    activities: {'sweets_bakery', 'bakery', 'dessert'},
  ),
  MimoCategory(
    'coffee',
    'قهوة ومشروبات',
    'Coffee & drinks',
    ['قهوه', 'كافي', 'كافيه', 'عصير', 'عصاير', 'مشروبات', 'coffee', 'juice'],
    activities: {'coffee_drinks'},
  ),
  MimoCategory(
    'food',
    'مطاعم',
    'Restaurants',
    [
      'مطعم',
      'مطاعم',
      'اكل',
      'اكله',
      'اكلات',
      'اكلات',
      'وجبه',
      'وجبات',
      'جوعان',
      'جوعانه',
      'عشا',
      'غدا',
      'فطور',
      'ريوك',
      'اتعشى',
      'اتغدى',
      'كباب',
      'تكه',
      'مشاوي',
      'برغر',
      'بركر',
      'برجر',
      'بيتزا',
      'شاورما',
      'فلافل',
      'دجاج مشوي',
      'مسكوف',
      'food',
      'eat',
      'restaurant',
      'hungry',
      'pizza',
      'burger',
    ],
    groups: {'food'},
  ),
  MimoCategory(
    'veg',
    'خضرة وفواكه',
    'Fruit & vegetables',
    ['خضره', 'خضار', 'فواكه', 'فاكهه', 'فواكة', 'vegetables', 'fruit'],
    activities: {'fruits_vegetables'},
  ),
  MimoCategory(
    'meat',
    'لحوم ودجاج',
    'Meat & poultry',
    ['لحم', 'لحوم', 'قصاب', 'قصابه', 'دجاج', 'meat', 'chicken'],
    activities: {'meat_poultry'},
  ),
  MimoCategory(
    'fish',
    'أسماك',
    'Seafood',
    ['سمك', 'اسماك', 'fish', 'seafood'],
    activities: {'seafood'},
  ),
  MimoCategory(
    'water',
    'ماء',
    'Water',
    ['ماء', 'مي', 'قناني', 'water'],
    activities: {'mineral_water'},
  ),
  MimoCategory(
    'nuts',
    'كرزات',
    'Nuts & snacks',
    ['كرزات', 'مكسرات', 'nuts', 'snacks'],
    activities: {'nuts_snacks'},
  ),
  MimoCategory(
    'supermarket',
    'سوبرماركت',
    'Supermarkets',
    [
      'سوبر',
      'سوبرماركت',
      'ماركت',
      'بقاله',
      'مواد غذائيه',
      'ارزاق',
      'supermarket',
      'grocery',
    ],
    groups: {'supermarket'},
  ),
  MimoCategory(
    'pharmacy',
    'صيدليات',
    'Pharmacies',
    [
      'صيدليه',
      'صيدليات',
      'صيدلي',
      'دوا',
      'دواء',
      'ادويه',
      'علاج',
      'حبوب',
      'pharmacy',
      'medicine',
    ],
    groups: {'pharmacy'},
  ),
  MimoCategory(
    'beauty',
    'تجميل وعناية',
    'Beauty & care',
    ['تجميل', 'مكياج', 'عطور', 'عطر', 'عنايه', 'beauty', 'perfume'],
    activities: {'personal_care_beauty'},
  ),
  MimoCategory(
    'fashion',
    'أزياء وملابس',
    'Fashion',
    [
      'ملابس',
      'هدوم',
      'ازياء',
      'قاط',
      'فستان',
      'احذيه',
      'قمصان',
      'clothes',
      'fashion',
    ],
    groups: {'fashion'},
  ),
  MimoCategory(
    'electronics',
    'إلكترونيات',
    'Electronics',
    [
      'موبايل',
      'تلفون',
      'هاتف',
      'شاحن',
      'الكترونيات',
      'كهربائيات',
      'اجهزه',
      'لابتوب',
      'اضويه',
      'electronics',
      'phone',
    ],
    groups: {'electronics'},
  ),
  MimoCategory(
    'flowers',
    'ورد وهدايا',
    'Flowers & gifts',
    ['ورد', 'زهور', 'هدايا', 'هديه', 'flowers', 'gift'],
    activities: {'flowers_gifts'},
  ),
  MimoCategory(
    'pets',
    'مستلزمات حيوانات',
    'Pet supplies',
    ['حيوانات', 'قطط', 'قطه', 'بزونه', 'كلاب', 'pets', 'cat'],
    activities: {'pet_supplies'},
  ),
  MimoCategory(
    'home',
    'أثاث وبيت',
    'Home & furniture',
    [
      'اثاث',
      'مفروشات',
      'ديكور',
      'مطبخ',
      'ادوات منزليه',
      'مواد بناء',
      'furniture',
      'home',
    ],
    groups: {'home'},
  ),
];

/// Sections that live outside the store list.
const _sections = <(String, List<String>, String, String)>[
  (
    'taxi',
    ['تكسي', 'تاكسي', 'سياره اجره', 'وصلني', 'taxi', 'ride'],
    'التكسي',
    'Taxi',
  ),
  (
    'offers',
    ['عروض', 'عرض', 'كوبون', 'كوبونات', 'خصم', 'خصومات', 'offers', 'coupon'],
    'العروض',
    'Offers',
  ),
  (
    'community',
    ['مجتمع', 'منشورات', 'بوستات', 'community'],
    'المجتمع',
    'Community',
  ),
  (
    'orders',
    ['طلباتي', 'وين طلبي', 'تتبع', 'طلبي', 'my orders', 'track'],
    'طلباتك',
    'My orders',
  ),
  ('cart', ['سله', 'السله', 'سلتي', 'cart'], 'السلة', 'Cart'),
  ('jobs', ['وظيفه', 'وظايف', 'شغل', 'تعيين', 'jobs'], 'الوظائف', 'Jobs'),
  (
    'real_estate',
    ['عقار', 'عقارات', 'شقه', 'شقق', 'ايجار', 'real estate'],
    'العقارات',
    'Real estate',
  ),
  (
    'cars',
    ['سيارات', 'سياره للبيع', 'معرض سيارات', 'cars'],
    'السيارات',
    'Cars',
  ),
];

const _serviceWords = [
  'خدمه',
  'خدمات',
  'فني',
  'صيانه',
  'تصليح',
  'كهربائي',
  'كهربجي',
  'سباك',
  'بلاط',
  'تبريد',
  'سبلت',
  'مبرده',
  'تنظيف',
  'صباغ',
  'صبغ',
  'نجار',
  'حداد',
  'نقل',
  'ستلايت',
  'انترنت',
  'service',
  'repair',
  'plumber',
  'electrician',
  'cleaning',
];

const _pickWords = [
  'اختارلي',
  'اختار لي',
  'اختار انت',
  'انت اختار',
  'فاجئني',
  'محتار',
  'شنو اكل',
  'شاكل',
  'surprise me',
  'you choose',
  'pick for me',
];

const _shoppingWords = ['اتسوق', 'تسوق', 'محلات', 'متاجر', 'shop', 'shopping'];

/// Words that don't identify a store on their own.
const _genericNameWords = {
  'مطعم',
  'مطاعم',
  'محل',
  'محلات',
  'سوبر',
  'ماركت',
  'سوبرماركت',
  'صيدليه',
  'مخبز',
  'اسواق',
  'سوق',
  'شركه',
  'مركز',
  'معرض',
  'كافيه',
  'ابو',
  'ام',
  'ال',
  'و',
  'the',
  'store',
  'shop',
};

/// Arabic/English text in one comparable form (أ→ا، ة→ه، ى→ي، گ→ك…).
String mimoNormalize(String input) {
  var s = input.toLowerCase();
  s = s.replaceAll(RegExp('[ً-ْٰـ]'), '');
  const map = {
    'أ': 'ا',
    'إ': 'ا',
    'آ': 'ا',
    'ٱ': 'ا',
    'ة': 'ه',
    'ى': 'ي',
    'ئ': 'ي',
    'ؤ': 'و',
    'گ': 'ك',
    'ڤ': 'ف',
    'پ': 'ب',
    'چ': 'ج',
    'ژ': 'ز',
  };
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(map[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}

List<String> _tokens(String normalized) =>
    normalized.split(' ').where((t) => t.isNotEmpty).toList(growable: false);

const _prefixes = ['ال', 'بال', 'وال', 'لل', 'ب', 'و', 'ل', 'ف'];

/// [token] is [word], possibly with an Arabic prefix (لمشاوي → مشاوي).
bool _isWord(String token, String word) {
  if (token == word) return true;
  for (final p in _prefixes) {
    if (token.length > p.length + 1 &&
        token.startsWith(p) &&
        token.substring(p.length) == word) {
      return true;
    }
  }
  return false;
}

bool _hasWord(String text, List<String> tokens, String word) {
  final w = mimoNormalize(word);
  if (w.contains(' ')) return ' $text '.contains(' $w ');
  return tokens.any((t) => _isWord(t, w));
}

/// Edit distance ≤ 1 (one typo).
bool _closeTo(String a, String b) {
  if (a == b) return true;
  if ((a.length - b.length).abs() > 1 || a.length < 4) return false;
  var i = 0, j = 0, edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length > b.length) {
      i++;
    } else if (b.length > a.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}

/// True when two store names are the same store (Mimo checks before he taps).
bool mimoSameName(String a, String b) {
  final x = mimoNormalize(a);
  final y = mimoNormalize(b);
  if (x.isEmpty || y.isEmpty) return false;
  return x == y || x.contains(y) || y.contains(x);
}

class MimoOfflineBrain {
  MimoOfflineBrain(
    this.dir, {
    this.lang = 'ar',
    this.firstName,
    math.Random? random,
  }) : _random = random ?? math.Random();

  final MimoDirectory dir;
  final String lang;
  final String? firstName;
  final math.Random _random;

  bool get _ar => lang != 'en';
  String _t(String ar, String en) => _ar ? ar : en;

  /// Answers [input] instantly, or null when unsure.
  MimoOfflineReply? answer(String input, {MimoTopic? topic}) {
    final text = mimoNormalize(input);
    if (text.isEmpty) return null;
    final tokens = _tokens(text);
    bool has(String w) => _hasWord(text, tokens, w);
    bool any(List<String> ws) => ws.any(has);

    // 1) A store by name ("وديني لمشاوي أبو علي").
    final named = _storeByName(text, tokens);
    if (named != null) return _aboutStore(named.$1, exact: named.$2);

    // 2) "You choose for me".
    if (any(_pickWords)) return _pickForMe();

    // 3) A follow-up on the last list ("أعلى تقييم", "بس المفتوحة").
    final sort = _sortFrom(has);
    final openOnly = has('مفتوح') || has('مفتوحه') || has('open');
    final cat = _categoryFrom(has);
    if (cat == null && topic != null && (sort != null || openOnly)) {
      if (topic.services) return _services(topic.query, sort: sort);
      if (topic.category != null) {
        return _storesOf(topic.category!, sort: sort, openOnly: openOnly);
      }
    }

    // 4) Services (craftsmen, repairs…).
    if (any(_serviceWords)) {
      return _services(input, sort: sort);
    }

    // 5) A store category ("مطاعم", "صيدلية", "بيتزا").
    if (cat != null) {
      final dish = _dishWord(tokens);
      return _storesOf(cat, sort: sort, openOnly: openOnly, dish: dish);
    }

    // 6) Sections outside the store list.
    for (final (key, words, ar, en) in _sections) {
      if (any(words)) return _section(key, ar, en);
    }

    // 7) "I want to shop".
    if (any(_shoppingWords)) return _shopping();

    // 8) A service by its name / provider.
    final svc = _servicesMatching(text, tokens);
    if (svc.isNotEmpty) return _servicesList(svc, query: input);
    return null;
  }

  /// Loose search used when the AI is unavailable: any store/service whose
  /// name shares a word with the message.
  MimoOfflineReply? search(String input) {
    final text = mimoNormalize(input);
    final tokens = _tokens(
      text,
    ).where((t) => t.length >= 3 && !_genericNameWords.contains(t)).toList();
    if (tokens.isEmpty) return null;
    final stores = dir.stores
        .where((s) {
          final h = mimoNormalize('${s.name} ${s.tagline ?? ''}');
          return tokens.any(h.contains);
        })
        .toList(growable: false);
    if (stores.isNotEmpty) {
      return MimoOfflineReply(
        text: _t(
          'لگيتلك هذني بالتطبيق، دوس على اللي يعجبك وأوديك:',
          'Here is what I found in the app, tap one and I will take you:',
        ),
        mood: MimoMood.curious,
        blocks: [_storesBlock(_rank(stores).take(8).toList(), null)],
      );
    }
    final svc = _servicesMatching(text, tokens);
    if (svc.isNotEmpty) return _servicesList(svc, query: input);
    return null;
  }

  // ---------------------------------------------------------------------------

  (MimoStore, bool)? _storeByName(String text, List<String> tokens) {
    (MimoStore, bool)? best;
    var bestLen = 0;
    for (final s in dir.stores) {
      final name = mimoNormalize(s.name);
      if (name.length < 3) continue;
      if (' $text '.contains(' $name ')) {
        if (name.length > bestLen) {
          best = (s, true);
          bestLen = name.length;
        }
        continue;
      }
      final distinctive = _tokens(
        name,
      ).where((t) => t.length >= 3 && !_genericNameWords.contains(t)).toList();
      if (distinctive.isEmpty) continue;
      final exact = distinctive.every((d) => tokens.any((t) => _isWord(t, d)));
      final fuzzy =
          !exact && distinctive.every((d) => tokens.any((t) => _closeTo(t, d)));
      if ((exact || fuzzy) && name.length > bestLen) {
        best = (s, exact);
        bestLen = name.length;
      }
    }
    return best;
  }

  MimoCategory? _categoryFrom(bool Function(String) has) {
    for (final c in _categories) {
      if (c.words.any(has)) return c;
    }
    return null;
  }

  /// A dish word that some store names/taglines contain (e.g. "بيتزا").
  String? _dishWord(List<String> tokens) {
    for (final t in tokens) {
      if (t.length < 3 || _genericNameWords.contains(t)) continue;
      final hit = dir.stores.any(
        (s) => mimoNormalize('${s.name} ${s.tagline ?? ''}').contains(t),
      );
      if (hit) return t;
    }
    return null;
  }

  String? _sortFrom(bool Function(String) has) {
    if (has('تقييم') || has('احسن') || has('افضل') || has('rated')) {
      return 'rating';
    }
    if (has('طلب') || has('مشهور') || has('مشهوره') || has('popular')) {
      return 'orders';
    }
    if (has('اسرع') || has('سريع') || has('fastest')) return 'fast';
    return null;
  }

  /// Open first, then most orders, then rating; random among exact ties.
  List<MimoStore> _rank(List<MimoStore> list, {String? sort}) {
    final shuffled = [...list]..shuffle(_random);
    int byRating(MimoStore a, MimoStore b) =>
        (b.rating ?? 0).compareTo(a.rating ?? 0) != 0
        ? (b.rating ?? 0).compareTo(a.rating ?? 0)
        : b.ratingCount.compareTo(a.ratingCount);
    shuffled.sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      switch (sort) {
        case 'rating':
          final r = byRating(a, b);
          return r != 0 ? r : b.orders.compareTo(a.orders);
        case 'fast':
          final ea = a.etaMax ?? 999, eb = b.etaMax ?? 999;
          return ea != eb ? ea.compareTo(eb) : b.orders.compareTo(a.orders);
        default:
          final o = b.orders.compareTo(a.orders);
          return o != 0 ? o : byRating(a, b);
      }
    });
    return shuffled;
  }

  String _ratingText(MimoStore s) {
    final parts = <String>[];
    if ((s.rating ?? 0) > 0) {
      parts.add('⭐ ${s.rating!.toStringAsFixed(1)} (${s.ratingCount})');
    } else {
      parts.add(_t('بعده بدون تقييم', 'no ratings yet'));
    }
    if (s.orders > 0) parts.add(_t('${s.orders} طلب', '${s.orders} orders'));
    parts.add(s.isOpen ? _t('مفتوح هسه', 'open now') : _t('مسدود', 'closed'));
    return parts.join(' • ');
  }

  String _place(MimoStore s) {
    final section = _t('التسوق', 'Shopping');
    final card = switch (s.group) {
      'food' => _t('مطاعم', 'Restaurants'),
      'supermarket' => _t('سوبرماركت', 'Supermarket'),
      'pharmacy' => _t('صيدليات', 'Pharmacies'),
      'fashion' => _t('أزياء', 'Fashion'),
      'electronics' => _t('إلكترونيات', 'Electronics'),
      'home' => _t('المنزل', 'Home'),
      _ => _t('كل المتاجر', 'All stores'),
    };
    final area = (s.area ?? '').trim();
    final where = area.isEmpty
        ? ''
        : _t('، وعنوانه: $area', ', address: $area');
    return _t(
      'مكانه بالتطبيق: $section ← $card$where',
      'In the app: $section → $card$where',
    );
  }

  Map<String, dynamic> _storesBlock(List<MimoStore> list, String? title) => {
    'type': 'stores',
    'title': ?title,
    'items': [for (final s in list) s.toCard()],
  };

  Map<String, dynamic> _replies(List<String> options) => {
    'type': 'replies',
    'options': options,
  };

  MimoOfflineReply _aboutStore(MimoStore s, {required bool exact}) {
    final lines = <String>[
      exact
          ? _t('هذا «${s.name}» 👌', "That's «${s.name}» 👌")
          : _t('تقصد «${s.name}»؟ 🤔', 'Do you mean «${s.name}»? 🤔'),
      _ratingText(s),
      _place(s),
      _t(
        'دوس على البطاقة وأوديك له بنفسي 🏃',
        'Tap the card and I will walk you there 🏃',
      ),
    ];
    return MimoOfflineReply(
      text: lines.join('\n'),
      mood: exact ? MimoMood.happy : MimoMood.curious,
      blocks: [
        _storesBlock([s], null),
      ],
    );
  }

  MimoOfflineReply _pickForMe() {
    final food = dir.stores.where(
      (s) => s.group == 'food' || s.type == 'restaurant',
    );
    final pool = _rank(food.toList());
    if (pool.isEmpty) return _empty(_t('مطاعم', 'restaurants'));
    final top = pool.first;
    final hi = (firstName ?? '').isEmpty ? '' : '$firstName، ';
    return MimoOfflineReply(
      text: _t(
        '$hi اخترتلك «${top.name}» 😋 لأن أكثر الناس يطلبون منه.\n${_ratingText(top)}\nدوس عليه وأوديك، أو شوف غيره:',
        '$hi I picked «${top.name}» 😋 — most people order from it.\n${_ratingText(top)}\nTap it and I will take you, or see others:',
      ).trim(),
      mood: MimoMood.yummy,
      blocks: [
        _storesBlock(
          pool.take(6).toList(),
          _t('اختياري إلك', 'My pick for you'),
        ),
        _replies([
          _t('أعلى تقييم', 'Top rated'),
          _t('الأكثر طلب', 'Most ordered'),
          _t('بس المفتوحة', 'Open only'),
        ]),
      ],
      topic: MimoTopic(
        category: _categories.firstWhere((c) => c.key == 'food'),
      ),
    );
  }

  MimoOfflineReply _storesOf(
    MimoCategory cat, {
    String? sort,
    bool openOnly = false,
    String? dish,
  }) {
    var list = dir.stores.where(cat.matches).toList();
    if (dish != null) {
      final withDish = list
          .where(
            (s) => mimoNormalize('${s.name} ${s.tagline ?? ''}').contains(dish),
          )
          .toList();
      if (withDish.isNotEmpty) list = withDish;
    }
    if (openOnly) list = list.where((s) => s.isOpen).toList();
    if (list.isEmpty) return _empty(_t(cat.ar, cat.en));
    final ranked = _rank(list, sort: sort);
    final top = ranked.first;
    final how = switch (sort) {
      'rating' => _t('مرتبة حسب التقييم', 'sorted by rating'),
      'fast' => _t('مرتبة حسب سرعة التوصيل', 'sorted by delivery speed'),
      _ => _t('الأكثر طلب أول', 'most ordered first'),
    };
    final count = ranked.length;
    return MimoOfflineReply(
      text: _t(
        'عدنا $count من ${cat.ar} ($how) 👇\nأولهم «${top.name}»: ${_ratingText(top)}\nدوس على أي واحد وأوديك له.',
        'We have $count ${cat.en} ($how) 👇\nTop: «${top.name}»: ${_ratingText(top)}\nTap any to go there.',
      ),
      mood: cat.key == 'pharmacy' ? MimoMood.happy : MimoMood.yummy,
      blocks: [
        _storesBlock(ranked.take(10).toList(), _t(cat.ar, cat.en)),
        _replies([
          if (sort != 'rating') _t('أعلى تقييم', 'Top rated'),
          if (sort != null) _t('الأكثر طلب', 'Most ordered'),
          if (!openOnly) _t('بس المفتوحة', 'Open only'),
        ]),
      ],
      topic: MimoTopic(category: cat),
    );
  }

  List<MimoService> _servicesMatching(String text, List<String> tokens) {
    final words = tokens
        .where((t) => t.length >= 3 && !_genericNameWords.contains(t))
        .toList();
    if (words.isEmpty) return const [];
    return dir.services.where((s) {
      final h = mimoNormalize(
        '${s.name} ${s.category ?? ''} ${s.subcategory ?? ''} ${s.provider ?? ''}',
      );
      return words.any(
        (w) => h.contains(w) || _tokens(h).any((t) => _closeTo(t, w)),
      );
    }).toList();
  }

  MimoOfflineReply _services(String? query, {String? sort}) {
    final text = mimoNormalize(query ?? '');
    final tokens = _tokens(
      text,
    ).where((t) => !_serviceWords.map(mimoNormalize).contains(t)).toList();
    var list = tokens.isEmpty
        ? <MimoService>[]
        : _servicesMatching(text, tokens);
    if (list.isEmpty) list = [...dir.services];
    return _servicesList(list, query: query, sort: sort);
  }

  MimoOfflineReply _servicesList(
    List<MimoService> list, {
    String? query,
    String? sort,
  }) {
    if (list.isEmpty) return _empty(_t('خدمات', 'services'));
    final ranked = [...list]..shuffle(_random);
    ranked.sort((a, b) {
      final r = (b.rating ?? 0).compareTo(a.rating ?? 0);
      final o = b.orders.compareTo(a.orders);
      return sort == 'rating' ? (r != 0 ? r : o) : (o != 0 ? o : r);
    });
    final top = ranked.first;
    final where = (top.area ?? '').isEmpty
        ? ''
        : _t(' — ${top.area}', ' — ${top.area}');
    final rating = (top.rating ?? 0) > 0
        ? '⭐ ${top.rating!.toStringAsFixed(1)} (${top.ratingCount})'
        : _t('بعده بدون تقييم', 'no ratings yet');
    return MimoOfflineReply(
      text: _t(
        'لگيتلك ${ranked.length} خدمة 🛠️\nأحسنهم: «${top.name}» عند ${top.provider ?? ''}$where\n$rating\nدوس على أي وحدة وأوديك.',
        'Found ${ranked.length} services 🛠️\nBest: «${top.name}» by ${top.provider ?? ''}$where\n$rating\nTap one to go there.',
      ),
      mood: MimoMood.happy,
      blocks: [
        {
          'type': 'services',
          'title': _t('الخدمات', 'Services'),
          'items': [for (final s in ranked.take(10)) s.toCard()],
        },
        if (sort != 'rating') _replies([_t('أعلى تقييم', 'Top rated')]),
      ],
      topic: MimoTopic(services: true, query: query),
    );
  }

  MimoOfflineReply _section(String key, String ar, String en) {
    return MimoOfflineReply(
      text: _t('تدلل! هسه أوديك لـ$ar 🏃', 'Sure! Taking you to $en 🏃'),
      mood: MimoMood.happy,
      blocks: [
        {'type': 'open_section', 'section': key, 'label': _t(ar, en)},
      ],
    );
  }

  MimoOfflineReply _shopping() {
    final open = _rank(dir.stores.where((s) => s.isOpen).toList());
    return MimoOfflineReply(
      text: _t(
        'عدنا ${dir.stores.length} متجر 🛍️ هذني الأكثر طلب هسه. لو تريد نوع معيّن اختار:',
        'We have ${dir.stores.length} stores 🛍️ — the most ordered right now. Or pick a type:',
      ),
      mood: MimoMood.dancing,
      blocks: [
        if (open.isNotEmpty) _storesBlock(open.take(8).toList(), null),
        _replies([
          _t('مطاعم', 'Restaurants'),
          _t('سوبرماركت', 'Supermarkets'),
          _t('صيدليات', 'Pharmacies'),
          _t('حلويات', 'Sweets'),
          _t('ملابس', 'Clothes'),
        ]),
      ],
    );
  }

  MimoOfflineReply _empty(String what) => MimoOfflineReply(
    text: _t(
      'للأسف هسه ماكو $what بالتطبيق 😔 بس راح أخبر الإدارة إن الناس يريدوها.',
      "Sorry, there are no $what in the app right now 😔",
    ),
    mood: MimoMood.sad,
  );
}
