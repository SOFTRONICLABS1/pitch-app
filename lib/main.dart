import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'dsp/pitch_detection.dart';
import 'state/pitch_notifier.dart';
import 'screens/login_screen.dart';
import 'screens/recordings_screen.dart';
import 'widgets/control_bar.dart';
import 'widgets/pitch_controls.dart';
import 'widgets/tuner_display.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
        home: const LoginScreen(),
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
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Tuner'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _NoteBadge(note: note),
            const SizedBox(height: 12),
            Expanded(
              child: TunerDisplay(history: state.history),
            ),
            const SizedBox(height: 6),
            ControlBar(
              listening: state.listening,
              errorMessage: state.errorMessage,
              onStart: state.start,
              onStop: state.stop,
              onOpenRecordings: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RecordingsScreen(),
                  ),
                );
              },
              onOpenTanpura: state.toggleTanpura,
              onOpenSettings: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.black,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  builder: (_) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
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
