import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/pitch_notifier.dart';

class PitchControls extends StatelessWidget {
  const PitchControls({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PitchNotifier>();
    const notes = [
      'Sa',
      'Sa#',
      'Re',
      'Re#',
      'Ga',
      'Ga#',
      'Ma',
      'Ma#',
      'Pa',
      'Pa#',
      'Dha',
      'Dha#',
      'Ni',
      'Ni#',
    ];
    const strings = ['Sa', 'Pa', 'Ma', 'Ni'];
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _SettingsHeader(),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SectionTitle('First string'),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<String>(
                value: strings.contains(state.tanpuraString)
                    ? state.tanpuraString
                    : strings.first,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.black,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final value in strings)
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  state.setTanpuraString(value);
                },
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SectionTitle('Note'),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<String>(
                value: state.tanpuraNote,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.black,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final note in notes)
                    DropdownMenuItem(value: note, child: Text(note)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  state.setTanpuraNote(value);
                },
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SectionTitle('Notation'),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'western', label: Text('Western')),
                  ButtonSegment(value: 'carnatic', label: Text('Carnatic')),
                ],
                selected: {state.tuningSystem},
                onSelectionChanged: (value) {
                  if (value.isEmpty) return;
                  state.setTuningSystem(value.first);
                },
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1),
            ),
            const SizedBox(height: 12),
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
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(color: Colors.white70, fontSize: 16),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.settings, size: 20),
        const SizedBox(width: 8),
        Text(
          'Tanpura Settings',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
