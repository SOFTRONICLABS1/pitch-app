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
    final selectedNote = _carnaticNoteFor(state.tanpuraNote) ??
        noteOptions.first.$2;
    final selectedString = _carnaticStringFor(state.tanpuraString) ??
        stringOptions.first.$2;
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
                      value: option.$2,
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
                      value: option.$2,
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

String? _carnaticNoteFor(String value) {
  const mapping = {
    'C': 'Sa',
    'C#': 'Ri1',
    'D': 'Ri2',
    'D#': 'Ga1',
    'E': 'Ga2',
    'F': 'Ma1',
    'F#': 'Ma2',
    'G': 'Pa',
    'G#': 'Da1',
    'A': 'Da2',
    'A#': 'Ni1',
    'B': 'Ni2',
    'Sa': 'Sa',
    'Ri1': 'Ri1',
    'Ri2': 'Ri2',
    'Ga1': 'Ga1',
    'Ga2': 'Ga2',
    'Ma1': 'Ma1',
    'Ma2': 'Ma2',
    'Pa': 'Pa',
    'Da1': 'Da1',
    'Da2': 'Da2',
    'Ni1': 'Ni1',
    'Ni2': 'Ni2',
  };
  return mapping[value];
}

String? _carnaticStringFor(String value) {
  const mapping = {
    'C': 'Sa',
    'F': 'Ma',
    'G': 'Pa',
    'B': 'Ni',
    'Sa': 'Sa',
    'Ma': 'Ma',
    'Pa': 'Pa',
    'Ni': 'Ni',
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
