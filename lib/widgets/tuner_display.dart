import 'dart:math';

import 'package:flutter/material.dart';

import '../state/pitch_notifier.dart';

class TunerDisplay extends StatelessWidget {
  const TunerDisplay({super.key, required this.history});

  final List<PitchPoint> history;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TunerPainter(history: history),
      child: const SizedBox.expand(),
    );
  }
}

class _NoteRow {
  const _NoteRow({
    required this.label,
    required this.midi,
    required this.minHz,
    required this.maxHz,
  });

  final String label;
  final int midi;
  final double minHz;
  final double maxHz;
}

class _TunerPainter extends CustomPainter {
  _TunerPainter({required this.history});

  final List<PitchPoint> history;

  static const labelWidth = 58.0;
  static const timeSpan = Duration(milliseconds: 6400);

  List<_NoteRow> _noteRows() {
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
      rows.add(_NoteRow(label: label, midi: midi, minHz: minHz, maxHz: maxHz));
    }
    return rows.reversed.toList();
  }

  (int, double) _rowPositionForFrequency(
    double frequency,
    List<_NoteRow> rows,
  ) {
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (frequency >= row.minHz && frequency < row.maxHz) {
        final ratio = (frequency - row.minHz) / (row.maxHz - row.minHz);
        return (i, ratio.clamp(0.0, 1.0));
      }
    }
    if (frequency >= rows.first.maxHz) {
      return (0, 1.0);
    }
    return (rows.length - 1, 0.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rows = _noteRows();
    final rowHeight = size.height / rows.length;
    final now = DateTime.now();
    final startTime = now.subtract(timeSpan);

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
      final isSharp = row.label.contains('#');
      final labelBg = Paint()
        ..color = isSharp ? Colors.black : const Color(0xFFCBD1D6);
      canvas.drawRect(rect, labelBg);

      final textPainter = TextPainter(
        text: TextSpan(
          text: row.label,
          style: TextStyle(
            color: isSharp ? Colors.white : Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
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

    final points = <Offset>[];
    int? previousRowIndex;
    var stableCount = 0;
    for (final point in history) {
      final timeMs = point.time.millisecondsSinceEpoch;
      final startMs = startTime.millisecondsSinceEpoch;
      final t = (timeMs - startMs) / timeSpan.inMilliseconds;
      if (t < 0 || t > 1) {
        continue;
      }
      final x = labelWidth + t * (size.width - labelWidth - 12);
      final (rowIndex, ratio) = _rowPositionForFrequency(point.frequency, rows);
      final rowTop = rowIndex * rowHeight;
      final y = rowTop + (1 - ratio) * rowHeight;

      points.add(Offset(x, y));

      if (previousRowIndex == rowIndex) {
        stableCount += 1;
      } else {
        stableCount = 1;
      }

      if (stableCount >= 3) {
        final barPaint = Paint()
          ..color = const Color(0xFFF08A00)
          ..style = PaintingStyle.fill;
        final barHeight = rowHeight;
        final barCenterY = rowTop + rowHeight / 2;
        final barWidth = max(10.0, rowHeight * 0.6);
        final barRect = Rect.fromCenter(
          center: Offset(x, barCenterY),
          width: barWidth,
          height: barHeight,
        );
        canvas.drawRect(barRect, barPaint);
      }
      previousRowIndex = rowIndex;
    }

    final line = Paint()
      ..color = Colors.white
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final smoothedPoints = _smoothPoints(points, window: 5);
    canvas.drawPath(_smoothPath(smoothedPoints), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

double _midiToHz(int midi) {
  return 440.0 * pow(2, (midi - 69) / 12);
}

Path _smoothPath(List<Offset> points) {
  if (points.length < 2) {
    return Path();
  }
  if (points.length == 2) {
    return Path()
      ..moveTo(points.first.dx, points.first.dy)
      ..lineTo(points.last.dx, points.last.dy);
  }

  final path = Path()..moveTo(points[0].dx, points[0].dy);

  for (var i = 0; i < points.length - 1; i++) {
    final p0 = i == 0 ? points[0] : points[i - 1];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = i + 2 < points.length ? points[i + 2] : p2;

    final cp1 = Offset(
      p1.dx + (p2.dx - p0.dx) / 6,
      p1.dy + (p2.dy - p0.dy) / 6,
    );
    final cp2 = Offset(
      p2.dx - (p3.dx - p1.dx) / 6,
      p2.dy - (p3.dy - p1.dy) / 6,
    );
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
  }

  return path;
}

List<Offset> _smoothPoints(List<Offset> points, {int window = 5}) {
  if (points.length <= 2 || window <= 1) {
    return points;
  }
  final half = window ~/ 2;
  final smoothed = <Offset>[];
  for (var i = 0; i < points.length; i++) {
    final start = (i - half).clamp(0, points.length - 1);
    final end = (i + half).clamp(0, points.length - 1);
    var sumY = 0.0;
    var count = 0;
    for (var j = start; j <= end; j++) {
      sumY += points[j].dy;
      count += 1;
    }
    final avgY = sumY / count;
    smoothed.add(Offset(points[i].dx, avgY));
  }
  return smoothed;
}
