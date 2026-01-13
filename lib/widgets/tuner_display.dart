import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../state/pitch_notifier.dart';

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
const _defaultRowCount = 30;

class TunerDisplay extends StatefulWidget {
  const TunerDisplay({
    super.key,
    required this.history,
    this.showBlocks = true,
    this.showLabels = true,
    this.nowOverride,
    this.onBaseMidiChanged,
    this.onViewportChanged,
    this.noteLabels = _westernNoteLabels,
    this.labelTextStyle,
    this.guidelineFraction = 1.0,
    this.guidelineOffset = -15.0,
    this.rowCount = _defaultRowCount,
  });

  final List<PitchPoint> history;
  final bool showBlocks;
  final bool showLabels;
  final DateTime? nowOverride;
  final ValueChanged<int>? onBaseMidiChanged;
  final void Function(int baseMidi, double baseOffset)? onViewportChanged;
  final List<String> noteLabels;
  final TextStyle? labelTextStyle;
  final double guidelineFraction;
  final double guidelineOffset;
  final int rowCount;

  @override
  State<TunerDisplay> createState() => _TunerDisplayState();
}

class _TunerDisplayState extends State<TunerDisplay>
    with SingleTickerProviderStateMixin {
  static const _sampleCount = 2048;
  static const _frameInterval = Duration(milliseconds: 16);
  static const _minMidi = 21;
  static const _maxMidi = 108;
  static const _scrollStep = 6;
  static const _edgeThreshold = 2;
  static const _scrollDuration = Duration(milliseconds: 240);

  ui.FragmentProgram? _program;
  ui.Image? _dataImage;
  bool _updating = false;
  bool _pending = false;
  late final Ticker _ticker;
  Duration _lastFrameTime = Duration.zero;
  double _baseMidi = 33.0;
  int _baseMidiFloor = 33;
  double _baseOffset = 0.0;
  int _targetBaseMidi = 33;
  double _scrollFrom = 33.0;
  double _scrollTo = 33.0;
  Duration? _scrollStart;
  double? _lastMidi;
  late List<_NoteRow> _rows = _buildRows(
    _baseMidiFloor,
    widget.rowCount,
    widget.noteLabels,
    widget.labelTextStyle,
  );

  @override
  void initState() {
    super.initState();
    _loadProgram();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onBaseMidiChanged?.call(_baseMidiFloor);
      widget.onViewportChanged?.call(_baseMidiFloor, _baseOffset);
    });
  }

  @override
  void didUpdateWidget(TunerDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteLabels != widget.noteLabels ||
        oldWidget.labelTextStyle != widget.labelTextStyle ||
        oldWidget.rowCount != widget.rowCount) {
      _rows = _buildRows(
        _baseMidiFloor,
        widget.rowCount,
        widget.noteLabels,
        widget.labelTextStyle,
      );
    }
    _scheduleUpdate();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _dataImage?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _lastFrameTime < _frameInterval) {
      return;
    }
    _lastFrameTime = elapsed;
    _updateViewport(elapsed);
    _scheduleUpdate();
  }

  Future<void> _loadProgram() async {
    final program = await ui.FragmentProgram.fromAsset(
      'shaders/tuner_plot.frag',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _program = program;
    });
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    if (_program == null) {
      return;
    }
    if (_updating) {
      _pending = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _updateDataImage();
    });
  }

  Future<void> _updateDataImage() async {
    if (_updating || _program == null) {
      return;
    }
    _updating = true;
    _pending = false;
    final pixels = _buildDataPixels(
      widget.history,
      sampleCount: _sampleCount,
      showBlocks: widget.showBlocks,
      nowOverride: widget.nowOverride,
      rows: _rows,
      baseOffset: _baseOffset,
    );
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: _sampleCount,
      height: 1,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    buffer.dispose();
    if (!mounted) {
      frame.image.dispose();
      _updating = false;
      return;
    }
    setState(() {
      _dataImage?.dispose();
      _dataImage = frame.image;
    });
    _updating = false;
    if (_pending) {
      _scheduleUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _TunerPainter(
          history: widget.history,
          program: _program,
          dataImage: _dataImage,
          sampleCount: _sampleCount,
          nowOverride: widget.nowOverride,
          rows: _rows,
          baseOffset: _baseOffset,
          noteLabels: widget.noteLabels,
          labelTextStyle: widget.labelTextStyle,
          guidelineFraction: widget.guidelineFraction,
          guidelineOffset: widget.guidelineOffset,
          showLabels: widget.showLabels,
        ),
        isComplex: true,
        willChange: true,
        child: const SizedBox.expand(),
      ),
    );
  }

  void _updateViewport(Duration elapsed) {
    if (widget.history.isEmpty) {
      return;
    }
    final latest = widget.history.last;
    final midi = _midiFromFrequency(latest.frequency);
    final topMidi = _baseMidiFloor + widget.rowCount - 1;
    final upperTrigger = topMidi - _edgeThreshold;
    final lowerTrigger = _baseMidiFloor + _edgeThreshold;
    var nextBase = _targetBaseMidi;
    final lastMidi = _lastMidi;
    if (_scrollStart == null && lastMidi != null) {
      if (midi >= upperTrigger && lastMidi < upperTrigger) {
        nextBase = _targetBaseMidi + _scrollStep;
      } else if (midi <= lowerTrigger && lastMidi > lowerTrigger) {
        nextBase = _targetBaseMidi - _scrollStep;
      }
    }
    nextBase = nextBase.clamp(_minMidi, _maxMidi - widget.rowCount + 1);
    if (nextBase != _targetBaseMidi) {
      _targetBaseMidi = nextBase;
      _scrollFrom = _baseMidi;
      _scrollTo = nextBase.toDouble();
      _scrollStart = elapsed;
    }

    if (_scrollStart != null) {
      final t =
          ((elapsed - _scrollStart!).inMilliseconds / _scrollDuration.inMilliseconds)
              .clamp(0.0, 1.0);
      _baseMidi = _scrollFrom + (_scrollTo - _scrollFrom) * t;
      if (t >= 1.0) {
        _scrollStart = null;
        _baseMidi = _scrollTo;
      }
    }

    final nextFloor = _baseMidi.floor();
    final nextOffset = _baseMidi - nextFloor;
    if (nextFloor != _baseMidiFloor || nextOffset != _baseOffset) {
      setState(() {
        _baseMidiFloor = nextFloor;
        _baseOffset = nextOffset;
        _rows = _buildRows(
          _baseMidiFloor,
          widget.rowCount,
          widget.noteLabels,
          widget.labelTextStyle,
        );
      });
      widget.onBaseMidiChanged?.call(_baseMidiFloor);
      widget.onViewportChanged?.call(_baseMidiFloor, _baseOffset);
    }
    _lastMidi = midi;
  }
}

