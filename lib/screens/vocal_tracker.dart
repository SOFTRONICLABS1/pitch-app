import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../dsp/pitch_detection.dart';
import '../models/recording.dart';
import '../state/pitch_notifier.dart';
import '../services/headset_service.dart';
import '../widgets/tuner_display.dart';

class VocalTrackerScreen extends StatefulWidget {
  const VocalTrackerScreen({super.key, required this.recording});

  final RecordingEntry recording;

  @override
  State<VocalTrackerScreen> createState() => _VocalTrackerScreenState();
}

class _VocalTrackerScreenState extends State<VocalTrackerScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _stopwatch = Stopwatch();
  Duration _elapsed = Duration.zero;
  bool _running = false;
  late final List<_TargetBlock> _targets;
  late final int _totalDurationMs;
  int _bpm = 60;
  DateTime? _frozenAt;
  int _viewportBaseMidi = 33;
  double _viewportOffset = 0.0;
  static const _viewportRowCount = 30;
  bool _harmonicsEnabled = false;
  final AudioPlayer _harmonicsPlayer = AudioPlayer();
  Timer? _harmonicsStopTimer;
  int? _currentHarmonicsKey;
  double _lastTargetElapsedMs = 0.0;
  Duration _targetElapsedOffset = Duration.zero;
  double? _screenWidth;
  static const _guidelineFraction = 0.8;
  static const _guidelineOffset = 0.0;
  DateTime? _harmonicsWindowStart;
  DateTime? _harmonicsWindowEnd;
  int? _harmonicsMidi;
  List<PitchPoint>? _historySnapshot;
  List<PitchPoint>? _filteredHistoryCache;
  int _filteredHistorySourceLength = 0;
  int _filteredHistoryLastMs = -1;
  int? _filteredHistoryStartMs;
  int? _filteredHistoryEndMs;
  int? _filteredHistoryMidi;

  @override
  void initState() {
    super.initState();
    final result = _targetBlocksFromRecording(widget.recording);
    _targets = result.blocks;
    _totalDurationMs = result.totalDurationMs;
    _ticker = createTicker(_onTick);
    _running = false;
    _elapsed = Duration.zero;
    _stopwatch.reset();
    _frozenAt = DateTime.now();
    _harmonicsPlayer.setReleaseMode(ReleaseMode.stop);
    _preloadHarmonics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PitchNotifier>().stop();
    });
  }

  Future<void> _showHarmonicsWarning() async {
    if (!mounted) return;
    if (await HeadsetService.isHeadsetConnected()) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Warning'),
          content: const Text(
            'Harmonics playback can affect pitch detection. '
            'Use headphones for accurate plotting.',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _harmonicsStopTimer?.cancel();
    _stopHarmonics();
    try {
      final pitchState = context.read<PitchNotifier>();
      pitchState.stop();
      if (_historySnapshot != null) {
        pitchState.replaceHistory(_historySnapshot!);
        _historySnapshot = null;
      }
    } catch (_) {}
    _harmonicsPlayer.dispose();
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (!_running) return;
    setState(() {
      _elapsed = _stopwatch.elapsed;
    });
    final targetElapsed = _effectiveTargetElapsed();
    _updateHarmonics(targetElapsed);
    _lastTargetElapsedMs = targetElapsed.inMilliseconds.toDouble();
  }

  Future<void> _handleStart(PitchNotifier state) async {
    if (_running) return;
    _historySnapshot ??= List<PitchPoint>.from(state.history);
    await state.start();
    if (!mounted || !state.listening) return;
    if (!_harmonicsEnabled) {
      await _showHarmonicsWarning();
      if (!mounted) return;
      _harmonicsEnabled = true;
    }
    _stopwatch
      ..reset()
      ..start();
    setState(() {
      _elapsed = Duration.zero;
      _running = true;
      _frozenAt = null;
      _currentHarmonicsKey = null;
      _lastTargetElapsedMs = 0.0;
      _targetElapsedOffset = Duration.zero;
    });
    _ticker.start();
  }

  Future<void> _handleStop(PitchNotifier state) async {
    await state.stop();
    _stopwatch.stop();
    _ticker.stop();
    _stopHarmonics();
    if (_historySnapshot != null) {
      state.replaceHistory(_historySnapshot!);
      _historySnapshot = null;
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _frozenAt = DateTime.now();
      _lastTargetElapsedMs = 0.0;
      _targetElapsedOffset = Duration.zero;
      _harmonicsEnabled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PitchNotifier>();
    final frequency = state.frequency;
    final note = frequency == null
        ? '--'
        : _noteLabel(frequency, state.tuningSystem);
    final noteLabels = _noteLabelsForSystem(state.tuningSystem);
    final labelStyle = _labelStyleForSystem(state.tuningSystem);
    _screenWidth = MediaQuery.of(context).size.width;

    return WillPopScope(
      onWillPop: () async {
        await _handleStop(state);
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () async {
              await _handleStop(state);
              if (!mounted) return;
              Navigator.of(context).pop();
            },
          ),
          title: Text(widget.recording.name),
        ),
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: _NoteBadge(note: note),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          TunerDisplay(
                            history: _filteredHistory(state.history),
                            showBlocks: false,
                            nowOverride: _running ? null : _frozenAt,
                            noteLabels: noteLabels,
                            labelTextStyle: labelStyle,
                            guidelineFraction: _guidelineFraction,
                            guidelineOffset: _guidelineOffset,
                            onViewportChanged: (base, offset) {
                              if (!mounted) return;
                              setState(() {
                                _viewportBaseMidi = base;
                                _viewportOffset = offset;
                              });
                            },
                          ),
                          _TargetNoteTrack(
                            targets: _targets,
                            elapsed: _effectiveTargetElapsed(),
                            totalDurationMs: _totalDurationMs,
                            running: _running,
                            bpm: _bpm,
                            baseMidi: _viewportBaseMidi,
                            rowCount: _viewportRowCount,
                            baseOffset: _viewportOffset,
                            tuningSystem: state.tuningSystem,
                            guidelineFraction: _guidelineFraction,
                            guidelineOffset: _guidelineOffset,
                          ),
                        ],
                      ),
                    ),
                    _PlayPauseBar(
                      listening: state.listening,
                      errorMessage: state.errorMessage,
                      harmonicsEnabled: _harmonicsEnabled,
                      onStart: () => _handleStart(state),
                      onStop: () => _handleStop(state),
                      onToggleHarmonics: null,
                      onOpenSettings: _showBpmSettings,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBpmSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2F353A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        final pitchState = context.watch<PitchNotifier>();
        var current = _bpm;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                height: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  Text(
                    'BPM',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$current',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: _bpmIndex(current).toDouble(),
                    min: 0,
                    max: (_bpmOptions.length - 1).toDouble(),
                    divisions: _bpmOptions.length - 1,
                    label: '$current',
                    onChanged: (value) {
                      final next = _bpmFromIndex(value.round());
                      setSheetState(() {
                        current = next;
                      });
                      setState(() {
                        _bpm = next;
                        _currentHarmonicsKey = null;
                      });
                    },
                  ),
                  const SizedBox(height: 4),
                  _BpmTickLabels(
                    positions: const {
                      20: 0,
                      40: 2,
                      60: 4,
                      120: 10,
                    },
                    maxIndex: _bpmOptions.length - 1,
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Clarity threshold (${pitchState.clarityThreshold.toStringAsFixed(2)})',
                    ),
                  ),
                  Slider(
                    value: pitchState.clarityThreshold,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (value) {
                      pitchState.setClarityThreshold(value);
                      setSheetState(() {});
                    },
                  ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleHarmonics() async {
    final enable = !_harmonicsEnabled;
    if (!enable) {
      if (_running) {
        return;
      }
      _stopHarmonics();
      setState(() {
        _harmonicsEnabled = false;
        _currentHarmonicsKey = null;
      });
      return;
    }
    await _showHarmonicsWarning();
    if (!mounted) return;
    setState(() {
      _harmonicsEnabled = true;
      _currentHarmonicsKey = null;
    });
    _stopHarmonics();
    if (_running) {
      _targetElapsedOffset = _elapsed;
      _lastTargetElapsedMs = 0.0;
    }
  }

  Future<void> _preloadHarmonics() async {
    final assets = <String>[];
    for (final block in _targets) {
      final path = _harmonicsAssetForMidi(block.midi);
      if (path != null) {
        assets.add(path);
      }
    }
    final unique = assets.toSet().toList();
    for (final path in unique) {
      try {
        await rootBundle.load(path);
      } catch (_) {
        // Ignore missing assets; playback will also skip.
      }
    }
  }

  Duration _effectiveTargetElapsed() {
    final diff = _elapsed - _targetElapsedOffset;
    return diff.isNegative ? Duration.zero : diff;
  }

  void _updateHarmonics(Duration targetElapsed) {
    if (!_harmonicsEnabled || !_running || _targets.isEmpty) {
      _stopHarmonics();
      return;
    }
    if (_totalDurationMs <= 0) {
      _stopHarmonics();
      return;
    }
    final elapsedMs = targetElapsed.inMilliseconds.toDouble();
    var previousElapsedMs = _lastTargetElapsedMs;
    if (previousElapsedMs > elapsedMs) {
      previousElapsedMs = elapsedMs;
    }
    if (elapsedMs <= previousElapsedMs) {
      return;
    }
    final scale = 60.0 / max(1, _bpm).toDouble();
    final loopMs = max(1, _totalDurationMs).toDouble() * scale;
    final minCycle = (previousElapsedMs / loopMs).floor();
    final maxCycle = (elapsedMs / loopMs).floor();

    int? index;
    int? cycleIndex;
    double? durationMs;
    double? bestStart;
    for (var k = minCycle; k <= maxCycle; k++) {
      final cycleOffset = k * loopMs;
      for (var i = 0; i < _targets.length; i++) {
        final start = _targets[i].startOffsetMs * scale + cycleOffset;
        final duration = _targets[i].durationMs * scale;
        final end = start + duration;
        final overlaps = end >= previousElapsedMs && start <= elapsedMs;
        if (!overlaps) {
          continue;
        }
        if (bestStart == null || start < bestStart) {
          bestStart = start;
          index = i;
          cycleIndex = k;
          durationMs = duration;
        }
      }
    }

    if (index == null || durationMs == null || cycleIndex == null) {
      return;
    }
    final key = cycleIndex * 10000 + index;
    if (_currentHarmonicsKey == key) {
      return;
    }
    _currentHarmonicsKey = key;
    _playHarmonicFor(_targets[index], durationMs);
  }

  void _playHarmonicFor(_TargetBlock block, double durationMs) {
    final path = _harmonicsAssetForMidi(block.midi);
    if (path == null) {
      return;
    }
    _harmonicsStopTimer?.cancel();
    _harmonicsPlayer.stop();
    _harmonicsPlayer.play(AssetSource(path), volume: 1.0);
    final duration = durationMs.clamp(50, 600000).toDouble();
    _harmonicsMidi = block.midi;
    _harmonicsWindowStart = DateTime.now();
    _harmonicsWindowEnd =
        _harmonicsWindowStart!.add(Duration(milliseconds: duration.round()));
    _harmonicsStopTimer = Timer(
      Duration(milliseconds: duration.round()),
      () {
        _harmonicsPlayer.stop();
      },
    );
  }

  void _stopHarmonics() {
    _harmonicsStopTimer?.cancel();
    _harmonicsStopTimer = null;
    _currentHarmonicsKey = null;
    _harmonicsMidi = null;
    _harmonicsWindowStart = null;
    _harmonicsWindowEnd = null;
    _filteredHistoryCache = null;
    _harmonicsPlayer.stop();
  }

  List<PitchPoint> _filteredHistory(List<PitchPoint> history) {
    _filteredHistoryCache = null;
    return history;
  }

  String? _harmonicsAssetForMidi(int midi) {
    const names = [
      'c',
      'csharp',
      'd',
      'dsharp',
      'e',
      'f',
      'fsharp',
      'g',
      'gsharp',
      'a',
      'asharp',
      'b',
    ];
    final octave = (midi / 12).floor() - 1;
    if (octave < 0 || octave > 8) {
      return null;
    }
    final name = names[midi % 12];
    return 'harmonics/${name}${octave}.wav';
  }
}

