class CarBrandCatalog {
  final String brand;
  final List<String> models;

  const CarBrandCatalog({required this.brand, required this.models});
}

const carCatalog = <CarBrandCatalog>[
  CarBrandCatalog(
    brand: 'Toyota',
    models: [
      'Corolla',
      'Camry',
      'Yaris',
      'Avalon',
      'Crown',
      'Prius',
      'RAV4',
      'C-HR',
      'Land Cruiser',
      'Prado',
      'Hilux',
      'Fortuner',
      'Rush',
    ],
  ),
  CarBrandCatalog(
    brand: 'Nissan',
    models: [
      'Sunny',
      'Sentra',
      'Altima',
      'Maxima',
      'Patrol',
      'X-Trail',
      'Kicks',
      'Juke',
      'Navara',
      '370Z',
    ],
  ),
  CarBrandCatalog(
    brand: 'Hyundai',
    models: [
      'Accent',
      'Elantra',
      'Sonata',
      'Azera',
      'i10',
      'i20',
      'Creta',
      'Tucson',
      'Santa Fe',
      'Palisade',
      'Staria',
    ],
  ),
  CarBrandCatalog(
    brand: 'Kia',
    models: [
      'Picanto',
      'Rio',
      'Cerato',
      'K5',
      'K8',
      'Seltos',
      'Sportage',
      'Sorento',
      'Telluride',
      'Carens',
    ],
  ),
  CarBrandCatalog(
    brand: 'Chevrolet',
    models: [
      'Spark',
      'Aveo',
      'Malibu',
      'Impala',
      'Captiva',
      'Trailblazer',
      'Traverse',
      'Tahoe',
      'Suburban',
      'Silverado',
    ],
  ),
  CarBrandCatalog(
    brand: 'Ford',
    models: [
      'Figo',
      'Focus',
      'Fusion',
      'Taurus',
      'Mustang',
      'Explorer',
      'Edge',
      'Expedition',
      'Ranger',
      'F-150',
    ],
  ),
  CarBrandCatalog(
    brand: 'Honda',
    models: [
      'City',
      'Civic',
      'Accord',
      'CR-V',
      'HR-V',
      'Pilot',
      'Odyssey',
      'Jazz',
    ],
  ),
  CarBrandCatalog(
    brand: 'Mazda',
    models: [
      'Mazda 2',
      'Mazda 3',
      'Mazda 6',
      'CX-3',
      'CX-5',
      'CX-9',
      'BT-50',
      'MX-5',
    ],
  ),
  CarBrandCatalog(
    brand: 'Mitsubishi',
    models: [
      'Lancer',
      'Attrage',
      'ASX',
      'Outlander',
      'Pajero',
      'Montero Sport',
      'Eclipse Cross',
      'L200',
    ],
  ),
  CarBrandCatalog(
    brand: 'Suzuki',
    models: [
      'Alto',
      'Swift',
      'Ciaz',
      'Ertiga',
      'Vitara',
      'Jimny',
      'Baleno',
      'Dzire',
    ],
  ),
  CarBrandCatalog(
    brand: 'Volkswagen',
    models: [
      'Polo',
      'Golf',
      'Passat',
      'Jetta',
      'Tiguan',
      'Touareg',
      'T-Roc',
      'Arteon',
    ],
  ),
  CarBrandCatalog(
    brand: 'BMW',
    models: [
      '1 Series',
      '2 Series',
      '3 Series',
      '4 Series',
      '5 Series',
      '7 Series',
      'X1',
      'X3',
      'X5',
      'X6',
    ],
  ),
  CarBrandCatalog(
    brand: 'Mercedes-Benz',
    models: [
      'A-Class',
      'C-Class',
      'E-Class',
      'S-Class',
      'CLA',
      'GLA',
      'GLC',
      'GLE',
      'GLS',
      'G-Class',
    ],
  ),
  CarBrandCatalog(
    brand: 'Audi',
    models: ['A3', 'A4', 'A6', 'A8', 'Q2', 'Q3', 'Q5', 'Q7', 'Q8'],
  ),
  CarBrandCatalog(
    brand: 'Lexus',
    models: ['IS', 'ES', 'LS', 'UX', 'NX', 'RX', 'GX', 'LX'],
  ),
  CarBrandCatalog(
    brand: 'Renault',
    models: [
      'Logan',
      'Symbol',
      'Megane',
      'Duster',
      'Koleos',
      'Captur',
      'Sandero',
      'Clio',
    ],
  ),
  CarBrandCatalog(
    brand: 'Peugeot',
    models: ['208', '301', '308', '508', '2008', '3008', '5008', 'Partner'],
  ),
  CarBrandCatalog(
    brand: 'Skoda',
    models: ['Fabia', 'Octavia', 'Superb', 'Kodiaq', 'Karoq', 'Kamiq'],
  ),
  CarBrandCatalog(
    brand: 'Seat',
    models: ['Ibiza', 'Leon', 'Toledo', 'Arona', 'Ateca', 'Tarraco'],
  ),
  CarBrandCatalog(
    brand: 'Fiat',
    models: ['500', 'Panda', 'Tipo', 'Egea', 'Doblo', 'Fiorino'],
  ),
  CarBrandCatalog(
    brand: 'Jeep',
    models: [
      'Renegade',
      'Compass',
      'Cherokee',
      'Grand Cherokee',
      'Wrangler',
      'Gladiator',
    ],
  ),
  CarBrandCatalog(
    brand: 'Dodge',
    models: ['Charger', 'Challenger', 'Durango', 'Journey'],
  ),
  CarBrandCatalog(
    brand: 'GMC',
    models: ['Terrain', 'Acadia', 'Yukon', 'Sierra', 'Canyon'],
  ),
  CarBrandCatalog(
    brand: 'Cadillac',
    models: ['CT4', 'CT5', 'XT4', 'XT5', 'XT6', 'Escalade'],
  ),
  CarBrandCatalog(
    brand: 'Subaru',
    models: ['Impreza', 'Legacy', 'XV', 'Forester', 'Outback', 'WRX', 'BRZ'],
  ),
  CarBrandCatalog(
    brand: 'Volvo',
    models: ['S60', 'S90', 'XC40', 'XC60', 'XC90', 'V60'],
  ),
  CarBrandCatalog(
    brand: 'Porsche',
    models: [
      '718 Cayman',
      '718 Boxster',
      'Macan',
      'Cayenne',
      'Panamera',
      'Taycan',
    ],
  ),
  CarBrandCatalog(
    brand: 'Land Rover',
    models: [
      'Defender',
      'Discovery',
      'Discovery Sport',
      'Range Rover',
      'Evoque',
      'Velar',
    ],
  ),
  CarBrandCatalog(
    brand: 'Jaguar',
    models: ['XE', 'XF', 'F-Pace', 'E-Pace', 'I-Pace'],
  ),
  CarBrandCatalog(
    brand: 'Tesla',
    models: ['Model 3', 'Model S', 'Model X', 'Model Y', 'Cybertruck'],
  ),
  CarBrandCatalog(
    brand: 'MG',
    models: ['MG3', 'MG5', 'MG6', 'ZS', 'HS', 'RX5'],
  ),
  CarBrandCatalog(
    brand: 'Changan',
    models: ['Alsvin', 'Eado', 'CS35', 'CS55', 'CS75', 'UNI-T', 'UNI-K'],
  ),
  CarBrandCatalog(
    brand: 'Geely',
    models: [
      'Emgrand',
      'Coolray',
      'Azkarra',
      'Tugella',
      'Monjaro',
      'Geometry C',
    ],
  ),
  CarBrandCatalog(brand: 'Haval', models: ['Jolion', 'H6', 'H9', 'Dargo']),
  CarBrandCatalog(
    brand: 'Chery',
    models: [
      'Arrizo 5',
      'Arrizo 6',
      'Tiggo 2',
      'Tiggo 4',
      'Tiggo 7',
      'Tiggo 8',
    ],
  ),
  CarBrandCatalog(
    brand: 'BYD',
    models: [
      'F3',
      'Qin',
      'Han',
      'Song',
      'Yuan',
      'Tang',
      'Dolphin',
      'Atto 3',
      'Seal',
    ],
  ),
  CarBrandCatalog(brand: 'Dongfeng', models: ['Shine', 'S30', 'AX7', 'T5']),
  CarBrandCatalog(brand: 'Isuzu', models: ['D-Max', 'MU-X', 'N-Series']),
  CarBrandCatalog(brand: 'Great Wall', models: ['Wingle', 'Poer', 'Cannon']),
  CarBrandCatalog(
    brand: 'Infiniti',
    models: ['Q50', 'Q60', 'QX50', 'QX55', 'QX60', 'QX80'],
  ),
  CarBrandCatalog(brand: 'Acura', models: ['ILX', 'TLX', 'RDX', 'MDX', 'NSX']),
  CarBrandCatalog(brand: 'Alfa Romeo', models: ['Giulia', 'Stelvio', 'Tonale']),
];

List<String> carBrandNames() {
  return carCatalog.map((item) => item.brand).toList(growable: false);
}

List<String> carModelsForBrand(String brand) {
  for (final item in carCatalog) {
    if (item.brand.toLowerCase() == brand.toLowerCase()) {
      return item.models;
    }
  }
  return const [];
}