const _maxPlotGapMs = 150;

class _NoteRow {
  const _NoteRow({
    required this.label,
    required this.midi,
    required this.minHz,
    required this.maxHz,
    required this.isSharp,
    required this.labelPainter,
  });

  final String label;
  final int midi;
  final double minHz;
  final double maxHz;
  final bool isSharp;
  final TextPainter labelPainter;
}

class _TunerPainter extends CustomPainter {
  _TunerPainter({
    required this.history,
    required this.program,
    required this.dataImage,
    required this.sampleCount,
    required this.nowOverride,
    required this.rows,
    required this.baseOffset,
    required this.noteLabels,
    required this.labelTextStyle,
    required this.guidelineFraction,
    required this.guidelineOffset,
    required this.showLabels,
  });

  final List<PitchPoint> history;
  final ui.FragmentProgram? program;
  final ui.Image? dataImage;
  final int sampleCount;
  final DateTime? nowOverride;
  final List<_NoteRow> rows;
  final double baseOffset;
  final List<String> noteLabels;
  final TextStyle? labelTextStyle;
  final double guidelineFraction;
  final double guidelineOffset;
  final bool showLabels;

  static const labelWidth = 58.0;
  static const timeSpan = Duration(milliseconds: 6400);
  static const lineWidth = 2.0;
  static const lineStrokeWidth = 1.0;
  static const lineSmoothingAlpha = 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = this.rows;
    final rowHeight = size.height / rows.length;
    final now = nowOverride ?? DateTime.now();
    final startTime = now.subtract(timeSpan);
    final startMs = startTime.millisecondsSinceEpoch;
    final spanMs = timeSpan.inMilliseconds;
    final nowX = size.width * guidelineFraction + guidelineOffset;
    final plotRightPadding =
        (size.width - nowX).clamp(0.0, size.width).toDouble();