class _BpmTickLabels extends StatelessWidget {
  const _BpmTickLabels({
    required this.positions,
    required this.maxIndex,
  });

  final Map<int, int> positions;
  final int maxIndex;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Stack(
        children: [
          for (final entry in positions.entries)
            Align(
              alignment: Alignment(
                _alignmentX(entry.value),
                0,
              ),
              child: Text('${entry.key}'),
            ),
        ],
      ),
    );
  }

  double _alignmentX(int index) {
    if (maxIndex <= 0) {
      return -1;
    }
    final fraction = index / maxIndex;
    return (fraction * 2) - 1;
  }
}

const _bpmOptions = [
  20,
  30,
  40,
  50,
  60,
  70,
  80,
  90,
  100,
  110,
  120,
];

int _bpmIndex(int bpm) {
  final index = _bpmOptions.indexOf(bpm);
  if (index != -1) {
    return index;
  }
  var closestIndex = 0;
  var closestDelta = (bpm - _bpmOptions[0]).abs();
  for (var i = 1; i < _bpmOptions.length; i++) {
    final delta = (bpm - _bpmOptions[i]).abs();
    if (delta < closestDelta) {
      closestDelta = delta;
      closestIndex = i;
    }
  }
  return closestIndex;
}

int _bpmFromIndex(int index) {
  final clamped = index.clamp(0, _bpmOptions.length - 1);
  return _bpmOptions[clamped];
}

