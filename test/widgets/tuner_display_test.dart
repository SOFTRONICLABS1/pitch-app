import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/state/pitch_notifier.dart';
import 'package:pitch_app/widgets/tuner_display.dart';

void main() {
  testWidgets('TunerDisplay renders with empty history', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TunerDisplay(history: const []),
        ),
      ),
    );

    expect(find.byType(TunerDisplay), findsOneWidget);
  });

  testWidgets('TunerDisplay renders with sample history', (tester) async {
    final now = DateTime(2024, 1, 1, 12, 0, 0);
    final history = [
      PitchPoint(time: now, frequency: 440.0, clarity: 0.9),
      PitchPoint(time: now.add(const Duration(milliseconds: 50)), frequency: 445.0, clarity: 0.9),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TunerDisplay(
            history: history,
            nowOverride: now,
          ),
        ),
      ),
    );

    expect(find.byType(TunerDisplay), findsOneWidget);
  });
}