    final rowShift = baseOffset * rowHeight;

    // Background stripes
    for (var i = -1; i <= rows.length; i++) {
      final isEven = i % 2 == 0;
      final top = (i * rowHeight) + rowShift;
      final rect = Rect.fromLTWH(0, top, size.width, rowHeight);
      final paint = Paint()
        ..color = isEven ? const Color(0xFF2A2F33) : const Color(0xFF343A3F);
      canvas.drawRect(rect, paint);
    }

    if (showLabels) {
      // Label column background
      final labelPaint = Paint()..color = const Color(0xFF23272B);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, labelWidth, double.infinity),
        labelPaint,
      );

      // Note labels
      for (var i = -1; i <= rows.length; i++) {
        final top = (i * rowHeight) + rowShift;
        final rect = Rect.fromLTWH(0, top, labelWidth, rowHeight);
        final row = _rowForIndex(i, rows, noteLabels, labelTextStyle);
        final isSharp = _isSharpSemitone(row.midi);
        final labelBg = Paint()
          ..color = isSharp ? Colors.black : const Color(0xFFCBD1D6);
        canvas.drawRect(rect, labelBg);

        final textPainter = row.labelPainter;
        textPainter.paint(
          canvas,
          Offset(
            rect.left + (labelWidth - textPainter.width) / 2,
            rect.top + (rowHeight - textPainter.height) / 2,
          ),
        );
      }
    }

    if (program == null || dataImage == null) {
      return;
    }

    final shader = program!.fragmentShader();
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, labelWidth)
      ..setFloat(3, plotRightPadding)
      ..setFloat(4, lineWidth)
      ..setFloat(5, rowHeight)
      ..setFloat(6, max(10.0, rowHeight * 0.6))
      ..setFloat(7, sampleCount.toDouble())
      ..setFloat(8, 1.0)
      ..setFloat(9, 1.0)
      ..setFloat(10, 1.0)
      ..setFloat(11, 0.0)
      ..setFloat(12, 0xF0 / 255.0)
      ..setFloat(13, 0x8A / 255.0)
      ..setFloat(14, 0x00 / 255.0)
      ..setFloat(15, 1.0)
      ..setImageSampler(0, dataImage!);
    final plotPaint = Paint()..shader = shader;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      plotPaint,
    );

    if (history.isNotEmpty) {
      final now = nowOverride ?? DateTime.now();
      final startTime = now.subtract(timeSpan);
      final startMs = startTime.millisecondsSinceEpoch;
      final spanMs = timeSpan.inMilliseconds;
      final plotWidth = size.width - labelWidth - plotRightPadding;
      final dynamicGapMs = _computeDynamicGapMs(history, startMs, now);
      final linePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = lineStrokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      int? lastMs;
      var started = false;
      double? smoothedY;
      for (final point in history) {
        final timeMs = point.time.millisecondsSinceEpoch;
        if (timeMs < startMs) {
          continue;
        }
        if (timeMs > now.millisecondsSinceEpoch) {
          break;
        }
        if (lastMs != null && timeMs - lastMs > dynamicGapMs) {
          started = false;
          smoothedY = null;
        }
        final midi = _midiFromFrequency(point.frequency);
        final (rowIndex, ratio) = _rowPositionForMidi(midi, rows);
        final yNorm = ((rowIndex + (1 - ratio) + baseOffset) / rows.length)
            .clamp(0.0, 1.0)
            .toDouble();
        final x = labelWidth + ((timeMs - startMs) / spanMs) * plotWidth;
        final y = yNorm * size.height;
        if (!started || smoothedY == null) {
          smoothedY = y;
        } else {
          smoothedY = smoothedY! + lineSmoothingAlpha * (y - smoothedY!);
        }
        if (!started) {
          path.moveTo(x, smoothedY!);
          started = true;
        } else {
          path.lineTo(x, smoothedY!);
        }
        lastMs = timeMs;
      }
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(labelWidth, 0, plotWidth, size.height),
      );
      canvas.drawPath(path, linePaint);
      canvas.restore();
    }

    final guidelinePaint = Paint()
      ..color = const Color(0xFFEAEAEA)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(nowX, 0),
      Offset(nowX, size.height),
      guidelinePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

