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
    final cents = frequency == null ? 0.0 : _centsOffset(frequency);
    final note = frequency == null ? '--' : _noteLabel(frequency);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _TunerHeader(note: note, cents: cents),
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

class _TunerHeader extends StatelessWidget {
  const _TunerHeader({required this.note, required this.cents});

  final String note;
  final double cents;

  @override
  Widget build(BuildContext context) {
    final sliderWidth = min(
      MediaQuery.of(context).size.width - 48,
      340,
    ).toDouble();
    return Column(
      children: [
        Container(
          width: 180,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Align(alignment: Alignment.center, child: _AmberDot()),
        ),
        const SizedBox(height: 12),
        Container(
          width: sliderWidth,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2C3136),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('-50C', style: TextStyle(color: Colors.white70)),
                  Text(note, style: const TextStyle(fontSize: 18)),
                  const Text('+50C', style: TextStyle(color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 8),
              _CentsSlider(cents: cents),
            ],
          ),
        ),
      ],
    );
  }
}

class _AmberDot extends StatelessWidget {
  const _AmberDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Color(0xFFF08A00),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _CentsSlider extends StatelessWidget {
  const _CentsSlider({required this.cents});

  final double cents;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final clamped = cents.clamp(-50.0, 50.0);
        final pos = (clamped + 50) / 100 * trackWidth;
        return SizedBox(
          height: 18,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Positioned(
                left: pos - 10,
                child: Container(
                  width: 20,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: const Color(0xFFF08A00),
                child: const Text(
                  'Upgrade',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
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
