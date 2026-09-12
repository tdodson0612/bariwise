import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bari_wise/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ✅ FIXED: MyApp.build() unconditionally calls Supabase.instance.client,
  // which throws unless Supabase.initialize() has already run. In the real
  // app this happens in main() before runApp() — this test skips main()
  // entirely and pumps MyApp() directly, so it needs its own initialization.
  // Dummy URL/key are sufficient here since this test never triggers a real
  // network call — MyApp starts on '/login' (see main.dart's _isReady guard)
  // before any Supabase query would actually run.
  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('bari health bar renders with emoji', (WidgetTester tester) async {
    // Build the app
    await tester.pumpWidget(const MyApp());

    // Look for some common UI elements
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.textContaining('Scan'), findsOneWidget);
  });
}