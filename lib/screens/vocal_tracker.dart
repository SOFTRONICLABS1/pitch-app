import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../dsp/pitch_detection.dart';
import '../models/recording.dart';
import '../services/recording_store.dart';
import '../state/pitch_notifier.dart';
import '../services/headset_service.dart';
import '../widgets/tuner_display.dart';

class VocalTrackerScreen extends StatefulWidget {
  const VocalTrackerScreen({super.key, required this.recording});

  final RecordingEntry recording;

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
  final GlobalKey<_EditableTargetOverlayState> _editOverlayKey =
      GlobalKey<_EditableTargetOverlayState>();
  int _bpm = 60;
  DateTime? _frozenAt;
  int _viewportBaseMidi = 33;
  double _viewportOffset = 0.0;
  static const _viewportRowCount = 30;
  bool _harmonicsEnabled = false;
  bool _editMode = false;
  List<RecordedNote>? _editNotes;
  bool _editDirty = false;
  bool _tanpuraEnabled = false;
  final AudioPlayer _harmonicsPlayer = AudioPlayer();
  Timer? _harmonicsStopTimer;
  int? _currentHarmonicsKey;
  double _lastTargetElapsedMs = 0.0;
  Duration _targetElapsedOffset = Duration.zero;
  double? _screenWidth;
  static const _guidelineFraction = 0.8;
  static const _guidelineOffset = 0.0;
  static const _tunerLabelWidth = 58.0;
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

