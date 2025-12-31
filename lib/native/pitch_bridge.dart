import '../dsp/pitch_detection.dart';
import 'pitch_ffi.dart';

class RustPitchDetector implements PitchDetector {
  RustPitchDetector(this.detector);

  final NativeDetector detector;

  @override
  PitchDetectionResult? getPitch(
    List<double> signal,
    int sampleRate,
    double powerThreshold,
    double clarityThreshold,
  ) {
    return PitchFfi.instance.detect(
      signal: signal,
      sampleRate: sampleRate,
      powerThreshold: powerThreshold,
      clarityThreshold: clarityThreshold,
      detector: detector,
    );
  }
}
