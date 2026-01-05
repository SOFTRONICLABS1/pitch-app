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
}
