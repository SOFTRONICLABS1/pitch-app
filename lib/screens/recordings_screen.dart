import 'package:flutter/material.dart';

import '../models/recording.dart';
import '../services/recording_store.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await RecordingStore.instance.load();
    if (!mounted) return;
    setState(() {
      _recordings = list;
      _loading = false;
    });
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

  void _showDetails(RecordingEntry entry) {
    final content = entry.notes
        .map((note) => '${note.note}:${note.durationMs}')
        .join(', ');
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(entry.name),
          content: Text(content.isEmpty ? 'No notes captured.' : content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _openTracker(RecordingEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VocalTrackerScreen(recording: entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddRecordingSheet,
          ),
        ],
      ),
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
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _recordings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final recording = _recordings[index];
                    final date =
                        recording.createdAt.toLocal().toString().split('.').first;
                    return Card(
                      child: ListTile(
                        title: Text(recording.name),
                        subtitle: Text(date),
                        onTap: () {
                          final handler = widget.onSelect;
                          if (handler != null) {
                            handler(recording);
                          } else {
                            _openTracker(recording);
                          }
                        },
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility_outlined),
                              onPressed: () => _showDetails(recording),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _confirmDelete(recording),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  void _showAddRecordingSheet() {
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

class _AddRecordingSheet extends StatefulWidget {
  const _AddRecordingSheet({required this.onSaved});

  final VoidCallback onSaved;

  @override
  State<_AddRecordingSheet> createState() => _AddRecordingSheetState();
}

class _AddRecordingSheetState extends State<_AddRecordingSheet> {
  static const _defaultDurationMs = 500;
  static const _previewHeight = 170.0;

  _SheetStep _step = _SheetStep.select;
  final List<String> _selectedNotes = [];
  final List<TextEditingController> _durationControllers = [];
  String? _activeNote;
  int? _selectedIndex;
  bool _saving = false;

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

  @override
  void dispose() {
    for (final controller in _durationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addNote(String note) {
    setState(() {
      _selectedNotes.add(note);
      _durationControllers.add(
        TextEditingController(text: _defaultDurationMs.toString()),
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
          TextEditingController(text: _defaultDurationMs.toString()),
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

  Future<void> _saveRecording() async {
    if (_saving || _selectedNotes.isEmpty) return;
    setState(() {
      _saving = true;
    });
    try {
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
      final notes = <RecordedNote>[];
      for (var i = 0; i < _selectedNotes.length; i++) {
        final duration =
            int.tryParse(_durationControllers[i].text.trim()) ??
                _defaultDurationMs;
        notes.add(
          RecordedNote(
            note: _selectedNotes[i].toLowerCase(),
            durationMs: duration,
          ),
        );
      }
      final entry = RecordingEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        createdAt: DateTime.now(),
        notes: notes,
      );
      await RecordingStore.instance.save(entry);
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
          _SheetStep.select => _buildSelectNotes(context),
          _SheetStep.preview => _buildPreview(context),
          _SheetStep.duration => _buildDurations(context),
        },
      ),
    );
  }

  Widget _buildSelectNotes(BuildContext context) {
    return Column(
      key: const ValueKey('select'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select notes',
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
            children: [
              for (final entry in _noteOptionsByOctave.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
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
                        note: note,
                        active: _activeNote == note,
                        onTap: () => _applyNoteSelection(note),
                        onDoubleTap: () => _addNote(note),
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
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _selectedNotes.isEmpty ? null : _goToPreview,
          child: const Text('Next'),
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    return Column(
      key: const ValueKey('preview'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Preview',
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
    return Column(
      key: const ValueKey('duration'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Durations (ms)',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: ListView.separated(
            itemCount: _selectedNotes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedNotes[index],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _durationControllers[index],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        filled: true,
                        hintText: '500',
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
                onPressed: _saving ? null : _saveRecording,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Done'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SelectedNotesPreview extends StatelessWidget {
  const _SelectedNotesPreview({
    required this.notes,
    required this.height,
    required this.onRemove,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> notes;
  final double height;
  final ValueChanged<int> onRemove;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

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
                        label: Text(notes[index]),
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
  });

  final String note;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

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
          ),
        ),
      ),
    );
  }
}

enum _SheetStep { select, preview, duration }
