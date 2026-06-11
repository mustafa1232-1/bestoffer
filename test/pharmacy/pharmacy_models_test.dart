import 'package:maslaki/features/pharmacy/models/pharmacy_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses pharmacy conversation details payload with owner-facing fields', () {
    final details = PharmacyConversationDetailsModel.fromJson({
      'conversation': {
        'id': 7,
        'merchantId': 42,
        'customerUserId': 1001,
        'merchantName': 'Health Pharmacy',
        'merchantImageUrl': 'https://example.com/pharmacy.png',
        'status': 'cart_proposed',
        'bucket': 'active',
        'activityType': 'pharmacy',
        'conversationType': 'pharmacy_direct',
        'supportsChat': true,
        'supportsAttachments': true,
        'supportsPharmacyWorkflow': true,
        'messagesCount': 3,
        'metadata': {
          'source': 'product_catalog',
        },
        'customer': {
          'fullName': 'Mona Ali',
          'phone': '+9647700000000',
        },
      },
      'messages': [
        {
          'id': 1,
          'conversationId': 7,
          'senderType': 'customer',
          'senderUserId': 1001,
          'senderFullName': 'Mona Ali',
          'messageType': 'text',
          'text': 'Need pain reliever',
          'metadata': {
            'productId': 10,
          },
        },
      ],
      'latestProposedCart': {
        'id': 9,
        'conversationId': 7,
        'version': 2,
        'status': 'proposed',
        'subtotal': 12000,
        'deliveryFee': 1000,
        'total': 13000,
        'notes': 'Take after food',
        'confirmedAt': '2026-05-29T10:00:00.000Z',
        'revisionRequestedAt': '2026-05-29T11:00:00.000Z',
        'items': [
          {
            'id': 1,
            'proposedCartId': 9,
            'productId': 10,
            'productName': 'Paracetamol',
            'quantity': 2,
            'unitPrice': 6000,
            'lineTotal': 12000,
            'note': '500mg',
            'alternativeGroupId': 'pain-tier-a',
            'requiresPrescription': false,
            'requiresReview': true,
            'metadata': {
              'sku': 'PARA-500',
            },
          },
        ],
      },
    });

    expect(details.conversation.id, 7);
    expect(details.conversation.supportsPharmacyWorkflow, isTrue);
    expect(details.conversation.messagesCount, 3);
    expect(details.conversation.customer?.fullName, 'Mona Ali');
    expect(details.messages.single.senderFullName, 'Mona Ali');
    expect(details.messages.single.metadata['productId'], 10);
    expect(details.latestProposedCart, isNotNull);
    expect(details.latestProposedCart!.notes, 'Take after food');
    expect(details.latestProposedCart!.revisionRequestedAt, isNotNull);
    expect(details.latestProposedCart!.items.single.productName, 'Paracetamol');
    expect(details.latestProposedCart!.items.single.note, '500mg');
    expect(
      details.latestProposedCart!.items.single.alternativeGroupId,
      'pain-tier-a',
    );
    expect(details.latestProposedCart!.items.single.requiresReview, isTrue);
  });
}
