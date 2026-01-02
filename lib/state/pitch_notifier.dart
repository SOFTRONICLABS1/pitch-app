import 'package:flutter/foundation.dart';

import '../dsp/pitch_detection.dart';
import '../native/pitch_bridge.dart';
import '../native/pitch_ffi.dart';
import '../services/audio_pitch_service.dart';

class PitchPoint {
  PitchPoint({
    required this.time,
    required this.frequency,
    required this.clarity,
  });

  final DateTime time;
  final double frequency;
  final double clarity;
}

class PitchNotifier extends ChangeNotifier {
  PitchNotifier();

  static const defaultSampleRate = 44100;
  static const _historySpan = Duration(seconds: 12);

  double? frequency;
  double? clarity;
  String? errorMessage;

  bool listening = false;
  String detectorName = 'autocorrelation'; // or mcleod/yin
  int windowSize = 2048;
  int hopSize = 256;
  double clarityThreshold = 0.75;
  double powerThreshold = 0.15;
  String displayMode = 'timeline'; // or circle

  List<PitchPoint> history = [];

  AudioPitchService? _service;
  double? _smoothedFrequency;
  final List<double> _recentFrequencies = [];

  Future<void> start() async {
    if (listening) return;
    errorMessage = null;
    _service = AudioPitchService(
      onResult: _onResult,
      detectorFactory: _buildDetector,
      sampleRate: defaultSampleRate,
      windowSize: windowSize,
      hopSize: hopSize,
      powerThreshold: powerThreshold,
      clarityThreshold: clarityThreshold,
    );
    try {
      await _service!.start();
      listening = true;
    } catch (e) {
      errorMessage = e.toString();
      listening = false;
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _service?.stop();
    listening = false;
    frequency = null;
    clarity = null;
    notifyListeners();
  }

  Future<void> restartIfNeeded() async {
    if (!listening) return;
    await stop();
    await start();
  }

  void setDetector(String value) {
    detectorName = value;
    restartIfNeeded();
    notifyListeners();
  }

  void setWindowSize(int value) {
    windowSize = value;
    restartIfNeeded();
    notifyListeners();
  }

  void setClarityThreshold(double value) {
    clarityThreshold = value;
    restartIfNeeded();
    notifyListeners();
  }

  void setDisplayMode(String value) {
    displayMode = value;
    notifyListeners();
  }

  void _onResult(PitchDetectionResult? result) {
    if (result == null || result.clarity < clarityThreshold) {
      frequency = null;
      clarity = null;
    } else {
      final cleaned = _smoothFrequency(result.frequency);
      frequency = cleaned;
      clarity = result.clarity;
      final now = DateTime.now();
      history.add(
        PitchPoint(time: now, frequency: cleaned, clarity: result.clarity),
      );
      history = history
          .where((p) => p.time.isAfter(now.subtract(_historySpan)))
          .toList();
    }
    notifyListeners();
  }

  double _smoothFrequency(double next) {
    _recentFrequencies.add(next);
    if (_recentFrequencies.length > 5) {
      _recentFrequencies.removeAt(0);
    }
    final sorted = List<double>.from(_recentFrequencies)..sort();
    final median = sorted[sorted.length ~/ 2];
    final previous = _smoothedFrequency;
    const alpha = 0.25;
    final smoothed = previous == null
        ? median
        : previous + alpha * (median - previous);
    _smoothedFrequency = smoothed;
    return smoothed;
  }

  PitchDetector _buildDetector() {
    final useFfi = defaultTargetPlatform != TargetPlatform.iOS;
    switch (detectorName) {
      case 'autocorrelation':
        return useFfi
            ? RustPitchDetector(NativeDetector.autocorrelation)
            : AutocorrelationPitchDetector(size: windowSize);
      case 'yin':
        return useFfi
            ? RustPitchDetector(NativeDetector.yin)
            : McLeodPitchDetector(size: windowSize);
      case 'mcleod':
        return useFfi
            ? RustPitchDetector(NativeDetector.mcleod)
            : McLeodPitchDetector(size: windowSize);
      default:
        return useFfi
            ? RustPitchDetector(NativeDetector.mcleod)
            : McLeodPitchDetector(size: windowSize);
    }
  }
}
