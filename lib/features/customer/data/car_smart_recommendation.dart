enum CarBodyType {
  any,
  sedan,
  suv,
  crossover,
  hatchback,
  pickup,
  van,
}

enum CarUsage {
  taxi,
  personal,
  work,
  mixed,
}

enum CarCondition {
  any,
  newCar,
  used,
}

enum FuelPreference {
  any,
  economy,
  hybrid,
  electric,
}

enum TransmissionPref {
  any,
  automatic,
  manual,
}

enum PriorityGoal {
  balanced,
  lowestPrice,
  lowestFuelCost,
  comfort,
  space,
  resale,
  maintenance,
}

class PriceRangeM {
  final int min;
  final int max;

  const PriceRangeM(this.min, this.max);

  bool overlaps(RangeDouble budget) {
    return max >= budget.start.round() && min <= budget.end.round();
  }
}

class RangeDouble {
  final double start;
  final double end;

  const RangeDouble(this.start, this.end);
}

class CarSpec {
  final String brand;
  final String model;
  final CarBodyType bodyType;
  final int seats;
  final bool hasAutomatic;
  final bool hasManual;
  final bool hasHybrid;
  final bool isElectric;
  final PriceRangeM? newPriceM;
  final PriceRangeM? usedPriceM;
  final int fuelEfficiency;
  final int comfort;
  final int space;
  final int resale;
  final int maintenance;
  final int reliability;
  final int taxiFit;
  final int personalFit;
  final int workFit;

  const CarSpec({
    required this.brand,
    required this.model,
    required this.bodyType,
    required this.seats,
    required this.hasAutomatic,
    required this.hasManual,
    required this.hasHybrid,
    required this.isElectric,
    required this.newPriceM,
    required this.usedPriceM,
    required this.fuelEfficiency,
    required this.comfort,
    required this.space,
    required this.resale,
    required this.maintenance,
    required this.reliability,
    required this.taxiFit,
    required this.personalFit,
    required this.workFit,
  });

  String get fullName => '$brand $model';

  int usageFit(CarUsage usage) {
    switch (usage) {
      case CarUsage.taxi:
        return taxiFit;
      case CarUsage.personal:
        return personalFit;
      case CarUsage.work:
        return workFit;
      case CarUsage.mixed:
        return ((taxiFit + personalFit + workFit) / 3).round();
    }
  }
}

class SmartCarCriteria {
  final RangeDouble budgetM;
  final CarBodyType bodyType;
  final CarUsage usage;
  final CarCondition condition;
  final FuelPreference fuelPreference;
  final TransmissionPref transmissionPref;
  final PriorityGoal priorityGoal;
  final int minSeats;
  final String freeText;

  const SmartCarCriteria({
    required this.budgetM,
    required this.bodyType,
    required this.usage,
    required this.condition,
    required this.fuelPreference,
    required this.transmissionPref,
    required this.priorityGoal,
    required this.minSeats,
    required this.freeText,
  });
}

class SmartCarRecommendation {
  final CarSpec spec;
  final int score;
  final PriceRangeM matchedPrice;
  final List<String> reasons;

  const SmartCarRecommendation({
    required this.spec,
    required this.score,
    required this.matchedPrice,
    required this.reasons,
  });
}

PriceRangeM? _priceForCondition(CarSpec spec, CarCondition condition) {
  switch (condition) {
    case CarCondition.any:
      if (spec.usedPriceM == null && spec.newPriceM == null) return null;
      if (spec.usedPriceM == null) return spec.newPriceM;
      if (spec.newPriceM == null) return spec.usedPriceM;
      return PriceRangeM(
        spec.usedPriceM!.min < spec.newPriceM!.min
            ? spec.usedPriceM!.min
            : spec.newPriceM!.min,
        spec.usedPriceM!.max > spec.newPriceM!.max
            ? spec.usedPriceM!.max
            : spec.newPriceM!.max,
      );
    case CarCondition.newCar:
      return spec.newPriceM;
    case CarCondition.used:
      return spec.usedPriceM;
  }
}

