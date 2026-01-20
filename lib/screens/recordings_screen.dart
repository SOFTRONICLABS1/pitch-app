import 'dart:async';
import 'dart:ui';

import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/melakarta_ragas.dart';
import '../data/varisai_sequences.dart';
import '../models/recording.dart';
import '../services/recording_store.dart';
import '../state/pitch_notifier.dart';
import 'gamified_game_menu.dart';
import 'vocal_tracker.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key, this.onSelect});

  final ValueChanged<RecordingEntry>? onSelect;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<RecordingEntry> _recordings = [];
  bool _loading = true;
  static final _defaultRecordingIds = {
    'default-swaravalis-sarale-1',
    'default-swaravalis-sarale-2',
    'default-swaravalis-sarale-3',
    'default-swaravalis-sarale-4',
    'default-swaravalis-sarale-5',
    'default-swaravalis-sarale-6',
    'default-swaravalis-sarale-7',
    'default-swaravalis-sarale-8',
    'default-swaravalis-sarale-9',
    'default-swaravalis-sarale-10',
    'default-swaravalis-sarale-11',
    'default-swaravalis-sarale-12',
    'default-swaravalis-sarale-13',
    'default-swaravalis-sarale-14',
    'default-swaravalis-janta-1',
    'default-swaravalis-janta-2',
    'default-swaravalis-janta-3',
    'default-swaravalis-janta-4',
    'default-swaravalis-janta-5',
    'default-swaravalis-janta-6',
    'default-swaravalis-janta-7',
    'default-swaravalis-janta-8',
    'default-swaravalis-janta-9',
    'default-swaravalis-janta-10',
    'default-swaravalis-janta-11',
    'default-swaravalis-janta-12',
    'default-swaravalis-daatu-1',
    'default-swaravalis-daatu-2',
    'default-swaravalis-daatu-3',
    'default-swaravalis-melstaayi-1',
    'default-swaravalis-melstaayi-2',
    'default-swaravalis-melstaayi-3',
    'default-swaravalis-melstaayi-4',
    'default-swaravalis-melstaayi-5',
    'default-swaravalis-mandra-1',
    'default-swaravalis-mandra-2',
    'default-swaravalis-mandra-3',
    'default-swaravalis-mandra-4',
    'default-swaravalis-mandra-5',
    'default-swaravalis-alankaaram-1',
    'default-swaravalis-alankaaram-2',
    'default-swaravalis-alankaaram-3',
    'default-swaravalis-alankaaram-4',
    'default-swaravalis-alankaaram-5',
    'default-swaravalis-alankaaram-6',
    'default-swaravalis-alankaaram-7',
    'default-swaravalis-alankaaram-8',
    'default-swaravalis-alankaaram-9',
  }..addAll(
      List.generate(72, (index) => 'default-melakarta-${index + 1}'),
    );
  static const _ungroupedLabel = 'Ungrouped';
  static const _swaravalisGroup = 'Swaravalis';
  static const _swaravalisSubgroupOrder = [
    'Sarale Varase',
    'Janti Varase',
    'Daatu Varase',
    'Thara Staayi Varase',
    'Mandra Staayi Varisai',
    'Alankaara',
  ];
  static const _swaravalisLegacySubgroups = [
    'Sarale Varisai',
    'Janta Varisai',
    'Daatu Varisai',
    'Melstaayi Varisai',
    'Mandra Staayi Varisai',
    'Alankaaram',
  ];
  static const _swaravalisSubgroupRename = {
    'Sarale Varisai': 'Sarale Varase',
    'Sarale Varasai': 'Sarale Varase',
    'Sarali Varase': 'Sarale Varase',
    'Sarali Varasai': 'Sarale Varase',
    'Janta Varisai': 'Janti Varase',
    'Daatu Varisai': 'Daatu Varase',
    'Melstaayi Varisai': 'Thara Staayi Varase',
    'Mandra Staayi Varisai': 'Mandra Staayi Varisai',
    'Mandra Staaayi Varisai': 'Mandra Staayi Varisai',
    'Mandra Staayi Varasai': 'Mandra Staayi Varisai',
    'Alankaaram': 'Alankaara',
  };
  _RecordingSort _sortOrder = _RecordingSort.nameAsc;
  final Map<String, _GroupSettings> _groupSettings = {};
  final AudioPlayer _inlinePlayer = AudioPlayer();
  Timer? _inlineTicker;
  Stopwatch? _inlineStopwatch;
  List<_InlineTargetBlock> _inlineTargets = [];
  int _inlineTotalDurationMs = 0;
  double _inlineLastTargetElapsedMs = 0.0;
  int? _inlineHarmonicsKey;
  Timer? _inlineHarmonicsStopTimer;
  double _inlineScale = 1.0;
  String? _playingId;
  int _inlinePlaybackToken = 0;
  bool _inlinePlaying = false;
  bool _inlinePaused = false;
  static const _melakartaBaseOctave = 3;
  static const _melakartaNoteNames = [
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
  static const _melakartaSemitones = {
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
  static const _defaultSwaraForSemitone = {
    0: 'S',
    1: 'R',
    4: 'G',
    5: 'M',
    7: 'P',
    8: 'D',
    11: 'N',
  };
  static const _defaultRagaSemitones = {
    'S': 0,
    'R': 1,
    'G': 4,
    'M': 5,
    'P': 7,
    'D': 8,
    'N': 11,
  };

  @override
  void initState() {
    super.initState();
    _inlinePlayer.setReleaseMode(ReleaseMode.stop);
    _inlinePlayer.setPlayerMode(PlayerMode.lowLatency);
    _load();
  }

  @override
  void dispose() {
    _inlinePlaybackToken++;
    _inlineTicker?.cancel();
    _inlineHarmonicsStopTimer?.cancel();
    _inlinePlayer.stop();
    _inlinePlayer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await RecordingStore.instance.load();
    final normalizedList = list.map(_normalizeLegacyId).toList();
    final savedById = <String, RecordingEntry>{
      for (final entry in normalizedList) entry.id: entry,
    };
    final defaults = _buildDefaultRecordings();
    final merged = [
      for (final entry in defaults) savedById[entry.id] ?? entry,
      for (final entry in normalizedList)
        if (!_defaultRecordingIds.contains(entry.id)) entry,
    ]
        .where(
          (entry) =>
              entry.id != 'default-mayamalavagowla' &&
              entry.id != 'default-swaravalis-sarale' &&
              entry.id != 'default-mayamalavagowla-sarale' &&
              entry.id != 'default-saralavalis-sarale' &&
              entry.group != 'Melakarta Ragas',
        )
        .map(_normalizeSwaravalisEntry)
        .toList();
    final saraleNames = <String>{};
    final deduped = <RecordingEntry>[];
    for (final entry in merged) {
      if (entry.group == _swaravalisGroup &&
          entry.subgroup == 'Sarale Varase') {
        if (saraleNames.add(entry.name)) {
          deduped.add(entry);
        }
        continue;
      }
      deduped.add(entry);
    }
    if (!mounted) return;
    setState(() {
      _recordings = deduped;
      _loading = false;
    });
  }

  List<RecordingEntry> _buildDefaultRecordings() {
    const beatMs = 1000;
    const notes = [
      RecordedNote(note: 'c3', durationMs: beatMs), // Sa
      RecordedNote(note: 'c#3', durationMs: beatMs), // Ri1
      RecordedNote(note: 'e3', durationMs: beatMs), // Ga2
      RecordedNote(note: 'f3', durationMs: beatMs), // Ma1
      RecordedNote(note: 'g3', durationMs: beatMs), // Pa
      RecordedNote(note: 'g#3', durationMs: beatMs), // Da1
      RecordedNote(note: 'b3', durationMs: beatMs), // Ni2
      RecordedNote(note: 'c4', durationMs: beatMs), // Sa
      RecordedNote(note: 'b3', durationMs: beatMs), // Ni2
      RecordedNote(note: 'g#3', durationMs: beatMs), // Da1
      RecordedNote(note: 'g3', durationMs: beatMs), // Pa
      RecordedNote(note: 'f3', durationMs: beatMs), // Ma1
      RecordedNote(note: 'e3', durationMs: beatMs), // Ga2
      RecordedNote(note: 'c#3', durationMs: beatMs), // Ri1
      RecordedNote(note: 'c3', durationMs: beatMs), // Sa
    ];
    return [
      for (var i = 0; i < saraleVaraseSequences.length; i++)
        RecordingEntry(
          id: 'default-swaravalis-sarale-${i + 1}',
          name:
              'Swaravalis Sarale Varase ${(i + 1).toString().padLeft(3, '0')}',
          createdAt: DateTime(2000, 1, 1),
          notes: _buildSaraleVaraseNotes(beatMs, index: i),
          group: _swaravalisGroup,
          subgroup: 'Sarale Varase',
        ),
      for (var i = 0; i < jantaVarisaiSequences.length; i++)
        RecordingEntry(
          id: 'default-swaravalis-janta-${i + 1}',
          name:
              'Swaravalis Janti Varase ${(i + 1).toString().padLeft(3, '0')}',
          createdAt: DateTime(2000, 1, 1),
          notes: _buildJantaVarisaiNotes(beatMs, index: i),
          group: _swaravalisGroup,
          subgroup: 'Janti Varase',
        ),
      for (var i = 0; i < daatuVarisaiSequences.length; i++)
        RecordingEntry(
          id: 'default-swaravalis-daatu-${i + 1}',
          name:
              'Swaravalis Daatu Varase ${(i + 1).toString().padLeft(3, '0')}',
          createdAt: DateTime(2000, 1, 1),
          notes: _buildDaatuVarisaiNotes(beatMs, index: i),
          group: _swaravalisGroup,
          subgroup: 'Daatu Varase',
        ),
      for (var i = 0; i < melstaayiVarisaiSequences.length; i++)
        RecordingEntry(
          id: 'default-swaravalis-melstaayi-${i + 1}',
          name:
              'Swaravalis Thara Staayi Varase ${(i + 1).toString().padLeft(3, '0')}',
          createdAt: DateTime(2000, 1, 1),
          notes: _buildMelstaayiVarisaiNotes(beatMs, index: i),
          group: _swaravalisGroup,
          subgroup: 'Thara Staayi Varase',
        ),
      for (var i = 0; i < mandraStaayiVarisaiSequences.length; i++)
        RecordingEntry(
          id: 'default-swaravalis-mandra-${i + 1}',
          name:
              'Swaravalis Mandra Staayi Varisai ${(i + 1).toString().padLeft(3, '0')}',
          createdAt: DateTime(2000, 1, 1),
          notes: _buildMandraStaayiVarisaiNotes(beatMs, index: i),
          group: _swaravalisGroup,
          subgroup: 'Mandra Staayi Varisai',
        ),
      for (var i = 0; i < alankaaramSequences.length; i++)
        RecordingEntry(
          id: 'default-swaravalis-alankaaram-${i + 1}',
          name:
              'Swaravalis Alankaara ${(i + 1).toString().padLeft(3, '0')}',
          createdAt: DateTime(2000, 1, 1),
          notes: _buildAlankaaramNotes(beatMs, index: i),
          group: _swaravalisGroup,
          subgroup: 'Alankaara',
        ),
      for (final raga in melakartaRagas)
        RecordingEntry(
          id: 'default-melakarta-${raga.number}',
          name:
              '${raga.number.toString().padLeft(3, '0')} ${raga.name}'.trim(),
          createdAt:
              DateTime(2000, 1, 1).add(Duration(seconds: raga.number)),
          notes: _buildMelakartaNotes(raga, beatMs),
          group: 'Melakarta Ragas',
        ),
    ];
  }

  RecordingEntry _normalizeLegacyId(RecordingEntry entry) {
    final id = entry.id;
    String? nextId;
    final match = RegExp(
      r'^default-(?:mayamalavagowla|saralavalis)-(sarale|janta|daatu|melstaayi|mandra|alankaaram)(?:-(\\d+))?$',
    ).firstMatch(id);
    if (match != null) {
      final suffix = match.group(1);
      final index = match.group(2);
      if (index != null) {
        nextId = 'default-swaravalis-$suffix-$index';
      }
    }
    if (nextId == null || nextId == id) {
      return entry;
    }
    return RecordingEntry(
      id: nextId,
      name: entry.name,
      createdAt: entry.createdAt,
      notes: entry.notes,
      group: entry.group,
      subgroup: entry.subgroup,
    );
  }

  RecordingEntry _normalizeSwaravalisEntry(RecordingEntry entry) {
    if (entry.group?.trim() != 'Mayamalavagowla' &&
        entry.group?.trim() != 'Saralavalis' &&
        entry.group?.trim() != _swaravalisGroup) {
      return entry;
    }
    final nextGroup = _swaravalisGroup;
    final nextSubgroup = _swaravalisSubgroupRename[entry.subgroup] ??
        (entry.subgroup?.trim().isEmpty == true ? null : entry.subgroup);
    final nextName = entry.name.startsWith('Mayamalavagowla ')
        ? entry.name.replaceFirst('Mayamalavagowla ', 'Swaravalis ')
        : (entry.name.startsWith('Saralavalis ')
            ? entry.name.replaceFirst('Saralavalis ', 'Swaravalis ')
            : entry.name);
    if (entry.group == nextGroup &&
        entry.subgroup == nextSubgroup &&
        entry.name == nextName) {
      return entry;
    }
    return RecordingEntry(
      id: entry.id,
      name: nextName,
      createdAt: entry.createdAt,
      notes: entry.notes,
      group: nextGroup,
      subgroup: nextSubgroup,
    );
  }

  List<RecordedNote> _buildSaraleVaraseNotes(
    int beatMs, {
    int? index,
  }) {
    final sequences = index == null
        ? saraleVaraseSequences
        : [
            saraleVaraseSequences[index],
          ];
    final notes = <RecordedNote>[];
    for (final group in sequences) {
      for (final line in group) {
        _appendSaraleLine(notes, line, beatMs);
      }
    }
    return notes;
  }

  List<RecordedNote> _buildJantaVarisaiNotes(
    int beatMs, {
    int? index,
  }) {
    final sequences = index == null
        ? jantaVarisaiSequences
        : [
            jantaVarisaiSequences[index],
          ];
    final notes = <RecordedNote>[];
    for (final group in sequences) {
      for (final line in group) {
        _appendSaraleLine(notes, line, beatMs);
      }
    }
    return notes;
  }

  List<RecordedNote> _buildDaatuVarisaiNotes(
    int beatMs, {
    int? index,
  }) {
    final sequences = index == null
        ? daatuVarisaiSequences
        : [
            daatuVarisaiSequences[index],
          ];
    final notes = <RecordedNote>[];
    for (final group in sequences) {
      for (final line in group) {
        _appendSaraleLine(notes, line, beatMs);
      }
    }
    return notes;
  }

  List<RecordedNote> _buildMelstaayiVarisaiNotes(
    int beatMs, {
    int? index,
  }) {
    final sequences = index == null
        ? melstaayiVarisaiSequences
        : [
            melstaayiVarisaiSequences[index],
          ];
    final notes = <RecordedNote>[];
    for (final group in sequences) {
      for (final line in group) {
        _appendSaraleLine(notes, line, beatMs);
      }
    }
    return notes;
  }

  List<RecordedNote> _buildMandraStaayiVarisaiNotes(
    int beatMs, {
    int? index,
  }) {
    final sequences = index == null
        ? mandraStaayiVarisaiSequences
        : [
            mandraStaayiVarisaiSequences[index],
          ];
    final notes = <RecordedNote>[];
    for (final group in sequences) {
      for (final line in group) {
        _appendSaraleLine(notes, line, beatMs);
      }
    }
    return notes;
  }

  List<RecordedNote> _buildAlankaaramNotes(
    int beatMs, {
    int? index,
  }) {
    final sequences = index == null
        ? alankaaramSequences
        : [
            alankaaramSequences[index],
          ];
    final notes = <RecordedNote>[];
    for (final group in sequences) {
      for (final line in group) {
        _appendSaraleLine(notes, line, beatMs);
      }
    }
    return notes;
  }

  List<RecordedNote> _buildMelakartaNotes(
    MelakartaRaga raga,
    int beatMs,
  ) {
    final asc = _melakartaNotesFromTokens(
      raga.arohanam.split(' '),
      ascending: true,
      startOctave: _melakartaBaseOctave,
    );
    final desc = _melakartaNotesFromTokens(
      raga.avarohanam.split(' '),
      ascending: false,
      startOctave: _melakartaBaseOctave + 1,
    );
    return [
      for (final note in asc) RecordedNote(note: note, durationMs: beatMs),
      for (final note in desc) RecordedNote(note: note, durationMs: beatMs),
    ];
  }

  List<String> _melakartaNotesFromTokens(
    List<String> tokens, {
    required bool ascending,
    required int startOctave,
  }) {
    final notes = <String>[];
    var octave = startOctave;
    int? prevSemitone;
    for (final raw in tokens) {
      final token = raw.trim();
      if (token.isEmpty) continue;
      final semitone = _melakartaSemitones[token];
      if (semitone == null) continue;
      if (prevSemitone != null) {
        if (ascending && semitone < prevSemitone) {
          octave += 1;
        } else if (!ascending && semitone > prevSemitone) {
          octave -= 1;
        }
      }
      prevSemitone = semitone;
      notes.add('${_melakartaNoteNames[semitone]}$octave');
    }
    return notes;
  }

  RecordingEntry _mapRecordingForRaga(
    RecordingEntry entry,
    String ragaName,
  ) {
    final mapping = _ragaSemitoneMap(ragaName);
    if (mapping == null) {
      return entry;
    }
    final mappedNotes = entry.notes.map((note) {
      final mapped = _mapNoteForRaga(note.note, mapping);
      if (mapped == null) {
        return note;
      }
      return RecordedNote(note: mapped, durationMs: note.durationMs);
    }).toList();
    return RecordingEntry(
      id: entry.id,
      name: entry.name,
      createdAt: entry.createdAt,
      notes: mappedNotes,
      group: entry.group,
      subgroup: entry.subgroup,
    );
  }

  Map<String, int>? _ragaSemitoneMap(String ragaName) {
    if (ragaName.trim().isEmpty) {
      return _defaultRagaSemitones;
    }
    final raga = melakartaRagas
        .cast<MelakartaRaga?>()
        .firstWhere(
          (item) => item?.name.toLowerCase() == ragaName.toLowerCase(),
          orElse: () => null,
        );
    if (raga == null) {
      return _defaultRagaSemitones;
    }
    final map = <String, int>{};
    final tokens = raga.arohanam.split(' ');
    for (final token in tokens) {
      if (token.isEmpty) continue;
      final letter = token[0].toUpperCase();
      if (!'SRGMPDN'.contains(letter)) {
        continue;
      }
      final semitone = _melakartaSemitones[token];
      if (semitone != null) {
        map[letter] = semitone;
      }
    }
    for (final entry in _defaultRagaSemitones.entries) {
      map.putIfAbsent(entry.key, () => entry.value);
    }
    return map;
  }

  String? _mapNoteForRaga(String note, Map<String, int> mapping) {
    final match = RegExp(r'^([a-g])(#?)(-?\d+)$').firstMatch(note.trim());
    if (match == null) {
      return null;
    }
    final name = match.group(1);
    final sharp = match.group(2);
    final octave = int.tryParse(match.group(3) ?? '');
    if (name == null || octave == null) {
      return null;
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
    final swara = _defaultSwaraForSemitone[semitone];
    if (swara == null) {
      return null;
    }
    final target = mapping[swara] ?? semitone;
    return '${_melakartaNoteNames[target]}$octave';
  }

  void _appendSaraleLine(
    List<RecordedNote> notes,
    String line,
    int beatMs,
  ) {
    final tokens = line
        .replaceAll('|', ' ')
        .replaceAll('||', ' ')
        .trim()
        .split(RegExp(r'\s+'));
    for (final token in tokens) {
      if (token.isEmpty) continue;
      if (token == '-' || token == ',') {
        if (notes.isNotEmpty) {
          final last = notes.removeLast();
          notes.add(
            RecordedNote(
              note: last.note,
              durationMs: last.durationMs + beatMs,
            ),
          );
        }
        continue;
      }
      final mapped = _saraleNoteToWestern(token);
      if (mapped == null) {
        continue;
      }
      notes.add(RecordedNote(note: mapped, durationMs: beatMs));
    }
  }

  String? _saraleNoteToWestern(String token) {
    switch (token) {
      case 's':
        return 'c3';
      case 'r':
        return 'c#3';
      case 'g':
        return 'e3';
      case 'm':
        return 'f3';
      case 'p':
        return 'g3';
      case 'd':
        return 'g#3';
      case 'n':
        return 'b3';
      case 'S':
        return 'c4';
      default:
        return null;
    }
  }

  Future<void> _confirmDelete(RecordingEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete recording'),
          content: const Text('Do you really want to delete the recording?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await RecordingStore.instance.delete(entry.id);
    await _load();
  }

  void _editRecording(RecordingEntry entry) {
    final controller = TextEditingController(text: entry.name);
    final groupController = TextEditingController(text: entry.group ?? '');
    final subgroupController = TextEditingController(text: entry.subgroup ?? '');
    final groupOptions = _groupOptions();
    final subgroupOptions = _subgroupOptions();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename recording'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Recording name'),
            ),
            const SizedBox(height: 12),
            _buildTagField(
              label: 'Group',
              controller: groupController,
              options: groupOptions,
            ),
            const SizedBox(height: 12),
            _buildTagField(
              label: 'Sub group',
              controller: subgroupController,
              options: subgroupOptions,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                return;
              }
              final group = groupController.text.trim();
              final subgroup = subgroupController.text.trim();
              final updated = RecordingEntry(
                id: entry.id,
                name: name,
                createdAt: entry.createdAt,
                notes: entry.notes,
                group: group.isEmpty ? null : group,
                subgroup: subgroup.isEmpty ? null : subgroup,
              );
              await RecordingStore.instance.update(updated);
              if (!mounted) return;
              Navigator.of(context).pop();
              await _load();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTracker(RecordingEntry entry) async {
    if (_inlinePlaying) {
      await _stopInlinePlayback();
    }
    final groupName = entry.group?.trim().isNotEmpty == true
        ? entry.group!.trim()
        : _ungroupedLabel;
    final settings = _groupSettingsFor(groupName);
    final mappedEntry = _mapRecordingForRaga(entry, settings.ragaName);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VocalTrackerScreen(
          recording: mappedEntry,
          initialBpm: settings.bpm,
          initialCarnaticRootSemitone: settings.rootSemitone,
          initialRagaName: settings.ragaName,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openGamifiedTracker(RecordingEntry entry) async {
    if (_inlinePlaying) {
      await _stopInlinePlayback();
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GamifiedGameMenuScreen(recording: entry),
      ),
    );
  }

  Future<void> _playRecording(RecordingEntry entry) async {
    if (_inlinePlaying) {
      await _stopInlinePlayback();
    }
    final groupName = entry.group?.trim().isNotEmpty == true
        ? entry.group!.trim()
        : _ungroupedLabel;
    final settings = _groupSettingsFor(groupName);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.9;
        return Container(
          height: height,
          decoration: const BoxDecoration(
            color: Color(0xFF1E2226),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: VocalTrackerScreen(
            recording: _mapRecordingForRaga(entry, settings.ragaName),
            readOnly: true,
            allowEdit: false,
            allowSettings: false,
            initialBpm: settings.bpm,
            initialTanpuraEnabled: false,
            initialCarnaticRootSemitone: settings.rootSemitone,
            initialRagaName: settings.ragaName,
          ),
        );
      },
    );
  }

  Future<void> _toggleInlinePlayback(RecordingEntry entry) async {
    if (_inlinePlaying && _playingId == entry.id) {
      if (_inlinePaused) {
        _resumeInlinePlayback();
      } else {
        await _pauseInlinePlayback();
      }
      return;
    }
    await _startInlinePlayback(entry);
  }

  Future<void> _startInlinePlayback(RecordingEntry entry) async {
    await _stopInlinePlayback();
    if (entry.notes.isEmpty) {
      return;
    }
    final token = ++_inlinePlaybackToken;
    final baseOctave = context.read<PitchNotifier>().baseOctave;
    final tuningSystem = context.read<PitchNotifier>().tuningSystem;
    final groupName = entry.group?.trim().isNotEmpty == true
        ? entry.group!.trim()
        : _ungroupedLabel;
    final settings = _groupSettingsFor(groupName);
    final mappedEntry = _mapRecordingForRaga(entry, settings.ragaName);
    await _preloadInlineHarmonics(
      mappedEntry,
      baseOctave,
      settings.rootSemitone,
      tuningSystem,
    );
    _buildInlineTargets(
      mappedEntry,
      baseOctave,
      settings.rootSemitone,
      tuningSystem,
    );
    setState(() {
      _playingId = entry.id;
      _inlinePlaying = true;
      _inlinePaused = false;
    });
    _inlineScale = 60.0 / settings.bpm.toDouble();
    _inlineLastTargetElapsedMs = 0.0;
    _inlineHarmonicsKey = null;
    _inlineStopwatch = Stopwatch()..start();
    _inlineTicker?.cancel();
    _inlineTicker = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!_inlinePlaying || _inlinePlaybackToken != token) {
        timer.cancel();
        return;
      }
      final elapsedMs = _inlineStopwatch?.elapsedMilliseconds ?? 0;
      _updateInlineHarmonics(elapsedMs.toDouble());
    });
  }

  Future<void> _stopInlinePlayback() async {
    _inlinePlaybackToken++;
    _inlineTicker?.cancel();
    _inlineStopwatch?.stop();
    _inlineStopwatch = null;
    _inlineHarmonicsKey = null;
    _inlineLastTargetElapsedMs = 0.0;
    _inlineHarmonicsStopTimer?.cancel();
    _inlineHarmonicsStopTimer = null;
    _fadeOutAndStopInlinePlayer();
    if (!mounted) return;
    setState(() {
      _inlinePlaying = false;
      _playingId = null;
      _inlinePaused = false;
    });
  }

  Future<void> _pauseInlinePlayback() async {
    if (!_inlinePlaying || _inlinePaused) {
      return;
    }
    _inlineTicker?.cancel();
    _inlineStopwatch?.stop();
    _inlineHarmonicsKey = null;
    _inlineHarmonicsStopTimer?.cancel();
    _inlineHarmonicsStopTimer = null;
    await _inlinePlayer.pause();
    if (!mounted) return;
    setState(() {
      _inlinePaused = true;
    });
  }

  void _resumeInlinePlayback() {
    if (!_inlinePlaying || !_inlinePaused) {
      return;
    }
    final token = ++_inlinePlaybackToken;
    final elapsedMs = _inlineStopwatch?.elapsedMilliseconds ?? 0;
    _inlineLastTargetElapsedMs = max(0.0, elapsedMs.toDouble() - 1.0);
    _inlineStopwatch?.start();
    _inlineTicker?.cancel();
    _inlineTicker = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!_inlinePlaying || _inlinePlaybackToken != token || _inlinePaused) {
        timer.cancel();
        return;
      }
      final tickElapsedMs = _inlineStopwatch?.elapsedMilliseconds ?? 0;
      _updateInlineHarmonics(tickElapsedMs.toDouble());
    });
    if (!mounted) return;
    setState(() {
      _inlinePaused = false;
    });
  }

  void _buildInlineTargets(
    RecordingEntry entry,
    int baseOctave,
    int rootSemitone,
    String tuningSystem,
  ) {
    final targets = <_InlineTargetBlock>[];
    var offsetMs = 0;
    final semitoneOffset = tuningSystem == 'carnatic' ? rootSemitone : 0;
    for (final note in entry.notes) {
      final normalized = note.note.trim().toLowerCase();
      final midi = _midiFromNoteLabel(
        normalized,
        baseOctave: baseOctave,
        semitoneOffset: semitoneOffset,
      );
      if (midi == null) {
        offsetMs += note.durationMs;
        continue;
      }
      targets.add(
        _InlineTargetBlock(
          midi: midi,
          durationMs: note.durationMs,
          startOffsetMs: offsetMs,
        ),
      );
      offsetMs += note.durationMs;
    }
    _inlineTargets = targets;
    _inlineTotalDurationMs = max(0, offsetMs);
  }

  void _updateInlineHarmonics(double elapsedMs) {
    if (_inlineTargets.isEmpty || _inlineTotalDurationMs <= 0) {
      return;
    }
    var previousElapsedMs = _inlineLastTargetElapsedMs;
    if (previousElapsedMs > elapsedMs) {
      previousElapsedMs = elapsedMs;
    }
    if (elapsedMs <= previousElapsedMs) {
      return;
    }
    final scale = _inlineScale;
    final loopMs = max(1, _inlineTotalDurationMs).toDouble() * scale;
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
      for (var i = 0; i < _inlineTargets.length; i++) {
        final start = _inlineTargets[i].startOffsetMs * scale + cycleOffset;
        final duration = _inlineTargets[i].durationMs * scale;
        final end = start + duration;
        final effectiveEnd = end - min(gapMs, duration * 0.5);
        final overlaps =
            effectiveEnd >= previousElapsedMs && start <= elapsedMs;
        if (!overlaps) {
          continue;
        }
        if (start <= elapsedMs && (bestStart == null || start >= bestStart)) {
          bestStart = start;
          bestEnd = end;
          index = i;
          cycleIndex = k;
          durationMs = duration;
        }
      }
    }

    _inlineLastTargetElapsedMs = elapsedMs;
    if (index == null || durationMs == null || cycleIndex == null) {
      return;
    }
    final effectiveDuration = max(0.0, durationMs - gapMs);
    final key = cycleIndex * 10000 + index;
    if (_inlineHarmonicsKey == key) {
      final end = bestEnd ?? 0.0;
      if (end <= previousElapsedMs) {
        _inlineHarmonicsKey = null;
      } else {
        return;
      }
    }
    _inlineHarmonicsKey = key;
    unawaited(_playInlineHarmonic(_inlineTargets[index], effectiveDuration));
  }

  Future<void> _playInlineHarmonic(
    _InlineTargetBlock block,
    double durationMs,
  ) async {
    final path = _harmonicsAssetForMidi(block.midi);
    if (path == null) {
      return;
    }
    _inlineHarmonicsStopTimer?.cancel();
    await _fadeOutAndStopPlayer(_inlinePlayer, 1.0);
    await _inlinePlayer.setVolume(0.0);
    await _inlinePlayer.setSource(AssetSource(path));
    await _inlinePlayer.resume();
    unawaited(_fadeInPlayer(_inlinePlayer, 1.0));
    final duration = durationMs.clamp(50, 600000).toDouble();
    _inlineHarmonicsStopTimer =
        Timer(Duration(milliseconds: duration.round()), () {
      if (_inlinePlaying) {
        _fadeOutAndStopInlinePlayer();
      }
    });
  }

  void _fadeOutAndStopInlinePlayer() {
    unawaited(_fadeOutAndStopPlayer(_inlinePlayer, 1.0));
  }

  Future<void> _fadeInPlayer(
    AudioPlayer player,
    double targetVolume, {
    int steps = 4,
    int stepMs = 20,
  }) async {
    final clamped = targetVolume.clamp(0.0, 2.0);
    for (var i = 1; i <= steps; i++) {
      await player.setVolume((clamped * i) / steps);
      await Future<void>.delayed(Duration(milliseconds: stepMs));
    }
  }

  Future<void> _fadeOutAndStopPlayer(
    AudioPlayer player,
    double fromVolume, {
    int steps = 3,
    int stepMs = 20,
  }) async {
    final clamped = fromVolume.clamp(0.0, 2.0);
    for (var i = steps - 1; i >= 0; i--) {
      await player.setVolume((clamped * i) / steps);
      await Future<void>.delayed(Duration(milliseconds: stepMs));
    }
    await player.stop();
  }

  Future<void> _preloadInlineHarmonics(
    RecordingEntry entry,
    int baseOctave,
    int rootSemitone,
    String tuningSystem,
  ) async {
    final assets = <String>[];
    final semitoneOffset = tuningSystem == 'carnatic' ? rootSemitone : 0;
    for (final note in entry.notes) {
      final midi = _midiFromNoteLabel(
        note.note,
        baseOctave: baseOctave,
        semitoneOffset: semitoneOffset,
      );
      final path = midi == null ? null : _harmonicsAssetForMidi(midi);
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

  Future<void> _openNewTracker() async {
    final meta = await _showCreateRecordingDialog();
    if (meta == null || meta.name.trim().isEmpty) {
      return;
    }
    final entry = RecordingEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: meta.name.trim(),
      createdAt: DateTime.now(),
      notes: const [],
      group: meta.group?.trim().isEmpty == true ? null : meta.group,
      subgroup: meta.subgroup?.trim().isEmpty == true ? null : meta.subgroup,
    );
    final groupName = entry.group?.trim().isNotEmpty == true
        ? entry.group!.trim()
        : _ungroupedLabel;
    final settings = _groupSettingsFor(groupName);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VocalTrackerScreen(
          recording: entry,
          initialCarnaticRootSemitone: settings.rootSemitone,
          initialRagaName: settings.ragaName,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final tuningSystem = context.watch<PitchNotifier>().tuningSystem;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ragas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showGlobalSettings,
          ),
          PopupMenuButton<_RecordingSort>(
            onSelected: (value) {
              setState(() {
                _sortOrder = value == _RecordingSort.nameAsc ||
                        value == _RecordingSort.nameDesc
                    ? (_sortOrder == _RecordingSort.nameAsc
                        ? _RecordingSort.nameDesc
                        : _RecordingSort.nameAsc)
                    : (_sortOrder == _RecordingSort.createdAsc
                        ? _RecordingSort.createdDesc
                        : _RecordingSort.createdAsc);
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _RecordingSort.nameAsc,
                child: Text(
                  'Name ${_sortOrder == _RecordingSort.nameAsc ? '↑' : '↓'}',
                ),
              ),
              PopupMenuItem(
                value: _RecordingSort.createdAsc,
                child: Text(
                  'Created ${_sortOrder == _RecordingSort.createdAsc ? '↑' : '↓'}',
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _openNewTracker,
          ),
        ],
      ),
      backgroundColor: const Color(0xFF4A5158),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _recordings.isEmpty
              ? Center(
                  child: Card(
                    margin: const EdgeInsets.all(20),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.queue_music, size: 40),
                          SizedBox(height: 12),
                          Text(
                            'No recordings yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text('Your saved takes will appear here.'),
                        ],
                      ),
                    ),
                  ),
                )
              : _buildGroupedList(),
    );
  }

  Widget _buildGroupedList() {
    final grouped = <String, Map<String, List<RecordingEntry>>>{};
    for (final recording in _recordings) {
      final group = recording.group?.trim().isNotEmpty == true
          ? recording.group!.trim()
          : _ungroupedLabel;
      final subgroup = recording.subgroup?.trim().isNotEmpty == true
          ? recording.subgroup!.trim()
          : _ungroupedLabel;
      grouped.putIfAbsent(group, () => {}).putIfAbsent(subgroup, () => []);
      grouped[group]![subgroup]!.add(recording);
    }
    final groups = grouped.keys.toList()
      ..sort((a, b) {
        if (a == _swaravalisGroup) return -1;
        if (b == _swaravalisGroup) return 1;
        if (a == _ungroupedLabel) return 1;
        if (b == _ungroupedLabel) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final groupName = groups[index];
        final subgroups =
            grouped[groupName] ?? const <String, List<RecordingEntry>>{};
        final subgroupNames = subgroups.keys.toList()
          ..sort((a, b) {
            if (a == _ungroupedLabel) return 1;
            if (b == _ungroupedLabel) return -1;
            if (groupName == _swaravalisGroup) {
              final aIndex = _swaravalisSubgroupOrder.indexOf(a);
              final bIndex = _swaravalisSubgroupOrder.indexOf(b);
              if (aIndex != -1 && bIndex != -1) {
                return aIndex.compareTo(bIndex);
              }
              if (aIndex != -1) return -1;
              if (bIndex != -1) return 1;
            }
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
        final subgroupTiles = <Widget>[];
        for (final subgroupName in subgroupNames) {
          final items = _sortedRecordings(
            subgroups[subgroupName] ?? const <RecordingEntry>[],
          );
          subgroupTiles.add(
            ExpansionTile(
              title: Text(subgroupName),
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _buildRecordingTile(items[i]),
                  if (i != items.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          );
        }
        return Card(
          child: ExpansionTile(
            initiallyExpanded: index == 0,
            title: Row(
              children: [
                Expanded(child: Text(groupName)),
                IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: () => _showGroupSettings(groupName),
                ),
              ],
            ),
            children: subgroupTiles,
          ),
        );
      },
    );
  }

  Widget _buildRecordingTile(RecordingEntry recording) {
    final isDefault = _defaultRecordingIds.contains(recording.id);
    final isSwaravalis = recording.group?.trim() == _swaravalisGroup;
    final canDelete = !isDefault && !isSwaravalis;
    final isPlaying =
        _inlinePlaying && _playingId == recording.id && !_inlinePaused;
    return InkWell(
      onTap: widget.onSelect == null ? null : () => widget.onSelect?.call(recording),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(recording.name),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: isPlaying ? const _MiniEqualizer() : const SizedBox(),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: recording.notes.isEmpty
                      ? null
                      : () => _toggleInlinePlayback(recording),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editRecording(recording),
                ),
                IconButton(
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => _openTracker(recording),
                ),
                IconButton(
                  icon: const Icon(Icons.sports_esports),
                  onPressed: () => _openGamifiedTracker(recording),
                ),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(recording),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int? _midiFromNoteLabel(
    String note, {
    required int baseOctave,
    int semitoneOffset = 0,
  }) {
    if (note.isEmpty) return null;
    final match = RegExp(r'^([a-g])(#?)(-?\d+)$').firstMatch(note);
    if (match != null) {
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
      final midi = (octave + 1) * 12 + semitone + semitoneOffset;
      final offset = (baseOctave - PitchNotifier.defaultBaseOctave) * 12;
      return (midi + offset).clamp(0, 127);
    }
    final carnatic = RegExp(
      r'^(sa|ri1|ri2|ri3|ga1|ga2|ga3|ma1|ma2|pa|da1|da2|da3|ni1|ni2|ni3)(-?\d+)$',
      caseSensitive: false,
    ).firstMatch(note);
    if (carnatic == null) {
      return null;
    }
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
    final name = (carnatic.group(1) ?? '').toLowerCase();
    final octave = int.tryParse(carnatic.group(2) ?? '');
    if (octave == null) return null;
    final token = labelToToken[name];
    final semitone = token == null ? null : _melakartaSemitones[token];
    if (semitone == null) return null;
    final midi = (octave + 1) * 12 + semitone + semitoneOffset;
    final offset = (baseOctave - PitchNotifier.defaultBaseOctave) * 12;
    return (midi + offset).clamp(0, 127);
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
    final name = names[midi % 12];
    var octave = (midi / 12).floor() - 1;
    if (octave < 0) {
      return null;
    }
    if (octave > 8) {
      octave = 8;
    }
    if (octave == 8 && name != 'c') {
      octave = 7;
    }
    if (octave == 0 && name != 'a' && name != 'asharp' && name != 'b') {
      octave = 1;
    }
    return 'harmonics/${name}${octave}.wav';
  }

  _GroupSettings _groupSettingsFor(String group) {
    return _groupSettings.putIfAbsent(
      group,
      () => const _GroupSettings(
        bpm: 60,
        rootSemitone: 0,
        ragaName: 'Mayamalavagowla',
      ),
    );
  }

  List<String> _groupOptions() {
    final options = _recordings
        .map((recording) => recording.group?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return options;
  }

  List<String> _subgroupOptions() {
    final options = _recordings
        .map((recording) => recording.subgroup?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return options;
  }

  Widget _buildTagField({
    required String label,
    required TextEditingController controller,
    required List<String> options,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        if (options.isNotEmpty)
          PopupMenuButton<String>(
            icon: const Icon(Icons.arrow_drop_down),
            onSelected: (value) {
              controller.text = value;
            },
            itemBuilder: (context) => [
              for (final option in options)
                PopupMenuItem(
                  value: option,
                  child: Text(option),
                ),
            ],
          ),
      ],
    );
  }

  Future<_RecordingMeta?> _showCreateRecordingDialog() async {
    final controller = TextEditingController(
      text: 'Recording ${_recordings.length + 1}',
    );
    final groupController = TextEditingController();
    final subgroupController = TextEditingController();
    final groupOptions = _groupOptions();
    final subgroupOptions = _subgroupOptions();
    return showDialog<_RecordingMeta>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New recording'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Recording name'),
            ),
            const SizedBox(height: 12),
            _buildTagField(
              label: 'Group',
              controller: groupController,
              options: groupOptions,
            ),
            const SizedBox(height: 12),
            _buildTagField(
              label: 'Sub group',
              controller: subgroupController,
              options: subgroupOptions,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              _RecordingMeta(
                name: controller.text,
                group: groupController.text,
                subgroup: subgroupController.text,
              ),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  List<RecordingEntry> _sortedRecordings(List<RecordingEntry> items) {
    final sorted = List<RecordingEntry>.from(items);
    switch (_sortOrder) {
      case _RecordingSort.nameAsc:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case _RecordingSort.nameDesc:
        sorted.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case _RecordingSort.createdAsc:
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case _RecordingSort.createdDesc:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
    return sorted;
  }

  Future<void> _showAddRecordingOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF23272B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.mic),
                title: const Text('Live recording'),
                subtitle: const Text('Record from the tuner screen'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed('/tuner');
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Compose recording'),
                subtitle: const Text('Build a note sequence manually'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showComposeRecordingSheet();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showGroupSettings(String groupName) {
    final current = _groupSettingsFor(groupName);
    var bpm = current.bpm;
    var rootSemitone = current.rootSemitone;
    var ragaName = current.ragaName;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF23272B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$groupName settings',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'BPM',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$bpm',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: bpm > _bpmOptions.first
                            ? () {
                                final nextIndex = _bpmIndex(bpm) - 1;
                                setSheetState(() {
                                  bpm = _bpmFromIndex(nextIndex);
                                });
                              }
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: bpm < _bpmOptions.last
                            ? () {
                                final nextIndex = _bpmIndex(bpm) + 1;
                                setSheetState(() {
                                  bpm = _bpmFromIndex(nextIndex);
                                });
                              }
                            : null,
                      ),
                    ],
                  ),
                  Slider(
                    value: _bpmIndex(bpm).toDouble(),
                    min: 0,
                    max: (_bpmOptions.length - 1).toDouble(),
                    divisions: _bpmOptions.length - 1,
                    onChanged: (value) {
                      final next = _bpmFromIndex(value.round());
                      setSheetState(() {
                        bpm = next;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Raga',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: Colors.white70),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: ragaName,
                              dropdownColor: const Color(0xFF2A2F35),
                              decoration: const InputDecoration(
                                filled: true,
                                fillColor: Color(0xFF1B1F23),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              items: _ragaOptions
                                  .map(
                                    (name) => DropdownMenuItem<String>(
                                      value: name,
                                      child: Text(name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  ragaName = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Root note (Sa)',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: Colors.white70),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              value: rootSemitone,
                              dropdownColor: const Color(0xFF2A2F35),
                              decoration: const InputDecoration(
                                filled: true,
                                fillColor: Color(0xFF1B1F23),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              items: _rootNoteOptions
                                  .map(
                                    (note) => DropdownMenuItem<int>(
                                      value: note.semitone,
                                      child: Text(note.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  rootSemitone = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            setState(() {
                              _groupSettings[groupName] = _GroupSettings(
                                bpm: bpm,
                                rootSemitone: rootSemitone,
                                ragaName: ragaName,
                              );
                            });
                            _applyInlineBpmIfNeeded(groupName, bpm);
                            Navigator.of(context).pop();
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _applyInlineBpmIfNeeded(String groupName, int bpm) {
    if (!_inlinePlaying || _playingId == null) {
      return;
    }
    RecordingEntry? playing;
    for (final recording in _recordings) {
      if (recording.id == _playingId) {
        playing = recording;
        break;
      }
    }
    if (playing == null) {
      return;
    }
    final playingGroup = playing.group?.trim().isNotEmpty == true
        ? playing.group!.trim()
        : _ungroupedLabel;
    if (playingGroup != groupName) {
      return;
    }
    _inlineScale = 60.0 / bpm.toDouble();
    _inlineHarmonicsKey = null;
    _inlineLastTargetElapsedMs =
        (_inlineStopwatch?.elapsedMilliseconds ?? 0).toDouble();
  }

  void _showGlobalSettings() {
    final pitchState = context.read<PitchNotifier>();
    var baseOctave = pitchState.baseOctave;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF23272B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Global settings',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Base octave',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: baseOctave,
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: Color(0xFF2F353A),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var octave = 1; octave <= 8; octave++)
                        DropdownMenuItem(
                          value: octave,
                          child: Text('Octave $octave'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() {
                        baseOctave = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            pitchState.setBaseOctave(baseOctave);
                            Navigator.of(context).pop();
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showComposeRecordingSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF23272B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      isScrollControlled: true,
      builder: (context) => _AddRecordingSheet(
        onSaved: () async {
          await _load();
        },
      ),
    );
  }
}

class _RecordingMeta {
  const _RecordingMeta({
    required this.name,
    required this.group,
    required this.subgroup,
  });

  final String name;
  final String? group;
  final String? subgroup;
}

class _InlineTargetBlock {
  const _InlineTargetBlock({
    required this.midi,
    required this.durationMs,
    required this.startOffsetMs,
  });

  final int midi;
  final int durationMs;
  final int startOffsetMs;
}

enum _RecordingSort {
  nameAsc,
  nameDesc,
  createdAsc,
  createdDesc,
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

class _RootNoteOption {
  const _RootNoteOption(this.label, this.semitone);

  final String label;
  final int semitone;
}

final List<String> _ragaOptions = [
  'Mayamalavagowla',
  for (final raga in melakartaRagas)
    if (raga.name != 'Mayamalavagowla') raga.name,
];

const _rootNoteOptions = [
  _RootNoteOption('C', 0),
  _RootNoteOption('C#', 1),
  _RootNoteOption('D', 2),
  _RootNoteOption('D#', 3),
  _RootNoteOption('E', 4),
  _RootNoteOption('F', 5),
  _RootNoteOption('F#', 6),
  _RootNoteOption('G', 7),
  _RootNoteOption('G#', 8),
  _RootNoteOption('A', 9),
  _RootNoteOption('A#', 10),
  _RootNoteOption('B', 11),
];

class _GroupSettings {
  const _GroupSettings({
    required this.bpm,
    required this.rootSemitone,
    required this.ragaName,
  });

  final int bpm;
  final int rootSemitone;
  final String ragaName;
}

class _MiniEqualizer extends StatefulWidget {
  const _MiniEqualizer();

  @override
  State<_MiniEqualizer> createState() => _MiniEqualizerState();
}

class _MiniEqualizerState extends State<_MiniEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _barHeight(double t, double phase) {
    final value = (sin((t + phase) * pi * 2) + 1) / 2;
    return 6 + (value * 10);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 16,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Bar(height: _barHeight(t, 0.0)),
              _Bar(height: _barHeight(t, 0.2)),
              _Bar(height: _barHeight(t, 0.4)),
            ],
          );
        },
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: Colors.greenAccent,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _AddRecordingSheet extends StatefulWidget {
  const _AddRecordingSheet({
    required this.onSaved,
    this.initialEntry,
  });

  final VoidCallback onSaved;
  final RecordingEntry? initialEntry;

  @override
  State<_AddRecordingSheet> createState() => _AddRecordingSheetState();
}

class _AddRecordingSheetState extends State<_AddRecordingSheet> {
  static const _defaultDurationMs = 1000;
  static const _millisecondsPerSecond = 1000.0;
  static const _previewHeight = 170.0;
  int _defaultOctave = PitchNotifier.defaultBaseOctave;

  _SheetStep _step = _SheetStep.select;
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
      _step = _SheetStep.preview;
    });
  }

  void _goToDurations() {
    setState(() {
      _step = _SheetStep.duration;
    });
  }

  void _goBack() {
    setState(() {
      _step = _step == _SheetStep.preview
          ? _SheetStep.select
          : _SheetStep.preview;
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
          group: existingEntry.group,
          subgroup: existingEntry.subgroup,
        );
        await RecordingStore.instance.update(updated);
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
          group: null,
          subgroup: null,
        );
        await RecordingStore.instance.save(entry);
      }
      widget.onSaved();
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
          _SheetStep.select => _buildSelectNotes(context, tuningSystem),
          _SheetStep.preview => _buildPreview(context, tuningSystem),
          _SheetStep.duration => _buildDurations(context),
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
                        note: _displayLabel(note, tuningSystem),
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
                onChanged: (value) =>
                    _toggleSelectAll(value ?? false),
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
                      _displayLabel(_selectedNotes[index], tuningSystem),
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
                          _displayLabel(notes[index], tuningSystem),
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

TextStyle? _labelStyleForSystem(String tuningSystem) {
  if (tuningSystem != 'carnatic') {
    return null;
  }
  return const TextStyle(
    fontFamily: 'RobotoMono',
    fontFeatures: [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w600,
  );
}

class _EditRecordingSheet extends StatefulWidget {
  const _EditRecordingSheet({
    required this.entry,
    required this.onSaved,
  });

  final RecordingEntry entry;
  final VoidCallback onSaved;

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

  void _openAddNotes() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF23272B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      isScrollControlled: true,
      builder: (context) => _AddRecordingSheet(
        initialEntry: widget.entry,
        onSaved: () async {
          widget.onSaved();
        },
      ),
    ).then((_) {
      if (!mounted) return;
      Navigator.of(context).pop();
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
        group: widget.entry.group,
        subgroup: widget.entry.subgroup,
      );
      await RecordingStore.instance.update(updated);
      widget.onSaved();
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
            onPressed: _openAddNotes,
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

enum _SheetStep { select, preview, duration }
