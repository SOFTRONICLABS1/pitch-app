import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/recording.dart';

class RecordingStore {
  RecordingStore._internal();

  static final RecordingStore instance = RecordingStore._internal();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/recordings.json');
  }

  Future<List<RecordingEntry>> load() async {
    final file = await _file();
    if (!await file.exists()) {
      return [];
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return [];
    }
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(RecordingEntry.fromJson)
        .toList();
  }

  Future<void> save(RecordingEntry entry) async {
    final list = await load();
    list.add(entry);
    await _writeAll(list);
  }

  Future<void> update(RecordingEntry entry) async {
    final list = await load();
    final index = list.indexWhere((item) => item.id == entry.id);
    if (index >= 0) {
      list[index] = entry;
    } else {
      list.add(entry);
    }
    await _writeAll(list);
  }

  Future<void> delete(String id) async {
    final list = await load();
    list.removeWhere((entry) => entry.id == id);
    await _writeAll(list);
  }

  Future<void> _writeAll(List<RecordingEntry> entries) async {
    final file = await _file();
    final payload = jsonEncode(entries.map((e) => e.toJson()).toList());
    await file.writeAsString(payload);
  }
}
