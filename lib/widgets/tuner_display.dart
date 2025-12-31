import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../state/pitch_notifier.dart';

class TunerDisplay extends StatefulWidget {
  const TunerDisplay({super.key, required this.history});

  final List<PitchPoint> history;

  @override
  State<TunerDisplay> createState() => _TunerDisplayState();
}

class _TunerDisplayState extends State<TunerDisplay> {
  static const _sampleCount = 1024;
  static const _minUpdateInterval = Duration(milliseconds: 33);

  ui.FragmentProgram? _program;
  ui.Image? _dataImage;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _updating = false;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _loadProgram();
  }

  @override
  void didUpdateWidget(TunerDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleUpdate();
  }

  @override
  void dispose() {
    _dataImage?.dispose();
    super.dispose();
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
    final now = DateTime.now();
    if (now.difference(_lastUpdate) < _minUpdateInterval) {
      return;
    }
    _updateDataImage();
  }

  Future<void> _updateDataImage() async {
    if (_updating || _program == null) {
      return;
    }
    _updating = true;
    _pending = false;
    _lastUpdate = DateTime.now();
    final pixels = _buildDataPixels(
      widget.history,
      sampleCount: _sampleCount,
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
        ),
        isComplex: true,
        willChange: true,
        child: const SizedBox.expand(),
      ),
    );
  }
}

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
  });

  final List<PitchPoint> history;
  final ui.FragmentProgram? program;
  final ui.Image? dataImage;

  static const labelWidth = 58.0;
  static const timeSpan = Duration(milliseconds: 6400);
  static const plotRightPadding = 12.0;
  static const lineWidth = 1.4;
  static final List<_NoteRow> _rows = _buildRows();

  static List<_NoteRow> _buildRows() {
    const noteLabels = <int, String>{
      0: 'C',
      1: 'C#',
      2: 'D',
      3: 'D#',
      4: 'E',
      5: 'F',
      6: 'F#',
      7: 'G',
      8: 'G#',
      9: 'A',
      10: 'A#',
      11: 'B',
    };

    final rows = <_NoteRow>[];
    for (var midi = 33; midi <= 62; midi++) {
      final semitone = midi % 12;
      final octave = (midi / 12).floor() - 1;
      final label = '${noteLabels[semitone]}$octave';
      final minHz = _midiToHz(midi);
      final maxHz = _midiToHz(midi + 1);
      final isSharp = label.contains('#');
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: isSharp ? Colors.white : Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
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

  @override
  void paint(Canvas canvas, Size size) {
    final rows = _rows;
    final rowHeight = size.height / rows.length;
    final now = DateTime.now();
    final startTime = now.subtract(timeSpan);
    final startMs = startTime.millisecondsSinceEpoch;
    final spanMs = timeSpan.inMilliseconds;

    // Background stripes
    for (var i = 0; i < rows.length; i++) {
      final isEven = i % 2 == 0;
      final rect = Rect.fromLTWH(0, i * rowHeight, size.width, rowHeight);
      final paint = Paint()
        ..color = isEven ? const Color(0xFF2A2F33) : const Color(0xFF343A3F);
      canvas.drawRect(rect, paint);
    }

    // Label column background
    final labelPaint = Paint()..color = const Color(0xFF23272B);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, labelWidth, double.infinity),
      labelPaint,
    );

    // Note labels
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rect = Rect.fromLTWH(0, i * rowHeight, labelWidth, rowHeight);
      final labelBg = Paint()
        ..color = row.isSharp ? Colors.black : const Color(0xFFCBD1D6);
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

    // Guideline at "now"
    final nowX = size.width - 10;
    final linePaint = Paint()
      ..color = const Color(0xFFEAEAEA)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(nowX, 0), Offset(nowX, size.height), linePaint);

    if (history.isEmpty) {
      return;
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
      ..setFloat(7, 1.0)
      ..setFloat(8, 1.0)
      ..setFloat(9, 1.0)
      ..setFloat(10, 1.0)
      ..setFloat(11, 0xF0 / 255.0)
      ..setFloat(12, 0x8A / 255.0)
      ..setFloat(13, 0x00 / 255.0)
      ..setFloat(14, 1.0)
      ..setImageSampler(0, dataImage!);
    final plotPaint = Paint()..shader = shader;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      plotPaint,
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

Uint8List _buildDataPixels(
  List<PitchPoint> history, {
  required int sampleCount,
}) {
  final rows = _TunerPainter._rows;
  final pixels = Uint8List(sampleCount * 4);
  if (history.isEmpty) {
    return pixels;
  }

  final now = DateTime.now();
  final startTime = now.subtract(_TunerPainter.timeSpan);
  final startMs = startTime.millisecondsSinceEpoch;
  final spanMs = _TunerPainter.timeSpan.inMilliseconds;
  const maxGapMs = 200;
  final times = List<int>.generate(
    sampleCount,
    (i) => startMs + ((i / (sampleCount - 1)) * spanMs).round(),
  );

  final yNorms = List<double>.filled(sampleCount, 0.0);
  final blockCenters = List<double>.filled(sampleCount, 0.0);
  final hasBlocks = List<bool>.filled(sampleCount, false);
  final valids = List<bool>.filled(sampleCount, false);

  int historyIndex = 0;
  int? previousRowIndex;
  var stableCount = 0;
  for (var i = 0; i < sampleCount; i++) {
    final target = times[i];
    while (historyIndex + 1 < history.length &&
        history[historyIndex + 1].time.millisecondsSinceEpoch < target) {
      historyIndex++;
    }
    final prev = history[historyIndex];
    final prevTime = prev.time.millisecondsSinceEpoch;
    if (prevTime > target || prevTime < startMs || prevTime > startMs + spanMs) {
      stableCount = 0;
      continue;
    }
    if (target - prevTime > maxGapMs) {
      stableCount = 0;
      continue;
    }

    double frequency = prev.frequency;
    if (historyIndex + 1 < history.length) {
      final next = history[historyIndex + 1];
      final nextTime = next.time.millisecondsSinceEpoch;
      if (nextTime - prevTime > maxGapMs) {
        stableCount = 0;
        continue;
      }
      if (nextTime >= target && nextTime != prevTime) {
        var t = (target - prevTime) / (nextTime - prevTime);
        t = 0.5 - 0.5 * cos(pi * t);
        frequency = prev.frequency + t * (next.frequency - prev.frequency);
      }
    }

    final midi = _midiFromFrequency(frequency);
    final (rowIndex, ratio) = _rowPositionForMidi(midi, rows);
    final yNorm = ((rowIndex + (1 - ratio)) / rows.length)
        .clamp(0.0, 1.0)
        .toDouble();

    if (previousRowIndex == rowIndex) {
      stableCount += 1;
    } else {
      stableCount = 1;
    }
    final hasBlock = stableCount >= 3;
    final rowCenterNorm =
        ((rowIndex + 0.5) / rows.length).clamp(0.0, 1.0).toDouble();

    valids[i] = true;
    yNorms[i] = yNorm;
    blockCenters[i] = rowCenterNorm;
    hasBlocks[i] = hasBlock;
    previousRowIndex = rowIndex;
  }

  const smoothWindow = 7;
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
