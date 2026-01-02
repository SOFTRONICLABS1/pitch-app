import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/pitch_notifier.dart';

class PitchControls extends StatelessWidget {
  const PitchControls({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PitchNotifier>();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SectionTitle(
                'Clarity threshold (${state.clarityThreshold.toStringAsFixed(2)})',
              ),
            ),
            Slider(
              value: state.clarityThreshold,
              min: 0.0,
              max: 1.0,
              onChanged: (value) => state.setClarityThreshold(value),
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
