import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../dsp/pitch_detection.dart';
import '../models/recording.dart';
import '../state/pitch_notifier.dart';
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

  @override
  void initState() {
    super.initState();
    final result = _targetBlocksFromRecording(widget.recording);
    _targets = result.blocks;
    _totalDurationMs = result.totalDurationMs;
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (!_running) return;
    setState(() {
      _elapsed = _stopwatch.elapsed;
    });
  }

  Future<void> _handleStart(PitchNotifier state) async {
    if (_running) return;
    await state.start();
    if (!mounted || !state.listening) return;
    _stopwatch
      ..reset()
      ..start();
    setState(() {
      _elapsed = Duration.zero;
      _running = true;
      _frozenAt = null;
    });
    _ticker.start();
  }

  Future<void> _handleStop(PitchNotifier state) async {
    await state.stop();
    _stopwatch.stop();
    _ticker.stop();
    if (!mounted) return;
    setState(() {
      _running = false;
      _frozenAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PitchNotifier>();
    final frequency = state.frequency;
    final note = frequency == null ? '--' : _noteLabel(frequency);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(widget.recording.name),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _NoteBadge(note: note),
            const SizedBox(height: 12),
            Expanded(
              child: Stack(
                children: [
                  TunerDisplay(
                    history: state.history,
                    showBlocks: false,
                    nowOverride: _running ? null : _frozenAt,
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
                    elapsed: _elapsed,
                    totalDurationMs: _totalDurationMs,
                    running: _running,
                    bpm: _bpm,
                    baseMidi: _viewportBaseMidi,
                    rowCount: _viewportRowCount,
                    baseOffset: _viewportOffset,
                  ),
                ],
              ),
            ),
            _PlayPauseBar(
              listening: state.listening,
              errorMessage: state.errorMessage,
              onStart: () => _handleStart(state),
              onStop: () => _handleStop(state),
              onOpenSettings: _showBpmSettings,
            ),
          ],
        ),
      ),
    );
  }

  void _showBpmSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF23272B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        var current = _bpm;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20),
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
                    max: 3,
                    divisions: 3,
                    label: '$current',
                    onChanged: (value) {
                      final next = _bpmFromIndex(value.round());
                      setSheetState(() {
                        current = next;
                      });
                      setState(() {
                        _bpm = next;
                      });
                    },
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('20'),
                      Text('40'),
                      Text('60'),
                      Text('120'),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

int _bpmIndex(int bpm) {
  switch (bpm) {
    case 20:
      return 0;
    case 40:
      return 1;
    case 60:
      return 2;
    case 120:
      return 3;
    default:
      return 2;
  }
}

int _bpmFromIndex(int index) {
  switch (index) {
    case 0:
      return 20;
    case 1:
      return 40;
    case 2:
      return 60;
    case 3:
      return 120;
    default:
      return 60;
  }
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
  });

  final List<_TargetBlock> targets;
  final Duration elapsed;
  final int totalDurationMs;
  final bool running;
  final int bpm;
  final int baseMidi;
  final int rowCount;
  final double baseOffset;

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
    required this.onStart,
    required this.onStop,
    required this.onOpenSettings,
  });

  final bool listening;
  final String? errorMessage;
  final VoidCallback onStart;
  final VoidCallback onStop;
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
              const Expanded(child: SizedBox()),
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

String _noteLabel(double frequency) {
  const sharps = [
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
  const flats = [
    'C',
    'Db',
    'D',
    'Eb',
    'E',
    'F',
    'Gb',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ];
  final midi = midiFromFrequency(frequency).round().clamp(0, 127);
  final octave = (midi / 12).floor() - 1;
  final sharp = sharps[midi % 12];
  final flat = flats[midi % 12];
  final label = sharp == flat ? sharp : '$sharp/$flat';
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
  });

  final List<_TargetBlock> targets;
  final Duration elapsed;
  final int totalDurationMs;
  final bool running;
  final int bpm;
  final int baseMidi;
  final int rowCount;
  final double baseOffset;

  static const _labelWidth = 58.0;
  static const _plotRightPadding = 12.0;
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

    final plotWidth = size.width - _labelWidth - _plotRightPadding;
    if (plotWidth <= 0) {
      return;
    }

    final rowHeight = size.height / rowCount;
    final speed = plotWidth / _trackWindowMs;
    final elapsedMs = elapsed.inMilliseconds.toDouble();
    final scale = 60.0 / max(1, bpm).toDouble();
    final loopMs = max(1, totalDurationMs).toDouble() * scale;
    final loopElapsed = (running ? elapsedMs : elapsedMs) % loopMs;
    final paint = Paint()..color = _blockColor.withOpacity(0.4);
    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(_labelWidth, 0, plotWidth, size.height),
    );
    final cycleWidth = speed * loopMs;
    final cyclesNeeded =
        (plotWidth / max(1.0, cycleWidth)).ceil() + 2;
    final nowX = size.width - 15;
    for (var i = 0; i < cyclesNeeded; i++) {
      final cycleOffset = i * loopMs;
      for (final block in targets) {
        final blockWidth = block.durationMs * scale * speed;
        if (blockWidth <= 0) {
          continue;
        }
        final rightEdge = nowX -
            speed * (loopElapsed - (block.startOffsetMs * scale) + cycleOffset);
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
          text: TextSpan(text: block.label, style: textStyle),
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
        oldDelegate.baseOffset != baseOffset;
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
