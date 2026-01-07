import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../dsp/pitch_detection.dart';
import '../native/pitch_bridge.dart';
import '../native/pitch_ffi.dart';
import '../services/audio_pitch_service.dart';
import '../models/recording.dart';

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
  String tuningSystem = 'western'; // or carnatic
  String tanpuraString = 'Sa';
  String tanpuraNote = 'Sa';
  bool tanpuraPlaying = false;
  bool recording = false;

  List<PitchPoint> history = [];

  AudioPitchService? _service;
  double? _smoothedFrequency;
  final List<double> _recentFrequencies = [];
  final AudioPlayer _tanpuraPlayer = AudioPlayer();
  final List<RecordedNote> _recordedNotes = [];
  DateTime? _recordingStartedAt;
  DateTime? _currentNoteStart;
  String? _currentNote;
  DateTime? _lastSampleAt;
  static const _noteGapTolerance = Duration(milliseconds: 200);

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

  void setTuningSystem(String value) {
    tuningSystem = value;
    notifyListeners();
  }

  void replaceHistory(List<PitchPoint> nextHistory) {
    history = List<PitchPoint>.from(nextHistory);
    notifyListeners();
  }

  void setTanpuraString(String value) {
    tanpuraString = value;
    if (tanpuraPlaying) {
      _restartTanpura();
    } else {
      notifyListeners();
    }
  }

  void setTanpuraNote(String value) {
    tanpuraNote = value;
    if (tanpuraPlaying) {
      _restartTanpura();
    } else {
      notifyListeners();
    }
  }

  Future<void> startRecording() async {
    if (recording) return;
    if (!listening) {
      await start();
      if (!listening) {
        return;
      }
    }
    recording = true;
    _recordedNotes.clear();
    _recordingStartedAt = DateTime.now();
    _currentNote = null;
    _currentNoteStart = null;
    notifyListeners();
  }

  RecordingDraft stopRecording() {
    if (!recording) {
      return RecordingDraft(
        startedAt: DateTime.now(),
        endedAt: DateTime.now(),
        notes: const [],
      );
    }
    final endedAt = DateTime.now();
    _finalizeCurrentNote(endedAt);
    recording = false;
    notifyListeners();
    return RecordingDraft(
      startedAt: _recordingStartedAt ?? endedAt,
      endedAt: endedAt,
      notes: List<RecordedNote>.from(_recordedNotes),
    );
  }

  Future<void> toggleTanpura() async {
    if (tanpuraPlaying) {
      await _tanpuraPlayer.stop();
      tanpuraPlaying = false;
      notifyListeners();
      return;
    }
    await _restartTanpura();
  }

  Future<void> _restartTanpura() async {
    final asset = _tanpuraAssetPath();
    await _tanpuraPlayer.setReleaseMode(ReleaseMode.loop);
    await _tanpuraPlayer.stop();
    await _tanpuraPlayer.play(AssetSource(asset));
    tanpuraPlaying = true;
    notifyListeners();
  }

  String _tanpuraAssetPath() {
    final stringPart = _normalizeForAsset(tanpuraString);
    final notePart = _tanpuraNoteToken(tanpuraNote);
    return 'tanpura-tones/${stringPart}_$notePart.wav';
  }

  String _normalizeForAsset(String value) {
    return value.toLowerCase().replaceAll(' ', '');
  }

  String _tanpuraNoteToken(String value) {
    const westernTokens = {
      'C': 'c',
      'C#': 'csharp',
      'D': 'd',
      'D#': 'dsharp',
      'E': 'e',
      'F': 'f',
      'F#': 'fsharp',
      'G': 'g',
      'G#': 'gsharp',
      'A': 'a',
      'A#': 'asharp',
      'B': 'b',
    };
    const carnaticToWestern = {
      'Sa': 'C',
      'Ri1': 'C#',
      'Ri2': 'D',
      'Ga1': 'D#',
      'Ga2': 'E',
      'Ma1': 'F',
      'Ma2': 'F#',
      'Pa': 'G',
      'Da1': 'G#',
      'Da2': 'A',
      'Ni1': 'A#',
      'Ni2': 'B',
    };
    final western = westernTokens[value];
    if (western != null) {
      return western;
    }
    final mapped = carnaticToWestern[value];
    if (mapped != null) {
      return westernTokens[mapped] ?? _normalizeForAsset(mapped);
    }
    return _normalizeForAsset(value);
  }

  @override
  void dispose() {
    _tanpuraPlayer.dispose();
    super.dispose();
  }

  void _onResult(PitchDetectionResult? result) {
    final now = DateTime.now();
    if (recording) {
      _recordSample(result, now);
    }
    if (result == null || result.clarity < clarityThreshold) {
      frequency = null;
      clarity = null;
    } else {
      final cleaned = _smoothFrequency(result.frequency);
      frequency = cleaned;
      clarity = result.clarity;
      history.add(
        PitchPoint(time: now, frequency: cleaned, clarity: result.clarity),
      );
    }
    _trimHistory(now);
    notifyListeners();
  }

  void _trimHistory(DateTime now) {
    if (history.isEmpty) return;
    final cutoff = now.subtract(_historySpan);
    if (!history.first.time.isBefore(cutoff)) {
      return;
    }
    var removeCount = 0;
    while (removeCount < history.length &&
        history[removeCount].time.isBefore(cutoff)) {
      removeCount++;
    }
    if (removeCount > 0) {
      history.removeRange(0, removeCount);
    }
  }

  void _recordSample(PitchDetectionResult? result, DateTime now) {
    if (result == null || result.clarity < clarityThreshold) {
      if (_currentNote != null &&
          _lastSampleAt != null &&
          now.difference(_lastSampleAt!) > _noteGapTolerance) {
        _finalizeCurrentNote(_lastSampleAt!);
      }
      return;
    }
    final note = _noteNameForFrequency(result.frequency);
    if (_currentNote == null) {
      _currentNote = note;
      _currentNoteStart = now;
      _lastSampleAt = now;
      return;
    }
    if (note != _currentNote) {
      _finalizeCurrentNote(_lastSampleAt ?? now);
      _currentNote = note;
      _currentNoteStart = now;
      _lastSampleAt = now;
      return;
    }
    _lastSampleAt = now;
  }

  void _finalizeCurrentNote(DateTime now) {
    if (_currentNote == null || _currentNoteStart == null) {
      return;
    }
    final duration = now.difference(_currentNoteStart!).inMilliseconds;
    if (duration >= 500) {
      _recordedNotes.add(
        RecordedNote(note: _currentNote!.toLowerCase(), durationMs: duration),
      );
    }
    _currentNote = null;
    _currentNoteStart = null;
    _lastSampleAt = null;
  }

  String _noteNameForFrequency(double frequency) {
    const names = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final midi = midiFromFrequency(frequency).round().clamp(0, 127);
    final octave = (midi / 12).floor() - 1;
    final name = names[midi % 12];
    return '$name$octave';
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