class _NoteBadge extends StatelessWidget {
  const _NoteBadge({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2C3136),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        note,
        style: const TextStyle(fontSize: 16, letterSpacing: 0.5),
      ),
    );
  }
}

class _TargetNoteTrack extends StatelessWidget {
  const _TargetNoteTrack({
    required this.targets,
    required this.elapsed,
    required this.totalDurationMs,
    required this.running,
    required this.bpm,
    required this.baseMidi,
    required this.rowCount,
    required this.baseOffset,
    required this.tuningSystem,
    required this.guidelineFraction,
    required this.guidelineOffset,
  });

  final List<_TargetBlock> targets;
  final Duration elapsed;
  final int totalDurationMs;
  final bool running;
  final int bpm;
  final int baseMidi;
  final int rowCount;
  final double baseOffset;
  final String tuningSystem;
  final double guidelineFraction;
  final double guidelineOffset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _TargetNotePainter(
          targets: targets,
          elapsed: elapsed,
          totalDurationMs: totalDurationMs,
          running: running,
          bpm: bpm,
          baseMidi: baseMidi,
          rowCount: rowCount,
          baseOffset: baseOffset,
          tuningSystem: tuningSystem,
          guidelineFraction: guidelineFraction,
          guidelineOffset: guidelineOffset,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PlayPauseBar extends StatelessWidget {
  const _PlayPauseBar({
    required this.listening,
    required this.errorMessage,
    required this.harmonicsEnabled,
    required this.onStart,
    required this.onStop,
    required this.onToggleHarmonics,
    required this.onOpenSettings,
  });

  final bool listening;
  final String? errorMessage;
  final bool harmonicsEnabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback? onToggleHarmonics;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF262B2F),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (errorMessage != null) ...[
            Text(
              errorMessage ?? '',
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(
                      Icons.graphic_eq,
                      size: 30,
                      color: harmonicsEnabled
                          ? const Color(0xFFF08A00)
                          : (onToggleHarmonics == null
                              ? Colors.white54
                              : Colors.white),
                    ),
                    onPressed: onToggleHarmonics,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  listening ? Icons.pause : Icons.play_arrow,
                  size: 36,
                ),
                onPressed: listening ? onStop : onStart,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.tune),
                    onPressed: onOpenSettings,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _noteLabel(double frequency, String tuningSystem) {
  final labels = _noteLabelsForSystem(tuningSystem);
  final midi = midiFromFrequency(frequency).round().clamp(0, 127);
  final octave = (midi / 12).floor() - 1;
  final label = labels[midi % 12];
  return '$label$octave';
}

class _TargetBlock {
  const _TargetBlock({
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

class _TargetNotePainter extends CustomPainter {
  _TargetNotePainter({
    required this.targets,
    required this.elapsed,
    required this.totalDurationMs,
    required this.running,
    required this.bpm,
    required this.baseMidi,
    required this.rowCount,
    required this.baseOffset,
    required this.tuningSystem,
    required this.guidelineFraction,
    required this.guidelineOffset,
  });

  final List<_TargetBlock> targets;
  final Duration elapsed;
  final int totalDurationMs;
  final bool running;
  final int bpm;
  final int baseMidi;
  final int rowCount;
  final double baseOffset;
  final String tuningSystem;
  final double guidelineFraction;
  final double guidelineOffset;

  static const _labelWidth = 58.0;
  static const _trackWindowMs = 6400.0;
  static const _blockColor = Color(0xFF2B6BFF);

  @override
  void paint(Canvas canvas, Size size) {
    if (!running) {
      return;
    }
    if (targets.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'No target notes in this recording.',
          style: TextStyle(color: Colors.white70),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(
        canvas,
        Offset(
          (size.width - tp.width) / 2,
          (size.height - tp.height) / 2,
        ),
      );
      return;
    }

    final nowX = size.width * guidelineFraction + guidelineOffset;
    final plotRightPadding =
        (size.width - nowX).clamp(0.0, size.width).toDouble();
    final plotWidth = size.width - _labelWidth - plotRightPadding;
    if (plotWidth <= 0) {
      return;
    }

    final rowHeight = size.height / rowCount;
    final speed = plotWidth / _trackWindowMs;
    final elapsedMs = elapsed.inMilliseconds.toDouble();
    final scale = 60.0 / max(1, bpm).toDouble();
    final loopMs = max(1, totalDurationMs).toDouble() * scale;
    final windowMs = _trackWindowMs.toDouble();
    final paint = Paint()..color = _blockColor.withOpacity(0.4);
    final textStyle = (tuningSystem == 'carnatic'
            ? const TextStyle(
                fontFamily: 'RobotoMono',
                fontFeatures: [FontFeature.tabularFigures()],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )
            : const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ))
        .copyWith(color: Colors.white);

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(_labelWidth, 0, plotWidth, size.height),
    );
    final minCycle = 0;
    final maxCycle =
        ((elapsedMs + windowMs) / loopMs).ceil() + 1;
    for (var k = minCycle; k <= maxCycle; k++) {
      final cycleOffset = k * loopMs;
      for (final block in targets) {
        final blockWidth = block.durationMs * scale * speed;
        if (blockWidth <= 0) {
          continue;
        }
        final end = block.startOffsetMs * scale +
            cycleOffset +
            (block.durationMs * scale);
        final rightEdge = nowX - speed * (elapsedMs - end);
        final leftEdge = rightEdge - blockWidth;
        if (rightEdge < _labelWidth || leftEdge > _labelWidth + plotWidth) {
          continue;
        }

      final rowIndex = _rowIndexForMidi(block.midi);
        final blockHeight = rowHeight;
      final top = (rowIndex + baseOffset) * rowHeight;
        final rect = Rect.fromLTWH(leftEdge, top, blockWidth, blockHeight);
        canvas.drawRect(rect, paint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: _displayLabel(block.label, tuningSystem),
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: max(0, rect.width - 6));
        if (textPainter.width > 0 && textPainter.height > 0) {
          final textOffset = Offset(
            rect.left + (rect.width - textPainter.width) / 2,
            rect.top + (rect.height - textPainter.height) / 2,
          );
          textPainter.paint(canvas, textOffset);
        }
      }
    }
    canvas.restore();
  }

  int _rowIndexForMidi(int midi) {
    final topMidi = baseMidi + rowCount - 1;
    if (midi >= topMidi) {
      return 0;
    }
    if (midi <= baseMidi) {
      return rowCount - 1;
    }
    return (topMidi - midi).clamp(0, rowCount - 1);
  }

  @override
  bool shouldRepaint(covariant _TargetNotePainter oldDelegate) {
    return oldDelegate.elapsed != elapsed ||
        oldDelegate.targets != targets ||
        oldDelegate.totalDurationMs != totalDurationMs ||
        oldDelegate.running != running ||
        oldDelegate.bpm != bpm ||
        oldDelegate.baseMidi != baseMidi ||
        oldDelegate.rowCount != rowCount ||
        oldDelegate.baseOffset != baseOffset ||
        oldDelegate.tuningSystem != tuningSystem;
  }
}

class _TargetBuildResult {
  const _TargetBuildResult({
    required this.blocks,
    required this.totalDurationMs,
  });

  final List<_TargetBlock> blocks;
  final int totalDurationMs;
}

_TargetBuildResult _targetBlocksFromRecording(RecordingEntry entry) {
  final targets = <_TargetBlock>[];
  var offsetMs = 0;
  for (final note in entry.notes) {
    final normalized = note.note.trim().toLowerCase();
    final midi = _midiFromNoteLabel(normalized);
    if (midi == null) {
      offsetMs += note.durationMs;
      continue;
    }
    if (targets.isNotEmpty && targets.last.midi == midi) {
      final last = targets.removeLast();
      targets.add(
        _TargetBlock(
          midi: last.midi,
          label: last.label,
          durationMs: last.durationMs + note.durationMs,
          startOffsetMs: last.startOffsetMs,
        ),
      );
      offsetMs += note.durationMs;
      continue;
    }
    targets.add(
      _TargetBlock(
        midi: midi,
        label: note.note.toUpperCase(),
        durationMs: note.durationMs,
        startOffsetMs: offsetMs,
      ),
    );
    offsetMs += note.durationMs;
  }
  return _TargetBuildResult(
    blocks: targets,
    totalDurationMs: max(0, offsetMs),
  );
}

int? _midiFromNoteLabel(String note) {
  if (note.isEmpty) return null;
  final match = RegExp(r'^([a-g])(#?)(-?\d+)$').firstMatch(note);
  if (match == null) return null;
  final name = match.group(1);
  final sharp = match.group(2);
  final octave = int.tryParse(match.group(3) ?? '');
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
  return (octave + 1) * 12 + semitone;
}

const _westernNoteLabels = [
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

const _carnaticNoteLabels = [
  'Sa-',
  'Ri1-',
  'Ri2-',
  'Ga1-',
  'Ga2-',
  'Ma1-',
  'Ma2-',
  'Pa-',
  'Da1-',
  'Da2-',
  'Ni1-',
  'Ni2-',
];

List<String> _noteLabelsForSystem(String tuningSystem) {
  return tuningSystem == 'carnatic'
      ? _carnaticNoteLabels
      : _westernNoteLabels;
}

TextStyle? _labelStyleForSystem(String tuningSystem) {
  if (tuningSystem != 'carnatic') {
    return null;
  }
  return const TextStyle(
    fontFamily: 'RobotoMono',
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
}

String _displayLabel(String westernNote, String tuningSystem) {
  if (tuningSystem != 'carnatic') {
    return westernNote;
  }
  final match = RegExp(r'^([A-G])(#?)(-?\d+)$').firstMatch(westernNote);
  if (match == null) {
    return westernNote;
  }
  final name = match.group(1);
  final sharp = match.group(2);
  final octave = match.group(3);
  if (name == null || octave == null) {
    return westernNote;
  }
  final baseIndex = switch (name) {
    'C' => 0,
    'D' => 2,
    'E' => 4,
    'F' => 5,
    'G' => 7,
    'A' => 9,
    'B' => 11,
    _ => 0,
  };
  final semitone = (baseIndex + (sharp == '#' ? 1 : 0)) % 12;
  final label = _carnaticNoteLabels[semitone];
  return '$label$octave ($westernNote)';
}
