import 'package:flutter/material.dart';

import '../dsp/pitch_detection.dart';

class PitchSummary extends StatelessWidget {
  const PitchSummary({
    super.key,
    required this.frequency,
    required this.clarity,
  });

  final double? frequency;
  final double? clarity;

  @override
  Widget build(BuildContext context) {
    final freq = frequency;
    final clarityValue = clarity ?? 0;
    final hasPitch = freq != null && freq > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasPitch ? noteLabel(freq) : 'Waiting for pitch…',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              hasPitch
                  ? '${freq.toStringAsFixed(2)} Hz'
                  : 'No stable pitch yet',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: (clarityValue).clamp(0.0, 1.0),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(width: 12),
                Text('${(clarityValue * 100).toStringAsFixed(0)}% clarity'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
