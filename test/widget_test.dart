import 'package:bestoffer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots and shows login screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BestOfferApp()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('BestOffer'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.byIcon(Icons.storefront), findsOneWidget);
  });
}
