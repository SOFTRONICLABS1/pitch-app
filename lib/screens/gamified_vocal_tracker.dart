import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsp/harmonium_synth.dart';
import '../dsp/pitch_detection.dart';
import '../models/recording.dart';
import '../state/pitch_notifier.dart';

enum GameVisualTheme { arcade, retro, tactical }

class GamifiedVocalTrackerScreen extends StatefulWidget {
  const GamifiedVocalTrackerScreen({
    super.key,
    required this.recording,
    this.theme = GameVisualTheme.arcade,
  });

  final RecordingEntry recording;
  final GameVisualTheme theme;

  @override
  State<GamifiedVocalTrackerScreen> createState() =>
      _GamifiedVocalTrackerScreenState();
}

class _GamifiedVocalTrackerScreenState extends State<GamifiedVocalTrackerScreen> {
  final AudioPlayer _harmonicsPlayer = AudioPlayer();
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _tickTimer;
  Timer? _harmonicsStopTimer;
  static const int _harmonicsFadeSteps = 5;
  static const double _harmonicsVolume = 25.0;
  int _harmonicsFadeToken = 0;
  double _lastHarmonicsDurationMs = 0.0;
  List<_GameTargetBlock> _targets = [];
  int _totalDurationMs = 0;
  bool _running = false;
  int _currentIndex = 0;
  double _accuracy = 0.0;
  int _score = 0;
  int _streak = 0;
  int _bpm = 60;
  double _lastUiUpdateMs = 0.0;
  double _lastTargetElapsedMs = 0.0;
  double _lastHarmonicsElapsedMs = 0.0;
  double _scoreMs = 0.0;
  double _totalMs = 0.0;
  int? _currentHarmonicsKey;
  PitchNotifier? _pitchNotifier;
  int _baseOctave = PitchNotifier.defaultBaseOctave;
  final List<_Bullet> _bullets = [];
  double _aimXNorm = 0.5;
  double _lastShotMs = 0.0;
  int _minTargetMidi = 60;
  int _maxTargetMidi = 72;
  final List<int> _bpmOptions = List<int>.generate(31, (i) => 20 + i * 10);

  @override
  void initState() {
    super.initState();
    _pitchNotifier = context.read<PitchNotifier>();
    _baseOctave = _pitchNotifier?.baseOctave ?? PitchNotifier.defaultBaseOctave;
    _harmonicsPlayer.setReleaseMode(ReleaseMode.stop);
    _harmonicsPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    _rebuildTargets();
    _preloadHarmonics();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _harmonicsStopTimer?.cancel();
    _harmonicsPlayer.dispose();
    super.dispose();
  }

  void _rebuildTargets() {
    final targets = <_GameTargetBlock>[];
    var offsetMs = 0;
    int? minMidi;
    int? maxMidi;
    final tuningSystem = _pitchNotifier?.tuningSystem ?? 'western';
    for (final note in widget.recording.notes) {
      final normalized = _normalizeNoteForStorage(note.note, tuningSystem);
      final midi = _midiFromNoteLabel(normalized, _baseOctave);
      if (midi == null) {
        offsetMs += note.durationMs;
        continue;
      }
      minMidi = minMidi == null ? midi : min(minMidi, midi);
      maxMidi = maxMidi == null ? midi : max(maxMidi, midi);
      targets.add(
        _GameTargetBlock(
          midi: midi,
          label: note.note,
          durationMs: note.durationMs,
          startOffsetMs: offsetMs,
        ),
      );
      offsetMs += note.durationMs;
    }
    _targets = targets;
    _totalDurationMs = max(0, offsetMs);
    _minTargetMidi = minMidi ?? _minTargetMidi;
    _maxTargetMidi = maxMidi ?? _maxTargetMidi;
    if (_targets.isNotEmpty) {
      _aimXNorm = _targetXNorm(_targets.first.midi);
    }
  }