int _budgetScore(PriceRangeM price, RangeDouble budget) {
  final bMin = budget.start.round();
  final bMax = budget.end.round();
  final overlapMin = price.min > bMin ? price.min : bMin;
  final overlapMax = price.max < bMax ? price.max : bMax;
  if (overlapMin > overlapMax) return 0;
  final overlapWidth = (overlapMax - overlapMin + 1).toDouble();
  final budgetWidth = (bMax - bMin + 1).toDouble();
  final ratio = overlapWidth / budgetWidth;
  return (ratio * 30).round().clamp(5, 30);
}

int _priorityScore(CarSpec spec, PriorityGoal goal) {
  switch (goal) {
    case PriorityGoal.balanced:
      return ((spec.reliability +
                  spec.fuelEfficiency +
                  spec.comfort +
                  spec.resale +
                  spec.maintenance) /
              5)
          .round();
    case PriorityGoal.lowestPrice:
      return spec.maintenance;
    case PriorityGoal.lowestFuelCost:
      return spec.fuelEfficiency;
    case PriorityGoal.comfort:
      return spec.comfort;
    case PriorityGoal.space:
      return spec.space;
    case PriorityGoal.resale:
      return spec.resale;
    case PriorityGoal.maintenance:
      return spec.maintenance;
  }
}

bool _matchText(CarSpec spec, String freeText) {
  final q = freeText.trim().toLowerCase();
  if (q.isEmpty) return true;
  final source = '${spec.brand} ${spec.model}'.toLowerCase();
  return source.contains(q);
}

List<String> _buildReasons({
  required CarSpec spec,
  required CarCondition condition,
  required CarUsage usage,
  required PriorityGoal priority,
  required PriceRangeM price,
}) {
  final reasons = <String>[
    'ضمن ميزانيتك التقريبية: ${price.min}–${price.max} مليون IQD',
    'مناسبة لاستخدامك: ${carUsageLabel(usage)}',
  ];

  if (priority == PriorityGoal.lowestFuelCost) {
    reasons.add('كفاءة وقود ممتازة مقارنة بالخيارات الأخرى');
  } else if (priority == PriorityGoal.resale) {
    reasons.add('قيمة إعادة بيع جيدة في السوق المحلي');
  } else if (priority == PriorityGoal.maintenance ||
      priority == PriorityGoal.lowestPrice) {
    reasons.add('صيانة وقطع غيار أسهل من المتوسط');
  } else if (priority == PriorityGoal.comfort) {
    reasons.add('مستوى راحة أعلى للقيادة اليومية');
  } else if (priority == PriorityGoal.space) {
    reasons.add('مساحة عملية للركاب والأغراض');
  } else {
    reasons.add('توازن جيد بين الاعتمادية والراحة والاستهلاك');
  }

  if (condition == CarCondition.newCar) {
    reasons.add('الترشيح موجه للسيارات الجديدة');
  } else if (condition == CarCondition.used) {
    reasons.add('الترشيح موجه للسيارات المستعملة');
  }

  return reasons;
}

