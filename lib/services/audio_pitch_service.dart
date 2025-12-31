import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:sound_stream/sound_stream.dart';

import '../dsp/pitch_detection.dart';

typedef PitchCallback = void Function(PitchDetectionResult? result);

class AudioPitchService {
  AudioPitchService({
    required this.onResult,
    required this.detectorFactory,
    required this.sampleRate,
    required this.windowSize,
    required this.hopSize,
    required this.powerThreshold,
    required this.clarityThreshold,
  });

  final PitchCallback onResult;
  final PitchDetector Function() detectorFactory;
  final int sampleRate;
  final int windowSize;
  final int hopSize;
  final double powerThreshold;
  final double clarityThreshold;

  final List<double> _buffer = [];
  RecorderStream? _recorder;
  StreamSubscription<Uint8List>? _subscription;
  PitchDetector? _detector;

  bool _starting = false;

  Future<void> start() async {
    if (_starting) return;
    _starting = true;
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        throw const MicrophonePermissionException(
          'Microphone permission is required to detect pitch.',
        );
      }

      _detector = detectorFactory();
      _recorder = RecorderStream();

      await _recorder!.initialize(sampleRate: sampleRate);
      await _recorder!.start();

      _subscription = _recorder!.audioStream.listen(
        _handleSamples,
        onError: (error) {
          onResult(null);
        },
      );
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _recorder?.stop();
    _recorder = null;
    _buffer.clear();
  }

  void _handleSamples(Uint8List chunk) {
    if (chunk.isEmpty) return;
    // Data arrives as 16-bit PCM; convert to normalized doubles.
    final bytes = Uint8List.fromList(chunk);
    final usableLength = bytes.lengthInBytes - (bytes.lengthInBytes % 2);
    if (usableLength == 0) {
      return;
    }
    final samples = Int16List.view(bytes.buffer, 0, usableLength ~/ 2);
    for (final sample in samples) {
      _buffer.add(sample / 32768.0);
    }
    while (_buffer.length >= windowSize) {
      final window = _buffer.sublist(0, windowSize);
      PitchDetectionResult? result;
      try {
        result = _detector?.getPitch(
          window,
          sampleRate,
          powerThreshold,
          clarityThreshold,
        );
      } catch (_) {
        result = null;
      }
      onResult(result);
      final drop = min(hopSize, _buffer.length);
      _buffer.removeRange(0, drop);
    }
  }
}

class MicrophonePermissionException implements Exception {
  const MicrophonePermissionException(this.message);
  final String message;

  @override
  String toString() => message;
}
