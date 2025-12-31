import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as ffi_alloc;

import '../dsp/pitch_detection.dart';

enum NativeDetector { mcleod, autocorrelation, yin }

final class _PitchResultStruct extends ffi.Struct {
  @ffi.Float()
  external double frequency;

  @ffi.Float()
  external double clarity;
}

typedef _PitchDetectC =
    _PitchResultStruct Function(
      ffi.Pointer<ffi.Float>,
      ffi.IntPtr,
      ffi.Uint32,
      ffi.Float,
      ffi.Float,
      ffi.Int32,
    );
typedef _PitchDetectDart =
    _PitchResultStruct Function(
      ffi.Pointer<ffi.Float>,
      int,
      int,
      double,
      double,
      int,
    );

class PitchFfi {
  PitchFfi._internal() {
    _lib = _openLibrary();
    _pitchDetect = _lib.lookupFunction<_PitchDetectC, _PitchDetectDart>(
      'pitch_detect',
    );
  }

  static final PitchFfi instance = PitchFfi._internal();

  late final ffi.DynamicLibrary _lib;
  late final _PitchDetectDart _pitchDetect;

  PitchDetectionResult? detect({
    required List<double> signal,
    required int sampleRate,
    required double powerThreshold,
    required double clarityThreshold,
    required NativeDetector detector,
  }) {
    final ptr = ffi_alloc.calloc<ffi.Float>(signal.length);
    try {
      final floatList = ptr.asTypedList(signal.length);
      for (var i = 0; i < signal.length; i++) {
        floatList[i] = signal[i].toDouble();
      }

      final result = _pitchDetect(
        ptr,
        signal.length,
        sampleRate,
        powerThreshold,
        clarityThreshold,
        detector.index,
      );

      if (result.frequency <= 0) {
        return null;
      }
      return PitchDetectionResult(
        frequency: result.frequency,
        clarity: result.clarity,
      );
    } finally {
      ffi_alloc.calloc.free(ptr);
    }
  }

  static ffi.DynamicLibrary _openLibrary() {
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libpitch_ffi.so');
    }
    if (Platform.isMacOS) {
      // Helpful for simulator/desktop debugging; adjust path if needed.
      final candidate = File(
        'native/pitch_ffi/target/debug/libpitch_ffi.dylib',
      );
      if (candidate.existsSync()) {
        return ffi.DynamicLibrary.open(candidate.path);
      }
    }
    return ffi.DynamicLibrary.process();
  }
}
