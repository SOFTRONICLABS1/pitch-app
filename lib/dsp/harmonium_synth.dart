import 'dart:math';
import 'dart:typed_data';

enum HarmoniumProfile {
  softFlute,
  mellowHarmonium,
}

class HarmoniumSynth {
  static const int _defaultSampleRate = 44100;
  static const int _bytesPerSample = 2;

  static Uint8List buildWavBytes({
    required int midi,
    required int durationMs,
    int sampleRate = _defaultSampleRate,
    HarmoniumProfile profile = HarmoniumProfile.softFlute,
    bool steady = false,
  }) {
    final clampedDurationMs = max(1, durationMs);
    final totalSamples =
        max(1, (clampedDurationMs * sampleRate / 1000).round());
    final pcm = Int16List(totalSamples);

    final frequency = 440.0 * pow(2.0, (midi - 69) / 12.0);
    final config = _profileConfig(profile);
    final harmonics = config.harmonics;
    final weightSum = harmonics.fold<double>(0.0, (sum, v) => sum + v);
    final gain = config.gain / max(0.001, weightSum);

    final attackSamples = max(1, (sampleRate * config.attackSeconds).round());
    final releaseSamples =
        max(1, (sampleRate * config.releaseSeconds).round());
    final vibratoHz = config.vibratoHz;
    final vibratoDepth = steady ? 0.0 : config.vibratoDepth;
    final tremoloHz = config.tremoloHz;
    final tremoloDepth = steady ? 0.0 : config.tremoloDepth;

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final vibrato = 1.0 + (vibratoDepth * sin(2 * pi * vibratoHz * t));
      final tremolo = 1.0 + (tremoloDepth * sin(2 * pi * tremoloHz * t));
      double sample = 0.0;
      for (var h = 0; h < harmonics.length; h++) {
        sample += harmonics[h] *
            sin(2 * pi * frequency * vibrato * (h + 1) * t);
      }
      var envelope = 1.0;
      if (i < attackSamples) {
        envelope = i / attackSamples;
      } else if (i > totalSamples - releaseSamples) {
        envelope = (totalSamples - i) / releaseSamples;
      }
      final scaled = _softLimit(sample * gain * envelope * tremolo);
      pcm[i] = (scaled * 32767).round().clamp(-32767, 32767);
    }

    final dataBytes = pcm.buffer.asUint8List();
    final dataSize = dataBytes.length;
    final headerSize = 44;
    final fileSize = headerSize - 8 + dataSize;

    final header = BytesBuilder();
    header
      ..add(_asciiBytes('RIFF'))
      ..add(_uint32le(fileSize))
      ..add(_asciiBytes('WAVE'))
      ..add(_asciiBytes('fmt '))
      ..add(_uint32le(16))
      ..add(_uint16le(1))
      ..add(_uint16le(1))
      ..add(_uint32le(sampleRate))
      ..add(_uint32le(sampleRate * _bytesPerSample))
      ..add(_uint16le(_bytesPerSample))
      ..add(_uint16le(16))
      ..add(_asciiBytes('data'))
      ..add(_uint32le(dataSize));
    final wav = BytesBuilder()
      ..add(header.toBytes())
      ..add(dataBytes);
    return wav.toBytes();
  }

  static _HarmoniumProfileConfig _profileConfig(
    HarmoniumProfile profile,
  ) {
    switch (profile) {
      case HarmoniumProfile.mellowHarmonium:
        return const _HarmoniumProfileConfig(
          harmonics: [1.0, 0.3, 0.18, 0.08, 0.04],
          gain: 1.75,
          attackSeconds: 0.06,
          releaseSeconds: 0.12,
          vibratoHz: 4.0,
          vibratoDepth: 0.003,
          tremoloHz: 3.2,
          tremoloDepth: 0.02,
        );
      case HarmoniumProfile.softFlute:
      default:
        return const _HarmoniumProfileConfig(
          harmonics: [1.0, 0.06, 0.02],
          gain: 1.5,
          attackSeconds: 0.08,
          releaseSeconds: 0.14,
          vibratoHz: 4.8,
          vibratoDepth: 0.004,
          tremoloHz: 3.0,
          tremoloDepth: 0.015,
        );
    }
  }

  static Uint8List _asciiBytes(String value) {
    return Uint8List.fromList(value.codeUnits);
  }

  static Uint8List _uint16le(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static Uint8List _uint32le(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static double _softLimit(double value) {
    const threshold = 0.92;
    final magnitude = value.abs();
    if (magnitude <= threshold) {
      return value;
    }
    final excess = magnitude - threshold;
    final compressed = threshold + (1 - threshold) * (1 - exp(-3 * excess));
    return value.isNegative ? -compressed : compressed;
  }
}

class _HarmoniumProfileConfig {
  const _HarmoniumProfileConfig({
    required this.harmonics,
    required this.gain,
    required this.attackSeconds,
    required this.releaseSeconds,
    required this.vibratoHz,
    required this.vibratoDepth,
    required this.tremoloHz,
    required this.tremoloDepth,
  });

  final List<double> harmonics;
  final double gain;
  final double attackSeconds;
  final double releaseSeconds;
  final double vibratoHz;
  final double vibratoDepth;
  final double tremoloHz;
  final double tremoloDepth;
}
