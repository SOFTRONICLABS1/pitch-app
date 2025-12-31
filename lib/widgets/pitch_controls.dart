import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/pitch_notifier.dart';

class PitchControls extends StatelessWidget {
  const PitchControls({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PitchNotifier>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle('Detector'),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('McLeod'),
                  selected: state.detectorName == 'mcleod',
                  onSelected: (_) => state.setDetector('mcleod'),
                ),
                ChoiceChip(
                  label: const Text('Autocorrelation'),
                  selected: state.detectorName == 'autocorrelation',
                  onSelected: (_) => state.setDetector('autocorrelation'),
                ),
                ChoiceChip(
                  label: const Text('YIN'),
                  selected: state.detectorName == 'yin',
                  onSelected: (_) => state.setDetector('yin'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionTitle('Window size'),
            Wrap(
              spacing: 8,
              children: [
                for (final size in const [512, 1024, 2048, 4096])
                  ChoiceChip(
                    label: Text('$size'),
                    selected: state.windowSize == size,
                    onSelected: (_) => state.setWindowSize(size),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionTitle(
              'Clarity threshold (${state.clarityThreshold.toStringAsFixed(2)})',
            ),
            Slider(
              value: state.clarityThreshold,
              min: 0.0,
              max: 1.0,
              onChanged: (value) => state.setClarityThreshold(value),
            ),
            const SizedBox(height: 16),
            _SectionTitle('Display'),
            Text(
              'Timeline',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}