List<SmartCarRecommendation> getSmartCarRecommendations(
  SmartCarCriteria criteria, {
  int limit = 6,
}) {
  final items = <SmartCarRecommendation>[];

  for (final spec in _carKnowledgeBase) {
    if (criteria.bodyType != CarBodyType.any &&
        spec.bodyType != criteria.bodyType) {
      continue;
    }
    if (spec.seats < criteria.minSeats) continue;
    if (!_matchText(spec, criteria.freeText)) continue;

    final price = _priceForCondition(spec, criteria.condition);
    if (price == null) continue;
    if (!price.overlaps(criteria.budgetM)) continue;

    if (criteria.transmissionPref == TransmissionPref.automatic &&
        !spec.hasAutomatic) {
      continue;
    }
    if (criteria.transmissionPref == TransmissionPref.manual && !spec.hasManual) {
      continue;
    }

    if (criteria.fuelPreference == FuelPreference.hybrid && !spec.hasHybrid) {
      continue;
    }
    if (criteria.fuelPreference == FuelPreference.electric && !spec.isElectric) {
      continue;
    }
    if (criteria.fuelPreference == FuelPreference.economy &&
        spec.fuelEfficiency < 7) {
      continue;
    }

    var score = 0;
    score += _budgetScore(price, criteria.budgetM);
    score += (spec.usageFit(criteria.usage) * 2);
    score += _priorityScore(spec, criteria.priorityGoal);
    score += (spec.reliability ~/ 2);

    if (criteria.fuelPreference == FuelPreference.hybrid && spec.hasHybrid) {
      score += 8;
    }
    if (criteria.fuelPreference == FuelPreference.electric && spec.isElectric) {
      score += 10;
    }
    if (criteria.fuelPreference == FuelPreference.economy &&
        spec.fuelEfficiency >= 8) {
      score += 6;
    }

    final reasons = _buildReasons(
      spec: spec,
      condition: criteria.condition,
      usage: criteria.usage,
      priority: criteria.priorityGoal,
      price: price,
    );

    items.add(
      SmartCarRecommendation(
        spec: spec,
        score: score,
        matchedPrice: price,
        reasons: reasons,
      ),
    );
  }

  items.sort((a, b) => b.score.compareTo(a.score));
  return items.take(limit).toList(growable: false);
}

String carBodyTypeLabel(CarBodyType type) {
  switch (type) {
    case CarBodyType.any:
      return 'أي نوع';
    case CarBodyType.sedan:
      return 'سيدان';
    case CarBodyType.suv:
      return 'SUV';
    case CarBodyType.crossover:
      return 'كروس أوفر';
    case CarBodyType.hatchback:
      return 'هاتشباك';
    case CarBodyType.pickup:
      return 'بيك أب';
    case CarBodyType.van:
      return 'فان';
  }
}

String carUsageLabel(CarUsage usage) {
  switch (usage) {
    case CarUsage.taxi:
      return 'تكسي';
    case CarUsage.personal:
      return 'استخدام شخصي';
    case CarUsage.work:
      return 'للعمل';
    case CarUsage.mixed:
      return 'استخدام متنوع';
  }
}

String carConditionLabel(CarCondition condition) {
  switch (condition) {
    case CarCondition.any:
      return 'الكل';
    case CarCondition.newCar:
      return 'جديد';
    case CarCondition.used:
      return 'مستعمل';
  }
}

String fuelPreferenceLabel(FuelPreference preference) {
  switch (preference) {
    case FuelPreference.any:
      return 'لا يهم';
    case FuelPreference.economy:
      return 'اقتصادي';
    case FuelPreference.hybrid:
      return 'هايبرد';
    case FuelPreference.electric:
      return 'كهربائي';
  }
}

String transmissionLabel(TransmissionPref transmission) {
  switch (transmission) {
    case TransmissionPref.any:
      return 'أي ناقل';
    case TransmissionPref.automatic:
      return 'أوتوماتيك';
    case TransmissionPref.manual:
      return 'يدوي';
  }
}

String priorityGoalLabel(PriorityGoal goal) {
  switch (goal) {
    case PriorityGoal.balanced:
      return 'متوازن';
    case PriorityGoal.lowestPrice:
      return 'أقل كلفة شراء';
    case PriorityGoal.lowestFuelCost:
      return 'أقل صرف وقود';
    case PriorityGoal.comfort:
      return 'راحة أعلى';
    case PriorityGoal.space:
      return 'مساحة أكبر';
    case PriorityGoal.resale:
      return 'إعادة بيع أفضل';
    case PriorityGoal.maintenance:
      return 'صيانة أسهل';
  }
}

