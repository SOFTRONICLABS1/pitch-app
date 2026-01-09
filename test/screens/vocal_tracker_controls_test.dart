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

  testWidgets('VocalTracker controls render with harmonics disabled', (tester) async {
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

    final harmonicsButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.graphic_eq),
    );
    expect(harmonicsButton.onPressed, isNull);

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });
}
