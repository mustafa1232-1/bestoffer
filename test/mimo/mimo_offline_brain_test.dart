import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/mimo/brain/mimo_directory.dart';
import 'package:maslaki/features/mimo/brain/mimo_offline_brain.dart';
import 'package:maslaki/features/mimo/mimo_character.dart';

final dir = MimoDirectory.fromJson({
  'stores': [
    {
      'id': 1,
      'name': 'مشاوي أبو علي',
      'type': 'restaurant',
      'activityType': 'restaurant',
      'rating': 4.6,
      'ratingCount': 80,
      'orders': 420,
      'isOpen': true,
      'area': 'بسماية - بلوك A5',
    },
    {
      'id': 2,
      'name': 'بيتزا هت',
      'type': 'restaurant',
      'activityType': 'restaurant',
      'rating': 4.9,
      'ratingCount': 30,
      'orders': 150,
      'isOpen': true,
    },
    {
      'id': 3,
      'name': 'مطعم مسدود',
      'type': 'restaurant',
      'activityType': 'restaurant',
      'rating': 5,
      'ratingCount': 2,
      'orders': 999,
      'isOpen': false,
    },
    {
      'id': 4,
      'name': 'صيدلية الشفاء',
      'type': 'market',
      'activityType': 'pharmacy',
      'orders': 40,
    },
    {
      'id': 5,
      'name': 'أسواق النخلة',
      'type': 'market',
      'activityType': 'supermarket',
      'orders': 60,
    },
  ],
  'services': [
    {
      'id': 9,
      'name': 'تصليح كهرباء البيت',
      'category': 'كهربائي',
      'provider': 'أبو حسين',
      'area': 'B3',
      'rating': 4.8,
      'ratingCount': 12,
      'orders': 30,
    },
    {
      'id': 10,
      'name': 'تنظيف منازل',
      'category': 'تنظيف',
      'provider': 'نظافة بسماية',
      'orders': 5,
    },
  ],
});

MimoOfflineBrain brain() =>
    MimoOfflineBrain(dir, firstName: 'مصطفى', random: math.Random(1));

List<int> storeIds(MimoOfflineReply r) => [
  for (final b in r.blocks.where((b) => b['type'] == 'stores'))
    for (final i in b['items'] as List) (i as Map)['id'] as int,
];

void main() {
  test('Arabic spellings normalize the same', () {
    expect(mimoNormalize('مشاوي أبو علي'), mimoNormalize('مشاوي ابو علي'));
    expect(mimoNormalize('صيدليّة'), 'صيدليه');
    expect(mimoSameName('بيتزا هت', 'بيتزا  هت!'), isTrue);
    expect(mimoSameName('بيتزا هت', 'مشاوي'), isFalse);
  });

  test('"اختارلي" picks the most-ordered OPEN restaurant', () {
    final r = brain().answer('جوعان، اختارلي انت')!;
    expect(storeIds(r).first, 1, reason: 'closed store 3 has more orders');
    expect(r.text, contains('مصطفى'));
    expect(r.text, contains('«مشاوي أبو علي»'));
    expect(r.text, contains('⭐ 4.6 (80)'));
    expect(r.mood, MimoMood.yummy);
  });

  test('restaurants list + "أعلى تقييم" follow-up re-sorts the same list', () {
    final b = brain();
    final first = b.answer('اريد مطاعم')!;
    expect(storeIds(first), [1, 2, 3]);
    expect(first.text, contains('عدنا 3 من مطاعم'));
    final byRating = b.answer('أعلى تقييم', topic: first.topic)!;
    expect(storeIds(byRating), [2, 1, 3]);
    final open = b.answer('بس المفتوحة', topic: first.topic)!;
    expect(storeIds(open), [1, 2]);
  });

  test('a store by name: confirms it, its rating and where it is', () {
    final r = brain().answer('وديني لمشاوي ابو علي')!;
    expect(storeIds(r), [1]);
    expect(r.text, contains('هذا «مشاوي أبو علي»'));
    expect(r.text, contains('التسوق ← مطاعم'));
    expect(r.text, contains('بسماية - بلوك A5'));
  });

  test('a misspelled name asks "do you mean…?" instead of guessing', () {
    final r = brain().answer('اريد بيتزه هت')!;
    expect(storeIds(r), [2]);
    expect(r.text, startsWith('تقصد «بيتزا هت»؟'));
  });

  test('pharmacies, services and sections', () {
    expect(storeIds(brain().answer('احتاج صيدلية')!), [4]);

    final svc = brain().answer('احتاج كهربائي')!;
    final items = svc.blocks.first['items'] as List;
    expect((items.first as Map)['id'], 9);
    expect(svc.text, contains('أبو حسين'));

    final taxi = brain().answer('اريد تكسي')!;
    expect(taxi.blocks.single['type'], 'open_section');
    expect(taxi.blocks.single['section'], 'taxi');
  });

  test('unsure → null (the AI answers), and a missing category says so', () {
    expect(brain().answer('شنو عاصمة فرنسا؟'), isNull);
    final none = brain().answer('اريد ورد')!;
    expect(none.mood, MimoMood.sad);
    expect(none.text, contains('ماكو ورد وهدايا'));
  });

  test('loose search finds stores when the AI is unavailable', () {
    final r = brain().search('عندكم النخلة؟')!;
    expect(storeIds(r), [5]);
  });
}
