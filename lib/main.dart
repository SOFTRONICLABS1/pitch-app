import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dsp/pitch_detection.dart';
import 'state/pitch_notifier.dart';
import 'widgets/pitch_controls.dart';
import 'widgets/tuner_display.dart';

void main() {
  runApp(const PitchApp());
}

class PitchApp extends StatelessWidget {
  const PitchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PitchNotifier(),
      child: MaterialApp(
        title: 'pitch-app',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF23272B),
          cardColor: const Color(0xFF2C3136),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFF08A00),
            secondary: Color(0xFFECECEC),
          ),
        ),
        home: const PitchHomePage(),
      ),
    );
  }
}

class PitchHomePage extends StatelessWidget {
  const PitchHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PitchNotifier>();
    final frequency = state.frequency;
    final note = frequency == null ? '--' : _noteLabel(frequency);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _NoteBadge(note: note),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TunerDisplay(history: state.history),
              ),
            ),
            const SizedBox(height: 6),
            _BottomBar(
              listening: state.listening,
              errorMessage: state.errorMessage,
              onStart: state.start,
              onStop: state.stop,
              onOpenSettings: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: const Color(0xFF2C3136),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  builder: (_) => const Padding(
                    padding: EdgeInsets.all(16),
                    child: PitchControls(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteBadge extends StatelessWidget {
  const _NoteBadge({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2C3136),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        note,
        style: const TextStyle(fontSize: 16, letterSpacing: 0.5),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.listening,
    required this.errorMessage,
    required this.onStart,
    required this.onStop,
    required this.onOpenSettings,
  });

  final bool listening;
  final String? errorMessage;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF262B2F),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          if (errorMessage != null) ...[
            Text(
              errorMessage ?? '',
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 30),
                onPressed: () {},
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  listening ? Icons.pause : Icons.play_arrow,
                  size: 36,
                ),
                onPressed: listening ? onStop : onStart,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
                onPressed: listening ? onStop : onStart,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.settings, size: 30),
                onPressed: onOpenSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

double _centsOffset(double frequency) {
  final midi = midiFromFrequency(frequency);
  final rounded = midi.round();
  return (midi - rounded) * 100;
}

String _noteLabel(double frequency) {
  const sharps = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];
  const flats = [
    'C',
    'Db',
    'D',
    'Eb',
    'E',
    'F',
    'Gb',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ];
  final midi = midiFromFrequency(frequency).round().clamp(0, 127);
  final octave = (midi / 12).floor() - 1;
  final sharp = sharps[midi % 12];
  final flat = flats[midi % 12];
  final label = sharp == flat ? sharp : '$sharp/$flat';
  return '$label$octave';
}