  @override
  void initState() {
    super.initState();
    _recording = widget.recording;
    final result = _targetBlocksFromRecording(_recording);
    _targets = result.blocks;
    _totalDurationMs = result.totalDurationMs;
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
    if (_editMode) return;
    if (_running) {
      await _handleStop(context.read<PitchNotifier>());
    }
    setState(() {
      _editMode = true;
      _editNotes = List<RecordedNote>.from(_recording.notes);
      _editDirty = false;
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

  static const _minDurationMs = 0;
  static const _defaultInsertDurationMs = 1000;

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
        if (remainder >= (beatMs / 2)) {
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
    final result = _targetBlocksFromRecording(updated);
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PitchNotifier>();
    final frequency = state.frequency;
    final note = frequency == null
        ? '--'
        : _noteLabel(frequency, state.tuningSystem);
    final noteLabels = _noteLabelsForSystem(state.tuningSystem);
    final labelStyle = _labelStyleForSystem(state.tuningSystem);
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
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: _clearAllEditNotes,
              ),
            IconButton(
              icon: const Icon(Icons.tune),
              onPressed: _showBpmSettings,
            ),
          ],
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
                hasScrollBody: true,
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          TunerDisplay(
                            history: _filteredHistory(state.history),
                            showBlocks: false,
                            showLabels: !_editMode,
                            nowOverride: _running ? null : _frozenAt,
                            noteLabels: noteLabels,
                            labelTextStyle: labelStyle,
                            rowCount: _viewportRowCount,
                            guidelineFraction: _guidelineFraction,
                            guidelineOffset: _guidelineOffset,
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
                            rowCount: _viewportRowCount,
                            baseOffset: _viewportOffset,
                            tuningSystem: state.tuningSystem,
                            guidelineFraction: _guidelineFraction,
                            guidelineOffset: _guidelineOffset,
                          ),
                              if (_editMode)
                                Positioned.fill(
                                  child: _EditableTargetOverlay(
                                    key: _editOverlayKey,
                                    notes: _editNotes ?? _recording.notes,
                                    tuningSystem: state.tuningSystem,
                                    baseMidi: 21,
                                    rowCount: _viewportRowCount,
                                    baseOffset: 0.0,
                                    labelWidth: _tunerLabelWidth,
                                    guidelineFraction: _guidelineFraction,
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
                                    bpm: _bpm,
                                  ),
                                ),
                        ],
                      ),
                    ),
                    _PlayPauseBar(
                      listening: state.listening,
                      errorMessage: state.errorMessage,
                      onStart: () => _handleStart(state),
                      onStop: () => _handleStop(state),
                      onEdit: _openEditRecording,
                      editMode: _editMode,
                      onConfirmEdit: () => _saveEditMode(),
                      onCancelEdit: () => _cancelEditMode(),
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
    for (var k = minCycle; k <= maxCycle; k++) {
      final cycleOffset = k * loopMs;
      for (var i = 0; i < _targets.length; i++) {
        final start = _targets[i].startOffsetMs * scale + cycleOffset;
        final duration = _targets[i].durationMs * scale;
        final end = start + duration;
        final overlaps = end >= previousElapsedMs && start <= elapsedMs;
        if (!overlaps) {
          continue;
        }
        if (bestStart == null || start < bestStart) {
          bestStart = start;
          index = i;
          cycleIndex = k;
          durationMs = duration;
        }
      }
    }

    if (index == null || durationMs == null || cycleIndex == null) {
      return;
    }
    final key = cycleIndex * 10000 + index;
    if (_currentHarmonicsKey == key) {
      return;
    }
    _currentHarmonicsKey = key;
    _playHarmonicFor(_targets[index], durationMs);
  }

  void _playHarmonicFor(_TargetBlock block, double durationMs) {
    final path = _harmonicsAssetForMidi(block.midi);
    if (path == null) {
      return;
    }
    _harmonicsStopTimer?.cancel();
    _harmonicsPlayer.stop();
    _harmonicsPlayer.play(AssetSource(path), volume: 1.0);
    final duration = durationMs.clamp(50, 600000).toDouble();
    _harmonicsMidi = block.midi;
    _harmonicsWindowStart = DateTime.now();
    _harmonicsWindowEnd =
        _harmonicsWindowStart!.add(Duration(milliseconds: duration.round()));
    _harmonicsStopTimer = Timer(
      Duration(milliseconds: duration.round()),
      () {
        _harmonicsPlayer.stop();
      },
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
    _harmonicsPlayer.stop();
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
    required this.onConfirmEdit,
    required this.onCancelEdit,
  });

  final bool listening;
  final String? errorMessage;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onEdit;
  final bool editMode;
  final VoidCallback onConfirmEdit;
  final VoidCallback onCancelEdit;

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
                if (!editMode)
                  IconButton(
                    icon: Icon(
                      listening ? Icons.pause : Icons.play_arrow,
                      size: 36,
                    ),
                    onPressed: listening ? onStop : onStart,
                  ),
                if (editMode)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: onCancelEdit,
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: Icon(
                      editMode ? Icons.check : Icons.edit_outlined,
                    ),
                    onPressed: editMode ? onConfirmEdit : onEdit,
                  ),
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
    required this.guidelineFraction,
    required this.guidelineOffset,
    required this.scrollController,
    required this.verticalController,
    required this.onDelete,
    required this.onDurationDrag,
    required this.onInsertNotes,
    required this.bpm,
  });

  final List<RecordedNote> notes;
  final String tuningSystem;
  final int baseMidi;
  final int rowCount;
  final double baseOffset;
  final double labelWidth;
  final double guidelineFraction;
  final double guidelineOffset;
  final ScrollController scrollController;
  final ScrollController verticalController;
  final ValueChanged<int> onDelete;
  final void Function(int index, int deltaMs, bool commit) onDurationDrag;
  final void Function(int insertIndex, List<String> notes) onInsertNotes;
  final int bpm;

  static const _msToWidth = 0.08;
  static const _minTileWidth = 24.0;
  static const _defaultInsertDurationMs = 1000;

  @override
  State<_EditableTargetOverlay> createState() => _EditableTargetOverlayState();
}

class _EditableTargetOverlayState extends State<_EditableTargetOverlay> {
  bool _syncedVertical = false;
  bool _syncedHorizontal = false;
  final Map<int, double> _dragRemainderByIndex = {};
  int? _pendingInsertIndex;
  int? _pendingInsertMidi;
  double _currentScale = _EditableTargetOverlay._msToWidth;

