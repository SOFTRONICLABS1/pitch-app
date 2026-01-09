import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pitch_app/models/recording.dart';
import 'package:pitch_app/screens/vocal_tracker.dart';
import 'package:pitch_app/state/pitch_notifier.dart';

import '../helpers/plugin_mocks.dart';

void main() {
  setUpAll(() async {
    await setupPluginMocks();
  });

  testWidgets('Vocal Tracker settings opens and shows BPM', (tester) async {
    final entry = RecordingEntry(
      id: '1',
      name: 'Test Recording',
      createdAt: DateTime(2024, 1, 1),
      notes: const [
        RecordedNote(note: 'a3', durationMs: 1000),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PitchNotifier(),
        child: MaterialApp(
          home: VocalTrackerScreen(recording: entry),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('60'), findsWidgets);
  });
}
