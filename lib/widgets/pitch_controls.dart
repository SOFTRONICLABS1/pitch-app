import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/pitch_notifier.dart';

class PitchControls extends StatelessWidget {
  const PitchControls({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PitchNotifier>();
    const noteOptions = [
      ('C', 'Sa'),
      ('C#', 'Ri1'),
      ('D', 'Ri2'),
      ('D#', 'Ga1'),
      ('E', 'Ga2'),
      ('F', 'Ma1'),
      ('F#', 'Ma2'),
      ('G', 'Pa'),
      ('G#', 'Da1'),
      ('A', 'Da2'),
      ('A#', 'Ni1'),
      ('B', 'Ni2'),
    ];
    const stringOptions = [
      ('C', 'Sa'),
      ('G', 'Pa'),
      ('F', 'Ma'),
      ('B', 'Ni'),
    ];
    final selectedNote = _westernNoteFor(state.tanpuraNote) ??
        noteOptions.first.$1;
    final selectedString = _westernNoteFor(state.tanpuraString) ??
        stringOptions.first.$1;
    if (state.tanpuraNote != selectedNote) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state.setTanpuraNote(selectedNote);
      });
    }
    if (state.tanpuraString != selectedString) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state.setTanpuraString(selectedString);
      });
    }
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
                value: selectedString,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.black,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final option in stringOptions)
                    DropdownMenuItem(
                      value: option.$1,
                      child: Text('${option.$1} - ${option.$2}'),
                    ),
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
                value: selectedNote,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.black,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final option in noteOptions)
                    DropdownMenuItem(
                      value: option.$1,
                      child: Text('${option.$1} - ${option.$2}'),
                    ),
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

String? _westernNoteFor(String value) {
  const mapping = {
    'Sa': 'C',
    'Ri1': 'C#',
    'Ri2': 'D',
    'Ga1': 'D#',
    'Ga2': 'E',
    'Ma1': 'F',
    'Ma2': 'F#',
    'Pa': 'G',
    'Da1': 'G#',
    'Da2': 'A',
    'Ni1': 'A#',
    'Ni2': 'B',
    'C': 'C',
    'C#': 'C#',
    'D': 'D',
    'D#': 'D#',
    'E': 'E',
    'F': 'F',
    'F#': 'F#',
    'G': 'G',
    'G#': 'G#',
    'A': 'A',
    'A#': 'A#',
    'B': 'B',
  };
  return mapping[value];
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
