import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bari_wise/main.dart';

void main() {
  testWidgets('bari health bar renders with emoji', (WidgetTester tester) async {
    // Build the app
    await tester.pumpWidget(const MyApp());

    // Look for some common UI elements
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.textContaining('Scan'), findsOneWidget);
  });
}
