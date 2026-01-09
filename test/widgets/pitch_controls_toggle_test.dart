import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pitch_app/state/pitch_notifier.dart';
import 'package:pitch_app/widgets/pitch_controls.dart';

import '../helpers/plugin_mocks.dart';

void main() {
  setUpAll(() async {
    await setupPluginMocks();
  });

  testWidgets('PitchControls toggles notation', (tester) async {
    final notifier = PitchNotifier();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: notifier,
        child: const MaterialApp(
          home: Scaffold(
            body: PitchControls(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Carnatic'));
    await tester.pump();

    expect(notifier.tuningSystem, 'carnatic');
  });
}
