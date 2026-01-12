import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'screens/login_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/recordings_screen.dart';
import 'models/recording.dart';
import 'services/headset_service.dart';
import 'services/user_prefs.dart';
import 'services/recording_store.dart';
import 'dsp/pitch_detection.dart';
import 'state/pitch_notifier.dart';
import 'widgets/control_bar.dart';
import 'widgets/pitch_controls.dart';
import 'widgets/tuner_display.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const PitchApp());
}

class PitchApp extends StatefulWidget {
  const PitchApp({super.key});

  @override
  State<PitchApp> createState() => _PitchAppState();
}

class _PitchAppState extends State<PitchApp> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

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
        routes: {
          '/tuner': (_) => const PitchHomePage(),
        },
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  String? _lastSavedEmail;
  String? _lastSavedName;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data ?? FirebaseAuth.instance.currentUser;
        if (snapshot.connectionState == ConnectionState.waiting &&
            user == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (user != null) {
          final email = user.email;
          if (email != null && email != _lastSavedEmail) {
            _lastSavedEmail = email;
            UserPrefs.saveEmail(email);
          }
          final name = user.displayName;
          if (name != null && name != _lastSavedName) {
            _lastSavedName = name;
            UserPrefs.saveName(name);
          }
          return const MenuScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

class PitchHomePage extends StatefulWidget {
  const PitchHomePage({super.key});

  @override
  State<PitchHomePage> createState() => _PitchHomePageState();
}

class _PitchHomePageState extends State<PitchHomePage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    final state = context.read<PitchNotifier>();
    if (state.tanpuraPlaying) {
      state.toggleTanpura();
    }
    super.dispose();
  }

  Future<void> _showTanpuraWarning() async {
    if (!mounted) return;
    if (await HeadsetService.isHeadsetConnected()) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Warning'),
          content: const Text(
            'Tanpura playback can affect pitch detection. '
            'Use headphones for accurate plotting.',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PitchNotifier>();
    final frequency = state.frequency;
    final note = frequency == null
        ? '--'
        : _noteLabel(frequency, state.tuningSystem);
    final noteLabels = _noteLabelsForSystem(state.tuningSystem);
    final labelStyle = _labelStyleForSystem(state.tuningSystem);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Live Recording'),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Align(
                  alignment: Alignment.topRight,
                  child: _NoteBadge(note: note),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                children: [
                  Expanded(
                    child: TunerDisplay(
                      history: state.history,
                      noteLabels: noteLabels,
                      labelTextStyle: labelStyle,
                    ),
                  ),
                  const SizedBox(height: 6),
              ControlBar(
                listening: state.listening,
                recording: state.recording,
                errorMessage: state.errorMessage,
                tanpuraPlaying: state.tanpuraPlaying,
                onStart: state.start,
                onStop: state.stop,
                onOpenRecordings: () {
                  Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RecordingsScreen(),
                        ),
                      );
                    },
                    onOpenTanpura: () async {
                      if (state.tanpuraPlaying) {
                        await state.toggleTanpura();
                        return;
                      }
                      await _showTanpuraWarning();
                      if (!mounted) return;
                      await state.toggleTanpura();
                    },
                    onToggleRecording: () {
                      _handleRecording(context, state);
                    },
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
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _handleRecording(
  BuildContext context,
  PitchNotifier state,
) async {
  if (!state.recording) {
    await state.startRecording();
    return;
  }
  final draft = state.stopRecording();
  if (draft.notes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No notes captured.')),
    );
    return;
  }
  final existing = await RecordingStore.instance.load();
  final controller = TextEditingController(
    text: 'Recording ${existing.length + 1}',
  );
  final name = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Save recording'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Recording name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
  if (name == null || name.isEmpty) {
    return;
  }
  final entry = RecordingEntry(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    name: name,
    createdAt: draft.endedAt,
    notes: draft.notes,
  );
  await RecordingStore.instance.save(entry);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Recording saved.')),
  );
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

String _noteLabel(double frequency, String tuningSystem) {
  final labels = _noteLabelsForSystem(tuningSystem);
  final midi = midiFromFrequency(frequency).round().clamp(0, 127);
  final octave = (midi / 12).floor() - 1;
  final label = labels[midi % 12];
  return '$label$octave';
}

const _westernNoteLabels = [
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

const _carnaticNoteLabels = [
  'Sa-',
  'Ri1-',
  'Ri2-',
  'Ga1-',
  'Ga2-',
  'Ma1-',
  'Ma2-',
  'Pa-',
  'Da1-',
  'Da2-',
  'Ni1-',
  'Ni2-',
];

List<String> _noteLabelsForSystem(String tuningSystem) {
  return tuningSystem == 'carnatic'
      ? _carnaticNoteLabels
      : _westernNoteLabels;
}

TextStyle? _labelStyleForSystem(String tuningSystem) {
  if (tuningSystem != 'carnatic') {
    return null;
  }
  return const TextStyle(
    fontFamily: 'RobotoMono',
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
}
