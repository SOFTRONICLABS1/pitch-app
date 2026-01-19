import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/melakarta_ragas.dart';
import '../dsp/pitch_detection.dart';
import '../models/recording.dart';
import '../services/recording_store.dart';
import '../state/pitch_notifier.dart';
import '../services/headset_service.dart';
import '../screens/recordings_screen.dart';
import '../widgets/control_bar.dart';
import '../widgets/pitch_controls.dart';
import '../widgets/tuner_display.dart';

class VocalTrackerScreen extends StatefulWidget {
  const VocalTrackerScreen({
    super.key,
    required this.recording,
    this.readOnly = false,
    this.allowEdit = true,
    this.allowSettings = true,
    this.initialBpm,
    this.initialTanpuraEnabled = false,
    this.initialCarnaticRootSemitone = 0,
    this.initialRagaName,
  });

  final RecordingEntry recording;
  final bool readOnly;
  final bool allowEdit;
  final bool allowSettings;
  final int? initialBpm;
  final bool initialTanpuraEnabled;
  final int initialCarnaticRootSemitone;
  final String? initialRagaName;

  @override
  State<VocalTrackerScreen> createState() => _VocalTrackerScreenState();
}

class _VocalTrackerScreenState extends State<VocalTrackerScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _stopwatch = Stopwatch();
  Duration _elapsed = Duration.zero;
  bool _running = false;
  late List<_TargetBlock> _targets;
  late int _totalDurationMs;
  late RecordingEntry _recording;
  final ScrollController _editScrollController = ScrollController();
  final ScrollController _editVerticalController = ScrollController();
  final TunerDisplayController _tunerController = TunerDisplayController();
  final GlobalKey<_EditableTargetOverlayState> _editOverlayKey =
      GlobalKey<_EditableTargetOverlayState>();
  int _bpm = 60;
  int _baseOctave = PitchNotifier.defaultBaseOctave;
  int _rootSemitone = 0;
  String _ragaName = 'Mayamalavagowla';
  PitchNotifier? _pitchNotifier;
  DateTime? _frozenAt;
  int _viewportBaseMidi = 33;
  double _viewportOffset = 0.0;
  static const _viewportRowCount = 48;
  bool _harmonicsEnabled = false;
  bool _editMode = false;
  List<RecordedNote>? _editNotes;
  bool _editDirty = false;
  bool _tanpuraEnabled = false;
  final AudioPlayer _harmonicsPlayer = AudioPlayer();
  static const double _harmonicsVolume = 2.0;
  Timer? _harmonicsStopTimer;
  int? _currentHarmonicsKey;
  double _lastTargetElapsedMs = 0.0;
  Duration _targetElapsedOffset = Duration.zero;
  double? _screenWidth;
  double? _initialBaseMidi;
  static const _guidelineFraction = 0.8;
  static const _editGuidelineFraction = 0.9;
  static const _guidelineOffset = 0.0;
  static const _tunerLabelWidth = 72.0;
  String _lastNoteEntryInput = '';
  DateTime? _harmonicsWindowStart;
  DateTime? _harmonicsWindowEnd;
  int? _harmonicsMidi;
  List<PitchPoint>? _historySnapshot;
  List<PitchPoint>? _filteredHistoryCache;
  int _filteredHistorySourceLength = 0;
  int _filteredHistoryLastMs = -1;
  int? _filteredHistoryStartMs;
  int? _filteredHistoryEndMs;
  int? _filteredHistoryMidi;

  int _rowCountForSystem(String tuningSystem) {
    return _useExpandedRows(tuningSystem, _ragaName)
        ? (_viewportRowCount ~/ 12) * 16
        : _viewportRowCount;
  }

  @override
  void initState() {
    super.initState();
    _recording = widget.recording;
    _pitchNotifier = context.read<PitchNotifier>();
    _baseOctave = _pitchNotifier?.baseOctave ?? PitchNotifier.defaultBaseOctave;
    _rootSemitone = widget.initialCarnaticRootSemitone.clamp(0, 11);
    if (widget.initialRagaName != null &&
        widget.initialRagaName!.trim().isNotEmpty) {
      _ragaName = widget.initialRagaName!.trim();
    }
    _pitchNotifier?.addListener(_handleBaseOctaveChange);
    final result = _targetBlocksFromRecording(
      _recording,
      baseOctave: _baseOctave,
      tuningSystem: _pitchNotifier?.tuningSystem ?? 'western',
      rootSemitone: _rootSemitone,
    );
    _targets = result.blocks;
    _totalDurationMs = result.totalDurationMs;
    if (widget.initialBpm != null) {
      _bpm = widget.initialBpm!;
    }
    _tanpuraEnabled = widget.initialTanpuraEnabled;
    if (_targets.isNotEmpty) {
      _initialBaseMidi = _computeInitialBaseMidi(_targets.first.midi);
    }
    _ticker = createTicker(_onTick);
    _running = false;
    _elapsed = Duration.zero;
    _stopwatch.reset();
    _frozenAt = DateTime.now();
    _harmonicsPlayer.setReleaseMode(ReleaseMode.stop);
    _preloadHarmonics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pitchState = context.read<PitchNotifier>();
      if (_historySnapshot == null && pitchState.history.isNotEmpty) {
        _historySnapshot = List<PitchPoint>.from(pitchState.history);
        pitchState.replaceHistory(const []);
      }
      pitchState.stop();
    });
  }

  void _handleBaseOctaveChange() {
    final next = _pitchNotifier?.baseOctave ?? PitchNotifier.defaultBaseOctave;
    if (next == _baseOctave) return;
    setState(() {
      _baseOctave = next;
      final result = _targetBlocksFromRecording(
        _recording,
        baseOctave: _baseOctave,
        tuningSystem: _pitchNotifier?.tuningSystem ?? 'western',
        rootSemitone: _rootSemitone,
      );
      _targets = result.blocks;
      _totalDurationMs = result.totalDurationMs;
      _lastTargetElapsedMs = 0.0;
      _currentHarmonicsKey = null;
      _targetElapsedOffset = _elapsed;
      if (_targets.isNotEmpty) {
        _initialBaseMidi = _computeInitialBaseMidi(_targets.first.midi);
      }
    });
  }

  Future<void> _showHarmonicsWarning() async {
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
            'Harmonics playback can affect pitch detection. '
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
  void dispose() {
    _harmonicsStopTimer?.cancel();
    _stopHarmonics();
    _pitchNotifier?.removeListener(_handleBaseOctaveChange);
    try {
      final pitchState = context.read<PitchNotifier>();
      _stopTanpuraIfNeeded(pitchState);
      pitchState.stop();
      if (_historySnapshot != null) {
        pitchState.replaceHistory(_historySnapshot!);
        _historySnapshot = null;
      }
    } catch (_) {}
    _harmonicsPlayer.dispose();
    _editScrollController.dispose();
    _editVerticalController.dispose();
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (!_running) return;
    setState(() {
      _elapsed = _stopwatch.elapsed;
    });
    final targetElapsed = _effectiveTargetElapsed();
    _updateHarmonics(targetElapsed);
    _ensureTargetVisible(targetElapsed);
    _lastTargetElapsedMs = targetElapsed.inMilliseconds.toDouble();
  }

  Future<void> _handleStart(PitchNotifier state) async {
    if (_running) return;
    _historySnapshot ??= List<PitchPoint>.from(state.history);
    await state.start();
    if (!mounted || !state.listening) return;
    if (_tanpuraEnabled) {
      _harmonicsEnabled = false;
      _stopHarmonics();
    } else if (!_harmonicsEnabled) {
      await _showHarmonicsWarning();
      if (!mounted) return;
      _harmonicsEnabled = true;
    }
    _stopwatch
      ..reset()
      ..start();
    setState(() {
      _elapsed = Duration.zero;
      _running = true;
      _frozenAt = null;
      _currentHarmonicsKey = null;
      _lastTargetElapsedMs = 0.0;
      _targetElapsedOffset = Duration.zero;
    });
    _ticker.start();
    await _ensureTanpuraState(state);
  }

  Future<void> _handleStop(PitchNotifier state) async {
    await state.stop();
    _stopwatch.stop();
    _ticker.stop();
    _stopHarmonics();
    await _stopTanpuraIfNeeded(state);
    if (_historySnapshot != null) {
      state.replaceHistory(_historySnapshot!);
      _historySnapshot = null;
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _frozenAt = DateTime.now();
      _lastTargetElapsedMs = 0.0;
      _targetElapsedOffset = Duration.zero;
      _harmonicsEnabled = false;
    });
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

  Future<void> _ensureTanpuraState(PitchNotifier state) async {
    if (_tanpuraEnabled && !state.tanpuraPlaying) {
      await state.toggleTanpura();
    }
  }

  Future<void> _stopTanpuraIfNeeded(PitchNotifier state) async {
    if (state.tanpuraPlaying) {
      await state.toggleTanpura();
    }
  }

  Future<void> _openEditRecording() async {
    if (_editMode || !widget.allowEdit) return;
    if (_running) {
      await _handleStop(context.read<PitchNotifier>());
    }
    setState(() {
      _editMode = true;
      _editNotes = List<RecordedNote>.from(_recording.notes);
      _editDirty = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editOverlayKey.currentState?.prepareInitialFocus();
    });
  }

  Future<void> _saveEditMode() async {
    if (!_editMode) return;
    final notes = _editNotes;
    if (notes != null && _editDirty) {
    final updated = RecordingEntry(
      id: _recording.id,
      name: _recording.name,
      createdAt: _recording.createdAt,
      notes: notes,
      group: _recording.group,
    );
      await RecordingStore.instance.update(updated);
      _applyRecordingUpdate(updated);
    }
    setState(() {
      _editMode = false;
      _editNotes = null;
      _editDirty = false;
    });
  }

  Future<void> _cancelEditMode() async {
    if (!_editMode) return;
    if (_editDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text(
              'You have unsaved changes. Discard them?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Discard'),
              ),
            ],
          );
        },
      );
      if (discard != true) {
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _editMode = false;
      _editNotes = null;
      _editDirty = false;
    });
  }

  Future<void> _openNoteEntry() async {
    if (!_editMode) return;
    final existingNotes = _editNotes ?? _recording.notes;
    final tuningSystem = context.read<PitchNotifier>().tuningSystem;
    final seed = existingNotes.isEmpty
        ? _lastNoteEntryInput
        : _serializeNotesForEntry(
            existingNotes,
            bpm: _bpm,
            baseOctave: _baseOctave,
            tuningSystem: tuningSystem,
          );
    final controller = TextEditingController(text: seed);
    final input = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter notes'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Insert'),
            ),
          ],
        );
      },
    );
    if (input == null || input.isEmpty) {
      return;
    }
    _lastNoteEntryInput = input;
    final result = _parseNoteEntry(
      input,
      bpm: _bpm,
      baseOctave: _baseOctave,
      tuningSystem: tuningSystem,
    );
    if (result.notes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'No valid notes found.'),
        ),
      );
      return;
    }
    setState(() {
      _editNotes = List<RecordedNote>.from(result.notes);
      _editDirty = true;
    });
    _editOverlayKey.currentState?.queueInsertAtEnd();
  }

  void _clearAllEditNotes() {
    if (!_editMode) return;
    setState(() {
      _editNotes = [];
      _editDirty = true;
    });
    _editOverlayKey.currentState?.clearPendingInsert();
  }

  void _queueInsertAtEnd() {
    _editOverlayKey.currentState?.queueInsertAtEnd();
  }

  Future<void> _deleteTargetAt(int index) async {
    final notes = _editNotes;
    if (notes == null || index < 0 || index >= notes.length) {
      return;
    }
    final updatedNotes = List<RecordedNote>.from(notes)..removeAt(index);
    setState(() {
      _editNotes = updatedNotes;
      _editDirty = true;
    });
  }

  static const _minDurationMs = 200;
  static const _defaultInsertDurationMs = 1000;

  void _quantizeEditNotesToBpm(int bpm) {
    final notes = _editNotes;
    if (!_editMode || notes == null || notes.isEmpty) {
      return;
    }
    final beatMs = (60000 / max(1, bpm)).round();
    var changed = false;
    final updated = <RecordedNote>[];
    for (final note in notes) {
      var nextDuration = note.durationMs;
      final remainder = nextDuration % beatMs;
      if (remainder != 0) {
        if (remainder >= (beatMs * 0.1)) {
          nextDuration = nextDuration + (beatMs - remainder);
        } else {
          nextDuration = nextDuration - remainder;
        }
        nextDuration = max(_minDurationMs, nextDuration);
      }
      if (nextDuration != note.durationMs) {
        changed = true;
      }
      updated.add(
        RecordedNote(
          note: note.note,
          durationMs: nextDuration,
        ),
      );
    }
    if (!changed) {
      return;
    }
    setState(() {
      _editNotes = updated;
      _editDirty = true;
    });
  }

  Future<void> _insertTargetsAt(
    int insertIndex,
    List<String> selectedNotes,
  ) async {
    if (selectedNotes.isEmpty) return;
    final tuningSystem = context.read<PitchNotifier>().tuningSystem;
    final notes = List<RecordedNote>.from(_editNotes ?? _recording.notes);
    final defaultDurationMs = (60000 / max(1, _bpm)).round();
    final normalizedNotes = selectedNotes
        .map((note) => _normalizeNoteForStorage(note, tuningSystem))
        .where((note) => note.isNotEmpty)
        .toList();
    if (normalizedNotes.isEmpty) return;
    final clampedIndex = insertIndex.clamp(0, notes.length);
    notes.insertAll(
      clampedIndex,
      [
        for (final note in normalizedNotes)
          RecordedNote(
            note: note,
            durationMs: defaultDurationMs,
          ),
      ],
    );
    setState(() {
      _editNotes = notes;
      _editDirty = true;
    });
  }

  void _updateTargetNoteAt(int index, String label) {
    final notes = _editNotes;
    if (notes == null || index < 0 || index >= notes.length) {
      return;
    }
    final tuningSystem = context.read<PitchNotifier>().tuningSystem;
    final normalized = _normalizeNoteForStorage(label, tuningSystem);
    if (normalized.isEmpty) {
      return;
    }
    final updatedNotes = List<RecordedNote>.from(notes);
    final current = updatedNotes[index];
    updatedNotes[index] = RecordedNote(
      note: normalized,
      durationMs: current.durationMs,
    );
    setState(() {
      _editNotes = updatedNotes;
      _editDirty = true;
    });
  }

  Future<void> _adjustTargetDuration(
    int index,
    int deltaMs, {
    required bool commit,
  }) async {
    final notes = _editNotes;
    if (notes == null || index < 0 || index >= notes.length) {
      return;
    }
    final updatedNotes = List<RecordedNote>.from(notes);
    final current = updatedNotes[index];
    var nextDuration =
        max(_minDurationMs, current.durationMs + deltaMs).toInt();
    if (commit) {
      final beatMs = (60000 / max(1, _bpm)).round();
      final remainder = nextDuration % beatMs;
      if (remainder != 0) {
        if (remainder >= (beatMs * 0.1)) {
          nextDuration = nextDuration + (beatMs - remainder);
        } else {
          nextDuration = nextDuration - remainder;
        }
      }
    }
    if (nextDuration == current.durationMs) {
      return;
    }
    updatedNotes[index] = RecordedNote(
      note: current.note,
      durationMs: nextDuration,
    );
    setState(() {
      _editNotes = updatedNotes;
      _editDirty = true;
    });
  }

  void _applyRecordingUpdate(
    RecordingEntry updated, {
    bool preload = true,
  }) {
    final result = _targetBlocksFromRecording(
      updated,
      baseOctave: _baseOctave,
      tuningSystem: _pitchNotifier?.tuningSystem ?? 'western',
      rootSemitone: _rootSemitone,
    );
    if (preload) {
      _stopHarmonics();
    }
    setState(() {
      _recording = updated;
      _targets = result.blocks;
      _totalDurationMs = result.totalDurationMs;
      _currentHarmonicsKey = null;
    });
    if (preload) {
      _preloadHarmonics();
    }
  }

  Future<void> _toggleTanpura(PitchNotifier state) async {
    final nextEnabled = !_tanpuraEnabled;
    setState(() {
      _tanpuraEnabled = nextEnabled;
      _lastTargetElapsedMs = 0.0;
      _targetElapsedOffset = _elapsed;
      _currentHarmonicsKey = null;
    });
    if (_tanpuraEnabled) {
      _harmonicsEnabled = false;
      _stopHarmonics();
      if (!state.tanpuraPlaying) {
        await _showTanpuraWarning();
        if (!mounted) return;
        await state.toggleTanpura();
      }
    } else {
      if (state.tanpuraPlaying) {
        await state.toggleTanpura();
      }
      if (_running && !_harmonicsEnabled) {
        await _showHarmonicsWarning();
        if (!mounted) return;
        _harmonicsEnabled = true;
      }
    }
  }

  Future<void> _handleRecording(PitchNotifier state) async {
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
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
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
      group: null,
    );
    await RecordingStore.instance.save(entry);
    await _handleStop(state);
    _applyRecordingUpdate(entry);
  }

  void _ensureTargetVisible(Duration targetElapsed) {
    if (_editMode || _targets.isEmpty) {
      return;
    }
    final index = _currentTargetIndex(targetElapsed);
    if (index == null) {
      return;
    }
    final midi = _targets[index].midi;
    final bottom = _viewportBaseMidi;
    final rowCount =
        _rowCountForSystem(_pitchNotifier?.tuningSystem ?? 'western');
    final top = _viewportBaseMidi + rowCount - 1;
    final tuningSystem = _pitchNotifier?.tuningSystem ?? 'western';
    final useExpanded = _useExpandedRows(tuningSystem, _ragaName);
    final targetRow = useExpanded
        ? _expandedRowIndexForMidi(midi, tuningSystem, _ragaName)
        : midi;
    if (targetRow < bottom || targetRow > top) {
      _tunerController.scrollToMidi(midi, alignment: 0.7);
    }
  }

  int? _currentTargetIndex(Duration targetElapsed) {
    if (_targets.isEmpty || _totalDurationMs <= 0) {
      return null;
    }
    final scale = 60.0 / max(1, _bpm).toDouble();
    final loopMs = max(1, _totalDurationMs).toDouble() * scale;
    final elapsedMs = targetElapsed.inMilliseconds.toDouble();
    final cycleOffset = (elapsedMs / loopMs).floor() * loopMs;
    final position = elapsedMs - cycleOffset;
    for (var i = 0; i < _targets.length; i++) {
      final start = _targets[i].startOffsetMs * scale;
      final end = start + _targets[i].durationMs * scale;
      if (position >= start && position <= end) {
        return i;
      }
    }
    return null;
  }

  double _computeInitialBaseMidi(int targetMidi) {
    const alignment = 0.9;
    const minMidi = 21.0;
    const maxMidi = 108.0;
    final tuningSystem = _pitchNotifier?.tuningSystem ?? 'western';
    final rowCount = _rowCountForSystem(tuningSystem);
    final useExpanded = _useExpandedRows(tuningSystem, _ragaName);
    final targetRow = useExpanded
        ? _expandedRowIndexForMidi(targetMidi, tuningSystem, _ragaName)
        : targetMidi;
    final minRow = useExpanded
        ? _expandedRowIndexForMidi(minMidi.toInt(), tuningSystem, _ragaName)
        : minMidi;
    final maxRow = useExpanded
        ? _expandedRowIndexForMidi(maxMidi.toInt(), tuningSystem, _ragaName)
        : maxMidi;
    final maxBase = maxRow - rowCount + 1;
    final baseMidi =
        targetRow + ((alignment - 1) * rowCount + 0.5);
    return baseMidi.clamp(minRow, maxBase).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PitchNotifier>();
    final frequency = state.frequency;
    final note = frequency == null
        ? '--'
        : _noteLabel(
            frequency,
            state.tuningSystem,
            rootSemitone: _rootSemitone,
            ragaName: _ragaName,
          );
    final rootSemitoneForView =
        state.tuningSystem == 'carnatic' ? _rootSemitone : 0;
    final noteLabels = _noteLabelsForSystem(
      state.tuningSystem,
      rootSemitone: rootSemitoneForView,
      ragaName: _ragaName,
    );
    final labelStyle = _labelStyleForSystem(state.tuningSystem);
    final useExpandedRows =
        _useExpandedRows(state.tuningSystem, _ragaName);
    final rowCount = _rowCountForSystem(state.tuningSystem);
    final minRowIndex = useExpandedRows
        ? _expandedRowIndexForMidi(21, state.tuningSystem, _ragaName)
        : null;
    final maxRowIndex = useExpandedRows
        ? _expandedRowIndexForMidi(108, state.tuningSystem, _ragaName)
        : null;
    String labelForRowIndex(int rowIndex) {
      return _expandedLabelForIndex(rowIndex);
    }
    _screenWidth = MediaQuery.of(context).size.width;

    return WillPopScope(
      onWillPop: () async {
        if (_editMode) {
          await _cancelEditMode();
          return false;
        }
        await _handleStop(state);
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () async {
              if (_editMode) {
                await _cancelEditMode();
                return;
              }
              await _handleStop(state);
              if (!mounted) return;
              Navigator.of(context).pop();
            },
          ),
          title: Text(_recording.name),
          actions: [
            if (_editMode && (_editNotes?.isEmpty ?? true))
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _queueInsertAtEnd,
              ),
            if (_editMode)
              IconButton(
                icon: const Icon(Icons.keyboard_outlined),
                onPressed: _openNoteEntry,
              ),
            if (_editMode)
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: _clearAllEditNotes,
              ),
            if (widget.allowSettings)
              IconButton(
                icon: const Icon(Icons.tune),
                onPressed: _showBpmSettings,
              ),
          ],
        ),
        body: SafeArea(
          child: _editMode
              ? Column(
                  children: [
                    Expanded(
                      child: _EditableTargetOverlay(
                        key: _editOverlayKey,
                        notes: _editNotes ?? _recording.notes,
                        tuningSystem: state.tuningSystem,
                        baseMidi: 21,
                        rowCount: rowCount,
                        baseOffset: 0.0,
                        labelWidth: _tunerLabelWidth,
                        rootSemitone: rootSemitoneForView,
                        ragaName: _ragaName,
                        guidelineFraction: 2.0,
                        guidelineOffset: _guidelineOffset,
                        scrollController: _editScrollController,
                        verticalController: _editVerticalController,
                        onDelete: _deleteTargetAt,
                        onDurationDrag: (index, deltaMs, commit) {
                          _adjustTargetDuration(
                            index,
                            deltaMs,
                            commit: commit,
                          );
                        },
                        onInsertNotes: _insertTargetsAt,
                        onNoteChanged: _updateTargetNoteAt,
                        bpm: _bpm,
                        baseOctave: _baseOctave,
                      ),
                    ),
                    _PlayPauseBar(
                      listening: state.listening,
                      errorMessage: state.errorMessage,
                      onStart: () => _handleStart(state),
                      onStop: () => _handleStop(state),
                      onEdit: _openEditRecording,
                      editMode: true,
                      tanpuraEnabled: _tanpuraEnabled,
                      onTanpuraToggle: () => _toggleTanpura(state),
                      onConfirmEdit: () => _saveEditMode(),
                      onCancelEdit: () => _cancelEditMode(),
                      showEdit: widget.allowEdit,
                    ),
                  ],
                )
              : CustomScrollView(
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
                      hasScrollBody: true,
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                TunerDisplay(
                                  history: _filteredHistory(state.history),
                                  showBlocks: false,
                                  showLabels: true,
                                  enableManualScroll: true,
                                  initialBaseMidi: _initialBaseMidi,
                                  controller: _tunerController,
                                  nowOverride: _running ? null : _frozenAt,
                                  noteLabels: noteLabels,
                                  labelTextStyle: labelStyle,
                                  rowCount: rowCount,
                                  minRowIndex: minRowIndex,
                                  maxRowIndex: maxRowIndex,
                                  rowIndexForMidi: useExpandedRows
                                      ? (midi) => _expandedRowIndexForMidi(
                                            midi,
                                            state.tuningSystem,
                                            _ragaName,
                                          )
                                      : null,
                                  midiForRowIndex:
                                      useExpandedRows ? _midiForExpandedIndex : null,
                                  labelForRowIndex:
                                      useExpandedRows ? labelForRowIndex : null,
                                  guidelineFraction: _guidelineFraction,
                                  guidelineOffset: _guidelineOffset,
                                  rootSemitone: rootSemitoneForView,
                                  onViewportChanged: (base, offset) {
                                    if (!mounted) return;
                                    setState(() {
                                      _viewportBaseMidi = base;
                                      _viewportOffset = offset;
                                    });
                                  },
                                ),
                                _TargetNoteTrack(
                                  targets: _targets,
                                  elapsed: _effectiveTargetElapsed(),
                                  totalDurationMs: _totalDurationMs,
                                  running: _running,
                                  bpm: _bpm,
                                  baseMidi: _viewportBaseMidi,
                                  rowCount: rowCount,
                                  baseOffset: _viewportOffset,
                                  tuningSystem: state.tuningSystem,
                                  rootSemitone: rootSemitoneForView,
                                  ragaName: _ragaName,
                                  guidelineFraction: _guidelineFraction,
                                  guidelineOffset: _guidelineOffset,
                                ),
                              ],
                            ),
                          ),
                          if (!widget.allowEdit)
                            _PlayPauseBar(
                              listening: state.listening,
                              errorMessage: state.errorMessage,
                              onStart: () => _handleStart(state),
                              onStop: () => _handleStop(state),
                              onEdit: _openEditRecording,
                              editMode: false,
                              tanpuraEnabled: _tanpuraEnabled,
                              onTanpuraToggle: () => _toggleTanpura(state),
                              onConfirmEdit: () => _saveEditMode(),
                              onCancelEdit: () => _cancelEditMode(),
                              showEdit: false,
                            ),
                          if (widget.allowEdit)
                            ControlBar(
                              listening: state.listening,
                              recording: state.recording,
                              errorMessage: state.errorMessage,
                              tanpuraPlaying: state.tanpuraPlaying,
                              onStart: () => _handleStart(state),
                              onStop: () => _handleStop(state),
                              onOpenRecordings: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const RecordingsScreen(),
                                  ),
                                );
                              },
                              onOpenTanpura: () => _toggleTanpura(state),
                              onToggleRecording: () => _handleRecording(state),
                              onEdit: _openEditRecording,
                            ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _showBpmSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2F353A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        final pitchState = context.watch<PitchNotifier>();
        var current = _bpm;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedNote =
                _carnaticNoteFor(pitchState.tanpuraNote) ?? 'Sa';
            final selectedString =
                _carnaticStringFor(pitchState.tanpuraString) ?? 'Sa';
            final maxHeight = MediaQuery.of(context).size.height * 0.8;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'western', label: Text('Western')),
                        ButtonSegment(value: 'carnatic', label: Text('Carnatic')),
                      ],
                      selected: {pitchState.tuningSystem},
                      onSelectionChanged: (value) {
                        if (value.isEmpty) return;
                        pitchState.setTuningSystem(value.first);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                    'BPM',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$current',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: current > _bpmOptions.first
                            ? () {
                                final nextIndex = _bpmIndex(current) - 1;
                                final next = _bpmFromIndex(nextIndex);
                                setSheetState(() {
                                  current = next;
                                });
                                setState(() {
                                  _bpm = next;
                                  _currentHarmonicsKey = null;
                                });
                              }
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: current < _bpmOptions.last
                            ? () {
                                final nextIndex = _bpmIndex(current) + 1;
                                final next = _bpmFromIndex(nextIndex);
                                setSheetState(() {
                                  current = next;
                                });
                                setState(() {
                                  _bpm = next;
                                  _currentHarmonicsKey = null;
                                });
                              }
                            : null,
                      ),
                    ],
                  ),
                  Slider(
                    value: _bpmIndex(current).toDouble(),
                    min: 0,
                    max: (_bpmOptions.length - 1).toDouble(),
                    divisions: _bpmOptions.length - 1,
                    label: '$current',
                    onChanged: (value) {
                      final next = _bpmFromIndex(value.round());
                      setSheetState(() {
                        current = next;
                      });
                      setState(() {
                        _bpm = next;
                        _currentHarmonicsKey = null;
                      });
                    },
                  ),
                  const SizedBox(height: 4),
                  _BpmTickLabels(
                    positions: const {
                      20: 0,
                      40: 2,
                      60: 4,
                      120: 10,
                      240: 22,
                    },
                    maxIndex: _bpmOptions.length - 1,
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Clarity threshold (${pitchState.clarityThreshold.toStringAsFixed(2)})',
                    ),
                  ),
                  Slider(
                    value: pitchState.clarityThreshold,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (value) {
                      pitchState.setClarityThreshold(value);
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tanpura',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Switch(
                        value: _tanpuraEnabled,
                        onChanged: (value) async {
                          setState(() {
                            _tanpuraEnabled = value;
                            _lastTargetElapsedMs = 0.0;
                            _targetElapsedOffset = _elapsed;
                            _currentHarmonicsKey = null;
                          });
                          setSheetState(() {});
                          if (_tanpuraEnabled) {
                            _harmonicsEnabled = false;
                            _stopHarmonics();
                            if (_running) {
                              await _ensureTanpuraState(pitchState);
                            }
                          } else {
                            await _stopTanpuraIfNeeded(pitchState);
                            if (_running && !_harmonicsEnabled) {
                              await _showHarmonicsWarning();
                              if (!mounted) return;
                              _harmonicsEnabled = true;
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_tanpuraEnabled) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'First string',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(color: Colors.white70),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                value: selectedString,
                                decoration: const InputDecoration(
                                  filled: true,
                                  fillColor: Color(0xFF23272B),
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  for (final option in _tanpuraStringOptions)
                                    DropdownMenuItem(
                                      value: option.$2,
                                      child: Text('${option.$1} - ${option.$2}'),
                                    ),
                                ],
                                onChanged: (value) async {
                                  if (value == null) return;
                                  await pitchState.setTanpuraString(value);
                                  setSheetState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Note',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(color: Colors.white70),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                value: selectedNote,
                                decoration: const InputDecoration(
                                  filled: true,
                                  fillColor: Color(0xFF23272B),
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  for (final option in _tanpuraNoteOptions)
                                    DropdownMenuItem(
                                      value: option.$2,
                                      child: Text('${option.$1} - ${option.$2}'),
                                    ),
                                ],
                                onChanged: (value) async {
                                  if (value == null) return;
                                  await pitchState.setTanpuraNote(value);
                                  setSheetState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tanpura volume (${(pitchState.tanpuraVolume * 100).round()}%)',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: Colors.white70),
                      ),
                    ),
                    Slider(
                      value: pitchState.tanpuraVolume,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (value) {
                        pitchState.setTanpuraVolume(value);
                        setSheetState(() {});
                      },
                    ),
                  ],
                  ],
                ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _preloadHarmonics() async {
    final assets = <String>[];
    for (final block in _targets) {
      final path = _harmonicsAssetForMidi(block.midi);
      if (path != null) {
        assets.add(path);
      }
    }
    final unique = assets.toSet().toList();
    for (final path in unique) {
      try {
        await rootBundle.load(path);
      } catch (_) {
        // Ignore missing assets; playback will also skip.
      }
    }
  }

  Duration _effectiveTargetElapsed() {
    final diff = _elapsed - _targetElapsedOffset;
    return diff.isNegative ? Duration.zero : diff;
  }

  void _updateHarmonics(Duration targetElapsed) {
    if (_tanpuraEnabled || !_harmonicsEnabled || !_running || _targets.isEmpty) {
      _stopHarmonics();
      return;
    }
    if (_totalDurationMs <= 0) {
      _stopHarmonics();
      return;
    }
    final elapsedMs = targetElapsed.inMilliseconds.toDouble();
    var previousElapsedMs = _lastTargetElapsedMs;
    if (previousElapsedMs > elapsedMs) {
      previousElapsedMs = elapsedMs;
    }
    if (elapsedMs <= previousElapsedMs) {
      return;
    }
    final scale = 60.0 / max(1, _bpm).toDouble();
    final loopMs = max(1, _totalDurationMs).toDouble() * scale;
    final minCycle = (previousElapsedMs / loopMs).floor();
    final maxCycle = (elapsedMs / loopMs).floor();

    int? index;
    int? cycleIndex;
    double? durationMs;
    double? bestStart;
    double? bestEnd;
    const gapMs = 7.0;
    for (var k = minCycle; k <= maxCycle; k++) {
      final cycleOffset = k * loopMs;
      for (var i = 0; i < _targets.length; i++) {
        final start = _targets[i].startOffsetMs * scale + cycleOffset;
        final duration = _targets[i].durationMs * scale;
        final end = start + duration;
        final effectiveEnd = end - min(gapMs, duration * 0.5);
        final overlaps =
            effectiveEnd >= previousElapsedMs && start <= elapsedMs;
        if (!overlaps) {
          continue;
        }
        if (start <= elapsedMs &&
            (bestStart == null || start >= bestStart)) {
          bestStart = start;
          bestEnd = end;
          index = i;
          cycleIndex = k;
          durationMs = duration;
        }
      }
    }

    if (index == null || durationMs == null || cycleIndex == null) {
      return;
    }
    final effectiveDuration = max(0.0, durationMs - gapMs);
    final key = cycleIndex * 10000 + index;
    if (_currentHarmonicsKey == key) {
      final end = bestEnd ?? 0.0;
      if (end <= previousElapsedMs) {
        _currentHarmonicsKey = null;
      } else {
        return;
      }
    }
    _currentHarmonicsKey = key;
    _playHarmonicFor(_targets[index], effectiveDuration);
  }

  void _playHarmonicFor(_TargetBlock block, double durationMs) {
    final path = _harmonicsAssetForMidi(block.midi);
    if (path == null) {
      return;
    }
    _harmonicsStopTimer?.cancel();
    _harmonicsPlayer.stop();
    _harmonicsPlayer.setVolume(0.0);
    _harmonicsPlayer.play(AssetSource(path), volume: 0.0);
    Timer(const Duration(milliseconds: 30), () {
      _harmonicsPlayer.setVolume(_harmonicsVolume);
    });
    final duration = durationMs.clamp(50, 600000).toDouble();
    _harmonicsMidi = block.midi;
    _harmonicsWindowStart = DateTime.now();
    _harmonicsWindowEnd =
        _harmonicsWindowStart!.add(Duration(milliseconds: duration.round()));
    _harmonicsStopTimer = Timer(
      Duration(milliseconds: duration.round()),
      _fadeOutAndStopHarmonics,
    );
  }

  void _stopHarmonics() {
    _harmonicsStopTimer?.cancel();
    _harmonicsStopTimer = null;
    _currentHarmonicsKey = null;
    _harmonicsMidi = null;
    _harmonicsWindowStart = null;
    _harmonicsWindowEnd = null;
    _filteredHistoryCache = null;
    _fadeOutAndStopHarmonics();
  }

  void _fadeOutAndStopHarmonics() {
    _harmonicsPlayer.setVolume(0.0);
    Timer(const Duration(milliseconds: 30), () {
      _harmonicsPlayer.stop();
    });
  }

  List<PitchPoint> _filteredHistory(List<PitchPoint> history) {
    _filteredHistoryCache = null;
    return history;
  }

  String? _harmonicsAssetForMidi(int midi) {
    const names = [
      'c',
      'csharp',
      'd',
      'dsharp',
      'e',
      'f',
      'fsharp',
      'g',
      'gsharp',
      'a',
      'asharp',
      'b',
    ];
    final octave = (midi / 12).floor() - 1;
    if (octave < 0 || octave > 8) {
      return null;
    }
    final name = names[midi % 12];
    return 'harmonics/${name}${octave}.wav';
  }
}

class _BpmTickLabels extends StatelessWidget {
  const _BpmTickLabels({
    required this.positions,
    required this.maxIndex,
  });

  final Map<int, int> positions;
  final int maxIndex;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Stack(
        children: [
          for (final entry in positions.entries)
            Align(
              alignment: Alignment(
                _alignmentX(entry.value),
                0,
              ),
              child: Text('${entry.key}'),
            ),
        ],
      ),
    );
  }

  double _alignmentX(int index) {
    if (maxIndex <= 0) {
      return -1;
    }
    final fraction = index / maxIndex;
    return (fraction * 2) - 1;
  }
}

