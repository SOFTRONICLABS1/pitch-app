import 'dart:math';

import 'package:flutter/material.dart';

import '../dsp/pitch_detection.dart';
import '../state/pitch_notifier.dart';

class PitchDisplay extends StatelessWidget {
  const PitchDisplay({
    super.key,
    required this.history,
    required this.frequency,
    required this.clarity,
    required this.mode,
  });

  final List<PitchPoint> history;
  final double? frequency;
  final double? clarity;
  final String mode;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: 280,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: mode == 'circle'
              ? _PitchCircle(frequency: frequency, clarity: clarity ?? 0)
              : _PitchTimeline(history: history),
        ),
      ),
    );
  }
}

class _PitchTimeline extends StatelessWidget {
  const _PitchTimeline({required this.history});
  final List<PitchPoint> history;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TimelinePainter(history: history),
      child: const SizedBox.expand(),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({required this.history});

  final List<PitchPoint> history;

  static const minFreq = 50.0;
  static const maxFreq = 2000.0;
  static final span = const Duration(seconds: 10);

  double _yForFreq(double freq, double height) {
    final clamped = freq.clamp(minFreq, maxFreq);
    final t = (log(clamped) - log(minFreq)) / (log(maxFreq) - log(minFreq));
    return height - t * height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final start = now.subtract(span);

    final bg = Paint()
      ..color = Colors.grey.shade100
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(12),
      ),
      bg,
    );

    // Draw horizontal guide lines for common notes
    final guidePaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;
    for (final freq in [100, 200, 400, 800, 1600]) {
      final y = _yForFreq(freq.toDouble(), size.height);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        guidePaint..color = Colors.grey.shade300,
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${freq.toStringAsFixed(0)} Hz',
          style: const TextStyle(color: Colors.grey, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(4, y - 10));
    }

    if (history.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'No samples yet…',
          style: TextStyle(color: Colors.grey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height),
      );
      return;
    }

    final path = Path();
    final clarityPaint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    bool started = false;
    for (final point in history) {
      final dx =
          (((point.time.millisecondsSinceEpoch - start.millisecondsSinceEpoch) /
                      span.inMilliseconds) *
                  size.width)
              .clamp(0.0, size.width);
      final dy = _yForFreq(point.frequency, size.height);
      final alpha = (point.clarity.clamp(0, 1) * 0.8 + 0.2);
      clarityPaint.color = Colors.indigo.withOpacity(alpha);

      if (!started) {
        path.moveTo(dx, dy);
        started = true;
      } else {
        path.lineTo(dx, dy);
      }
    }
    canvas.drawPath(path, clarityPaint);

    // Draw dots
    for (final point in history) {
      final dx =
          (((point.time.millisecondsSinceEpoch - start.millisecondsSinceEpoch) /
                      span.inMilliseconds) *
                  size.width)
              .clamp(0.0, size.width);
      final dy = _yForFreq(point.frequency, size.height);
      final opacity = (point.clarity.clamp(0, 1) * 0.6 + 0.2);
      final paint = Paint()
        ..color = Colors.blueAccent.withOpacity(opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(dx, dy), 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _PitchCircle extends StatelessWidget {
  const _PitchCircle({required this.frequency, required this.clarity});
  final double? frequency;
  final double clarity;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _CirclePainter(frequency: frequency, clarity: clarity),
            ),
          ),
        );
      },
    );
  }
}

class _CirclePainter extends CustomPainter {
  _CirclePainter({required this.frequency, required this.clarity});

  final double? frequency;
  final double clarity;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final outerR = min(w, h) * 0.35;
    final innerR = outerR * 0.65;

    final ringPaint = Paint()
      ..color = Colors.indigo.shade50
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerR, ringPaint);
    canvas.drawCircle(center, innerR, Paint()..color = Colors.white);

    final tickPaint = Paint()
      ..color = Colors.grey.shade500
      ..strokeWidth = 2;
    for (var i = 0; i < 60; i++) {
      final angle = (i / 60) * 2 * pi - pi / 2;
      final tickLen = i % 5 == 0 ? 12.0 : 6.0;
      final start = Offset(
        center.dx + cos(angle) * (outerR - tickLen),
        center.dy + sin(angle) * (outerR - tickLen),
      );
      final end = Offset(
        center.dx + cos(angle) * outerR,
        center.dy + sin(angle) * outerR,
      );
      canvas.drawLine(start, end, tickPaint);
    }

    if (frequency != null) {
      final angle = ((log(frequency! / 440) / ln2) - 0.5);
      final normalized = ((angle % 1) + 1) % 1;
      final theta = normalized * 2 * pi - pi / 2;
      final pointerPaint = Paint()
        ..color = Colors.blueAccent.withOpacity(
          (clarity.clamp(0, 1) * 0.8) + 0.2,
        )
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      final start = Offset(
        center.dx + cos(theta) * (innerR * 0.2),
        center.dy + sin(theta) * (innerR * 0.2),
      );
      final end = Offset(
        center.dx + cos(theta) * (outerR * 0.95),
        center.dy + sin(theta) * (outerR * 0.95),
      );
      canvas.drawLine(start, end, pointerPaint);

      final noteText = TextPainter(
        text: TextSpan(
          text: noteLabel(frequency!),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      noteText.paint(
        canvas,
        Offset(center.dx - noteText.width / 2, center.dy - 18),
      );

      final freqText = TextPainter(
        text: TextSpan(
          text: '${frequency!.toStringAsFixed(1)} Hz',
          style: const TextStyle(color: Colors.black54, fontSize: 16),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      freqText.paint(
        canvas,
        Offset(center.dx - freqText.width / 2, center.dy + 6),
      );
    } else {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'Listening…',
          style: TextStyle(color: Colors.grey),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(
        canvas,
        Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
