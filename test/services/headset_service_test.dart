import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/services/headset_service.dart';

import '../helpers/plugin_mocks.dart';

void main() {
  setUpAll(() async {
    await setupPluginMocks();
  });

  test('HeadsetService returns false when disconnected', () async {
    final connected = await HeadsetService.isHeadsetConnected();
    expect(connected, isFalse);
  });
}
