import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pitch_app/screens/recordings_screen.dart';
import 'package:pitch_app/state/pitch_notifier.dart';

import '../helpers/plugin_mocks.dart';

void main() {
  setUpAll(() async {
    await setupPluginMocks();
  });

  testWidgets('Recordings add flow saves a new entry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PitchNotifier(),
        child: const MaterialApp(
          home: RecordingsScreen(),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Select notes'), findsOneWidget);

    final noteFinder = find.byWidgetPredicate((widget) {
      if (widget is! Text) return false;
      final text = widget.data ?? '';
      final western = RegExp(r'^[A-G]#?-?\d+$');
      final carnatic =
          RegExp(r'^(Sa|Ri1|Ri2|Ga1|Ga2|Ma1|Ma2|Pa|Da1|Da2|Ni1|Ni2)-\d+$');
      return western.hasMatch(text) || carnatic.hasMatch(text);
    });
    await _pumpUntilFound(tester, noteFinder);
    await tester.ensureVisible(noteFinder.first);
    await tester.tap(noteFinder.first);
    await tester.pump(const Duration(milliseconds: 200));

    await _ensureNextEnabled(tester, noteFinder.first);
    await _tapNext(tester);
    await tester.pump(const Duration(milliseconds: 200));

    await _pumpUntilFound(tester, find.text('Preview'));
    await _tapNext(tester);
    await tester.pump(const Duration(milliseconds: 200));

    await _pumpUntilFound(tester, find.text('Durations (ms)'));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pump(const Duration(milliseconds: 200));

    await _pumpUntilFound(tester, find.text('Save recording'));
    await tester.enterText(
      find.byType(TextField).last,
      'Test Recording',
    );
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 500));

    await _pumpUntilFound(tester, find.text('Test Recording'));
    expect(find.text('Test Recording'), findsOneWidget);
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

Future<void> _tapNext(WidgetTester tester) async {
  final finder = find.widgetWithText(FilledButton, 'Next');
  await _pumpUntilFound(tester, finder);
  await tester.tap(finder.last);
}

Future<void> _ensureNextEnabled(WidgetTester tester, Finder noteFinder) async {
  var nextFinder = find.widgetWithText(FilledButton, 'Next');
  await _pumpUntilFound(tester, nextFinder);
  var button = tester.widget<FilledButton>(nextFinder.last);
  if (button.onPressed != null) return;

  await tester.tap(noteFinder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(noteFinder);
  await tester.pump(const Duration(milliseconds: 200));

  button = tester.widget<FilledButton>(nextFinder.last);
  expect(button.onPressed, isNotNull);
}