double _midiToHz(int midi) {
  return 440.0 * pow(2, (midi - 69) / 12);
}

double _midiFromFrequency(double frequency) {
  return 69 + 12 * (log(frequency / 440.0) / ln2);
}

bool _isSharpSemitone(int midi) {
  const sharpSemitones = {1, 3, 6, 8, 10};
  return sharpSemitones.contains(midi % 12);
}

int _computeDynamicGapMs(List<PitchPoint> history, int startMs, DateTime now) {
  if (history.length < 2) {
    return _maxPlotGapMs;
  }
  final endMs = now.millisecondsSinceEpoch;
  final deltas = <int>[];
  var previous = history.first;
  for (final point in history.skip(1)) {
    final timeMs = point.time.millisecondsSinceEpoch;
    if (timeMs < startMs || timeMs > endMs) {
      previous = point;
      continue;
    }
    final prevMs = previous.time.millisecondsSinceEpoch;
    if (prevMs >= startMs && prevMs <= endMs) {
      final delta = timeMs - prevMs;
      if (delta > 0) {
        deltas.add(delta);
      }
    }
    previous = point;
  }
  if (deltas.isEmpty) {
    return _maxPlotGapMs;
  }
  deltas.sort();
  final median = deltas[deltas.length ~/ 2];
  final threshold = median * 4;
  return threshold < _maxPlotGapMs ? _maxPlotGapMs : threshold;
}

(int, double) _rowPositionForMidi(double midi, List<_NoteRow> rows) {
  final midiInt = midi.round();
  final topMidi = rows.first.midi.toDouble();
  final bottomMidi = rows.last.midi.toDouble();
  if (midiInt >= topMidi + 1) {
    return (0, 1.0);
  }
  if (midiInt <= bottomMidi - 1) {
    return (rows.length - 1, 0.0);
  }

  var bestIndex = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < rows.length; i++) {
    final distance = (midiInt - rows[i].midi).abs().toDouble();
    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = i;
    }
  }

  final centerMidi = rows[bestIndex].midi.toDouble();
  final ratio = (midi - centerMidi + 0.5).clamp(0.0, 1.0);
  return (bestIndex, ratio);
}

_NoteRow _rowForIndex(
  int index,
  List<_NoteRow> rows,
  List<String> noteLabels,
  TextStyle? labelTextStyle,
) {
  if (index >= 0 && index < rows.length) {
    return rows[index];
  }
  final baseMidi = rows.isNotEmpty ? rows.last.midi : 33;
  final midi = baseMidi + (rows.length - 1 - index);
  return _noteRowForMidi(midi, noteLabels, labelTextStyle);
}

