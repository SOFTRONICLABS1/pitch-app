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

  static const labelWidth = 74.0;
  static const timeSpan = Duration(seconds: 8);

  List<_NoteRow> _noteRows() {
    const naturals = <int>[0, 2, 4, 5, 7, 9, 11];
    const noteLabels = <int, String>{
      0: 'C',
      2: 'D',
      4: 'E',
      5: 'F',
      7: 'G',
      9: 'A',
      11: 'B',
    };

    final rows = <_NoteRow>[];
    for (var midi = 33; midi <= 62; midi++) {
      final semitone = midi % 12;
      if (!naturals.contains(semitone)) {
        continue;
      }
      final octave = (midi / 12).floor() - 1;
      final label = '${noteLabels[semitone]}$octave';
      final minHz = _midiToHz(midi);
      final maxHz = _midiToHz(midi + 1);
      rows.add(_NoteRow(label: label, midi: midi, minHz: minHz, maxHz: maxHz));
    }
    return rows.reversed.toList();
  }

  int _rowIndexForFrequency(double frequency, List<_NoteRow> rows) {
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (frequency >= row.minHz && frequency < row.maxHz) {
        return i;
      }
    }
    if (frequency >= rows.first.maxHz) {
      return 0;
    }
    return rows.length - 1;
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
      final labelBg = Paint()..color = const Color(0xFFCBD1D6);
      canvas.drawRect(rect, labelBg);

      final textPainter = TextPainter(
        text: TextSpan(
          text: row.label,
          style: const TextStyle(
            color: Colors.black87,
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

    final path = Path();
    var started = false;
    for (final point in history) {
      final timeMs = point.time.millisecondsSinceEpoch;
      final startMs = startTime.millisecondsSinceEpoch;
      final t = (timeMs - startMs) / timeSpan.inMilliseconds;
      if (t < 0 || t > 1) {
        continue;
      }
      final x = labelWidth + t * (size.width - labelWidth - 12);
      final rowIndex = _rowIndexForFrequency(point.frequency, rows);
      final y = rowIndex * rowHeight + rowHeight / 2;

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }

      final barPaint = Paint()
        ..color = const Color(0xFFF08A00)
        ..style = PaintingStyle.fill;
      final barHeight = rowHeight * 0.75;
      final barRect = Rect.fromCenter(
        center: Offset(x, y),
        width: 14,
        height: barHeight,
      );
      canvas.drawRect(barRect, barPaint);
    }

    final line = Paint()
      ..color = Colors.white
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

double _midiToHz(int midi) {
  return 440.0 * pow(2, (midi - 69) / 12);
}
