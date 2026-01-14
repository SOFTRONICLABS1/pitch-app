import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/recording.dart';
import '../services/recording_store.dart';
import '../state/pitch_notifier.dart';
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
  static const _defaultRecordingIds = {
    'default-mayamalavagowla',
    'default-shankarabharanam',
    'default-mayamalavagowla-sarale',
    'default-mayamalavagowla-sarale-1',
    'default-mayamalavagowla-sarale-2',
    'default-mayamalavagowla-sarale-3',
    'default-mayamalavagowla-sarale-4',
    'default-mayamalavagowla-sarale-5',
    'default-mayamalavagowla-sarale-6',
    'default-mayamalavagowla-sarale-7',
    'default-mayamalavagowla-sarale-8',
    'default-mayamalavagowla-sarale-9',
    'default-mayamalavagowla-sarale-10',
    'default-mayamalavagowla-sarale-11',
    'default-mayamalavagowla-sarale-12',
    'default-mayamalavagowla-sarale-13',
    'default-mayamalavagowla-sarale-14',
  };
  static const _ungroupedLabel = 'Ungrouped';
  _RecordingSort _sortOrder = _RecordingSort.createdDesc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await RecordingStore.instance.load();
    if (!mounted) return;
    setState(() {
      _recordings = [
        ..._buildDefaultRecordings(),
        ...list,
      ];
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
      RecordingEntry(
        id: 'default-mayamalavagowla',
        name: 'Mayamalavagowla (C3–C4)',
        createdAt: DateTime(2000, 1, 1),
        notes: notes,
        group: 'Mayamalavagowla',
      ),
      RecordingEntry(
        id: 'default-mayamalavagowla-sarale',
        name: 'Mayamalavagowla Sarale Varase 001–014 (C3–C4)',
        createdAt: DateTime(2000, 1, 1),
        notes: _buildSaraleVaraseNotes(beatMs),
        group: 'Mayamalavagowla',
      ),
      for (var i = 0; i < _saraleVaraseSequences.length; i++)
        RecordingEntry(
          id: 'default-mayamalavagowla-sarale-${i + 1}',
          name:
              'Mayamalavagowla Sarale Varase ${(i + 1).toString().padLeft(3, '0')} (C3–C4)',
          createdAt: DateTime(2000, 1, 1),
          notes: _buildSaraleVaraseNotes(beatMs, index: i),
          group: 'Mayamalavagowla',
        ),
      RecordingEntry(
        id: 'default-shankarabharanam',
        name: 'Shankarabharanam (C3–C4)',
        createdAt: DateTime(2000, 1, 1),
        notes: const [
          RecordedNote(note: 'c3', durationMs: beatMs), // Sa
          RecordedNote(note: 'd3', durationMs: beatMs), // Ri2
          RecordedNote(note: 'e3', durationMs: beatMs), // Ga2
          RecordedNote(note: 'f3', durationMs: beatMs), // Ma1
          RecordedNote(note: 'g3', durationMs: beatMs), // Pa
          RecordedNote(note: 'a3', durationMs: beatMs), // Da2
          RecordedNote(note: 'b3', durationMs: beatMs), // Ni2
          RecordedNote(note: 'c4', durationMs: beatMs), // Sa
          RecordedNote(note: 'b3', durationMs: beatMs), // Ni2
          RecordedNote(note: 'a3', durationMs: beatMs), // Da2
          RecordedNote(note: 'g3', durationMs: beatMs), // Pa
          RecordedNote(note: 'f3', durationMs: beatMs), // Ma1
          RecordedNote(note: 'e3', durationMs: beatMs), // Ga2
          RecordedNote(note: 'd3', durationMs: beatMs), // Ri2
          RecordedNote(note: 'c3', durationMs: beatMs), // Sa
        ],
        group: 'Shankarabharanam',
      ),
    ];
  }

  static const _saraleVaraseSequences = [
      [
        's r g m | p d | n S ||',
        'S n d p | m g | r s ||',
      ],
      [
        's r - s r - | s r | g m ||',
        's r g m | p d | n S ||',
        'S n - S n - | S n | d p ||',
        'S n d p | m g | r s ||',
      ],
      [
        's r g - s | r g - | s r ||',
        's r g m | p d | n S ||',
        'S n d - s | n d - | s n ||',
        'S n d p | m g | r s ||',
      ],
      [
        's r g m - | s r | g m - ||',
        's r g m | p d | n s ||',
        'S n d p - | S n | d p - ||',
        'S n d p | m g | r s ||',
      ],
      [
        's r g m | p , - | s r ||',
        's r g m | p d | n S ||',
        'S n d p | m , - | S n ||',
        'S n d p | m g | r s ||',
      ],
      [
        's r g m | p d - | s r ||',
        's r g m | p d | n S ||',
        'S n d p | m g - | S n ||',
        'S n d p | m g | r s ||',
      ],
      [
        's r g m | p d | n , ||',
        's r g m | p d | n S ||',
        'S n d p | m g | r , ||',
        'S n d p | m g | r s ||',
      ],
      [
        's r g m | p m | g r ||',
        's r g m | p d | n S ||',
        'S n d p | m p | d n ||',
        'S n d p | m g | r s ||',
      ],
      [
        's r g m | p m | d p ||',
        's r g m | p d | n S ||',
        'S n d p | m p | g m ||',
        'S n d p | m g | r s ||',
      ],
      [
        's r g m | p , | g m ||',
        'p , , , | p , | , , ||',
        'g m p d | n d | p m ||',
        'g m p - g | m g | r s ||',
      ],
      [
        'S , n d | n , | d p ||',
        'd , p m | p , | p , ||',
        'g m p d | n d | p m ||',
        'g m p - g | m g | r s ||',
      ],
      [
        'S S n d | n n | d p ||',
        'd d p m | p , | p , ||',
        'g m p d | n d | p m ||',
        'g m p - g | m g | r s ||',
      ],
      [
        's r g r | g , - | g m ||',
        'p m p , - | d p | d , ||',
        'm p d p | d n | d p ||',
        'm p d p | m g | r s ||',
      ],
      [
        's r g m | p , | p , ||',
        'd d p , | m m | p , ||',
        'd n S , | S n | d p ||',
        'S n d p | m g | r s ||',
      ],
    ];

  List<RecordedNote> _buildSaraleVaraseNotes(
    int beatMs, {
    int? index,
  }) {
    final sequences = index == null
        ? _saraleVaraseSequences
        : [
            _saraleVaraseSequences[index],
          ];
    final notes = <RecordedNote>[];
    for (final group in sequences) {
      for (final line in group) {
        _appendSaraleLine(notes, line, beatMs);
      }
    }
    return notes;
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
    final options = _groupOptions();
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
            _buildGroupField(
              controller: groupController,
              options: options,
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
              final updated = RecordingEntry(
                id: entry.id,
                name: name,
                createdAt: entry.createdAt,
                notes: entry.notes,
                group: group.isEmpty ? null : group,
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VocalTrackerScreen(recording: entry),
      ),
    );
    await _load();
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
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VocalTrackerScreen(recording: entry),
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
    final grouped = <String, List<RecordingEntry>>{};
    for (final recording in _recordings) {
      final group = recording.group?.trim().isNotEmpty == true
          ? recording.group!.trim()
          : _ungroupedLabel;
      grouped.putIfAbsent(group, () => []).add(recording);
    }
    final groups = grouped.keys.toList()
      ..sort((a, b) {
        if (a == _ungroupedLabel) return 1;
        if (b == _ungroupedLabel) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final groupName = groups[index];
        final items = _sortedRecordings(grouped[groupName] ?? const []);
        return Card(
          child: ExpansionTile(
            initiallyExpanded: index == 0,
            title: Text(groupName),
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _buildRecordingTile(items[i]),
                if (i != items.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecordingTile(RecordingEntry recording) {
    final isDefault = _defaultRecordingIds.contains(recording.id);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(recording.name)),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
            onPressed: () => _editRecording(recording),
          ),
        ],
      ),
      onTap: widget.onSelect == null ? null : () => widget.onSelect?.call(recording),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: recording.notes.isEmpty ? null : () => _openTracker(recording),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: isDefault ? null : () => _confirmDelete(recording),
          ),
        ],
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

  Widget _buildGroupField({
    required TextEditingController controller,
    required List<String> options,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Group'),
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
    final options = _groupOptions();
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
            _buildGroupField(
              controller: groupController,
              options: options,
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
  const _RecordingMeta({required this.name, required this.group});

  final String name;
  final String? group;
}

enum _RecordingSort {
  nameAsc,
  nameDesc,
  createdAsc,
  createdDesc,
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
  static const _defaultOctave = 3;

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