_NoteRow _noteRowForMidi(
  int midi,
  List<String> noteLabels,
  TextStyle? labelTextStyle,
) {
  const sharpSemitones = {1, 3, 6, 8, 10};
  final semitone = midi % 12;
  final octave = (midi / 12).floor() - 1;
  final label = '${noteLabels[semitone]}$octave';
  final minHz = _midiToHz(midi);
  final maxHz = _midiToHz(midi + 1);
  final isSharp = sharpSemitones.contains(semitone);
  final baseStyle = labelTextStyle ??
      TextStyle(
        color: isSharp ? Colors.white : Colors.black87,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      );
  final resolvedStyle = baseStyle.copyWith(
    color: isSharp ? Colors.white : Colors.black87,
  );
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: resolvedStyle,
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return _NoteRow(
    label: label,
    midi: midi,
    minHz: minHz,
    maxHz: maxHz,
    isSharp: isSharp,
    labelPainter: painter,
  );
}

List<_NoteRow> _buildRows(
  int baseMidi,
  int count,
  List<String> noteLabels,
  TextStyle? labelTextStyle,
) {
  const sharpSemitones = {1, 3, 6, 8, 10};
  final rows = <_NoteRow>[];
  for (var midi = baseMidi; midi < baseMidi + count; midi++) {
    final semitone = midi % 12;
    final octave = (midi / 12).floor() - 1;
    final label = '${noteLabels[semitone]}$octave';
    final minHz = _midiToHz(midi);
    final maxHz = _midiToHz(midi + 1);
    final isSharp = sharpSemitones.contains(semitone);
    final baseStyle = labelTextStyle ??
        TextStyle(
          color: isSharp ? Colors.white : Colors.black87,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        );
    final resolvedStyle = baseStyle.copyWith(
      color: isSharp ? Colors.white : Colors.black87,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: resolvedStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rows.add(
      _NoteRow(
        label: label,
        midi: midi,
        minHz: minHz,
        maxHz: maxHz,
        isSharp: isSharp,
        labelPainter: painter,
      ),
    );
  }
  return rows.reversed.toList();
}

Uint8List _buildDataPixels(
  List<PitchPoint> history, {
  required int sampleCount,
  bool showBlocks = true,
  DateTime? nowOverride,
  required List<_NoteRow> rows,
  required double baseOffset,
}) {
  final pixels = Uint8List(sampleCount * 4);
  if (history.isEmpty) {
    return pixels;
  }

  final now = nowOverride ?? DateTime.now();
  final startTime = now.subtract(_TunerPainter.timeSpan);
  final startMs = startTime.millisecondsSinceEpoch;
  final spanMs = _TunerPainter.timeSpan.inMilliseconds;
  const maxGapMs = _maxPlotGapMs;
  const holdMs = 100;
  const maxJumpSemitones = 4.0;
  var effectiveHistory = history;
  if (history.isNotEmpty) {
    final last = history.last;
    final tailGap = now.millisecondsSinceEpoch -
        last.time.millisecondsSinceEpoch;
    if (tailGap > 0 && tailGap <= holdMs) {
      effectiveHistory = List<PitchPoint>.from(history)
        ..add(
          PitchPoint(
            time: now,
            frequency: last.frequency,
            clarity: last.clarity,
          ),
        );
    }
  }
  final timeStep = spanMs / (sampleCount - 1);

  final yNorms = List<double>.filled(sampleCount, 0.0);
  final blockCenters = List<double>.filled(sampleCount, 0.0);
  final hasBlocks = List<bool>.filled(sampleCount, false);
  final valids = List<bool>.filled(sampleCount, false);

  int historyIndex = 0;
  int? previousRowIndex;
  var stableCount = 0;
  double? lastAcceptedMidi;
  for (var i = 0; i < sampleCount; i++) {
    final target = startMs + (i * timeStep).round();
    while (historyIndex + 1 < effectiveHistory.length &&
        effectiveHistory[historyIndex + 1].time.millisecondsSinceEpoch <
            target) {
      historyIndex++;
    }
    final prev = effectiveHistory[historyIndex];
    final prevTime = prev.time.millisecondsSinceEpoch;
    if (prevTime > target || prevTime < startMs || prevTime > startMs + spanMs) {
      stableCount = 0;
      lastAcceptedMidi = null;
      previousRowIndex = null;
      continue;
    }
    if (target - prevTime > maxGapMs) {
      stableCount = 0;
      lastAcceptedMidi = null;
      previousRowIndex = null;
      continue;
    }

    double frequency = prev.frequency;
    if (historyIndex + 1 < effectiveHistory.length) {
      final next = effectiveHistory[historyIndex + 1];
      final nextTime = next.time.millisecondsSinceEpoch;
      if (nextTime - prevTime > maxGapMs) {
        stableCount = 0;
        lastAcceptedMidi = null;
        previousRowIndex = null;
        continue;
      }
      if (nextTime >= target && nextTime != prevTime) {
        var t = (target - prevTime) / (nextTime - prevTime);
        t = 0.5 - 0.5 * cos(pi * t);
        frequency = prev.frequency + t * (next.frequency - prev.frequency);
      }
    }

    final midi = _midiFromFrequency(frequency);
    final prevMidi = _midiFromFrequency(prev.frequency);
    if ((midi - prevMidi).abs() > maxJumpSemitones) {
      stableCount = 0;
      lastAcceptedMidi = null;
      previousRowIndex = null;
      continue;
    }
    if (lastAcceptedMidi != null &&
        (midi - lastAcceptedMidi!).abs() > maxJumpSemitones) {
      stableCount = 0;
      lastAcceptedMidi = null;
      previousRowIndex = null;
      continue;
    }
    final (rowIndex, ratio) = _rowPositionForMidi(midi, rows);
    final yNorm = ((rowIndex + (1 - ratio) + baseOffset) / rows.length)
        .clamp(0.0, 1.0)
        .toDouble();

    if (previousRowIndex == rowIndex) {
      stableCount += 1;
    } else {
      stableCount = 1;
    }
    final hasBlock = showBlocks && stableCount >= 3;
    final rowCenterNorm = ((rowIndex + 0.5 + baseOffset) / rows.length)
        .clamp(0.0, 1.0)
        .toDouble();

    valids[i] = true;
    yNorms[i] = yNorm;
    blockCenters[i] = rowCenterNorm;
    hasBlocks[i] = hasBlock;
    lastAcceptedMidi = midi;
    previousRowIndex = rowIndex;
  }

  const smoothWindow = 11;
  final half = smoothWindow ~/ 2;
  final smoothed = List<double>.from(yNorms);
  for (var i = 0; i < sampleCount; i++) {
    if (!valids[i]) {
      continue;
    }
    var sum = 0.0;
    var count = 0;
    final start = max(0, i - half);
    final end = min(sampleCount - 1, i + half);
    for (var j = start; j <= end; j++) {
      if (!valids[j]) {
        continue;
      }
      sum += yNorms[j];
      count += 1;
    }
    if (count > 0) {
      smoothed[i] = sum / count;
    }
  }

  for (var i = 0; i < sampleCount; i++) {
    final base = i * 4;
    if (!valids[i]) {
      pixels[base + 3] = 0;
      continue;
    }
    pixels[base] = (smoothed[i] * 255).round().clamp(0, 255);
    if (hasBlocks[i]) {
      pixels[base + 1] = (blockCenters[i] * 255).round().clamp(0, 255);
      pixels[base + 2] = 255;
    } else {
      pixels[base + 1] = 0;
      pixels[base + 2] = 0;
    }
    pixels[base + 3] = 255;
  }
  return pixels;
}
