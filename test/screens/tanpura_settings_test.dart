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

  testWidgets('Tanpura settings show western/carnatic pairs', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PitchNotifier(),
        child: const MaterialApp(
          home: Scaffold(
            body: PitchControls(),
          ),
        ),
      ),
    );

    expect(find.text('C - Sa'), findsWidgets);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('G - Pa'), findsWidgets);
  });
}