const _carKnowledgeBase = <CarSpec>[
  CarSpec(
    brand: 'Toyota',
    model: 'Corolla',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(28, 40),
    usedPriceM: PriceRangeM(10, 30),
    fuelEfficiency: 9,
    comfort: 7,
    space: 6,
    resale: 10,
    maintenance: 9,
    reliability: 10,
    taxiFit: 9,
    personalFit: 8,
    workFit: 8,
  ),
  CarSpec(
    brand: 'Toyota',
    model: 'Camry',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(45, 62),
    usedPriceM: PriceRangeM(20, 45),
    fuelEfficiency: 8,
    comfort: 9,
    space: 8,
    resale: 9,
    maintenance: 8,
    reliability: 9,
    taxiFit: 8,
    personalFit: 9,
    workFit: 8,
  ),
  CarSpec(
    brand: 'Toyota',
    model: 'Yaris',
    bodyType: CarBodyType.hatchback,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(22, 30),
    usedPriceM: PriceRangeM(8, 20),
    fuelEfficiency: 9,
    comfort: 6,
    space: 5,
    resale: 8,
    maintenance: 9,
    reliability: 9,
    taxiFit: 8,
    personalFit: 7,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Toyota',
    model: 'RAV4',
    bodyType: CarBodyType.suv,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(52, 75),
    usedPriceM: PriceRangeM(28, 58),
    fuelEfficiency: 7,
    comfort: 8,
    space: 8,
    resale: 9,
    maintenance: 8,
    reliability: 9,
    taxiFit: 6,
    personalFit: 9,
    workFit: 8,
  ),
  CarSpec(
    brand: 'Nissan',
    model: 'Sunny',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(20, 28),
    usedPriceM: PriceRangeM(7, 18),
    fuelEfficiency: 8,
    comfort: 6,
    space: 6,
    resale: 7,
    maintenance: 8,
    reliability: 8,
    taxiFit: 8,
    personalFit: 7,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Nissan',
    model: 'Altima',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(39, 56),
    usedPriceM: PriceRangeM(16, 38),
    fuelEfficiency: 7,
    comfort: 8,
    space: 8,
    resale: 7,
    maintenance: 7,
    reliability: 7,
    taxiFit: 6,
    personalFit: 8,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Hyundai',
    model: 'Accent',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(18, 26),
    usedPriceM: PriceRangeM(6, 17),
    fuelEfficiency: 8,
    comfort: 6,
    space: 6,
    resale: 7,
    maintenance: 8,
    reliability: 7,
    taxiFit: 8,
    personalFit: 7,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Hyundai',
    model: 'Elantra',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(25, 36),
    usedPriceM: PriceRangeM(9, 26),
    fuelEfficiency: 8,
    comfort: 7,
    space: 7,
    resale: 7,
    maintenance: 8,
    reliability: 7,
    taxiFit: 8,
    personalFit: 8,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Kia',
    model: 'Rio',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(18, 26),
    usedPriceM: PriceRangeM(6, 17),
    fuelEfficiency: 8,
    comfort: 6,
    space: 6,
    resale: 7,
    maintenance: 8,
    reliability: 7,
    taxiFit: 8,
    personalFit: 7,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Kia',
    model: 'Cerato',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(24, 35),
    usedPriceM: PriceRangeM(8, 24),
    fuelEfficiency: 7,
    comfort: 7,
    space: 7,
    resale: 7,
    maintenance: 8,
    reliability: 7,
    taxiFit: 7,
    personalFit: 8,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Chevrolet',
    model: 'Malibu',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(35, 50),
    usedPriceM: PriceRangeM(12, 35),
    fuelEfficiency: 6,
    comfort: 8,
    space: 8,
    resale: 6,
    maintenance: 6,
    reliability: 6,
    taxiFit: 5,
    personalFit: 8,
    workFit: 6,
  ),
  CarSpec(
    brand: 'Ford',
    model: 'Focus',
    bodyType: CarBodyType.hatchback,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(25, 36),
    usedPriceM: PriceRangeM(8, 24),
    fuelEfficiency: 7,
    comfort: 7,
    space: 6,
    resale: 6,
    maintenance: 6,
    reliability: 6,
    taxiFit: 6,
    personalFit: 7,
    workFit: 6,
  ),
  CarSpec(
    brand: 'Honda',
    model: 'Civic',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(35, 50),
    usedPriceM: PriceRangeM(14, 35),
    fuelEfficiency: 8,
    comfort: 8,
    space: 7,
    resale: 8,
    maintenance: 7,
    reliability: 8,
    taxiFit: 7,
    personalFit: 9,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Mazda',
    model: 'Mazda 3',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(30, 44),
    usedPriceM: PriceRangeM(10, 30),
    fuelEfficiency: 7,
    comfort: 8,
    space: 6,
    resale: 7,
    maintenance: 7,
    reliability: 8,
    taxiFit: 6,
    personalFit: 8,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Mitsubishi',
    model: 'Lancer',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(26, 34),
    usedPriceM: PriceRangeM(8, 24),
    fuelEfficiency: 7,
    comfort: 6,
    space: 6,
    resale: 7,
    maintenance: 8,
    reliability: 7,
    taxiFit: 7,
    personalFit: 7,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Suzuki',
    model: 'Swift',
    bodyType: CarBodyType.hatchback,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(16, 24),
    usedPriceM: PriceRangeM(5, 16),
    fuelEfficiency: 9,
    comfort: 5,
    space: 5,
    resale: 7,
    maintenance: 8,
    reliability: 8,
    taxiFit: 7,
    personalFit: 7,
    workFit: 6,
  ),
  CarSpec(
    brand: 'Volkswagen',
    model: 'Jetta',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(33, 48),
    usedPriceM: PriceRangeM(12, 34),
    fuelEfficiency: 7,
    comfort: 8,
    space: 7,
    resale: 6,
    maintenance: 6,
    reliability: 6,
    taxiFit: 5,
    personalFit: 8,
    workFit: 6,
  ),
  CarSpec(
    brand: 'BMW',
    model: '3 Series',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(75, 115),
    usedPriceM: PriceRangeM(25, 70),
    fuelEfficiency: 6,
    comfort: 9,
    space: 7,
    resale: 7,
    maintenance: 4,
    reliability: 6,
    taxiFit: 3,
    personalFit: 9,
    workFit: 6,
  ),
  CarSpec(
    brand: 'Mercedes-Benz',
    model: 'C-Class',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(80, 125),
    usedPriceM: PriceRangeM(28, 75),
    fuelEfficiency: 6,
    comfort: 9,
    space: 7,
    resale: 7,
    maintenance: 4,
    reliability: 6,
    taxiFit: 3,
    personalFit: 9,
    workFit: 6,
  ),
  CarSpec(
    brand: 'Audi',
    model: 'A4',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(78, 120),
    usedPriceM: PriceRangeM(24, 70),
    fuelEfficiency: 6,
    comfort: 9,
    space: 7,
    resale: 6,
    maintenance: 4,
    reliability: 6,
    taxiFit: 2,
    personalFit: 9,
    workFit: 6,
  ),
  CarSpec(
    brand: 'Tesla',
    model: 'Model 3',
    bodyType: CarBodyType.sedan,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: true,
    newPriceM: PriceRangeM(70, 110),
    usedPriceM: PriceRangeM(45, 85),
    fuelEfficiency: 10,
    comfort: 8,
    space: 7,
    resale: 7,
    maintenance: 6,
    reliability: 7,
    taxiFit: 5,
    personalFit: 9,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Toyota',
    model: 'Prado',
    bodyType: CarBodyType.suv,
    seats: 7,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(95, 150),
    usedPriceM: PriceRangeM(45, 95),
    fuelEfficiency: 5,
    comfort: 8,
    space: 9,
    resale: 9,
    maintenance: 7,
    reliability: 9,
    taxiFit: 3,
    personalFit: 9,
    workFit: 8,
  ),
  CarSpec(
    brand: 'Nissan',
    model: 'Patrol',
    bodyType: CarBodyType.suv,
    seats: 7,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(120, 180),
    usedPriceM: PriceRangeM(55, 120),
    fuelEfficiency: 4,
    comfort: 9,
    space: 9,
    resale: 9,
    maintenance: 6,
    reliability: 8,
    taxiFit: 2,
    personalFit: 9,
    workFit: 8,
  ),
  CarSpec(
    brand: 'Hyundai',
    model: 'Tucson',
    bodyType: CarBodyType.crossover,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(40, 60),
    usedPriceM: PriceRangeM(18, 42),
    fuelEfficiency: 7,
    comfort: 8,
    space: 8,
    resale: 7,
    maintenance: 8,
    reliability: 7,
    taxiFit: 5,
    personalFit: 9,
    workFit: 8,
  ),
  CarSpec(
    brand: 'Kia',
    model: 'Sportage',
    bodyType: CarBodyType.crossover,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(42, 63),
    usedPriceM: PriceRangeM(20, 45),
    fuelEfficiency: 7,
    comfort: 8,
    space: 8,
    resale: 7,
    maintenance: 8,
    reliability: 7,
    taxiFit: 5,
    personalFit: 9,
    workFit: 8,
  ),
  CarSpec(
    brand: 'Chevrolet',
    model: 'Tahoe',
    bodyType: CarBodyType.suv,
    seats: 7,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(110, 170),
    usedPriceM: PriceRangeM(45, 110),
    fuelEfficiency: 4,
    comfort: 9,
    space: 10,
    resale: 8,
    maintenance: 5,
    reliability: 6,
    taxiFit: 2,
    personalFit: 9,
    workFit: 8,
  ),
  CarSpec(
    brand: 'Ford',
    model: 'Explorer',
    bodyType: CarBodyType.suv,
    seats: 7,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(95, 145),
    usedPriceM: PriceRangeM(35, 95),
    fuelEfficiency: 5,
    comfort: 8,
    space: 9,
    resale: 7,
    maintenance: 5,
    reliability: 6,
    taxiFit: 2,
    personalFit: 9,
    workFit: 8,
  ),
  CarSpec(
    brand: 'Jeep',
    model: 'Grand Cherokee',
    bodyType: CarBodyType.suv,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(105, 165),
    usedPriceM: PriceRangeM(36, 105),
    fuelEfficiency: 5,
    comfort: 8,
    space: 8,
    resale: 7,
    maintenance: 5,
    reliability: 6,
    taxiFit: 2,
    personalFit: 9,
    workFit: 7,
  ),
  CarSpec(
    brand: 'GMC',
    model: 'Yukon',
    bodyType: CarBodyType.suv,
    seats: 7,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(125, 190),
    usedPriceM: PriceRangeM(50, 125),
    fuelEfficiency: 4,
    comfort: 9,
    space: 10,
    resale: 8,
    maintenance: 5,
    reliability: 6,
    taxiFit: 2,
    personalFit: 9,
    workFit: 8,
  ),
  CarSpec(
    brand: 'Cadillac',
    model: 'Escalade',
    bodyType: CarBodyType.suv,
    seats: 7,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(150, 220),
    usedPriceM: PriceRangeM(70, 150),
    fuelEfficiency: 4,
    comfort: 10,
    space: 10,
    resale: 8,
    maintenance: 4,
    reliability: 6,
    taxiFit: 1,
    personalFit: 9,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Subaru',
    model: 'Forester',
    bodyType: CarBodyType.crossover,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(45, 65),
    usedPriceM: PriceRangeM(20, 45),
    fuelEfficiency: 7,
    comfort: 7,
    space: 8,
    resale: 7,
    maintenance: 7,
    reliability: 8,
    taxiFit: 4,
    personalFit: 8,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Volvo',
    model: 'XC60',
    bodyType: CarBodyType.suv,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(95, 145),
    usedPriceM: PriceRangeM(35, 95),
    fuelEfficiency: 6,
    comfort: 9,
    space: 8,
    resale: 7,
    maintenance: 5,
    reliability: 7,
    taxiFit: 2,
    personalFit: 9,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Porsche',
    model: 'Cayenne',
    bodyType: CarBodyType.suv,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(160, 260),
    usedPriceM: PriceRangeM(70, 160),
    fuelEfficiency: 5,
    comfort: 9,
    space: 8,
    resale: 7,
    maintenance: 4,
    reliability: 6,
    taxiFit: 1,
    personalFit: 9,
    workFit: 6,
  ),
  CarSpec(
    brand: 'Land Rover',
    model: 'Defender',
    bodyType: CarBodyType.suv,
    seats: 7,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(145, 230),
    usedPriceM: PriceRangeM(70, 160),
    fuelEfficiency: 4,
    comfort: 9,
    space: 9,
    resale: 7,
    maintenance: 4,
    reliability: 5,
    taxiFit: 1,
    personalFit: 9,
    workFit: 8,
  ),
  CarSpec(
    brand: 'Jaguar',
    model: 'F-Pace',
    bodyType: CarBodyType.suv,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: true,
    isElectric: false,
    newPriceM: PriceRangeM(110, 170),
    usedPriceM: PriceRangeM(45, 110),
    fuelEfficiency: 5,
    comfort: 9,
    space: 8,
    resale: 6,
    maintenance: 4,
    reliability: 5,
    taxiFit: 1,
    personalFit: 9,
    workFit: 7,
  ),
  CarSpec(
    brand: 'MG',
    model: 'ZS',
    bodyType: CarBodyType.crossover,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(28, 42),
    usedPriceM: PriceRangeM(14, 30),
    fuelEfficiency: 7,
    comfort: 7,
    space: 7,
    resale: 6,
    maintenance: 7,
    reliability: 6,
    taxiFit: 6,
    personalFit: 8,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Changan',
    model: 'CS35',
    bodyType: CarBodyType.crossover,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(26, 38),
    usedPriceM: PriceRangeM(12, 28),
    fuelEfficiency: 7,
    comfort: 6,
    space: 7,
    resale: 6,
    maintenance: 7,
    reliability: 6,
    taxiFit: 6,
    personalFit: 7,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Geely',
    model: 'Coolray',
    bodyType: CarBodyType.crossover,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(30, 45),
    usedPriceM: PriceRangeM(16, 34),
    fuelEfficiency: 7,
    comfort: 7,
    space: 7,
    resale: 6,
    maintenance: 7,
    reliability: 6,
    taxiFit: 5,
    personalFit: 8,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Haval',
    model: 'H6',
    bodyType: CarBodyType.suv,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(40, 58),
    usedPriceM: PriceRangeM(22, 45),
    fuelEfficiency: 6,
    comfort: 7,
    space: 8,
    resale: 6,
    maintenance: 6,
    reliability: 6,
    taxiFit: 4,
    personalFit: 8,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Chery',
    model: 'Tiggo 7',
    bodyType: CarBodyType.suv,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(35, 52),
    usedPriceM: PriceRangeM(18, 38),
    fuelEfficiency: 6,
    comfort: 7,
    space: 8,
    resale: 6,
    maintenance: 7,
    reliability: 6,
    taxiFit: 5,
    personalFit: 8,
    workFit: 7,
  ),
  CarSpec(
    brand: 'BYD',
    model: 'Atto 3',
    bodyType: CarBodyType.crossover,
    seats: 5,
    hasAutomatic: true,
    hasManual: false,
    hasHybrid: false,
    isElectric: true,
    newPriceM: PriceRangeM(55, 85),
    usedPriceM: PriceRangeM(35, 65),
    fuelEfficiency: 10,
    comfort: 8,
    space: 8,
    resale: 7,
    maintenance: 7,
    reliability: 7,
    taxiFit: 6,
    personalFit: 8,
    workFit: 7,
  ),
  CarSpec(
    brand: 'Isuzu',
    model: 'D-Max',
    bodyType: CarBodyType.pickup,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(50, 78),
    usedPriceM: PriceRangeM(20, 55),
    fuelEfficiency: 6,
    comfort: 6,
    space: 8,
    resale: 8,
    maintenance: 8,
    reliability: 8,
    taxiFit: 3,
    personalFit: 7,
    workFit: 10,
  ),
  CarSpec(
    brand: 'Great Wall',
    model: 'Poer',
    bodyType: CarBodyType.pickup,
    seats: 5,
    hasAutomatic: true,
    hasManual: true,
    hasHybrid: false,
    isElectric: false,
    newPriceM: PriceRangeM(45, 72),
    usedPriceM: PriceRangeM(24, 55),
    fuelEfficiency: 6,
    comfort: 6,
    space: 8,
    resale: 6,
    maintenance: 7,
    reliability: 7,
    taxiFit: 3,
    personalFit: 7,
    workFit: 9,
  ),
];
