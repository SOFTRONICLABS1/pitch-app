import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen shows sign-in actions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
