import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/company/models/company_models.dart';

void main() {
  test('company bootstrap parses dynamically keyed membership maps', () {
    final bootstrap = CompanyPortalBootstrap.fromJson({
      'user': {
        'id': 720,
        'fullName': 'شركة مسلكي',
        'phone': '07701231231',
        'role': 'company_portal',
      },
      'memberships': <Map<dynamic, dynamic>>[
        {
          'id': 1,
          'companyId': 1,
          'userId': 720,
          'role': 'company_owner',
          'companyName': 'شركة مسلكي',
          'companyCode': 'maslaki',
          'companyStatus': 'active',
        },
      ],
    });

    expect(bootstrap.user.role, 'company_portal');
    expect(bootstrap.memberships, hasLength(1));
    expect(bootstrap.memberships.single.companyId, 1);
    expect(bootstrap.memberships.single.companyName, 'شركة مسلكي');
  });
  test(
    'company branch detail keeps dynamically keyed inventory and products',
    () {
      final detail = CompanyBranchDetail.fromJson({
        'branch': {'id': 54, 'name': 'Maslaki bakery'},
        'inventoryItems': <Map<dynamic, dynamic>>[
          {
            'id': 10,
            'productId': 99,
            'productName': 'Bread',
            'quantity': 8,
            'stockStatus': 'in_stock',
            'productIsAvailable': true,
          },
        ],
        'products': <Map<dynamic, dynamic>>[
          {'id': 99, 'name': 'Bread', 'price': 1000, 'is_available': true},
        ],
        'categories': <Map<dynamic, dynamic>>[
          {'id': 5, 'name': 'Bakery'},
        ],
      });

      expect(detail.branch.id, 54);
      expect(detail.inventoryItems, hasLength(1));
      expect(detail.inventoryItems.single.productId, 99);
      expect(detail.products, hasLength(1));
      expect(detail.categories, hasLength(1));
    },
  );
}