  Future<void> _preloadHarmonics() async {
    // Harmonics are generated on-demand; nothing to preload.
  }

  void _start() async {
    if (_running || _targets.isEmpty) return;
    await _pitchNotifier?.start();
    _running = true;
    _stopwatch
      ..reset()
      ..start();
    _kickoffHarmonics();
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final elapsedMs = _stopwatch.elapsedMilliseconds.toDouble();
      _updateHarmonics(elapsedMs);
      _updateScore(elapsedMs);
      _updateBullets(elapsedMs);
      if (!mounted) return;
      if (elapsedMs - _lastUiUpdateMs >= 100) {
        setState(() {});
        _lastUiUpdateMs = elapsedMs;
      }
    });
    setState(() {});
  }

  void _stop() async {
    if (!_running) return;
    _running = false;
    _stopwatch.stop();
    _tickTimer?.cancel();
    _stopHarmonics();
    await _pitchNotifier?.stop();
    setState(() {});
  }

  void _restart() {
    _stopwatch.reset();
    _currentIndex = 0;
    _accuracy = 0.0;
    _score = 0;
    _streak = 0;
    _lastUiUpdateMs = 0.0;
    _lastTargetElapsedMs = 0.0;
    _lastHarmonicsElapsedMs = 0.0;
    _scoreMs = 0.0;
    _totalMs = 0.0;
    _currentHarmonicsKey = null;
    _bullets.clear();
    _aimXNorm = _targets.isNotEmpty ? _targetXNorm(_targets.first.midi) : 0.5;
    _lastShotMs = 0.0;
    setState(() {});
  }

  void _kickoffHarmonics() {
    _lastHarmonicsElapsedMs = -1.0;
    _updateHarmonics(0.0);
  }

  void _updateScore(double elapsedMs) {
    if (!_running || _targets.isEmpty || _totalDurationMs <= 0) {
      return;
    }
    final loopMs = _scaledLoopMs();
    final loopTime = elapsedMs % loopMs;
    final target = _findTarget(loopTime, _loopScale());
    if (target == null) return;
    _currentIndex = target.index;

    final delta = elapsedMs - _lastTargetElapsedMs;
    if (delta <= 0) return;
    _lastTargetElapsedMs = elapsedMs;
    _totalMs += delta;

    final match = _isMatching(target.block.midi);
    if (match) {
      _scoreMs += delta;
      _score = (_scoreMs / 100).round();
      _streak += 1;
    } else {
      _streak = 0;
    }
    _accuracy = _totalMs <= 0 ? 0.0 : (_scoreMs / _totalMs).clamp(0.0, 1.0);
  }

  void _updateBullets(double elapsedMs) {
    if (!_running || _targets.isEmpty || _totalDurationMs <= 0) {
      return;
    }
    final loopMs = _scaledLoopMs();
    final loopTime = elapsedMs % loopMs;
    final target = _findTarget(loopTime, _loopScale());
    if (target == null) return;
    final state = _pitchNotifier;
    final frequency = state?.frequency;
    final clarity = state?.clarity ?? 0.0;
    final hasPitch =
        frequency != null && clarity >= (state?.clarityThreshold ?? 0.0);
    if (hasPitch) {
      final midi = midiFromFrequency(frequency!);
      final targetX = _targetXNorm(midi.round());
      _aimXNorm = _aimXNorm + (targetX - _aimXNorm) * 0.18;
    }
    if (hasPitch && elapsedMs - _lastShotMs >= 260) {
      _lastShotMs = elapsedMs;
      final cents = _centsFromTarget(frequency!, target.block.midi);
      final color =
          cents.abs() <= 25 ? Colors.greenAccent : Colors.orangeAccent;
      _bullets.add(
        _Bullet(
          xNorm: _aimXNorm,
          spawnMs: elapsedMs,
          color: color,
        ),
      );
    }
    _bullets.removeWhere(
      (bullet) => elapsedMs - bullet.spawnMs > _Bullet.travelMs,
    );
  }

  void _updateHarmonics(double elapsedMs) {
    if (_targets.isEmpty || _totalDurationMs <= 0 || !_running) {
      _stopHarmonics();
      return;
    }
    var previousElapsedMs = _lastHarmonicsElapsedMs;
    if (previousElapsedMs > elapsedMs) {
      previousElapsedMs = elapsedMs;
    }
    if (elapsedMs <= previousElapsedMs) {
      return;
    }
    final loopMs = _scaledLoopMs();
    final minCycle = (previousElapsedMs / loopMs).floor();
    final maxCycle = (elapsedMs / loopMs).floor();
    final scale = _loopScale();
    int? index;
    int? cycleIndex;
    double? durationMs;
    double? bestStart;
    double? bestEnd;
    const gapMs = 60.0;
    for (var k = minCycle; k <= maxCycle; k++) {
      final cycleOffset = k * loopMs;
      for (var i = 0; i < _targets.length; i++) {
        final start = (_targets[i].startOffsetMs * scale) + cycleOffset;
        final duration = _targets[i].durationMs * scale;
        final end = start + duration;
        final effectiveEnd = end - min(gapMs, duration * 0.5);
        final overlaps =
            effectiveEnd >= previousElapsedMs && start <= elapsedMs;
        if (!overlaps) continue;
        if (start <= elapsedMs && (bestStart == null || start >= bestStart)) {
          bestStart = start;
          bestEnd = end;
          index = i;
          cycleIndex = k;
          durationMs = duration;
        }
      }
    }
    if (index == null || durationMs == null || cycleIndex == null) {
      return;
    }
    _lastHarmonicsElapsedMs = elapsedMs;
    final effectiveDuration = max(0.0, durationMs - gapMs);
    final key = cycleIndex * 10000 + index;
    if (_currentHarmonicsKey == key) {
      final end = bestEnd ?? 0.0;
      if (end <= previousElapsedMs) {
        _currentHarmonicsKey = null;
      } else {
        return;
      }
    }
    _currentHarmonicsKey = key;
    unawaited(_playHarmonic(_targets[index], effectiveDuration));
  }

  Future<void> _playHarmonic(_GameTargetBlock block, double durationMs) async {
    _harmonicsStopTimer?.cancel();
    final duration = durationMs.clamp(50, 600000).toDouble();
    final bytes = HarmoniumSynth.buildWavBytes(
      midi: block.midi,
      durationMs: duration.round(),
      steady: duration >= 300,
    );
    const steps = _harmonicsFadeSteps;
    final fadeStepMs = _fadeStepMsForDuration(duration, steps: steps);
    final fadeToken = _nextHarmonicsFadeToken();
    _lastHarmonicsDurationMs = duration;
    await _fadeOutAndStopPlayer(
      _harmonicsPlayer,
      _harmonicsVolume,
      steps: steps,
      stepMs: fadeStepMs,
      fadeToken: fadeToken,
    );
    if (fadeToken != _harmonicsFadeToken) {
      return;
    }
    await _harmonicsPlayer.setVolume(0.0);
    await _harmonicsPlayer.play(BytesSource(bytes), volume: 0.0);
    unawaited(_fadeInPlayer(
      _harmonicsPlayer,
      _harmonicsVolume,
      steps: steps,
      stepMs: fadeStepMs,
      fadeToken: fadeToken,
    ));
    _harmonicsStopTimer = Timer(
      Duration(milliseconds: duration.round()),
      () {
        if (fadeToken == _harmonicsFadeToken) {
          _fadeOutAndStopHarmonics();
        }
      },
    );
  }

  void _stopHarmonics() {
    _harmonicsStopTimer?.cancel();
    _harmonicsStopTimer = null;
    _currentHarmonicsKey = null;
    _fadeOutAndStopHarmonics();
  }

  void _fadeOutAndStopHarmonics() {
    final fadeToken = _nextHarmonicsFadeToken();
    const steps = _harmonicsFadeSteps;
    final fadeStepMs =
        _fadeStepMsForDuration(_lastHarmonicsDurationMs, steps: steps);
    unawaited(_fadeOutAndStopPlayer(
      _harmonicsPlayer,
      _harmonicsVolume,
      steps: steps,
      stepMs: fadeStepMs,
      fadeToken: fadeToken,
    ));
  }

  Future<void> _fadeInPlayer(
    AudioPlayer player,
    double targetVolume, {
    int steps = 4,
    int stepMs = 20,
    int? fadeToken,
  }) async {
    final clamped = targetVolume.clamp(0.0, 10.0);
    for (var i = 1; i <= steps; i++) {
      if (fadeToken != null && fadeToken != _harmonicsFadeToken) {
        return;
      }
      await player.setVolume((clamped * i) / steps);
      await Future<void>.delayed(Duration(milliseconds: stepMs));
    }
  }

  Future<void> _fadeOutAndStopPlayer(
    AudioPlayer player,
    double fromVolume, {
    int steps = 3,
    int stepMs = 20,
    int? fadeToken,
  }) async {
    final clamped = fromVolume.clamp(0.0, 10.0);
    for (var i = steps - 1; i >= 0; i--) {
      if (fadeToken != null && fadeToken != _harmonicsFadeToken) {
        return;
      }
      await player.setVolume((clamped * i) / steps);
      await Future<void>.delayed(Duration(milliseconds: stepMs));
    }
    await player.stop();
  }

  int _nextHarmonicsFadeToken() {
    _harmonicsFadeToken++;
    return _harmonicsFadeToken;
  }

  int _fadeStepMsForDuration(double durationMs, {int steps = 3}) {
    final totalMs = min(80.0, max(20.0, durationMs * 0.2));
    return max(4, (totalMs / max(1, steps)).round());
  }

  bool _isMatching(int targetMidi) {
    final state = _pitchNotifier;
    final frequency = state?.frequency;
    final clarity = state?.clarity ?? 0.0;
    if (frequency == null || clarity < (state?.clarityThreshold ?? 0.0)) {
      return false;
    }
    final midi = midiFromFrequency(frequency);
    return (midi - targetMidi).abs() <= 0.5;
  }

  _IndexedTarget? _findTarget(double loopMs, double scale) {
    for (var i = 0; i < _targets.length; i++) {
      final block = _targets[i];
      final start = block.startOffsetMs * scale;
      final end = start + (block.durationMs * scale);
      if (loopMs >= start && loopMs < end) {
        return _IndexedTarget(i, block);
      }
    }
    return null;
  }

  double _targetXNorm(int midi) {
    final range = max(1, _maxTargetMidi - _minTargetMidi);
    final t = ((midi - _minTargetMidi) / range).clamp(0.0, 1.0);
    return 0.15 + t * 0.7;
  }

  String _displayLabel(String note, String tuningSystem) {
    if (tuningSystem == 'carnatic') {
      final normalized = _normalizeNoteForStorage(note, tuningSystem);
      final midi = _midiFromNoteLabel(normalized, _baseOctave);
      if (midi != null) {
        return _labelForMidi(midi, tuningSystem, withOctave: false);
      }
    }
    return note
        .toUpperCase()
        .replaceAll(RegExp(r'\d'), '')
        .replaceAll('-', '');
  }

  @override
  Widget build(BuildContext context) {
    final pitchState = context.watch<PitchNotifier>();
    final tuningSystem = pitchState.tuningSystem;
    final palette = _paletteFor(widget.theme);
    final hasNotes = widget.recording.notes.isNotEmpty;
    final current = _targets.isEmpty
        ? null
        : _targets[min(_currentIndex, _targets.length - 1)];
    final next = _targets.isEmpty || _currentIndex + 1 >= _targets.length
        ? null
        : _targets[_currentIndex + 1];
    final targetXNorm =
        current == null ? 0.5 : _targetXNorm(current.midi);
    final loopMs = _scaledLoopMs();
    final progress = _totalDurationMs == 0
        ? 0.0
        : ((_stopwatch.elapsedMilliseconds % loopMs) / loopMs)
            .clamp(0.0, 1.0);
    final liveInfo = _livePitchInfo(pitchState, tuningSystem);
    final isMatch =
        current != null && liveInfo.$2 && _isMatching(current.midi);
    final targetCents = (current != null && liveInfo.$2)
        ? _centsFromTarget(pitchState.frequency!, current.midi)
        : null;

    return Scaffold(
      backgroundColor: palette.screen,
      appBar: AppBar(
        title: Text(widget.recording.name),
        actions: [
          IconButton(
            onPressed: _openSettingsSheet,
            icon: const Icon(Icons.settings),
            tooltip: 'Game settings',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _StatCard(
                  label: 'Score',
                  value: '$_score',
                  background: palette.panel,
                  valueColor: palette.textPrimary,
                  labelColor: palette.textSecondary,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  label: 'Accuracy',
                  value: '${(_accuracy * 100).round()}%',
                  background: palette.panel,
                  valueColor: palette.textPrimary,
                  labelColor: palette.textSecondary,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  label: 'Streak',
                  value: '$_streak',
                  background: palette.panel,
                  valueColor: palette.textPrimary,
                  labelColor: palette.textSecondary,
                ),
              ],
            ),
            if (pitchState.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                pitchState.errorMessage!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            if (_targets.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                hasNotes
                    ? 'No target notes parsed. First note: '
                        '${widget.recording.notes.first.note}'
                    : 'No notes found in this recording.',
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ],
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: palette.panel,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: palette.glow,
                      blurRadius: 24,
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _AimBoard(
                        targetLabel: current == null
                            ? '--'
                            : _displayLabel(current.label, tuningSystem),
                        nextLabel: next == null
                            ? null
                            : _displayLabel(next.label, tuningSystem),
                        aimXNorm: _aimXNorm,
                        targetXNorm: targetXNorm,
                        bullets: _bullets,
                        elapsedMs: _stopwatch.elapsedMilliseconds.toDouble(),
                        isMatch: isMatch,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 92,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              liveInfo.$1,
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: isMatch
                                    ? palette.accent
                                    : palette.textPrimary.withOpacity(0.75),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'You',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(color: palette.textSecondary),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  isMatch
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  color: isMatch
                                      ? palette.accent
                                      : palette.textSecondary.withOpacity(0.6),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              liveInfo.$2
                                  ? (targetCents == null
                                      ? '${liveInfo.$3.toStringAsFixed(1)} Hz'
                                      : '${liveInfo.$3.toStringAsFixed(1)} Hz '
                                          '(${targetCents >= 0 ? '+' : ''}'
                                          '${targetCents.toStringAsFixed(0)}c)')
                                  : '--',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: palette.textSecondary.withOpacity(0.2),
                      color: palette.accent,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      tuningSystem == 'carnatic'
                          ? 'Sing with the harmonics'
                          : 'Match the harmonics',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        !hasNotes ? null : (_running ? _stop : _start),
                    icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                    label: Text(_running ? 'Pause' : 'Start'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _restart,
                    icon: const Icon(Icons.replay),
                    label: const Text('Restart'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _loopScale() => 60.0 / _bpm;

  double _scaledLoopMs() {
    return max(1, _totalDurationMs).toDouble() * _loopScale();
  }

  void _openSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C3136),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final pitchState = context.read<PitchNotifier>();
        return StatefulBuilder(
          builder: (context, setModalState) {
            final tuningSystem = pitchState.tuningSystem;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Game Settings',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'BPM',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _bpm.toDouble(),
                          min: _bpmOptions.first.toDouble(),
                          max: _bpmOptions.last.toDouble(),
                          divisions: _bpmOptions.length - 1,
                          label: '$_bpm',
                          onChanged: (value) {
                            final next = _nearestBpm(value);
                            setModalState(() {
                              _bpm = next;
                            });
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 52,
                        child: Text(
                          '$_bpm',
                          textAlign: TextAlign.right,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: _bpm > _bpmOptions.first
                            ? () {
                                final nextIndex =
                                    _bpmOptions.indexOf(_bpm) - 1;
                                final next = _bpmOptions[
                                    nextIndex.clamp(0, _bpmOptions.length - 1)];
                                setModalState(() {
                                  _bpm = next;
                                });
                                setState(() {});
                              }
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _bpm < _bpmOptions.last
                            ? () {
                                final nextIndex =
                                    _bpmOptions.indexOf(_bpm) + 1;
                                final next = _bpmOptions[
                                    nextIndex.clamp(0, _bpmOptions.length - 1)];
                                setModalState(() {
                                  _bpm = next;
                                });
                                setState(() {});
                              }
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Notation',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Western'),
                        selected: tuningSystem == 'western',
                        onSelected: (selected) {
                          if (!selected) return;
                          pitchState.setTuningSystem('western');
                          _rebuildTargets();
                          setModalState(() {});
                          setState(() {});
                        },
                      ),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('Carnatic'),
                        selected: tuningSystem == 'carnatic',
                        onSelected: (selected) {
                          if (!selected) return;
                          pitchState.setTuningSystem('carnatic');
                          _rebuildTargets();
                          setModalState(() {});
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  int _nearestBpm(double value) {
    var closest = _bpmOptions.first;
    var closestDelta = (value - closest).abs();
    for (final bpm in _bpmOptions) {
      final delta = (value - bpm).abs();
      if (delta < closestDelta) {
        closest = bpm;
        closestDelta = delta;
      }
    }
    return closest;
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.background,
    required this.valueColor,
    required this.labelColor,
  });

  final String label;
  final String value;
  final Color background;
  final Color valueColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: labelColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _GamePalette {
  const _GamePalette({
    required this.screen,
    required this.panel,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.glow,
  });

  final Color screen;
  final Color panel;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color glow;
}

_GamePalette _paletteFor(GameVisualTheme theme) {
  switch (theme) {
    case GameVisualTheme.retro:
      return const _GamePalette(
        screen: Color(0xFF181014),
        panel: Color(0xFF2A1E25),
        accent: Color(0xFFFFD369),
        textPrimary: Color(0xFFF8F3E6),
        textSecondary: Color(0xFFB8A68A),
        glow: Color(0x66FF7A00),
      );
    case GameVisualTheme.tactical:
      return const _GamePalette(
        screen: Color(0xFF0F1418),
        panel: Color(0xFF1B242A),
        accent: Color(0xFF5AD4FF),
        textPrimary: Color(0xFFE7EEF2),
        textSecondary: Color(0xFF9AA7B2),
        glow: Color(0x6649B6D6),
      );
    case GameVisualTheme.arcade:
    default:
      return const _GamePalette(
        screen: Color(0xFF10101A),
        panel: Color(0xFF1E2033),
        accent: Color(0xFF63F0FF),
        textPrimary: Color(0xFFF0F3FF),
        textSecondary: Color(0xFF8F96B8),
        glow: Color(0x664D2BFF),
      );
  }
}

class _IndexedTarget {
  const _IndexedTarget(this.index, this.block);

  final int index;
  final _GameTargetBlock block;
}

class _GameTargetBlock {
  const _GameTargetBlock({
    required this.midi,
    required this.label,
    required this.durationMs,
    required this.startOffsetMs,
  });

  final int midi;
  final String label;
  final int durationMs;
  final int startOffsetMs;
}

class _Bullet {
  const _Bullet({
    required this.xNorm,
    required this.spawnMs,
    required this.color,
  });

  final double xNorm;
  final double spawnMs;
  final Color color;

  static const double travelMs = 900.0;
}

class _AimBoard extends StatelessWidget {
  const _AimBoard({
    required this.targetLabel,
    required this.nextLabel,
    required this.aimXNorm,
    required this.targetXNorm,
    required this.bullets,
    required this.elapsedMs,
    required this.isMatch,
  });

  final String targetLabel;
  final String? nextLabel;
  final double aimXNorm;
  final double? targetXNorm;
  final List<_Bullet> bullets;
  final double elapsedMs;
  final bool isMatch;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AimBoardPainter(
        targetLabel: targetLabel,
        nextLabel: nextLabel,
        aimXNorm: aimXNorm,
        targetXNorm: targetXNorm,
        bullets: bullets,
        elapsedMs: elapsedMs,
        isMatch: isMatch,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _AimBoardPainter extends CustomPainter {
  _AimBoardPainter({
    required this.targetLabel,
    required this.nextLabel,
    required this.aimXNorm,
    required this.targetXNorm,
    required this.bullets,
    required this.elapsedMs,
    required this.isMatch,
  });

  final String targetLabel;
  final String? nextLabel;
  final double aimXNorm;
  final double? targetXNorm;
  final List<_Bullet> bullets;
  final double elapsedMs;
  final bool isMatch;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = (targetXNorm ?? 0.5) * size.width;
    final targetY = size.height * 0.18;
    final targetRadius = min(size.width, size.height) * 0.12;
    final ringPaint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final hitPaint = Paint()
      ..color = (isMatch ? Colors.greenAccent : Colors.white70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(Offset(centerX, targetY), targetRadius, ringPaint);
    canvas.drawCircle(Offset(centerX, targetY), targetRadius * 0.65, ringPaint);
    canvas.drawCircle(Offset(centerX, targetY), targetRadius * 0.3, hitPaint);

    final arrowPaint = Paint()
      ..color = Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final arrowPath = Path()
      ..moveTo(centerX, targetY - targetRadius - 10)
      ..lineTo(centerX - 8, targetY - targetRadius - 2)
      ..moveTo(centerX, targetY - targetRadius - 10)
      ..lineTo(centerX + 8, targetY - targetRadius - 2);
    canvas.drawPath(arrowPath, arrowPaint);

    final labelPainter = TextPainter(
      text: TextSpan(
        text: targetLabel,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(
      canvas,
      Offset(
        centerX - labelPainter.width / 2,
        targetY - labelPainter.height / 2,
      ),
    );

    if (nextLabel != null) {
      final nextPainter = TextPainter(
        text: TextSpan(
          text: 'Next $nextLabel',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white54,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      nextPainter.paint(
        canvas,
        Offset(centerX - nextPainter.width / 2, targetY + targetRadius + 8),
      );
    }

    final gunY = size.height * 0.88;
    final gunX = aimXNorm * size.width;
    final baseWidth = 46.0;
    final baseHeight = 12.0;
    final gunBase = Rect.fromCenter(
      center: Offset(gunX, gunY),
      width: baseWidth,
      height: baseHeight,
    );
    final gunPaint = Paint()..color = Colors.white70;
    canvas.drawRRect(
      RRect.fromRectAndRadius(gunBase, const Radius.circular(6)),
      gunPaint,
    );
    final barrelPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(gunX, gunY - baseHeight / 2),
      Offset(gunX, targetY + targetRadius),
      barrelPaint,
    );

    for (final bullet in bullets) {
      final progress =
          ((elapsedMs - bullet.spawnMs) / _Bullet.travelMs).clamp(0.0, 1.0);
      final x = bullet.xNorm * size.width;
      final y = gunY - progress * (gunY - targetY);
      final bulletPaint = Paint()..color = bullet.color;
      canvas.drawCircle(Offset(x, y), 4, bulletPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AimBoardPainter oldDelegate) {
    return oldDelegate.aimXNorm != aimXNorm ||
        (oldDelegate.targetXNorm ?? 0.5) != (targetXNorm ?? 0.5) ||
        oldDelegate.elapsedMs != elapsedMs ||
        oldDelegate.isMatch != isMatch ||
        oldDelegate.targetLabel != targetLabel ||
        oldDelegate.nextLabel != nextLabel ||
        oldDelegate.bullets.length != bullets.length;
  }
}

(String, bool, double) _livePitchInfo(
  PitchNotifier state,
  String tuningSystem,
) {
  final frequency = state.frequency;
  final clarity = state.clarity ?? 0.0;
  if (frequency == null || clarity < state.clarityThreshold) {
    return ('--', false, 0.0);
  }
  final midi = midiFromFrequency(frequency);
  final midiInt = midi.round().clamp(0, 127);
  final label = _labelForMidi(
    midiInt,
    tuningSystem,
    withOctave: tuningSystem != 'carnatic',
  );
  return (label, true, frequency);
}

double _centsFromTarget(double frequency, int targetMidi) {
  final midi = midiFromFrequency(frequency);
  return (midi - targetMidi) * 100.0;
}

String _labelForMidi(
  int midi,
  String tuningSystem, {
  required bool withOctave,
}) {
  const western = [
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
  const carnatic = [
    'Sa',
    'Ri1',
    'Ri2',
    'Ga1',
    'Ga2',
    'Ma1',
    'Ma2',
    'Pa',
    'Da1',
    'Da2',
    'Ni1',
    'Ni2',
  ];
  final labels = tuningSystem == 'carnatic' ? carnatic : western;
  final note = labels[midi % 12];
  if (!withOctave) return note;
  final octave = (midi / 12).floor() - 1;
  return '$note$octave';
}

int? _midiFromNoteLabel(String note, int baseOctave) {
  if (note.isEmpty) return null;
  final match = RegExp(r'^([a-g])(#?)(-?\d+)?$').firstMatch(note);
  if (match == null) return null;
  final name = match.group(1);
  final sharp = match.group(2);
  final octaveText = match.group(3);
  final octave = octaveText == null ? baseOctave : int.tryParse(octaveText);
  if (name == null || octave == null) return null;
  final base = switch (name) {
    'c' => 0,
    'd' => 2,
    'e' => 4,
    'f' => 5,
    'g' => 7,
    'a' => 9,
    'b' => 11,
    _ => 0,
  };
  final semitone = base + (sharp == '#' ? 1 : 0);
  final midi = (octave + 1) * 12 + semitone;
  final offset = (baseOctave - PitchNotifier.defaultBaseOctave) * 12;
  return midi + offset;
}

String _normalizeNoteForStorage(String input, String tuningSystem) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final western = RegExp(r'^([A-Ga-g])(#?)(-?\d+)?$').firstMatch(trimmed);
  if (western != null) {
    final name = western.group(1) ?? '';
    final sharp = western.group(2) ?? '';
    final octave = western.group(3) ?? '';
    return '${name.toLowerCase()}$sharp$octave';
  }
  if (tuningSystem == 'carnatic') {
    final carnatic = RegExp(
      r'^(sa|ri1|ri2|ga1|ga2|ma1|ma2|pa|da1|da2|ni1|ni2)-?(\d+)?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (carnatic != null) {
      final name = (carnatic.group(1) ?? '').toLowerCase();
      final octave = carnatic.group(2) ?? '';
      const map = {
        'sa': 'c',
        'ri1': 'c#',
        'ri2': 'd',
        'ga1': 'd#',
        'ga2': 'e',
        'ma1': 'f',
        'ma2': 'f#',
        'pa': 'g',
        'da1': 'g#',
        'da2': 'a',
        'ni1': 'a#',
        'ni2': 'b',
      };
      final westernNote = map[name] ?? 'c';
      return '$westernNote$octave';
    }
  }
  return trimmed.toLowerCase();
}