  @override
  void didUpdateWidget(covariant _EditableTargetOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notes != widget.notes) {
      _syncedHorizontal = false;
      _syncedVertical = false;
      _pendingInsertIndex = null;
      _pendingInsertMidi = null;
    }
  }

  void _queueInsert(int insertIndex) {
    setState(() {
      _pendingInsertIndex = insertIndex;
      _pendingInsertMidi = null;
    });
  }

  void queueInsertAtEnd() {
    _queueInsert(widget.notes.length);
  }

  void clearPendingInsert() {
    setState(() {
      _pendingInsertIndex = null;
      _pendingInsertMidi = null;
    });
  }

  void _commitInsertWithLabel(String label) {
    final insertIndex = _pendingInsertIndex;
    if (insertIndex == null) return;
    widget.onInsertNotes(insertIndex, [label]);
    setState(() {
      _pendingInsertIndex = null;
      _pendingInsertMidi = null;
    });
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
        final scale = _EditableTargetOverlay._msToWidth;
        final bpm = max(1, widget.bpm);
        final gridMs = 60000.0 / bpm;
        _currentScale = scale;
        final pendingExtraMs = _pendingInsertIndex == null ? 0.0 : gridMs;
        final nowX =
            constraints.maxWidth * guidelineFraction + guidelineOffset;
        final plotRightPadding =
            (constraints.maxWidth - nowX).clamp(0.0, constraints.maxWidth);
        final plotWidth = max(
          0.0,
          constraints.maxWidth - labelWidth - plotRightPadding,
        );
        final width = max(plotWidth, (totalMs + pendingExtraMs) * scale)
            .toDouble();
        final rowHeight = rowCount > 0 ? viewportHeight / rowCount : 0.0;
        final topMidi = baseMidi + rowCount - 1;
        const minMidi = 21;
        const maxMidi = 108;
        final extraAboveRows = max(0, maxMidi - topMidi);
        final extraBelowRows = max(0, baseMidi - minMidi);
        final totalRows = rowCount + extraAboveRows + extraBelowRows;
        final extendedTopMidi = topMidi + extraAboveRows;
        final contentHeight = rowHeight * totalRows;
        if (!_syncedVertical) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !verticalController.hasClients) return;
            final firstMidi = notes.isNotEmpty
                ? _midiFromNoteLabel(notes.first.note)
                : null;
            final targetTop = _rowTopFor(
              midiFromNote: firstMidi,
              topMidi: extendedTopMidi,
              baseOffset: baseOffset,
              rowHeight: rowHeight,
            );
            final fallbackTop = extraAboveRows * rowHeight;
            final targetOffset = firstMidi == null ? fallbackTop : targetTop;
            verticalController.jumpTo(
              targetOffset.clamp(
                0.0,
                max(0.0, contentHeight - viewportHeight),
              ),
            );
          });
          _syncedVertical = true;
        }
        if (!_syncedHorizontal) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !scrollController.hasClients) return;
            scrollController.jumpTo(0.0);
          });
          _syncedHorizontal = true;
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
          blocks.add(
            _EditableTargetBlock(
              index: i,
              note: note,
              tuningSystem: tuningSystem,
              x: x,
              width: max(
                note.durationMs * scale,
                _EditableTargetOverlay._minTileWidth,
              ).toDouble(),
              top: _rowTopFor(
                midiFromNote: _midiFromNoteLabel(note.note),
                topMidi: extendedTopMidi,
                baseOffset: baseOffset,
                rowHeight: rowHeight,
              ),
              height: rowHeight,
              onDelete: widget.onDelete,
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
        final noteLabels = _noteLabelsForSystem(tuningSystem);
        const sharpSemitones = {1, 3, 6, 8, 10};
        final labelRows = <Widget>[];
        for (var i = 0; i < totalRows; i++) {
          final midi = extendedTopMidi - i;
          final semitone = (midi % 12 + 12) % 12;
          final octave = (midi / 12).floor() - 1;
          final label = '${noteLabels[semitone]}$octave';
          final isSharp = sharpSemitones.contains(semitone);
          final baseStyle = labelStyle ??
              TextStyle(
                color: isSharp ? Colors.white : Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              );
          final resolvedStyle =
              baseStyle.copyWith(color: isSharp ? Colors.white : Colors.black87);
          labelRows.add(
            Positioned(
              left: 0,
              right: 0,
              top: (i + baseOffset) * rowHeight,
              height: rowHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _commitInsertWithLabel(label),
                child: Container(
                  color: isSharp ? Colors.black : const Color(0xFFCBD1D6),
                  alignment: Alignment.center,
                  child: Text(label, style: resolvedStyle),
                ),
              ),
            ),
          );
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
                  final midi =
                      (extendedTopMidi - rowIndex).clamp(minMidi, maxMidi);
                  setState(() {
                    _pendingInsertMidi = midi;
                  });
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
                            child: Stack(children: blocks),
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
  }) {
    final midi = midiFromNote ?? topMidi;
    final rowIndex = topMidi - midi;
    return (rowIndex + baseOffset) * rowHeight;
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
        Positioned(
          left: x - (handleWidth / 2),
          bottom: 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showHandle)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    if (dragIndex == null) return;
                    final delta = details.delta.dx;
                    final remainder = _dragRemainderByIndex[dragIndex] ?? 0.0;
                    final totalDelta = remainder + delta;
                    final rawMs = totalDelta / _currentScale;
                    final deltaMs = rawMs > 0 ? rawMs.floor() : rawMs.ceil();
                    if (deltaMs == 0) {
                      _dragRemainderByIndex[dragIndex] = totalDelta;
                      return;
                    }
                    final consumedPx = deltaMs * _currentScale;
                    _dragRemainderByIndex[dragIndex] = totalDelta - consumedPx;
                    widget.onDurationDrag(dragIndex, deltaMs, false);
                  },
                  onHorizontalDragEnd: (_) {
                    if (dragIndex == null) return;
                    _dragRemainderByIndex.remove(dragIndex);
                    widget.onDurationDrag(dragIndex, 0, true);
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

class _EditableTargetBlock extends StatelessWidget {
  const _EditableTargetBlock({
    required this.index,
    required this.note,
    required this.tuningSystem,
    required this.x,
    required this.width,
    required this.top,
    required this.height,
    required this.onDelete,
  });

  final int index;
  final RecordedNote note;
  final String tuningSystem;
  final double x;
  final double width;
  final double top;
  final double height;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    final label = _formatNoteForEdit(note.note, tuningSystem);
    return Positioned(
      left: x,
      top: top,
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2B6BFF).withOpacity(0.4),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => onDelete(index),
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 18,
                    height: 18,
                    child: Icon(Icons.close, size: 18),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
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
  static const _defaultOctave = 3;
  static const _minOctave = 1;
  static const _maxOctave = 8;

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
  static const _defaultOctave = 3;

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

String _noteLabel(double frequency, String tuningSystem) {
  final labels = _noteLabelsForSystem(tuningSystem);
  final midi = midiFromFrequency(frequency).round().clamp(0, 127);
  final octave = (midi / 12).floor() - 1;
  final label = labels[midi % 12];
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
  final double guidelineFraction;
  final double guidelineOffset;

  static const _labelWidth = 58.0;
  static const _trackWindowMs = 6400.0;
  static const _blockColor = Color(0xFF2B6BFF);

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
    final textStyle = (tuningSystem == 'carnatic'
            ? const TextStyle(
                fontFamily: 'RobotoMono',
                fontFeatures: [FontFeature.tabularFigures()],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )
            : const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
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
        final blockHeight = rowHeight;
      final top = (rowIndex + baseOffset) * rowHeight;
        final rect = Rect.fromLTWH(leftEdge, top, blockWidth, blockHeight);
        canvas.drawRect(rect, paint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: _displayLabel(block.label, tuningSystem),
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
        oldDelegate.tuningSystem != tuningSystem;
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

_TargetBuildResult _targetBlocksFromRecording(RecordingEntry entry) {
  final targets = <_TargetBlock>[];
  var offsetMs = 0;
  for (final note in entry.notes) {
    final normalized = note.note.trim().toLowerCase();
    final midi = _midiFromNoteLabel(normalized);
    if (midi == null) {
      offsetMs += note.durationMs;
      continue;
    }
    if (targets.isNotEmpty && targets.last.midi == midi) {
      final last = targets.removeLast();
      targets.add(
        _TargetBlock(
          midi: last.midi,
          label: last.label,
          durationMs: last.durationMs + note.durationMs,
          startOffsetMs: last.startOffsetMs,
        ),
      );
      offsetMs += note.durationMs;
      continue;
    }
    targets.add(
      _TargetBlock(
        midi: midi,
        label: note.note.toUpperCase(),
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

int? _midiFromNoteLabel(String note) {
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
  return (octave + 1) * 12 + semitone;
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

String _displayLabel(String westernNote, String tuningSystem) {
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
  final label = _carnaticNoteLabels[semitone];
  return '$label$octave ($westernNote)';
}

String _composeDisplayLabel(String westernNote, String tuningSystem) {
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
  final label = _carnaticNoteLabels[semitone];
  return '$label$octave';
}

String _formatNoteForEdit(String note, String tuningSystem) {
  final trimmed = note.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (tuningSystem != 'carnatic') {
    return trimmed.toUpperCase();
  }
  final carnatic = RegExp(
    r'^(sa|ri1|ri2|ga1|ga2|ma1|ma2|pa|da1|da2|ni1|ni2)-?(\d+)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (carnatic != null) {
    const casing = {
      'sa': 'Sa',
      'ri1': 'Ri1',
      'ri2': 'Ri2',
      'ga1': 'Ga1',
      'ga2': 'Ga2',
      'ma1': 'Ma1',
      'ma2': 'Ma2',
      'pa': 'Pa',
      'da1': 'Da1',
      'da2': 'Da2',
      'ni1': 'Ni1',
      'ni2': 'Ni2',
    };
    final name = (carnatic.group(1) ?? '').toLowerCase();
    final octave = carnatic.group(2) ?? '';
    final label = casing[name] ?? name.toUpperCase();
    return '$label-$octave';
  }
  final western = RegExp(r'^([A-Ga-g])(#?)(-?\d+)$').firstMatch(trimmed);
  if (western != null) {
    final name = western.group(1);
    final sharp = western.group(2);
    final octave = western.group(3);
    if (name != null && octave != null) {
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
      final label = _carnaticNoteLabels[semitone];
      return '$label$octave';
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
      r'^(sa|ri1|ri2|ga1|ga2|ma1|ma2|pa|da1|da2|ni1|ni2)-?(\d+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (carnatic != null) {
      final name = (carnatic.group(1) ?? '').toLowerCase();
      final octave = carnatic.group(2) ?? '';
      const map = {
        'sa': 'c',
        'ri1': 'c#',
        'ri2': 'd',
        'ga1': 'd#',
        'ga2': 'e',
        'ma1': 'f',
        'ma2': 'f#',
        'pa': 'g',
        'da1': 'g#',
        'da2': 'a',
        'ni1': 'a#',
        'ni2': 'b',
      };
      final westernNote = map[name] ?? 'c';
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

bool _isValidNoteForSystem(String value, String tuningSystem) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  if (tuningSystem == 'carnatic') {
    final carnatic = RegExp(
      r'^(sa|ri1|ri2|ga1|ga2|ma1|ma2|pa|da1|da2|ni1|ni2)-?\d+$',
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
