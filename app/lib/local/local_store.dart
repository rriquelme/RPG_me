import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event.dart';
import 'local_engine.dart';
import 'timer_entry.dart';

/// Persists the offline data (events, axis config, running timers) to a JSON
/// file in the app's documents folder, so it survives app updates and is easy
/// to back up. On first run it migrates any data from the older
/// shared_preferences storage.
class LocalStore {
  static const _folder = 'rpg_me';
  static const _fileName = 'data.json';

  // Legacy shared_preferences keys (pre-0.7) — migrated on first file read.
  static const _legacyEvents = 'events_v1';
  static const _legacyAxes = 'axes_v1';
  static const _legacyTimers = 'timers_v1';

  Map<String, dynamic>? _cache;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/$_folder');
    if (!await folder.exists()) await folder.create(recursive: true);
    return File('${folder.path}/$_fileName');
  }

  Future<Map<String, dynamic>> _data() async {
    if (_cache != null) return _cache!;
    final file = await _file();
    if (await file.exists()) {
      try {
        _cache = (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>();
      } catch (_) {
        _cache = {};
      }
    } else {
      _cache = await _migrateFromPrefs();
      await _flush(); // seed the file
    }
    return _cache!;
  }

  Future<Map<String, dynamic>> _migrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> decode(String? raw) =>
        (raw == null || raw.isEmpty) ? [] : (jsonDecode(raw) as List);
    return {
      'events': decode(prefs.getString(_legacyEvents)),
      'axes': decode(prefs.getString(_legacyAxes)),
      'timers': decode(prefs.getString(_legacyTimers)),
    };
  }

  Future<void> _flush() async {
    final file = await _file();
    await file.writeAsString(jsonEncode(_cache));
  }

  Future<void> _setSection(String key, Object value) async {
    final data = await _data();
    data[key] = value;
    await _flush();
  }

  Future<List<dynamic>> _section(String key) async =>
      ((await _data())[key] as List?) ?? const [];

  // --- events -------------------------------------------------------------
  Future<List<Event>> loadEvents() async => (await _section('events'))
      .cast<Map<String, dynamic>>()
      .map(Event.fromStorageJson)
      .toList();

  Future<void> saveEvents(List<Event> events) async =>
      _setSection('events', events.map((e) => e.toStorageJson()).toList());

  // --- axis config --------------------------------------------------------
  Future<List<AxisDef>> loadAxes() async {
    final list = (await _section('axes')).cast<Map<String, dynamic>>();
    if (list.isEmpty) return List.of(kDefaultAxes);
    return list.map(AxisDef.fromJson).toList();
  }

  Future<void> saveAxes(List<AxisDef> axes) async =>
      _setSection('axes', axes.map((a) => a.toJson()).toList());

  // --- timers -------------------------------------------------------------
  Future<List<TimerEntry>> loadTimers() async => (await _section('timers'))
      .cast<Map<String, dynamic>>()
      .map(TimerEntry.fromJson)
      .toList();

  Future<void> saveTimers(List<TimerEntry> timers) async =>
      _setSection('timers', timers.map((t) => t.toJson()).toList());
}
