import 'dart:math';
import 'dart:typed_data';

class HarmoniumSynth {
  static const int _defaultSampleRate = 44100;
  static const int _bytesPerSample = 2;

  static Uint8List buildWavBytes({
    required int midi,
    required int durationMs,
    int sampleRate = _defaultSampleRate,
  }) {
    final clampedDurationMs = max(1, durationMs);
    final totalSamples =
        max(1, (clampedDurationMs * sampleRate / 1000).round());
    final pcm = Int16List(totalSamples);

    final frequency = 440.0 * pow(2.0, (midi - 69) / 12.0);
    const harmonics = [1.0, 0.62, 0.45, 0.3, 0.2, 0.12];
    final weightSum = harmonics.fold<double>(0.0, (sum, v) => sum + v);
    final gain = 0.9 / max(0.001, weightSum);

    final attackSamples = max(1, (sampleRate * 0.01).round());
    final releaseSamples = max(1, (sampleRate * 0.02).round());

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      double sample = 0.0;
      for (var h = 0; h < harmonics.length; h++) {
        sample += harmonics[h] * sin(2 * pi * frequency * (h + 1) * t);
      }
      var envelope = 1.0;
      if (i < attackSamples) {
        envelope = i / attackSamples;
      } else if (i > totalSamples - releaseSamples) {
        envelope = (totalSamples - i) / releaseSamples;
      }
      final scaled = (sample * gain * envelope).clamp(-1.0, 1.0);
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
}
