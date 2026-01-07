import 'package:headset_connection_event/headset_event.dart';

class HeadsetService {
  static final HeadsetEvent _event = HeadsetEvent();

  static Future<bool> isHeadsetConnected() async {
    try {
      await _event.requestPermission();
      final state = await _event.getCurrentState;
      return state == HeadsetState.CONNECT;
    } catch (_) {
      return false;
    }
  }
}
