import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:pitch_app/screens/recordings_screen.dart';

import '../helpers/plugin_mocks.dart';

void main() {
  setUpAll(() async {
    await setupPluginMocks();
  });

  testWidgets('Edit notes disables update on invalid input', (tester) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/recordings.json');
    final payload = jsonEncode([
      {
        'id': '1',
        'name': 'Test Recording',
        'createdAt': DateTime(2024, 1, 1).toIso8601String(),
        'notes': [
          {'note': 'c4', 'durationMs': 1000}
        ],
      },
    ]);
    await file.writeAsString(payload);

    await tester.pumpWidget(
      const MaterialApp(
        home: RecordingsScreen(),
      ),
    );

    await _pumpUntilFound(tester, find.text('Test Recording'));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    await tester.enterText(find.byType(TextField).first, '??');
    await tester.pump(const Duration(milliseconds: 200));

    final updateButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Update'),
    );
    expect(updateButton.onPressed, isNull);
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for ${finder.description}');
}
