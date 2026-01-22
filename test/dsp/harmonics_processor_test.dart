import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/dsp/harmonics_processor.dart';

void main() {
  test('limiter prevents clipping at max gain', () {
    const sampleRate = 44100;
    const frequency = 220.0;
    final processor = HarmonicsProcessor(
      sampleRate: sampleRate,
      harmonicsGain: 2.5,
    );
    for (var i = 0; i < sampleRate; i++) {
      final t = i / sampleRate;
      final sample = sin(2 * pi * frequency * t) +
          (0.7 * sin(2 * pi * frequency * 2 * t)) +
          (0.5 * sin(2 * pi * frequency * 3 * t));
      final output = processor.processSample(sample);
      expect(output.abs(), lessThanOrEqualTo(processor.limiterCeiling + 1e-6));
    }
    final metering = processor.metering;
    // ignore: avoid_print
    print(
      'Harmonics debug rms=${metering.rms.toStringAsFixed(4)} '
      'peak=${metering.peak.toStringAsFixed(4)} '
      'max=${metering.maxPeak.toStringAsFixed(4)}',
    );
    expect(
      metering.maxPeak,
      lessThanOrEqualTo(processor.limiterCeiling + 1e-6),
    );
  });
}
