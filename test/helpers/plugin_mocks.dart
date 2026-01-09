import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _audioPlayersChannel =
    MethodChannel('xyz.luan/audioplayers');
const MethodChannel _audioPlayersGlobalChannel =
    MethodChannel('xyz.luan/audioplayers.global');
const MethodChannel _soundStreamChannel =
    MethodChannel('vn.casperpas.sound_stream:methods');
const MethodChannel _headsetChannel =
    MethodChannel('flutter.moum/headset_connection_event');
const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

Future<Directory> setupPluginMocks() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance
      .defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(_audioPlayersChannel, (call) async {
    switch (call.method) {
      case 'create':
        return 1;
      default:
        return null;
    }
  });
  messenger.setMockMethodCallHandler(_audioPlayersGlobalChannel, (call) async {
    return null;
  });

  messenger.setMockMethodCallHandler(_soundStreamChannel, (call) async {
    return null;
  });

  messenger.setMockMethodCallHandler(_headsetChannel, (call) async {
    if (call.method == 'getCurrentState') {
      return 0;
    }
    return null;
  });

  messenger.setMockMessageHandler('flutter/assets', (message) async {
    return ByteData(0);
  });

  final tempDir = await Directory.systemTemp.createTemp('pitch_app_test');
  messenger.setMockMethodCallHandler(_pathProviderChannel, (call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
      case 'getTemporaryDirectory':
      case 'getApplicationSupportDirectory':
        return tempDir.path;
      default:
        return tempDir.path;
    }
  });

  return tempDir;
}
