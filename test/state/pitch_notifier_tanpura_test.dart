import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/state/pitch_notifier.dart';

import '../helpers/plugin_mocks.dart';

void main() {
  setUpAll(() async {
    await setupPluginMocks();
  });

  test('PitchNotifier toggles tanpura and restarts on note changes', () async {
    final notifier = PitchNotifier();
    expect(notifier.tanpuraPlaying, isFalse);

    await notifier.toggleTanpura();
    expect(notifier.tanpuraPlaying, isTrue);

    await notifier.setTanpuraNote('Sa');
    expect(notifier.tanpuraPlaying, isTrue);

    await notifier.setTanpuraString('Pa');
    expect(notifier.tanpuraPlaying, isTrue);

    await notifier.toggleTanpura();
    expect(notifier.tanpuraPlaying, isFalse);
  });
}