const _bpmOptions = [
  20,
  30,
  40,
  50,
  60,
  70,
  80,
  90,
  100,
  110,
  120,
  130,
  140,
  150,
  160,
  170,
  180,
  190,
  200,
  210,
  220,
  230,
  240,
  250,
  260,
  270,
  280,
  290,
  300,
  310,
  320,
];

const _tanpuraNoteOptions = [
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

const _tanpuraStringOptions = [
  ('C', 'Sa'),
  ('G', 'Pa'),
  ('F', 'Ma'),
  ('B', 'Ni'),
];

int _bpmIndex(int bpm) {
  final index = _bpmOptions.indexOf(bpm);
  if (index != -1) {
    return index;
  }
  var closestIndex = 0;
  var closestDelta = (bpm - _bpmOptions[0]).abs();
  for (var i = 1; i < _bpmOptions.length; i++) {
    final delta = (bpm - _bpmOptions[i]).abs();
    if (delta < closestDelta) {
      closestDelta = delta;
      closestIndex = i;
    }
  }
  return closestIndex;
}

int _bpmFromIndex(int index) {
  final clamped = index.clamp(0, _bpmOptions.length - 1);
  return _bpmOptions[clamped];
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

class _TargetNoteTrack extends StatelessWidget {
  const _TargetNoteTrack({
    required this.targets,
    required this.elapsed,
    required this.totalDurationMs,
    required this.running,
    required this.bpm,
    required this.baseMidi,
    required this.rowCount,
    required this.baseOffset,
    required this.tuningSystem,
    required this.rootSemitone,
    required this.ragaName,
    required this.guidelineFraction,
    required this.guidelineOffset,
  });

  final List<_TargetBlock> targets;
  final Duration elapsed;
  final int totalDurationMs;
  final bool running;
  final int bpm;
  final int baseMidi;
  final int rowCount;
  final double baseOffset;
  final String tuningSystem;
  final int rootSemitone;
  final String ragaName;
  final double guidelineFraction;
  final double guidelineOffset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _TargetNotePainter(
          targets: targets,
          elapsed: elapsed,
          totalDurationMs: totalDurationMs,
          running: running,
          bpm: bpm,
          baseMidi: baseMidi,
          rowCount: rowCount,
          baseOffset: baseOffset,
          tuningSystem: tuningSystem,
          rootSemitone: rootSemitone,
          ragaName: ragaName,
          guidelineFraction: guidelineFraction,
          guidelineOffset: guidelineOffset,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PlayPauseBar extends StatelessWidget {
  const _PlayPauseBar({
    required this.listening,
    required this.errorMessage,
    required this.onStart,
    required this.onStop,
    required this.onEdit,
    required this.editMode,
    required this.tanpuraEnabled,
    required this.onTanpuraToggle,
    required this.onConfirmEdit,
    required this.onCancelEdit,
    this.showEdit = true,
  });

  final bool listening;
  final String? errorMessage;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onEdit;
  final bool editMode;
  final bool tanpuraEnabled;
  final VoidCallback onTanpuraToggle;
  final VoidCallback onConfirmEdit;
  final VoidCallback onCancelEdit;
  final bool showEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF262B2F),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (errorMessage != null) ...[
            Text(
              errorMessage ?? '',
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!editMode)
                        IconButton(
                          icon: const Icon(
                            Icons.music_note,
                            color: Colors.white,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: tanpuraEnabled
                                ? Colors.orange
                                : Colors.transparent,
                          ),
                          onPressed: onTanpuraToggle,
                        ),
                      if (editMode)
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: onCancelEdit,
                        ),
                    ],
                  ),
                ),
                if (!editMode)
                  IconButton(
                    icon: Icon(
                      listening ? Icons.pause : Icons.play_arrow,
                      size: 36,
                    ),
                    onPressed: listening ? onStop : onStart,
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: showEdit
                      ? IconButton(
                          icon: Icon(
                            editMode ? Icons.check : Icons.edit_outlined,
                          ),
                          onPressed: editMode ? onConfirmEdit : onEdit,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableTargetOverlay extends StatefulWidget {
  const _EditableTargetOverlay({
    super.key,
    required this.notes,
    required this.tuningSystem,
    required this.baseMidi,
    required this.rowCount,
    required this.baseOffset,
    required this.labelWidth,
    required this.rootSemitone,
    required this.ragaName,
    required this.guidelineFraction,
    required this.guidelineOffset,
    required this.scrollController,
    required this.verticalController,
    required this.onDelete,
    required this.onDurationDrag,
    required this.onInsertNotes,
    required this.onNoteChanged,
    required this.bpm,
    required this.baseOctave,
  });

  final List<RecordedNote> notes;
  final String tuningSystem;
  final int baseMidi;
  final int rowCount;
  final double baseOffset;
  final double labelWidth;
  final int rootSemitone;
  final String ragaName;
  final double guidelineFraction;
  final double guidelineOffset;
  final ScrollController scrollController;
  final ScrollController verticalController;
  final ValueChanged<int> onDelete;
  final void Function(int index, int deltaMs, bool commit) onDurationDrag;
  final void Function(int insertIndex, List<String> notes) onInsertNotes;
  final void Function(int index, String label) onNoteChanged;
  final int bpm;
  final int baseOctave;

  static const _msToWidth = 0.08;
  static const _minTileWidth = 24.0;
  static const _defaultInsertDurationMs = 1000;
  static const _rowHeightFactor = 1.5;
  static const _blockHeightFactor = 1.0;
  static const _labelHeightFactor = 1.0;

  @override
  State<_EditableTargetOverlay> createState() => _EditableTargetOverlayState();
}

class _EditableTargetOverlayState extends State<_EditableTargetOverlay> {
  bool _syncedVertical = false;
  bool _syncedHorizontal = false;
  final Map<int, double> _dragRemainderByIndex = {};
  int? _activeDragIndex;
  int? _selectedNoteIndex;
  double? _activeBeatPx;
  int? _pendingInsertIndex;
  int? _pendingInsertMidi;
  double _currentScale = _EditableTargetOverlay._msToWidth;
  double _plotWidth = 0.0;
  int? _lastFocusMidi;
  bool _hasInitialFocus = false;
  final GlobalKey _dragTargetKey = GlobalKey();

  @override
  void didUpdateWidget(covariant _EditableTargetOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notes != widget.notes && _pendingInsertIndex == null) {
      _pendingInsertMidi = null;
    }
  }

  void _queueInsert(int insertIndex) {
    setState(() {
      _pendingInsertIndex = insertIndex;
      _pendingInsertMidi = null;
    });
    _centerOnInsertColumn();
  }

  int? currentInsertIndex() {
    return _pendingInsertIndex;
  }

  void moveInsertTo(int insertIndex) {
    _queueInsert(insertIndex);
  }

  void queueInsertAtEnd() {
    _queueInsert(widget.notes.length);
  }

  void prepareInitialFocus() {
    if (!mounted) return;
    setState(() {
      _hasInitialFocus = false;
    });
  }

  void clearPendingInsert() {
    setState(() {
      _pendingInsertIndex = null;
      _pendingInsertMidi = null;
    });
  }

  void _centerOnInsertColumn() {
    if (_plotWidth <= 0) return;
    final insertIndex = _pendingInsertIndex;
    if (insertIndex == null) return;
    var offsetMs = 0.0;
    for (var i = 0; i < widget.notes.length && i < insertIndex; i++) {
      offsetMs += widget.notes[i].durationMs.toDouble();
    }
    final targetX = offsetMs * _currentScale;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      final centered = (targetX - (_plotWidth / 2))
          .clamp(0.0, widget.scrollController.position.maxScrollExtent);
      widget.scrollController.animateTo(
        centered,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _centerOnMidi(
    int midi,
    double rowHeight,
    int topMidi,
    double baseOffset,
    double viewportHeight,
  ) {
    _scrollToMidi(
      midi,
      rowHeight,
      topMidi,
      baseOffset,
      viewportHeight,
      alignment: 0.5,
    );
  }

  void _scrollToMidi(
    int midi,
    double rowHeight,
    int topMidi,
    double baseOffset,
    double viewportHeight, {
    required double alignment,
    bool onlyIfAbove = false,
  }) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.verticalController.hasClients) return;
      final currentOffset = widget.verticalController.position.pixels;
      final top = _rowTopFor(
        midiFromNote: midi,
        topMidi: topMidi,
        baseOffset: baseOffset,
        rowHeight: rowHeight,
        tuningSystem: widget.tuningSystem,
        ragaName: widget.ragaName,
      );
      if (onlyIfAbove && top >= currentOffset) {
        return;
      }
      final target = (top - (viewportHeight * alignment - rowHeight / 2))
          .clamp(0.0, widget.verticalController.position.maxScrollExtent);
      widget.verticalController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _commitInsertWithLabel(String label) {
    final insertIndex = _pendingInsertIndex;
    if (insertIndex == null) return;
    widget.onInsertNotes(insertIndex, [label]);
    setState(() {
      _pendingInsertIndex = insertIndex + 1;
      _pendingInsertMidi = null;
      _lastFocusMidi = _midiFromNoteLabel(label, widget.baseOctave);
    });
    _centerOnInsertColumn();
  }

String _labelForMidi(int midi, String tuningSystem) {
    final labels = _noteLabelsForSystem(
      tuningSystem,
      rootSemitone: widget.rootSemitone,
      ragaName: widget.ragaName,
    );
    final semitone = (midi % 12 + 12) % 12;
    final octave = (midi / 12).floor() - 1;
    final label = _preferredLabelForSemitone(
      semitone,
      tuningSystem,
      widget.ragaName,
      labels,
    );
    return '$label$octave';
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes;
    return LayoutBuilder(
      builder: (context, constraints) {
        const controlGutterHeight = 72.0;
        final baseMidi = widget.baseMidi;
        final rowCount = widget.rowCount;
        final baseOffset = widget.baseOffset;
        final tuningSystem = widget.tuningSystem;
        final labelWidth = widget.labelWidth;
        final guidelineFraction = widget.guidelineFraction;
        final guidelineOffset = widget.guidelineOffset;
        final scrollController = widget.scrollController;
        final verticalController = widget.verticalController;
        final viewportHeight =
            max(0.0, constraints.maxHeight - controlGutterHeight);
        final totalMs = notes.fold<int>(0, (sum, note) => sum + note.durationMs);
        final bpm = max(1, widget.bpm);
        final bpmScale = 60.0 / bpm;
        final scale = _EditableTargetOverlay._msToWidth * bpmScale;
        final gridMs = 60000.0 / bpm;
        _currentScale = scale;
        final pendingExtraMs = _pendingInsertIndex == null ? 0.0 : gridMs;
        final trailingExtraMs = gridMs * 3;
        final nowX =
            constraints.maxWidth * guidelineFraction + guidelineOffset;
        final plotRightPadding =
            (constraints.maxWidth - nowX).clamp(0.0, constraints.maxWidth);
        final plotWidth = max(
          0.0,
          constraints.maxWidth - labelWidth - plotRightPadding,
        );
        _plotWidth = plotWidth;
        final width = max(
          plotWidth,
          (totalMs + pendingExtraMs + trailingExtraMs) * scale,
        )
            .toDouble();
        final baseRowHeight =
            rowCount > 0 ? viewportHeight / rowCount : 0.0;
        final rowHeight =
            baseRowHeight * _EditableTargetOverlay._rowHeightFactor;
        final blockHeight = rowHeight * _EditableTargetOverlay._blockHeightFactor;
        final labelHeight = rowHeight * _EditableTargetOverlay._labelHeightFactor;
        final topMidi = baseMidi + rowCount - 1;
        final expandedRows = _useExpandedRows(tuningSystem, widget.ragaName);
        const minMidi = 21;
        const maxMidi = 108;
        final minExpanded =
            _expandedRowIndexForMidi(minMidi, tuningSystem, widget.ragaName);
        final maxExpanded =
            _expandedRowIndexForMidi(maxMidi, tuningSystem, widget.ragaName);
        final baseExpanded =
            _expandedRowIndexForMidi(baseMidi, tuningSystem, widget.ragaName);
        final topExpanded = baseExpanded + rowCount - 1;
        final extraAboveRows = max(0, maxExpanded - topExpanded);
        final extraBelowRows = max(0, baseExpanded - minExpanded);
        final totalRows = rowCount + extraAboveRows + extraBelowRows;
        final extendedTopExpanded = topExpanded + extraAboveRows;
        final extendedTopMidi = expandedRows
            ? _midiForExpandedIndex(extendedTopExpanded)
            : topMidi + extraAboveRows;
        final contentHeight = rowHeight * totalRows;
        if (!_syncedVertical) {
          _syncedVertical = true;
        }
        if (!_syncedHorizontal) {
          _syncedHorizontal = true;
        }
        if (!_hasInitialFocus && notes.isNotEmpty) {
          _hasInitialFocus = true;
          final normalized =
              _normalizeNoteForStorage(notes.first.note, tuningSystem);
          final midi = _midiFromNoteLabel(normalized, widget.baseOctave);
          if (midi != null) {
            _scrollToMidi(
              midi,
              rowHeight,
              extendedTopMidi,
              baseOffset,
              viewportHeight,
              alignment: 0.1,
            );
          }
        }
        if (_lastFocusMidi != null) {
          final midi = _lastFocusMidi!;
          _lastFocusMidi = null;
          _centerOnMidi(
            midi,
            rowHeight,
            extendedTopMidi,
            baseOffset,
            viewportHeight,
          );
        }
        var offsetMs = 0.0;
        double? pendingInsertX;
        final lineByKey = <int, _GridLinePosition>{};
        void addLine({
          required double x,
          required bool isStrong,
          int? dragIndex,
          int? insertIndex,
          bool showHandle = false,
        }) {
          final key = x.round();
          final existing = lineByKey[key];
          if (existing != null) {
            if (isStrong && !existing.isStrong) {
              lineByKey[key] = _GridLinePosition(
                x: existing.x,
                dragIndex: existing.dragIndex,
                isStrong: true,
                insertIndex: existing.insertIndex,
                showHandle: existing.showHandle,
              );
            }
            return;
          }
          lineByKey[key] = _GridLinePosition(
            x: x,
            dragIndex: dragIndex,
            isStrong: isStrong,
            insertIndex: insertIndex,
            showHandle: showHandle,
          );
        }
        addLine(
          x: 0,
          isStrong: true,
          insertIndex: null,
          showHandle: false,
          dragIndex: null,
        );
        final blocks = <Widget>[];
        for (var i = 0; i < notes.length; i++) {
          if (_pendingInsertIndex == i) {
            pendingInsertX = offsetMs * scale;
            offsetMs += gridMs;
          }
          final note = notes[i];
          final x = offsetMs * scale;
          final blockWidth = max(
            note.durationMs * scale,
            _EditableTargetOverlay._minTileWidth,
          ).toDouble();
          final blockTop = _rowTopFor(
            midiFromNote: _midiFromNoteLabel(
              _normalizeNoteForStorage(note.note, tuningSystem),
              widget.baseOctave,
            ),
            topMidi: extendedTopMidi,
            baseOffset: baseOffset,
            rowHeight: rowHeight,
            tuningSystem: tuningSystem,
            ragaName: widget.ragaName,
          );
          final expandedTop =
              blockTop - (blockHeight - rowHeight) / 2;
          final isSelected = _selectedNoteIndex == i;
          blocks.add(
            Positioned(
              left: x,
              top: expandedTop,
              width: blockWidth,
              height: blockHeight,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedNoteIndex = i;
                  });
                },
                child: isSelected
                    ? Draggable<_NoteDragPayload>(
                        data: _NoteDragPayload(index: i),
                        axis: Axis.vertical,
                        feedback: Material(
                          color: Colors.transparent,
                          child: _EditableTargetContent(
                            label: _displayLabel(
                              note.note,
                              tuningSystem,
                              widget.rootSemitone,
                              ragaName: widget.ragaName,
                            ),
                            height: blockHeight,
                            onDelete: null,
                            selected: true,
                          ),
                        ),
                        childWhenDragging: const SizedBox.shrink(),
                        child: _EditableTargetContent(
                          label: _displayLabel(
                            note.note,
                            tuningSystem,
                            widget.rootSemitone,
                            ragaName: widget.ragaName,
                          ),
                          height: blockHeight,
                          onDelete: () => widget.onDelete(i),
                          selected: true,
                        ),
                      )
                    : _EditableTargetContent(
                        label: _displayLabel(
                          note.note,
                          tuningSystem,
                          widget.rootSemitone,
                          ragaName: widget.ragaName,
                        ),
                        height: blockHeight,
                        onDelete: () => widget.onDelete(i),
                        selected: false,
                      ),
              ),
            ),
          );
          offsetMs += note.durationMs.toDouble();
          final endX = offsetMs * scale;
          addLine(
            x: endX,
            isStrong: true,
            dragIndex: i,
            insertIndex: i + 1,
            showHandle: true,
          );
        }
        if (_pendingInsertIndex != null &&
            _pendingInsertIndex == notes.length) {
          pendingInsertX = offsetMs * scale;
          offsetMs += gridMs;
        }
        final maxMs = offsetMs;
        final gridLines = (maxMs / gridMs).ceil();
        for (var i = 0; i <= gridLines; i++) {
          final x = i * gridMs * scale;
          addLine(x: x, isStrong: false);
        }
        final linePositions = lineByKey.values.toList()
          ..sort((a, b) => a.x.compareTo(b.x));

        final labelStyle = _labelStyleForSystem(tuningSystem);
        final noteLabels = _noteLabelsForSystem(
          tuningSystem,
          rootSemitone: widget.rootSemitone,
          ragaName: widget.ragaName,
        );
        const sharpSemitones = {1, 3, 6, 8, 10};
        final labelRows = <Widget>[];
        final octaveBands = <Widget>[];
        var bandStartRow = 0;
        int? currentOctave;
        final bandRootSemitone =
            widget.tuningSystem == 'carnatic' ? widget.rootSemitone : 0;
        for (var i = 0; i <= totalRows; i++) {
        final expandedIndex = extendedTopExpanded - i;
        final midi = expandedRows
            ? _midiForExpandedIndex(expandedIndex)
            : expandedIndex;
          final adjustedMidi = midi + bandRootSemitone;
          final octave = (adjustedMidi / 12).floor() - 1;
          if (currentOctave == null) {
            currentOctave = octave;
            bandStartRow = 0;
          } else if (i == totalRows || octave != currentOctave) {
            final bandTop = (bandStartRow + baseOffset) * rowHeight;
            final bandHeight = (i - bandStartRow) * rowHeight;
            if (bandHeight > 0) {
              final bandColor = _octaveBandColor(
                currentOctave * 12,
                bandRootSemitone,
              );
              octaveBands.add(
                Positioned(
                  left: 0,
                  right: 0,
                  top: bandTop,
                  height: bandHeight,
                  child: IgnorePointer(
                    child: Container(
                      color: bandColor.withOpacity(0.12),
                      alignment: Alignment.center,
                      child: Text(
                        '$currentOctave',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: bandColor.withOpacity(0.35),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            currentOctave = octave;
            bandStartRow = i;
          }
        }
        for (var i = 0; i < totalRows; i++) {
          final expandedIndex = extendedTopExpanded - i;
          final midi = expandedRows
              ? _midiForExpandedIndex(expandedIndex)
              : expandedIndex;
          final semitone = (midi % 12 + 12) % 12;
          final labelsForRow = expandedRows
              ? [_expandedLabelForIndex(expandedIndex)]
              : _splitLabelsForSemitone(
                  semitone,
                  tuningSystem,
                  widget.ragaName,
                  noteLabels,
                );
          final isSharp = sharpSemitones.contains(semitone);
          final rowBg =
              isSharp ? Colors.black : const Color(0xFFCBD1D6);
          final rowTextColor = isSharp ? Colors.white : Colors.black;
          final baseStyle = labelStyle ??
              TextStyle(
                color: rowTextColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              );
          final resolvedStyle = baseStyle.copyWith(color: rowTextColor);
          final labelTop =
              (i + baseOffset) * rowHeight - (labelHeight - rowHeight) / 2;
          final combinedLabel = !expandedRows && labelsForRow.length > 1
              ? labelsForRow.join('/')
              : null;
          final displayLabels =
              combinedLabel != null ? [combinedLabel] : labelsForRow;
          final commitLabels = combinedLabel != null
              ? [
                  _preferredLabelForSemitone(
                    semitone,
                    tuningSystem,
                    widget.ragaName,
                    noteLabels,
                  )
                ]
              : labelsForRow;
          final segmentHeight = labelHeight / displayLabels.length;
          for (var j = 0; j < displayLabels.length; j++) {
            final displayLabel = displayLabels[j];
            final commitLabel = commitLabels[j];
            labelRows.add(
              Positioned(
                left: 0,
                right: 0,
                top: labelTop + (segmentHeight * j),
                height: segmentHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _commitInsertWithLabel(commitLabel),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          color: rowBg,
                          alignment: Alignment.center,
                          child: SizedBox(
                            height: segmentHeight,
                            child: Center(
                              child: Text(displayLabel, style: resolvedStyle),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        }

        if (_pendingInsertIndex != null && pendingInsertX != null) {
          final insertWidth = max(
            gridMs * scale,
            _EditableTargetOverlay._minTileWidth,
          ).toDouble();
          final selectedMidi = _pendingInsertMidi;
          blocks.add(
            Positioned(
              left: pendingInsertX,
              top: 0,
              width: insertWidth,
              height: contentHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (details) {
                  final localY = details.localPosition.dy;
                  final rowIndex = (localY / rowHeight).floor();
                  final expandedIndex = extendedTopExpanded - rowIndex;
                  final midi = expandedRows
                      ? _midiForExpandedIndex(expandedIndex)
                      : expandedIndex;
                  final label = expandedRows
                      ? _expandedLabelForIndex(expandedIndex)
                      : _labelForMidi(midi, tuningSystem);
                  _commitInsertWithLabel(label);
                  _centerOnMidi(
                    midi,
                    rowHeight,
                    extendedTopMidi,
                    baseOffset,
                    viewportHeight,
                  );
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          color: Colors.white10,
                        ),
                      ),
                    ),
                    if (selectedMidi != null)
                      Positioned(
                        top: _rowTopFor(
                          midiFromNote: selectedMidi,
                          topMidi: extendedTopMidi,
                          baseOffset: baseOffset,
                          rowHeight: rowHeight,
                          tuningSystem: tuningSystem,
                          ragaName: widget.ragaName,
                        ),
                        left: 0,
                        right: 0,
                        height: rowHeight,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white),
                            color: Colors.white24,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        final scrollableContent = Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: viewportHeight,
          child: ClipRect(
            child: SingleChildScrollView(
              controller: verticalController,
              scrollDirection: Axis.vertical,
              physics: const BouncingScrollPhysics(),
              primary: false,
              child: SizedBox(
                height: contentHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: labelWidth,
                      height: contentHeight,
                      child: Stack(
                        children: [
                          const Positioned.fill(
                            child: ColoredBox(color: Color(0xFF23272B)),
                          ),
                          for (var i = 0; i < totalRows; i++)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: (i + baseOffset) * rowHeight,
                              height: rowHeight,
                              child: ColoredBox(
                                color: _octaveBandColor(
                                  expandedRows
                                      ? _midiForExpandedIndex(
                                          extendedTopExpanded - i,
                                        )
                                      : extendedTopMidi - i,
                                  bandRootSemitone,
                                ),
                              ),
                            ),
                          for (var i = 0; i < totalRows; i++)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: (i + baseOffset) * rowHeight,
                              height: rowHeight,
                              child: ColoredBox(
                                color: i.isEven
                                    ? const Color(0xFF2A2F33)
                                    : const Color(0xFF343A3F),
                              ),
                            ),
                          ...labelRows,
                        ],
                      ),
                    ),
                    SizedBox(
                      width: plotWidth,
                      height: contentHeight,
                      child: ClipRect(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          primary: false,
                          child: SizedBox(
                            width: width,
                            height: contentHeight,
                            child: Stack(
                              children: [
                                for (var i = 0; i < totalRows; i++)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: (i + baseOffset) * rowHeight,
                                    height: rowHeight,
                                    child: ColoredBox(
                                      color: i.isEven
                                          ? const Color(0xFF2A2F33)
                                          : const Color(0xFF343A3F),
                                    ),
                                  ),
                                ...octaveBands,
                                ...blocks,
                                Positioned.fill(
                                  child: DragTarget<_NoteDragPayload>(
                                    key: _dragTargetKey,
                                    onAcceptWithDetails: (details) {
                                      final box = _dragTargetKey
                                          .currentContext
                                          ?.findRenderObject() as RenderBox?;
                                      if (box == null) return;
                                      final local =
                                          box.globalToLocal(details.offset);
                                      final rowIndex =
                                          (local.dy / rowHeight).floor();
                                      final expandedIndex =
                                          extendedTopExpanded - rowIndex;
                                      final midi = expandedRows
                                          ? _midiForExpandedIndex(expandedIndex)
                                              .clamp(minMidi, maxMidi)
                                          : (extendedTopMidi - rowIndex)
                                              .clamp(minMidi, maxMidi);
                                      final label = expandedRows
                                          ? _expandedLabelForIndex(expandedIndex)
                                          : _labelForMidi(midi, tuningSystem);
                                      widget.onNoteChanged(
                                        details.data.index,
                                        label,
                                      );
                                      setState(() {
                                        _selectedNoteIndex = null;
                                      });
                                      _centerOnMidi(
                                        midi,
                                        rowHeight,
                                        extendedTopMidi,
                                        baseOffset,
                                        viewportHeight,
                                      );
                                    },
                                    builder: (context, _, __) =>
                                        const SizedBox.expand(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: plotRightPadding),
                  ],
                ),
              ),
            ),
          ),
        );

        return Stack(
          children: [
            scrollableContent,
            if (_selectedNoteIndex != null)
              Positioned(
                left: labelWidth + 8,
                top: 8,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Drag up or down to move note',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: labelWidth,
              right: plotRightPadding,
              top: 0,
              bottom: 0,
              child: _GridLineOverlay(
                linePositions: linePositions,
                plotWidth: plotWidth,
                scrollController: scrollController,
                onBuildLine: _buildGridLine,
              ),
            ),
          ],
        );
      },
    );
  }

  double _rowTopFor({
    required int? midiFromNote,
    required int topMidi,
    required double baseOffset,
    required double rowHeight,
    required String tuningSystem,
    required String? ragaName,
  }) {
    final midi = midiFromNote ?? topMidi;
    if (_useExpandedRows(tuningSystem, ragaName)) {
      final topIndex = _expandedRowIndexForMidi(
        topMidi,
        tuningSystem,
        ragaName,
      );
      final rowIndex = topIndex -
          _expandedRowIndexForMidi(
            midi,
            tuningSystem,
            ragaName,
          );
      return (rowIndex + baseOffset) * rowHeight;
    }
    final rowIndex = topMidi - midi;
    return (rowIndex + baseOffset) * rowHeight;
  }

  Color _octaveBandColor(int midi, int rootSemitone) {
    const bands = [
      Color(0xFF1DB954),
      Color(0xFF2F80ED),
      Color(0xFFF2994A),
      Color(0xFF9B51E0),
      Color(0xFFEB5757),
    ];
    final adjustedMidi = midi + rootSemitone;
    final octave = (adjustedMidi / 12).floor() - 1;
    final index = octave.abs() % bands.length;
    return bands[index];
  }

  Widget _buildGridLine({
    required double x,
    required bool showHandle,
    required bool isStrong,
    required int? insertIndex,
    int? dragIndex,
  }) {
    const lineWidth = 1.0;
    const handleWidth = 20.0;
    const handleHeight = 28.0;
    final lineColor =
        Colors.white.withOpacity(isStrong ? 1.0 : 0.3);
    if (dragIndex == null && insertIndex == null) {
      return Positioned(
        left: x,
        top: 0,
        bottom: 0,
        child: Container(
          width: lineWidth,
          color: lineColor,
        ),
      );
    }
    return Stack(
      children: [
        Positioned(
          left: x,
          top: 0,
          bottom: 0,
          child: Container(
            width: lineWidth,
            color: lineColor,
          ),
        ),
        if (dragIndex != null && dragIndex == _activeDragIndex)
          Positioned(
            left: x,
            top: 0,
            bottom: 0,
            child: Container(
              width: 2,
              color: Colors.orange.withOpacity(0.9),
            ),
          ),
        if (dragIndex != null &&
            dragIndex == _activeDragIndex &&
            _activeBeatPx != null)
          Positioned(
            left: x + _activeBeatPx!,
            top: 0,
            bottom: 0,
            child: Container(
              width: 1,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        Positioned(
          left: x - (handleWidth / 2),
          bottom: 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showHandle)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    if (dragIndex == null) return;
                    final beatMs = (60000 / max(1, widget.bpm)).round();
                    final beatPx = beatMs * _currentScale;
                    setState(() {
                      _activeDragIndex = dragIndex;
                      _activeBeatPx = beatPx > 0 ? beatPx : null;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    if (dragIndex == null) return;
                    final delta = details.delta.dx;
                    final remainder = _dragRemainderByIndex[dragIndex] ?? 0.0;
                    final totalDelta = remainder + delta;
                    final beatMs = (60000 / max(1, widget.bpm)).round();
                    final beatPx = beatMs * _currentScale;
                    if (beatPx <= 0) {
                      _dragRemainderByIndex[dragIndex] = totalDelta;
                      return;
                    }
                    final ratio = totalDelta / beatPx;
                    final stepCount = ratio >= 0
                        ? (ratio + 0.1).floor()
                        : (ratio - 0.1).ceil();
                    if (stepCount == 0) {
                      _dragRemainderByIndex[dragIndex] = totalDelta;
                      return;
                    }
                    final deltaMs = stepCount * beatMs;
                    final consumedPx = stepCount * beatPx;
                    _dragRemainderByIndex[dragIndex] = totalDelta - consumedPx;
                    widget.onDurationDrag(dragIndex, deltaMs, false);
                    setState(() {
                      if (_activeDragIndex == dragIndex) {
                        _activeBeatPx = beatPx;
                      }
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    if (dragIndex == null) return;
                    _dragRemainderByIndex.remove(dragIndex);
                    widget.onDurationDrag(dragIndex, 0, true);
                    setState(() {
                      _activeDragIndex = null;
                      _activeBeatPx = null;
                    });
                  },
                  onHorizontalDragCancel: () {
                    if (dragIndex == null) return;
                    _dragRemainderByIndex.remove(dragIndex);
                    setState(() {
                      _activeDragIndex = null;
                      _activeBeatPx = null;
                    });
                  },
                  child: Container(
                    width: handleWidth,
                    height: handleHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2327),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: const Icon(
                      Icons.drag_indicator,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (showHandle) const SizedBox(height: 10),
              if (insertIndex != null)
                GestureDetector(
                  onTap: () => _queueInsert(insertIndex),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2B6BFF),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: const Icon(
                      Icons.add,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GridLinePosition {
  const _GridLinePosition({
    required this.x,
    required this.dragIndex,
    required this.isStrong,
    required this.insertIndex,
    required this.showHandle,
  });

  final double x;
  final int? dragIndex;
  final bool isStrong;
  final int? insertIndex;
  final bool showHandle;
}

class _GridLineOverlay extends StatelessWidget {
  const _GridLineOverlay({
    required this.linePositions,
    required this.plotWidth,
    required this.scrollController,
    required this.onBuildLine,
  });

  final List<_GridLinePosition> linePositions;
  final double plotWidth;
  final ScrollController scrollController;
  final Widget Function({
    required double x,
    required bool showHandle,
    required bool isStrong,
    required int? insertIndex,
    int? dragIndex,
  }) onBuildLine;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: scrollController,
        builder: (context, _) {
          final scrollOffset = scrollController.positions.isNotEmpty
              ? scrollController.positions.first.pixels
              : 0.0;
          final lines = <Widget>[];
          for (final pos in linePositions) {
            final left = pos.x - scrollOffset;
            if (left < -10 || left > plotWidth + 10) {
              continue;
            }
            lines.add(
              onBuildLine(
                x: left,
                showHandle: pos.showHandle,
                isStrong: pos.isStrong,
                insertIndex: pos.insertIndex,
                dragIndex: pos.dragIndex,
              ),
            );
          }
          return Stack(children: lines);
        },
      ),
    );
  }
}

class _NoteDragPayload {
  const _NoteDragPayload({required this.index});

  final int index;
}

class _EditableTargetChip extends StatelessWidget {
  const _EditableTargetChip({
    required this.label,
    required this.width,
    required this.height,
  });

  final String label;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF2B6BFF).withOpacity(0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
    );
  }
}

class _EditableTargetContent extends StatelessWidget {
  const _EditableTargetContent({
    required this.label,
    required this.height,
    required this.onDelete,
    required this.selected,
  });

  final String label;
  final double height;
  final VoidCallback? onDelete;
  final bool selected;
  static const _labelPaddingRight = 18.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF2B6BFF).withOpacity(0.4),
        borderRadius: BorderRadius.circular(6),
        border: selected ? Border.all(color: Colors.white, width: 1) : null,
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(
              right: onDelete != null ? _labelPaddingRight : 0,
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (onDelete != null)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: onDelete,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 18,
                    height: 18,
                    child: Icon(Icons.close, size: 18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InsertNotesSheet extends StatefulWidget {
  const _InsertNotesSheet({
    required this.tuningSystem,
  });

  final String tuningSystem;

  @override
  State<_InsertNotesSheet> createState() => _InsertNotesSheetState();
}

class _InsertNotesSheetState extends State<_InsertNotesSheet> {
  static const _minOctave = 1;
  static const _maxOctave = 8;
  int _defaultOctave = PitchNotifier.defaultBaseOctave;

  final List<String> _selectedNotes = [];
  final ScrollController _noteListController = ScrollController();
  final Map<int, GlobalKey> _octaveKeys = {};
  bool _didScrollToDefaultOctave = false;

  late final Map<int, List<String>> _noteOptionsByOctave = {
    for (var octave = _minOctave; octave <= _maxOctave; octave++)
      octave: [
        for (final note in const [
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
        ])
          '$note$octave',
      ],
  };

  @override
  void initState() {
    super.initState();
    _defaultOctave = context.read<PitchNotifier>().baseOctave;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToDefaultOctave();
    });
  }

  @override
  void dispose() {
    _noteListController.dispose();
    super.dispose();
  }

  void _scrollToDefaultOctave() {
    if (_didScrollToDefaultOctave) return;
    _didScrollToDefaultOctave = true;
    final key = _octaveKeys[_defaultOctave];
    final context = key?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 220),
      alignment: 0.2,
    );
  }

  void _toggleNote(String note) {
    setState(() {
      if (_selectedNotes.contains(note)) {
        _selectedNotes.remove(note);
      } else {
        _selectedNotes.add(note);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + bottomInset,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Insert notes',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '${_selectedNotes.length} selected',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                controller: _noteListController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var octave = _minOctave; octave <= _maxOctave; octave++)
                      _buildOctaveSection(octave),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _selectedNotes.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_selectedNotes),
                    child: const Text('Insert'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOctaveSection(int octave) {
    final notes = _noteOptionsByOctave[octave] ?? const [];
    final key = _octaveKeys.putIfAbsent(octave, GlobalKey.new);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Octave $octave',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final note in notes)
                _NoteOptionTile(
                  note: _composeDisplayLabel(note, widget.tuningSystem),
                  active: _selectedNotes.contains(note),
                  onTap: () => _toggleNote(note),
                  onDoubleTap: () => _toggleNote(note),
                  textStyle: null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditRecordingSheet extends StatefulWidget {
  const _EditRecordingSheet({
    required this.entry,
    required this.onSaved,
  });

  final RecordingEntry entry;
  final ValueChanged<RecordingEntry> onSaved;

  @override
  State<_EditRecordingSheet> createState() => _EditRecordingSheetState();
}

class _EditRecordingSheetState extends State<_EditRecordingSheet> {
  final List<TextEditingController> _noteControllers = [];
  final List<TextEditingController> _durationControllers = [];
  final List<String?> _noteErrors = [];
  final List<String?> _durationErrors = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final tuningSystem = context.read<PitchNotifier>().tuningSystem;
    for (final note in widget.entry.notes) {
      _noteControllers.add(
        TextEditingController(
          text: _formatNoteForEdit(note.note, tuningSystem),
        ),
      );
      _durationControllers.add(
        TextEditingController(text: note.durationMs.toString()),
      );
      _noteErrors.add(null);
      _durationErrors.add(null);
    }
    if (_noteControllers.isEmpty) {
      _addRow();
    }
  }

  @override
  void dispose() {
    for (final controller in _noteControllers) {
      controller.dispose();
    }
    for (final controller in _durationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() {
      _noteControllers.add(TextEditingController());
      _durationControllers.add(TextEditingController(text: '1000'));
      _noteErrors.add(null);
      _durationErrors.add(null);
    });
  }

  void _removeRow(int index) {
    setState(() {
      _noteControllers[index].dispose();
      _durationControllers[index].dispose();
      _noteControllers.removeAt(index);
      _durationControllers.removeAt(index);
      _noteErrors.removeAt(index);
      _durationErrors.removeAt(index);
    });
  }

  bool get _hasNotes {
    return _noteControllers.any((c) => c.text.trim().isNotEmpty);
  }

  bool _hasNoteErrors() {
    return _noteErrors.any((error) => error != null) ||
        _durationErrors.any((error) => error != null);
  }

  bool _hasEmptyFields() {
    for (var i = 0; i < _noteControllers.length; i++) {
      if (_noteControllers[i].text.trim().isEmpty ||
          _durationControllers[i].text.trim().isEmpty) {
        return true;
      }
    }
    return false;
  }

  void _openComposeNotes() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF23272B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      isScrollControlled: true,
      builder: (context) => _ComposeRecordingSheet(
        initialEntry: widget.entry,
        onSaved: (updated) {
          widget.onSaved(updated);
        },
      ),
    ).then((_) {
      if (!mounted) return;
      Navigator.of(context).pop();
    });
  }

  Future<void> _save() async {
    if (_saving || !_hasNotes) return;
    setState(() {
      _saving = true;
    });
    try {
      final tuningSystem = context.read<PitchNotifier>().tuningSystem;
      final notes = <RecordedNote>[];
      for (var i = 0; i < _noteControllers.length; i++) {
        final noteText = _noteControllers[i].text.trim();
        if (noteText.isEmpty) {
          continue;
        }
        final normalized = _normalizeNoteForStorage(noteText, tuningSystem);
        if (normalized.isEmpty) {
          continue;
        }
        final duration =
            int.tryParse(_durationControllers[i].text.trim()) ?? 500;
        notes.add(
          RecordedNote(
            note: normalized,
            durationMs: duration,
          ),
        );
      }
      final updated = RecordingEntry(
        id: widget.entry.id,
        name: widget.entry.name,
        createdAt: widget.entry.createdAt,
        notes: notes,
      );
      await RecordingStore.instance.update(updated);
      widget.onSaved(updated);
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final tuningSystem = context.watch<PitchNotifier>().tuningSystem;
    final noteFormat = _noteInputFormatForSystem(tuningSystem);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Edit notes',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 280,
            child: ListView.separated(
              itemCount: _noteControllers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _noteControllers[index],
                        decoration: InputDecoration(
                          labelText: 'Note',
                          filled: true,
                          errorText: _noteErrors[index],
                        ),
                        onChanged: (value) {
                          final invalid = value.isNotEmpty &&
                              !_isValidNoteForSystem(value, tuningSystem);
                          setState(() {
                            _noteErrors[index] = invalid
                                ? _noteErrorTextForSystem(tuningSystem)
                                : null;
                          });
                        },
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(noteFormat),
                        ],
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _durationControllers[index],
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          final invalid = value.isNotEmpty &&
                              !RegExp(r'^[0-9]+$').hasMatch(value);
                          setState(() {
                            _durationErrors[index] =
                                invalid ? 'Enter only numbers.' : null;
                          });
                        },
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'ms',
                          filled: true,
                          errorText: _durationErrors[index],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeRow(index),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _openComposeNotes,
            icon: const Icon(Icons.add),
            label: const Text('Add note'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed:
                (_saving || !_hasNotes || _hasNoteErrors() || _hasEmptyFields())
                    ? null
                    : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Update'),
          ),
        ],
      ),
    );
  }
}

class _ComposeRecordingSheet extends StatefulWidget {
  const _ComposeRecordingSheet({
    required this.onSaved,
    this.initialEntry,
  });

  final ValueChanged<RecordingEntry> onSaved;
  final RecordingEntry? initialEntry;

  @override
  State<_ComposeRecordingSheet> createState() => _ComposeRecordingSheetState();
}

class _ComposeRecordingSheetState extends State<_ComposeRecordingSheet> {
  static const _defaultDurationMs = 1000;
  static const _millisecondsPerSecond = 1000.0;
  static const _previewHeight = 170.0;
  int _defaultOctave = PitchNotifier.defaultBaseOctave;

  _ComposeSheetStep _step = _ComposeSheetStep.select;
  final List<String> _selectedNotes = [];
  final List<TextEditingController> _durationControllers = [];
  String? _activeNote;
  int? _selectedIndex;
  bool _saving = false;
  bool _editDurationMode = false;
  final Set<int> _durationSelections = {};

  final Map<int, List<String>> _noteOptionsByOctave = {
    for (var octave = 1; octave <= 8; octave++)
      octave: [
        for (final note in const [
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
        ])
          '$note$octave',
      ],
  };
  final ScrollController _noteListController = ScrollController();
  final Map<int, GlobalKey> _octaveKeys = {};
  bool _didScrollToDefaultOctave = false;

  @override
  void initState() {
    super.initState();
    _defaultOctave = context.read<PitchNotifier>().baseOctave;
    final entry = widget.initialEntry;
    if (entry != null) {
      for (final note in entry.notes) {
        _selectedNotes.add(note.note.toUpperCase());
        _durationControllers.add(
          TextEditingController(text: _formatSeconds(note.durationMs)),
        );
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToDefaultOctave();
    });
  }

  @override
  void dispose() {
    for (final controller in _durationControllers) {
      controller.dispose();
    }
    _noteListController.dispose();
    super.dispose();
  }

  void _addNote(String note) {
    setState(() {
      _selectedNotes.add(note);
      _durationControllers.add(
        TextEditingController(text: _formatSeconds(_defaultDurationMs)),
      );
      _activeNote = note;
    });
  }

  void _applyNoteSelection(String note) {
    setState(() {
      if (_selectedIndex != null &&
          _selectedIndex! >= 0 &&
          _selectedIndex! < _selectedNotes.length) {
        _selectedNotes[_selectedIndex!] = note;
        _selectedIndex = null;
      } else {
        _selectedNotes.add(note);
        _durationControllers.add(
          TextEditingController(text: _formatSeconds(_defaultDurationMs)),
        );
      }
      _activeNote = note;
    });
  }

  void _removeAt(int index) {
    setState(() {
      _selectedNotes.removeAt(index);
      _durationControllers[index].dispose();
      _durationControllers.removeAt(index);
      if (_selectedIndex != null) {
        if (_selectedNotes.isEmpty) {
          _selectedIndex = null;
        } else if (_selectedIndex == index) {
          _selectedIndex = (index - 1).clamp(0, _selectedNotes.length - 1);
        } else if (_selectedIndex! > index) {
          _selectedIndex = _selectedIndex! - 1;
        }
      }
    });
  }

  void _goToPreview() {
    setState(() {
      _step = _ComposeSheetStep.preview;
    });
  }

  void _goToDurations() {
    setState(() {
      _step = _ComposeSheetStep.duration;
    });
  }

  void _goBack() {
    setState(() {
      _step = _step == _ComposeSheetStep.preview
          ? _ComposeSheetStep.select
          : _ComposeSheetStep.preview;
    });
  }

  void _toggleDurationEdit() {
    setState(() {
      _editDurationMode = !_editDurationMode;
      _durationSelections.clear();
    });
  }

  void _toggleDurationSelection(int index) {
    setState(() {
      if (_durationSelections.contains(index)) {
        _durationSelections.remove(index);
      } else {
        _durationSelections.add(index);
      }
    });
  }

  void _toggleSelectAll(bool selected) {
    setState(() {
      _durationSelections.clear();
      if (selected) {
        _durationSelections.addAll(
          List<int>.generate(_selectedNotes.length, (index) => index),
        );
      }
    });
  }

  Future<void> _applyBulkDuration() async {
    if (_saving || _selectedNotes.isEmpty || _durationSelections.isEmpty) {
      return;
    }
    final controller = TextEditingController();
    final duration = await showDialog<int>(
      context: context,
      builder: (context) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Enter duration (s)'),
              content: TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (value) {
                  final trimmed = value.trim();
                  final invalid =
                      trimmed.isNotEmpty && double.tryParse(trimmed) == null;
                  setDialogState(() {
                    errorText = invalid ? 'Enter only the numbers.' : null;
                  });
                },
                decoration: InputDecoration(
                  filled: false,
                  hintText: '1.0',
                  errorText: errorText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: errorText != null
                      ? null
                      : () {
                          final raw = controller.text.trim();
                          final seconds = double.tryParse(raw);
                          if (raw.isEmpty || seconds == null) {
                            setDialogState(() {
                              errorText = 'Enter only the numbers.';
                            });
                            return;
                          }
                          final ms =
                              (seconds * _millisecondsPerSecond).round();
                          Navigator.of(context).pop(ms);
                        },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
    if (duration == null) {
      return;
    }
    for (var i = 0; i < _durationControllers.length; i++) {
      if (!_durationSelections.contains(i)) {
        continue;
      }
      _durationControllers[i].text = _formatSeconds(duration);
    }
    await _saveRecording();
  }

  Future<void> _saveRecording() async {
    if (_saving || _selectedNotes.isEmpty) return;
    setState(() {
      _saving = true;
    });
    try {
      final notes = <RecordedNote>[];
      for (var i = 0; i < _selectedNotes.length; i++) {
        final duration = _parseDurationMs(_durationControllers[i].text);
        notes.add(
          RecordedNote(
            note: _selectedNotes[i].toLowerCase(),
            durationMs: duration,
          ),
        );
      }
      final existingEntry = widget.initialEntry;
      if (existingEntry != null) {
        final updated = RecordingEntry(
          id: existingEntry.id,
          name: existingEntry.name,
          createdAt: existingEntry.createdAt,
          notes: notes,
        );
        await RecordingStore.instance.update(updated);
        widget.onSaved(updated);
      } else {
        final existing = await RecordingStore.instance.load();
        final nameController = TextEditingController(
          text: 'Recording ${existing.length + 1}',
        );
        final name = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Save recording'),
            content: TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Recording name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(nameController.text.trim());
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (name == null || name.isEmpty) {
          return;
        }
        final entry = RecordingEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: name,
          createdAt: DateTime.now(),
          notes: notes,
        );
        await RecordingStore.instance.save(entry);
        widget.onSaved(entry);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tuningSystem = context.watch<PitchNotifier>().tuningSystem;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + bottomInset,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: switch (_step) {
          _ComposeSheetStep.select => _buildSelectNotes(context, tuningSystem),
          _ComposeSheetStep.preview => _buildPreview(context, tuningSystem),
          _ComposeSheetStep.duration => _buildDurations(context),
        },
      ),
    );
  }

  Widget _buildSelectNotes(BuildContext context, String tuningSystem) {
    final labelStyle = _labelStyleForSystem(tuningSystem);
    return Column(
      key: const ValueKey('select'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'western', label: Text('Western')),
              ButtonSegment(value: 'carnatic', label: Text('Carnatic')),
            ],
            selected: {tuningSystem},
            onSelectionChanged: (value) {
              if (value.isEmpty) return;
              context.read<PitchNotifier>().setTuningSystem(value.first);
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.initialEntry == null ? 'Select notes' : 'Edit notes',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: ListView(
            controller: _noteListController,
            children: [
              for (final entry in _noteOptionsByOctave.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  key: _octaveKey(entry.key),
                  child: Text(
                    'Octave ${entry.key}',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: Colors.white70),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final note in entry.value)
                      _NoteOptionTile(
                        note: _composeDisplayLabel(note, tuningSystem),
                        active: _activeNote == note,
                        onTap: () => _applyNoteSelection(note),
                        onDoubleTap: () => _addNote(note),
                        textStyle: labelStyle,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SelectedNotesPreview(
          notes: _selectedNotes,
          height: _previewHeight,
          onRemove: _removeAt,
          selectedIndex: _selectedIndex,
          onSelect: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          tuningSystem: tuningSystem,
          textStyle: labelStyle,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _selectedNotes.isEmpty ? null : _goToPreview,
          child: const Text('Next'),
        ),
      ],
    );
  }

  void _scrollToDefaultOctave() {
    if (_didScrollToDefaultOctave) return;
    final key = _octaveKeys[_defaultOctave];
    final context = key?.currentContext;
    if (context == null) return;
    _didScrollToDefaultOctave = true;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 1),
      alignment: 0.0,
      curve: Curves.linear,
    );
  }

  GlobalKey _octaveKey(int octave) {
    return _octaveKeys.putIfAbsent(octave, () => GlobalKey());
  }

  Widget _buildPreview(BuildContext context, String tuningSystem) {
    final labelStyle = _labelStyleForSystem(tuningSystem);
    return Column(
      key: const ValueKey('preview'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.initialEntry == null ? 'Preview' : 'Edit preview',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        _SelectedNotesPreview(
          notes: _selectedNotes,
          height: _previewHeight,
          onRemove: _removeAt,
          selectedIndex: _selectedIndex,
          onSelect: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          tuningSystem: tuningSystem,
          textStyle: labelStyle,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _goBack,
              icon: const Icon(Icons.add),
              label: const Text('Add note'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _selectedNotes.isEmpty ? null : _goToDurations,
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDurations(BuildContext context) {
    final tuningSystem = context.watch<PitchNotifier>().tuningSystem;
    return Column(
      key: const ValueKey('duration'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Durations (s)',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
            TextButton(
              onPressed: _toggleDurationEdit,
              child: Text(
                _editDurationMode ? 'Cancel edit' : 'Edit note durations',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_editDurationMode)
          Row(
            children: [
              Checkbox(
                value: _selectedNotes.isNotEmpty &&
                    _durationSelections.length == _selectedNotes.length,
                onChanged: (value) => _toggleSelectAll(value ?? false),
              ),
              const Text('Select all'),
            ],
          ),
        if (_editDurationMode) const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: ListView.separated(
            itemCount: _selectedNotes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return Row(
                children: [
                  if (_editDurationMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Checkbox(
                        value: _durationSelections.contains(index),
                        onChanged: (_) => _toggleDurationSelection(index),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      _composeDisplayLabel(_selectedNotes[index], tuningSystem),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _durationControllers[index],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        filled: true,
                        hintText: '1.0',
                        suffixText: 's',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton(
              onPressed: _goBack,
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: (_selectedNotes.isEmpty ||
                        _saving ||
                        (_editDurationMode && _durationSelections.isEmpty))
                    ? null
                    : (_editDurationMode ? _applyBulkDuration : _saveRecording),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _editDurationMode
                            ? 'Next'
                            : (widget.initialEntry == null ? 'Done' : 'Update'),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatSeconds(int durationMs) {
    final seconds = durationMs / _millisecondsPerSecond;
    final fixed = seconds.toStringAsFixed(seconds.truncateToDouble() == seconds
        ? 0
        : 2);
    return _trimTrailingZeros(fixed);
  }

  int _parseDurationMs(String raw) {
    final seconds = double.tryParse(raw.trim());
    if (seconds == null) {
      return _defaultDurationMs;
    }
    final ms = (seconds * _millisecondsPerSecond).round();
    return ms > 0 ? ms : _defaultDurationMs;
  }

  String _trimTrailingZeros(String value) {
    if (!value.contains('.')) return value;
    final trimmed = value.replaceAll(RegExp(r'0+$'), '');
    return trimmed.replaceAll(RegExp(r'\.$'), '');
  }
}

class _SelectedNotesPreview extends StatelessWidget {
  const _SelectedNotesPreview({
    required this.notes,
    required this.height,
    required this.onRemove,
    required this.selectedIndex,
    required this.onSelect,
    required this.tuningSystem,
    required this.textStyle,
  });

  final List<String> notes;
  final double height;
  final ValueChanged<int> onRemove;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;
  final String tuningSystem;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: notes.isEmpty
          ? const Center(
              child: Text(
                'No notes selected yet.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < notes.length; index++)
                    GestureDetector(
                      onTap: () => onSelect(index),
                      child: Chip(
                        label: Text(
                          _composeDisplayLabel(notes[index], tuningSystem),
                          style: textStyle,
                        ),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => onRemove(index),
                        backgroundColor: selectedIndex == index
                            ? const Color(0xFF2B6BFF)
                            : const Color(0xFF2C3136),
                        labelStyle: const TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _NoteOptionTile extends StatelessWidget {
  const _NoteOptionTile({
    required this.note,
    required this.active,
    required this.onTap,
    required this.onDoubleTap,
    required this.textStyle,
  });

  final String note;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2B6BFF) : Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          note,
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w600,
          ).merge(textStyle),
        ),
      ),
    );
  }
}

enum _ComposeSheetStep { select, preview, duration }

String _noteLabel(
  double frequency,
  String tuningSystem, {
  required int rootSemitone,
  String? ragaName,
}) {
  final labels = _noteLabelsForSystem(
    tuningSystem,
    rootSemitone: rootSemitone,
    ragaName: ragaName,
  );
  final midi = midiFromFrequency(frequency).round().clamp(0, 127);
  final octave = (midi / 12).floor() - 1;
  final label = _preferredLabelForSemitone(
    midi % 12,
    tuningSystem,
    ragaName,
    labels,
  );
  return '$label$octave';
}

class _TargetBlock {
  const _TargetBlock({
    required this.midi,
    required this.label,
    required this.durationMs,
    required this.startOffsetMs,
  });

  final int midi;
  final String label;
  final int durationMs;
  final int startOffsetMs;
}

class _TargetNotePainter extends CustomPainter {
  _TargetNotePainter({
    required this.targets,
    required this.elapsed,
    required this.totalDurationMs,
    required this.running,
    required this.bpm,
    required this.baseMidi,
    required this.rowCount,
    required this.baseOffset,
    required this.tuningSystem,
    required this.rootSemitone,
    required this.ragaName,
    required this.guidelineFraction,
    required this.guidelineOffset,
  });

  final List<_TargetBlock> targets;
  final Duration elapsed;
  final int totalDurationMs;
  final bool running;
  final int bpm;
  final int baseMidi;
  final int rowCount;
  final double baseOffset;
  final String tuningSystem;
  final int rootSemitone;
  final String ragaName;
  final double guidelineFraction;
  final double guidelineOffset;

  static const _labelWidth = 70.0;
  static const _trackWindowMs = 6400.0;
  static const _blockColor = Color(0xFF2B6BFF);
  static const _blockHeightFactor = 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (!running) {
      return;
    }
    if (targets.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'No target notes in this recording.',
          style: TextStyle(color: Colors.white70),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(
        canvas,
        Offset(
          (size.width - tp.width) / 2,
          (size.height - tp.height) / 2,
        ),
      );
      return;
    }

    final nowX = size.width * guidelineFraction + guidelineOffset;
    final plotRightPadding =
        (size.width - nowX).clamp(0.0, size.width).toDouble();
    final plotWidth = size.width - _labelWidth - plotRightPadding;
    if (plotWidth <= 0) {
      return;
    }

    final rowHeight = size.height / rowCount;
    final speed = plotWidth / _trackWindowMs;
    final elapsedMs = elapsed.inMilliseconds.toDouble();
    final scale = 60.0 / max(1, bpm).toDouble();
    final loopMs = max(1, totalDurationMs).toDouble() * scale;
    final windowMs = _trackWindowMs.toDouble();
    final paint = Paint()..color = _blockColor.withOpacity(0.4);
    final expandedRows = _useExpandedRows(tuningSystem, ragaName);
    final textStyle = (tuningSystem == 'carnatic'
            ? const TextStyle(
                fontFamily: 'RobotoMono',
                fontFeatures: [FontFeature.tabularFigures()],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )
            : const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ))
        .copyWith(color: Colors.white);

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(_labelWidth, 0, plotWidth, size.height),
    );
    final minCycle = 0;
    final maxCycle =
        ((elapsedMs + windowMs) / loopMs).ceil() + 1;
    for (var k = minCycle; k <= maxCycle; k++) {
      final cycleOffset = k * loopMs;
      for (final block in targets) {
        final blockWidth = block.durationMs * scale * speed;
        if (blockWidth <= 0) {
          continue;
        }
        final end = block.startOffsetMs * scale +
            cycleOffset +
            (block.durationMs * scale);
        final rightEdge = nowX - speed * (elapsedMs - end);
        final leftEdge = rightEdge - blockWidth;
        if (rightEdge < _labelWidth || leftEdge > _labelWidth + plotWidth) {
          continue;
        }

        final rowIndex = _rowIndexForMidi(block.midi);
        final semitone = (block.midi % 12 + 12) % 12;
        final splitIndex = expandedRows
            ? 0
            : _preferredSplitIndex(semitone, tuningSystem, ragaName);
        final splitDivisor = expandedRows
            ? 1
            : (_isSplitSemitone(semitone, tuningSystem, ragaName) ? 2 : 1);
        final blockHeight = (rowHeight / splitDivisor) * _blockHeightFactor;
        final top =
            (rowIndex + baseOffset) * rowHeight +
            (splitIndex * (rowHeight / splitDivisor)) -
            (blockHeight - (rowHeight / splitDivisor)) / 2;
        final rect = Rect.fromLTWH(leftEdge, top, blockWidth, blockHeight);
        canvas.drawRect(rect, paint);
        final outline = Paint()
          ..color = Colors.white.withOpacity(0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        canvas.drawRect(rect, outline);

        final textPainter = TextPainter(
          text: TextSpan(
          text: _displayLabel(
            block.label,
            tuningSystem,
            rootSemitone,
            ragaName: ragaName,
          ),
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: max(0, rect.width - 6));
        if (textPainter.width > 0 && textPainter.height > 0) {
          final textOffset = Offset(
            rect.left + (rect.width - textPainter.width) / 2,
            rect.top + (rect.height - textPainter.height) / 2,
          );
          textPainter.paint(canvas, textOffset);
        }
      }
    }
    canvas.restore();
  }

  int _rowIndexForMidi(int midi) {
    final topMidi = baseMidi + rowCount - 1;
    final expandedRows = _useExpandedRows(tuningSystem, ragaName);
    if (expandedRows) {
      final rowIndex =
          _expandedRowIndexForMidi(midi, tuningSystem, ragaName);
      return (topMidi - rowIndex).clamp(0, rowCount - 1);
    }
    if (midi >= topMidi) {
      return 0;
    }
    if (midi <= baseMidi) {
      return rowCount - 1;
    }
    return (topMidi - midi).clamp(0, rowCount - 1);
  }

  @override
  bool shouldRepaint(covariant _TargetNotePainter oldDelegate) {
    return oldDelegate.elapsed != elapsed ||
        oldDelegate.targets != targets ||
        oldDelegate.totalDurationMs != totalDurationMs ||
        oldDelegate.running != running ||
        oldDelegate.bpm != bpm ||
        oldDelegate.baseMidi != baseMidi ||
        oldDelegate.rowCount != rowCount ||
        oldDelegate.baseOffset != baseOffset ||
        oldDelegate.tuningSystem != tuningSystem ||
        oldDelegate.rootSemitone != rootSemitone ||
        oldDelegate.ragaName != ragaName;
  }
}

class _TargetBuildResult {
  const _TargetBuildResult({
    required this.blocks,
    required this.totalDurationMs,
  });

  final List<_TargetBlock> blocks;
  final int totalDurationMs;
}

_TargetBuildResult _targetBlocksFromRecording(
  RecordingEntry entry, {
  required int baseOctave,
  required String tuningSystem,
  required int rootSemitone,
}) {
  final targets = <_TargetBlock>[];
  var offsetMs = 0;
  final semitoneOffset = tuningSystem == 'carnatic' ? rootSemitone : 0;
  for (final note in entry.notes) {
    final normalized = note.note.trim().toLowerCase();
    final midi = _midiFromNoteLabel(normalized, baseOctave);
    if (midi == null) {
      offsetMs += note.durationMs;
      continue;
    }
    final adjustedMidi = (midi + semitoneOffset).clamp(0, 127);
    targets.add(
      _TargetBlock(
        midi: adjustedMidi,
        label: _westernLabelForMidi(adjustedMidi),
        durationMs: note.durationMs,
        startOffsetMs: offsetMs,
      ),
    );
    offsetMs += note.durationMs;
  }
  return _TargetBuildResult(
    blocks: targets,
    totalDurationMs: max(0, offsetMs),
  );
}

int? _midiFromNoteLabel(String note, int baseOctave) {
  if (note.isEmpty) return null;
  final match = RegExp(r'^([a-g])(#?)(-?\d+)$').firstMatch(note);
  if (match == null) return null;
  final name = match.group(1);
  final sharp = match.group(2);
  final octave = int.tryParse(match.group(3) ?? '');
  if (name == null || octave == null) return null;
  final base = switch (name) {
    'c' => 0,
    'd' => 2,
    'e' => 4,
    'f' => 5,
    'g' => 7,
    'a' => 9,
    'b' => 11,
    _ => 0,
  };
  final semitone = base + (sharp == '#' ? 1 : 0);
  final midi = (octave + 1) * 12 + semitone;
  final offset = (baseOctave - PitchNotifier.defaultBaseOctave) * 12;
  return midi + offset;
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

const _westernNoteNamesLower = [
  'c',
  'c#',
  'd',
  'd#',
  'e',
  'f',
  'f#',
  'g',
  'g#',
  'a',
  'a#',
  'b',
];

String _westernLabelForMidi(int midi) {
  final semitone = (midi % 12 + 12) % 12;
  final octave = (midi / 12).floor() - 1;
  return '${_westernNoteLabels[semitone]}$octave';
}

const _carnaticNoteLabels = [
  'Sa',
  'Ri1',
  'Ri2',
  'Ga1',
  'Ga2',
  'Ma1',
  'Ma2',
  'Pa',
  'Da1',
  'Da2',
  'Ni1',
  'Ni2',
];

const _melakartaSemitones = {
  'S': 0,
  'R1': 1,
  'R2': 2,
  'R3': 3,
  'G1': 2,
  'G2': 3,
  'G3': 4,
  'M1': 5,
  'M2': 6,
  'P': 7,
  'D1': 8,
  'D2': 9,
  'D3': 10,
  'N1': 9,
  'N2': 10,
  'N3': 11,
};

const _carnaticTokenLabels = {
  'S': 'Sa',
  'R1': 'Ri1',
  'R2': 'Ri2',
  'R3': 'Ri3',
  'G1': 'Ga1',
  'G2': 'Ga2',
  'G3': 'Ga3',
  'M1': 'Ma1',
  'M2': 'Ma2',
  'P': 'Pa',
  'D1': 'Da1',
  'D2': 'Da2',
  'D3': 'Da3',
  'N1': 'Ni1',
  'N2': 'Ni2',
  'N3': 'Ni3',
};

const _expandedSemitoneOrder = [
  0,
  1,
  2,
  2,
  3,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  9,
  10,
  10,
  11,
];

const _expandedCarnaticLabelOrder = [
  'Sa',
  'Ri1',
  'Ri2',
  'Ga1',
  'Ri3',
  'Ga2',
  'Ga3',
  'Ma1',
  'Ma2',
  'Pa',
  'Da1',
  'Da2',
  'Ni1',
  'Da3',
  'Ni2',
  'Ni3',
];

bool _isExpandedCarnaticScale(String tuningSystem, String? ragaName) {
  if (tuningSystem != 'carnatic') {
    return false;
  }
  if (ragaName == null || ragaName.trim().isEmpty) {
    return false;
  }
  final normalized = _normalizeRagaName(ragaName);
  return normalized != _normalizeRagaName('Mayamalavagowla') &&
      normalized != _normalizeRagaName('Mayamalava gowla');
}

bool _useExpandedRows(String tuningSystem, String? ragaName) {
  return false;
}

int _expandedRowIndexForMidi(
  int midi,
  String tuningSystem,
  String? ragaName,
) {
  if (!_useExpandedRows(tuningSystem, ragaName)) {
    return midi;
  }
  final octave = (midi / 12).floor();
  final semitone = (midi % 12 + 12) % 12;
  final rowInOctave =
      _expandedRowInOctaveForSemitone(semitone, tuningSystem, ragaName);
  return (octave * 16) + rowInOctave;
}

int _expandedRowInOctaveForSemitone(
  int semitone,
  String tuningSystem,
  String? ragaName,
) {
  if (!_useExpandedRows(tuningSystem, ragaName)) {
    return semitone;
  }
  switch (semitone) {
    case 0:
      return 0;
    case 1:
      return 1;
    case 2:
      return 2 + _preferredSplitIndex(semitone, tuningSystem, ragaName);
    case 3:
      return 4 + _preferredSplitIndex(semitone, tuningSystem, ragaName);
    case 4:
      return 6;
    case 5:
      return 7;
    case 6:
      return 8;
    case 7:
      return 9;
    case 8:
      return 10;
    case 9:
      return 11 + _preferredSplitIndex(semitone, tuningSystem, ragaName);
    case 10:
      return 13 + _preferredSplitIndex(semitone, tuningSystem, ragaName);
    case 11:
      return 15;
    default:
      return semitone;
  }
}

int _midiForExpandedIndex(int expandedIndex) {
  final octave = expandedIndex ~/ 16;
  final rowInOctave = expandedIndex % 16;
  final semitone = _expandedSemitoneOrder[rowInOctave.clamp(0, 15)];
  return (octave * 12) + semitone;
}

String _expandedLabelForIndex(int expandedIndex) {
  final rowInOctave = expandedIndex % 16;
  return _expandedCarnaticLabelOrder[rowInOctave.clamp(0, 15)];
}

bool _isSplitSemitone(int semitone, String tuningSystem, String? ragaName) {
  if (tuningSystem != 'carnatic') {
    return false;
  }
  if (ragaName == null || ragaName.trim().isEmpty) {
    return false;
  }
  if (_normalizeRagaName(ragaName) ==
      _normalizeRagaName('Mayamalavagowla')) {
    return false;
  }
  return semitone == 2 || semitone == 3 || semitone == 9 || semitone == 10;
}

List<String> _splitLabelsForSemitone(
  int semitone,
  String tuningSystem,
  String? ragaName,
  List<String> baseLabels,
) {
  if (!_isSplitSemitone(semitone, tuningSystem, ragaName)) {
    return [baseLabels[semitone]];
  }
  switch (semitone) {
    case 2:
      return const ['Ri2', 'Ga1'];
    case 3:
      return const ['Ri3', 'Ga2'];
    case 9:
      return const ['Da2', 'Ni1'];
    case 10:
      return const ['Da3', 'Ni2'];
    default:
      return [baseLabels[semitone]];
  }
}

int _preferredSplitIndex(
  int semitone,
  String tuningSystem,
  String? ragaName,
) {
  if (!_isSplitSemitone(semitone, tuningSystem, ragaName)) {
    return 0;
  }
  final tokens = _ragaTokensFor(ragaName);
  switch (semitone) {
    case 2:
      return tokens.contains('G1') ? 1 : 0;
    case 3:
      return tokens.contains('G2') ? 1 : 0;
    case 9:
      return tokens.contains('N1') ? 1 : 0;
    case 10:
      return tokens.contains('N2') ? 1 : 0;
    default:
      return 0;
  }
}

String _preferredLabelForSemitone(
  int semitone,
  String tuningSystem,
  String? ragaName,
  List<String> baseLabels,
) {
  final labels = _splitLabelsForSemitone(
    semitone,
    tuningSystem,
    ragaName,
    baseLabels,
  );
  if (labels.length == 1) {
    return labels.first;
  }
  final index = _preferredSplitIndex(semitone, tuningSystem, ragaName);
  return labels[index.clamp(0, labels.length - 1)];
}

Set<String> _ragaTokensFor(String? ragaName) {
  if (ragaName == null || ragaName.trim().isEmpty) {
    return {};
  }
  final normalized = _normalizeRagaName(ragaName);
  MelakartaRaga? raga;
  for (final item in melakartaRagas) {
    if (_normalizeRagaName(item.name) == normalized) {
      raga = item;
      break;
    }
  }
  if (raga == null) {
    return {};
  }
  return <String>{
    ...raga.arohanam.split(' '),
    ...raga.avarohanam.split(' '),
  }.map((token) => token.trim()).where((token) => token.isNotEmpty).toSet();
}


List<String> _noteLabelsForSystem(
  String tuningSystem, {
  int rootSemitone = 0,
  String? ragaName,
}) {
  if (tuningSystem != 'carnatic') {
    return _westernNoteLabels;
  }
  final baseLabels = (ragaName != null && ragaName.trim().isNotEmpty)
      ? _ragaAwareCarnaticLabels(ragaName)
      : _carnaticNoteLabels;
  final resolvedLabels = List<String>.generate(baseLabels.length, (index) {
    if (_isSplitSemitone(index, tuningSystem, ragaName)) {
      final parts = _splitLabelsForSemitone(
        index,
        tuningSystem,
        ragaName,
        baseLabels,
      );
      return parts.join('/');
    }
    return baseLabels[index];
  });
  if (rootSemitone == 0) {
    return resolvedLabels;
  }
  return List<String>.generate(
    resolvedLabels.length,
    (index) => resolvedLabels[(index - rootSemitone) % resolvedLabels.length],
  );
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

String _displayLabel(
  String westernNote,
  String tuningSystem,
  int rootSemitone, {
  String? ragaName,
}) {
  if (tuningSystem != 'carnatic') {
    return westernNote.replaceAll(RegExp(r'-?\d+$'), '');
  }
  final match = RegExp(r'^([A-Ga-g])(#?)(-?\d+)$').firstMatch(westernNote);
  if (match == null) {
    return westernNote;
  }
  final name = match.group(1);
  final sharp = match.group(2);
  if (name == null) {
    return westernNote;
  }
  final baseIndex = switch (name.toUpperCase()) {
    'C' => 0,
    'D' => 2,
    'E' => 4,
    'F' => 5,
    'G' => 7,
    'A' => 9,
    'B' => 11,
    _ => 0,
  };
  final semitone = (baseIndex + (sharp == '#' ? 1 : 0)) % 12;
  final labels = _noteLabelsForSystem(
    tuningSystem,
    rootSemitone: rootSemitone,
    ragaName: ragaName,
  );
  return _preferredLabelForSemitone(
    semitone,
    tuningSystem,
    ragaName,
    labels,
  );
}

String _normalizeRagaName(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

List<String> _ragaAwareCarnaticLabels(String ragaName) {
  final normalized = _normalizeRagaName(ragaName);
  if (normalized == _normalizeRagaName('Mayamalavagowla') ||
      normalized == _normalizeRagaName('Mayamalava gowla')) {
    return _carnaticNoteLabels;
  }
  return [
    'Sa', // 0
    'Ri1', // 1
    'Ri2', // 2
    'Ri3', // 3
    'Ga3', // 4
    'Ma1', // 5
    'Ma2', // 6
    'Pa', // 7
    'Da1', // 8
    'Da2', // 9
    'Da3', // 10
    'Ni3', // 11
  ];
}

String _composeDisplayLabel(
  String westernNote,
  String tuningSystem, [
  int rootSemitone = 0,
]) {
  if (tuningSystem != 'carnatic') {
    return westernNote;
  }
  final match = RegExp(r'^([A-G])(#?)(-?\d+)$').firstMatch(westernNote);
  if (match == null) {
    return westernNote;
  }
  final name = match.group(1);
  final sharp = match.group(2);
  final octave = match.group(3);
  if (name == null || octave == null) {
    return westernNote;
  }
  final baseIndex = switch (name) {
    'C' => 0,
    'D' => 2,
    'E' => 4,
    'F' => 5,
    'G' => 7,
    'A' => 9,
    'B' => 11,
    _ => 0,
  };
  final semitone = (baseIndex + (sharp == '#' ? 1 : 0)) % 12;
  final label = _noteLabelsForSystem(
    tuningSystem,
    rootSemitone: rootSemitone,
  )[semitone];
  return '$label$octave';
}

String _formatNoteForEdit(String note, String tuningSystem) {
  final trimmed = note.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (tuningSystem != 'carnatic') {
    return trimmed.toUpperCase().replaceAll(RegExp(r'-?\d+$'), '');
  }
  final carnatic = RegExp(
    r'^(sa|ri1|ri2|ri3|ga1|ga2|ga3|ma1|ma2|pa|da1|da2|da3|ni1|ni2|ni3)-?(\d+)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (carnatic != null) {
    const casing = {
      'sa': 'Sa',
      'ri1': 'Ri1',
      'ri2': 'Ri2',
      'ri3': 'Ri3',
      'ga1': 'Ga1',
      'ga2': 'Ga2',
      'ga3': 'Ga3',
      'ma1': 'Ma1',
      'ma2': 'Ma2',
      'pa': 'Pa',
      'da1': 'Da1',
      'da2': 'Da2',
      'da3': 'Da3',
      'ni1': 'Ni1',
      'ni2': 'Ni2',
      'ni3': 'Ni3',
    };
    final name = (carnatic.group(1) ?? '').toLowerCase();
    final label = casing[name] ?? name.toUpperCase();
    return label;
  }
  final western = RegExp(r'^([A-Ga-g])(#?)(-?\d+)$').firstMatch(trimmed);
  if (western != null) {
    final name = western.group(1);
    final sharp = western.group(2);
    if (name != null) {
      final baseIndex = switch (name.toUpperCase()) {
        'C' => 0,
        'D' => 2,
        'E' => 4,
        'F' => 5,
        'G' => 7,
        'A' => 9,
        'B' => 11,
        _ => 0,
      };
      final semitone = (baseIndex + (sharp == '#' ? 1 : 0)) % 12;
      final noteName = '${name.toUpperCase()}${sharp ?? ''}';
      final label = _carnaticNoteFor(noteName) ?? _carnaticNoteLabels[semitone];
      return label;
    }
  }
  return trimmed.toUpperCase();
}

String _normalizeNoteForStorage(String input, String tuningSystem) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final western = RegExp(r'^([A-Ga-g])(#?)(-?\d+)$').firstMatch(trimmed);
  if (western != null) {
    final name = western.group(1) ?? '';
    final sharp = western.group(2) ?? '';
    final octave = western.group(3) ?? '';
    return '${name.toLowerCase()}$sharp$octave';
  }
  if (tuningSystem == 'carnatic') {
    final carnatic = RegExp(
      r'^(sa|ri1|ri2|ri3|ga1|ga2|ga3|ma1|ma2|pa|da1|da2|da3|ni1|ni2|ni3)-?(\d+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (carnatic != null) {
      final name = (carnatic.group(1) ?? '').toLowerCase();
      final octave = carnatic.group(2) ?? '';
      const labelToToken = {
        'sa': 'S',
        'ri1': 'R1',
        'ri2': 'R2',
        'ri3': 'R3',
        'ga1': 'G1',
        'ga2': 'G2',
        'ga3': 'G3',
        'ma1': 'M1',
        'ma2': 'M2',
        'pa': 'P',
        'da1': 'D1',
        'da2': 'D2',
        'da3': 'D3',
        'ni1': 'N1',
        'ni2': 'N2',
        'ni3': 'N3',
      };
      final token = labelToToken[name];
      final semitone = token == null ? null : _melakartaSemitones[token];
      if (semitone == null) {
        return '';
      }
      final westernNote = _westernNoteNamesLower[semitone];
      return '$westernNote$octave';
    }
  }
  return trimmed.toLowerCase();
}

RegExp _noteInputFormatForSystem(String tuningSystem) {
  if (tuningSystem == 'carnatic') {
    return RegExp(r'[A-Za-z0-9#]');
  }
  return RegExp(r'[A-Za-z0-9#]');
}

String _noteErrorTextForSystem(String tuningSystem) {
  if (tuningSystem == 'carnatic') {
    return 'Enter a valid note (e.g., C#4 or Sa3).';
  }
  return 'Enter a valid Western note (e.g., C#4, A3).';
}

class _ParsedNoteEntry {
  const _ParsedNoteEntry(this.notes, [this.error]);

  final List<RecordedNote> notes;
  final String? error;
}

_ParsedNoteEntry _parseNoteEntry(
  String input, {
  required int bpm,
  required int baseOctave,
  required String tuningSystem,
}) {
  final cleaned = input.replaceAll(RegExp(r'\s+'), '');
  if (cleaned.isEmpty) {
    return const _ParsedNoteEntry([], 'Enter at least one note.');
  }
  final segments = cleaned.split('|');
  final nonEmpty = <String>[];
  final sameBeatWithPrev = <bool>[];
  var seenEmpty = false;
  for (final segment in segments) {
    if (segment.isEmpty) {
      seenEmpty = true;
      continue;
    }
    if (nonEmpty.isEmpty) {
      nonEmpty.add(segment);
    } else {
      sameBeatWithPrev.add(seenEmpty);
      nonEmpty.add(segment);
    }
    seenEmpty = false;
  }
  if (nonEmpty.isEmpty) {
    return const _ParsedNoteEntry([], 'Enter at least one note.');
  }
  final beatGroups = <List<String>>[];
  beatGroups.add([nonEmpty.first]);
  for (var i = 1; i < nonEmpty.length; i++) {
    final sameBeat = sameBeatWithPrev[i - 1];
    if (sameBeat) {
      beatGroups.last.add(nonEmpty[i]);
    } else {
      beatGroups.add([nonEmpty[i]]);
    }
  }

  final beatMs = (60000 / max(1, bpm)).round();
  final notes = <RecordedNote>[];
  for (final group in beatGroups) {
    final tokens = <String>[];
    for (final segment in group) {
      for (var i = 0; i < segment.length; i++) {
        final char = segment[i];
        if (char == '-') {
          tokens.add('-');
          continue;
        }
        if (_isSwaraChar(char)) {
          tokens.add(char);
        }
      }
    }
    final noteTokens = tokens.where((token) => token != '-').toList();
    final dashCount = tokens.length - noteTokens.length;
    if (noteTokens.isEmpty) {
      if (dashCount == 0) {
        continue;
      }
      if (notes.isEmpty) {
        return const _ParsedNoteEntry([], 'Dash without a note.');
      }
      for (var i = 0; i < dashCount; i++) {
        final last = notes.last;
        notes[notes.length - 1] = RecordedNote(
          note: last.note,
          durationMs: last.durationMs + beatMs,
        );
      }
      continue;
    }
    final durations = _splitBeatDurations(beatMs, noteTokens.length);
    var durationIndex = 0;
    for (final token in tokens) {
      if (token == '-') {
        if (notes.isEmpty) {
          return const _ParsedNoteEntry([], 'Dash without a note.');
        }
        final last = notes.last;
        notes[notes.length - 1] = RecordedNote(
          note: last.note,
          durationMs: last.durationMs + beatMs,
        );
        continue;
      }
      final label = _noteLabelFromSwara(
        token,
        baseOctave: baseOctave,
        tuningSystem: tuningSystem,
      );
      if (label == null) {
        return const _ParsedNoteEntry([], 'Unsupported note token.');
      }
      final normalized = _normalizeNoteForStorage(label, tuningSystem);
      if (normalized.isEmpty) {
        return const _ParsedNoteEntry([], 'Unsupported note token.');
      }
      final duration = durations[durationIndex];
      durationIndex++;
      notes.add(RecordedNote(note: normalized, durationMs: duration));
    }
  }

  return _ParsedNoteEntry(notes);
}

bool _isSwaraChar(String value) {
  if (value.isEmpty) return false;
  const swaras = {'S', 'R', 'G', 'M', 'P', 'D', 'N'};
  return swaras.contains(value.toUpperCase());
}

List<int> _splitBeatDurations(int totalMs, int count) {
  if (count <= 0) return const [];
  final base = totalMs ~/ count;
  final remainder = totalMs % count;
  return List<int>.generate(
    count,
    (index) => base + (index < remainder ? 1 : 0),
  );
}

String? _noteLabelFromSwara(
  String token, {
  required int baseOctave,
  required String tuningSystem,
}) {
  const swaras = {'S', 'R', 'G', 'M', 'P', 'D', 'N'};
  if (token.isEmpty) return null;
  final upper = token.toUpperCase();
  if (!swaras.contains(upper)) {
    return null;
  }
  final octave = baseOctave + (token == upper ? 1 : 0);
  if (tuningSystem == 'carnatic') {
    const map = {
      'S': 'Sa',
      'R': 'Ri1',
      'G': 'Ga1',
      'M': 'Ma1',
      'P': 'Pa',
      'D': 'Da1',
      'N': 'Ni1',
    };
    return '${map[upper]}$octave';
  }
  const map = {
    'S': 'C',
    'R': 'C#',
    'G': 'D#',
    'M': 'F',
    'P': 'G',
    'D': 'G#',
    'N': 'A#',
  };
  return '${map[upper]}$octave';
}

String _serializeNotesForEntry(
  List<RecordedNote> notes, {
  required int bpm,
  required int baseOctave,
  required String tuningSystem,
}) {
  if (notes.isEmpty) return '';
  final beatMs = (60000 / max(1, bpm)).round();
  final beats = <String>[];
  final current = <String>[];
  var remainingMs = beatMs;

  void flushCurrent() {
    if (current.isEmpty) return;
    beats.add(current.join(''));
    current.clear();
    remainingMs = beatMs;
  }

  for (final note in notes) {
    final token = _swaraTokenFromStored(
      note.note,
      baseOctave: baseOctave,
      tuningSystem: tuningSystem,
    );
    if (token == null) {
      continue;
    }
    final durationMs = note.durationMs;
    if (durationMs >= beatMs) {
      flushCurrent();
      final beatsCount = max(1, (durationMs / beatMs).round());
      beats.add(token);
      for (var i = 1; i < beatsCount; i++) {
        beats.add('-');
      }
      continue;
    }
    if (durationMs > remainingMs) {
      flushCurrent();
    }
    current.add(token);
    remainingMs -= durationMs;
    if (remainingMs <= 1) {
      flushCurrent();
    }
  }
  flushCurrent();
  return beats.join('|');
}

String? _swaraTokenFromStored(
  String stored, {
  required int baseOctave,
  required String tuningSystem,
}) {
  final match = RegExp(r'^([a-g])(#?)(-?\d+)$').firstMatch(stored);
  if (match == null) return null;
  final name = match.group(1);
  final sharp = match.group(2);
  final octave = int.tryParse(match.group(3) ?? '');
  if (name == null || octave == null) return null;
  final baseIndex = switch (name.toUpperCase()) {
    'C' => 0,
    'D' => 2,
    'E' => 4,
    'F' => 5,
    'G' => 7,
    'A' => 9,
    'B' => 11,
    _ => 0,
  };
  final semitone = (baseIndex + (sharp == '#' ? 1 : 0)) % 12;
  const semitoneToSwara = {
    0: 'S',
    1: 'R',
    3: 'G',
    5: 'M',
    7: 'P',
    8: 'D',
    10: 'N',
  };
  final swara = semitoneToSwara[semitone];
  if (swara == null) return null;
  final useUpper = octave >= baseOctave + 1;
  return useUpper ? swara : swara.toLowerCase();
}

bool _isValidNoteForSystem(String value, String tuningSystem) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  if (tuningSystem == 'carnatic') {
    final carnatic = RegExp(
      r'^(sa|ri1|ri2|ri3|ga1|ga2|ga3|ma1|ma2|pa|da1|da2|da3|ni1|ni2|ni3)-?\d+$',
      caseSensitive: false,
    );
    if (carnatic.hasMatch(trimmed)) {
      return true;
    }
    final western = RegExp(
      r'^[A-Ga-g]#?\d+$',
    );
    return western.hasMatch(trimmed);
  }
  final western = RegExp(
    r'^[A-Ga-g]#?\d+$',
  );
  return western.hasMatch(trimmed);
}

String? _carnaticNoteFor(String value) {
  const mapping = {
    'C': 'Sa',
    'C#': 'Ri1',
    'D': 'Ri2',
    'D#': 'Ri3',
    'E': 'Ga3',
    'F': 'Ma1',
    'F#': 'Ma2',
    'G': 'Pa',
    'G#': 'Da1',
    'A': 'Da2',
    'A#': 'Da3',
    'B': 'Ni3',
    'Sa': 'Sa',
    'Ri1': 'Ri1',
    'Ri2': 'Ri2',
    'Ri3': 'Ri3',
    'Ga1': 'Ga1',
    'Ga2': 'Ga2',
    'Ga3': 'Ga3',
    'Ma1': 'Ma1',
    'Ma2': 'Ma2',
    'Pa': 'Pa',
    'Da1': 'Da1',
    'Da2': 'Da2',
    'Da3': 'Da3',
    'Ni1': 'Ni1',
    'Ni2': 'Ni2',
    'Ni3': 'Ni3',
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
