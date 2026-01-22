import 'dart:math';

class CompressorSettings {
  const CompressorSettings({
    this.thresholdDb = -18.0,
    this.ratio = 2.0,
    this.attackMs = 10.0,
    this.releaseMs = 100.0,
  });

  final double thresholdDb;
  final double ratio;
  final double attackMs;
  final double releaseMs;
}

class HarmonicsMetering {
  const HarmonicsMetering({
    required this.rms,
    required this.peak,
    required this.maxPeak,
  });

  final double rms;
  final double peak;
  final double maxPeak;
}

class HarmonicsProcessor {
  HarmonicsProcessor({
    required this.sampleRate,
    double harmonicsGain = 1.0,
    CompressorSettings compressorSettings = const CompressorSettings(),
    double limiterCeiling = defaultLimiterCeiling,
    int smoothingMs = 20,
    int rmsWindowMs = 100,
  })  : _compressorSettings = compressorSettings,
        _limiterCeiling = limiterCeiling.clamp(0.5, 0.99),
        _smoothingSamples = max(1, (smoothingMs * sampleRate / 1000).round()),
        _rmsCoeff = 1 -
            exp(-1 / max(1, (rmsWindowMs * sampleRate / 1000).round())) {
    final clampedGain = harmonicsGain.clamp(0.0, 2.5);
    _gainCurrent = clampedGain;
    _gainTarget = clampedGain;
    _updateCompressorCoefficients();
    _updateLimiterCoefficients();
  }

  static const double defaultLimiterCeiling = 0.89;

  final int sampleRate;

  double get harmonicsGain => _gainTarget;

  double get limiterCeiling => _limiterCeiling;

  CompressorSettings get compressorSettings => _compressorSettings;

  HarmonicsMetering get metering => HarmonicsMetering(
        rms: sqrt(_rmsMeanSquare),
        peak: _peak,
        maxPeak: _maxPeak,
      );

  void setHarmonicsGain(double value, {bool immediate = false}) {
    final clamped = value.clamp(0.0, 2.5);
    _gainTarget = clamped;
    if (immediate) {
      _gainCurrent = clamped;
      _gainStep = 0.0;
      _gainRampRemaining = 0;
      return;
    }
    _gainRampRemaining = _smoothingSamples;
    _gainStep = (_gainTarget - _gainCurrent) / _gainRampRemaining;
  }

  void updateCompressorSettings(CompressorSettings settings) {
    _compressorSettings = settings;
    _updateCompressorCoefficients();
  }

  void updateLimiterCeiling(double ceiling) {
    _limiterCeiling = ceiling.clamp(0.5, 0.99);
  }

  void resetMetering() {
    _rmsMeanSquare = 0.0;
    _peak = 0.0;
    _maxPeak = 0.0;
  }

  double processSample(double sample) {
    final smoothedGain = _nextGain();
    double value = sample * smoothedGain;
    value = _applyCompressor(value);
    value = _applyLimiter(value);
    value = _applySoftClipIfNeeded(value);
    _updateMetering(value);
    return value;
  }

  double _nextGain() {
    if (_gainRampRemaining > 0) {
      _gainCurrent += _gainStep;
      _gainRampRemaining -= 1;
    }
    return _gainCurrent;
  }

  double _applyCompressor(double sample) {
    final level = sample.abs();
    final coeff = level > _compEnv ? _compAttackCoeff : _compReleaseCoeff;
    _compEnv = level + coeff * (_compEnv - level);
    double gain = 1.0;
    if (_compEnv > _compThreshold) {
      final compressed =
          _compThreshold + (_compEnv - _compThreshold) / _compRatio;
      gain = compressed / max(1e-9, _compEnv);
    }
    return sample * gain;
  }

  double _applyLimiter(double sample) {
    final level = sample.abs();
    final desired =
        level > _limiterCeiling ? _limiterCeiling / level : 1.0;
    final coeff =
        desired < _limiterGain ? _limiterAttackCoeff : _limiterReleaseCoeff;
    _limiterGain = desired + coeff * (_limiterGain - desired);
    return sample * _limiterGain;
  }

  double _applySoftClipIfNeeded(double sample) {
    if (sample.abs() <= _limiterCeiling) {
      return sample;
    }
    return _limiterCeiling * _tanh(sample / _limiterCeiling);
  }

  void _updateMetering(double sample) {
    final level = sample.abs();
    if (level > _peak) {
      _peak = level;
    }
    if (level > _maxPeak) {
      _maxPeak = level;
    }
    final square = sample * sample;
    _rmsMeanSquare += _rmsCoeff * (square - _rmsMeanSquare);
  }

  void _updateCompressorCoefficients() {
    _compThreshold = _dbToLinear(_compressorSettings.thresholdDb);
    _compRatio = max(1.0, _compressorSettings.ratio);
    _compAttackCoeff = _timeToCoeff(_compressorSettings.attackMs);
    _compReleaseCoeff = _timeToCoeff(_compressorSettings.releaseMs);
  }

  void _updateLimiterCoefficients() {
    _limiterAttackCoeff = _timeToCoeff(2.0);
    _limiterReleaseCoeff = _timeToCoeff(80.0);
  }

  double _timeToCoeff(double timeMs) {
    final samples = max(1.0, sampleRate * timeMs / 1000);
    return exp(-1 / samples);
  }

  double _dbToLinear(double db) {
    return pow(10.0, db / 20.0).toDouble();
  }

  double _tanh(double value) {
    final expPos = exp(value);
    final expNeg = exp(-value);
    return (expPos - expNeg) / (expPos + expNeg);
  }

  CompressorSettings _compressorSettings;
  double _limiterCeiling;

  final int _smoothingSamples;
  final double _rmsCoeff;

  double _gainCurrent = 1.0;
  double _gainTarget = 1.0;
  double _gainStep = 0.0;
  int _gainRampRemaining = 0;

  double _compThreshold = 0.1;
  double _compRatio = 2.0;
  double _compAttackCoeff = 0.0;
  double _compReleaseCoeff = 0.0;
  double _compEnv = 0.0;

  double _limiterGain = 1.0;
  double _limiterAttackCoeff = 0.0;
  double _limiterReleaseCoeff = 0.0;

  double _rmsMeanSquare = 0.0;
  double _peak = 0.0;
  double _maxPeak = 0.0;
}
