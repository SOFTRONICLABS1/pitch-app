import 'dart:math';

class PitchDetectionResult {
  const PitchDetectionResult({required this.frequency, required this.clarity});

  final double frequency;
  final double clarity;
}

abstract class PitchDetector {
  PitchDetectionResult? getPitch(
    List<double> signal,
    int sampleRate,
    double powerThreshold,
    double clarityThreshold,
  );
}

class McLeodPitchDetector implements PitchDetector {
  McLeodPitchDetector({required this.size});

  final int size;

  @override
  PitchDetectionResult? getPitch(
    List<double> signal,
    int sampleRate,
    double powerThreshold,
    double clarityThreshold,
  ) {
    if (signal.length != size) return null;

    final power = _sumSquares(signal);
    if (power < powerThreshold) return null;

    final maxTau = size ~/ 2;
    final nsdf = List<double>.filled(maxTau, 0);

    for (var tau = 0; tau < maxTau; tau++) {
      var acf = 0.0;
      var norm = 0.0;
      final limit = size - tau;
      for (var i = 0; i < limit; i++) {
        final x1 = signal[i];
        final x2 = signal[i + tau];
        acf += x1 * x2;
        norm += (x1 * x1) + (x2 * x2);
      }
      if (norm > 0) {
        nsdf[tau] = 2 * acf / norm;
      }
    }

    int? peakIndex;
    var bestClarity = clarityThreshold;

    for (var i = 1; i < nsdf.length - 1; i++) {
      final current = nsdf[i];
      if (current > bestClarity &&
          current > nsdf[i - 1] &&
          current >= nsdf[i + 1]) {
        peakIndex = i;
        bestClarity = current;
      }
    }

    if (peakIndex == null) return null;

    final offset = _quadraticPeak(
      nsdf[peakIndex - 1],
      nsdf[peakIndex],
      nsdf[min(peakIndex + 1, nsdf.length - 1)],
    );
    final refinedTau = max(1e-6, peakIndex + offset);
    final frequency = sampleRate / refinedTau;
    return PitchDetectionResult(frequency: frequency, clarity: bestClarity);
  }
}

class AutocorrelationPitchDetector implements PitchDetector {
  AutocorrelationPitchDetector({required this.size});

  final int size;

  @override
  PitchDetectionResult? getPitch(
    List<double> signal,
    int sampleRate,
    double powerThreshold,
    double clarityThreshold,
  ) {
    if (signal.length != size) return null;

    final power = _sumSquares(signal);
    if (power < powerThreshold) return null;

    final maxTau = size ~/ 2;
    final corr = List<double>.filled(maxTau, 0);

    for (var tau = 0; tau < maxTau; tau++) {
      var value = 0.0;
      final limit = size - tau;
      for (var i = 0; i < limit; i++) {
        value += signal[i] * signal[i + tau];
      }
      corr[tau] = value;
    }

    final threshold = corr[0] * clarityThreshold;
    int? peakIndex;
    var best = threshold;
    for (var i = 1; i < corr.length - 1; i++) {
      final current = corr[i];
      if (current > best && current > corr[i - 1] && current >= corr[i + 1]) {
        best = current;
        peakIndex = i;
      }
    }
    if (peakIndex == null) return null;

    final offset = _quadraticPeak(
      corr[peakIndex - 1],
      corr[peakIndex],
      corr[min(peakIndex + 1, corr.length - 1)],
    );
    final refinedTau = max(1e-6, peakIndex + offset);
    final frequency = sampleRate / refinedTau;
    final clarity = corr[peakIndex] / corr[0];
    return PitchDetectionResult(frequency: frequency, clarity: clarity);
  }
}

double _sumSquares(List<double> data) {
  return data.fold(0.0, (sum, v) => sum + v * v);
}

double _quadraticPeak(double y0, double y1, double y2) {
  final denom = (2 * y1) - y0 - y2;
  if (denom.abs() < 1e-9) return 0;
  return 0.5 * (y0 - y2) / denom;
}

const _noteNames = [
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

double midiFromFrequency(double frequency) {
  return 69 + 12 * (log(frequency / 440.0) / ln2);
}

String noteLabel(double frequency) {
  final midi = midiFromFrequency(frequency);
  final midiInt = midi.round().clamp(0, 127);
  final note = _noteNames[midiInt % 12];
  final octave = (midiInt / 12).floor() - 1;
  final cents = ((midi - midiInt) * 100).toStringAsFixed(0);
  return '$note$octave (${cents}c)';
}
