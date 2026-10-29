import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_news_buddy_flutter/app/app.dart';

void main() {
  testWidgets('opens the backup demo without Supabase', (tester) async {
    await tester.pumpWidget(const MyNewsBuddyApp(supabaseConfigured: false));

    expect(find.text('Local Companion'), findsOneWidget);
    expect(find.text('Continue in backup demo mode'), findsOneWidget);

    final demoButton = find.text('Continue in backup demo mode');
    await tester.ensureVisible(demoButton);
    await tester.pumpAndSettle();
    await tester.tap(demoButton);
    await tester.pump();

    expect(find.text('BACKUP LOCATION'), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}
