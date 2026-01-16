class RecordedNote {
  const RecordedNote({required this.note, required this.durationMs});

  final String note;
  final int durationMs;

  Map<String, dynamic> toJson() => {
        'note': note,
        'durationMs': durationMs,
      };

  static RecordedNote fromJson(Map<String, dynamic> json) {
    return RecordedNote(
      note: json['note'] as String? ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class RecordingEntry {
  RecordingEntry({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.notes,
    this.group,
    this.subgroup,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final List<RecordedNote> notes;
  final String? group;
  final String? subgroup;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'notes': notes.map((note) => note.toJson()).toList(),
        'group': group,
        'subgroup': subgroup,
      };

  static RecordingEntry fromJson(Map<String, dynamic> json) {
    return RecordingEntry(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Recording',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      notes: (json['notes'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RecordedNote.fromJson)
          .toList(),
      group: json['group'] as String?,
      subgroup: json['subgroup'] as String?,
    );
  }
}

class RecordingDraft {
  RecordingDraft({required this.startedAt, required this.endedAt, required this.notes});

  final DateTime startedAt;
  final DateTime endedAt;
  final List<RecordedNote> notes;
}
