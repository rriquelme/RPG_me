import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'event.dart';
import 'local_engine.dart';
import 'timer_entry.dart';

/// Persists the offline data to a **Markdown** file in the app's documents
/// folder (`rpg_me/data.md`): a human-readable table of logged activities, plus
/// fenced JSON blocks (events, axes, timers) that are the round-trip source of
/// truth. Migrates from the older data.json / shared_preferences on first read.
class LocalStore {
  static const _folder = 'rpg_me';
  static const _mdName = 'data.md';
  static const _jsonName = 'data.json'; // legacy (v0.7)

  static const _legacyEvents = 'events_v1';
  static const _legacyAxes = 'axes_v1';
  static const _legacyTimers = 'timers_v1';

  Map<String, dynamic>? _cache;

  Future<Directory> _dir() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/$_folder');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  Future<File> _mdFile() async => File('${(await _dir()).path}/$_mdName');
  Future<File> _jsonFile() async => File('${(await _dir()).path}/$_jsonName');

  Future<Map<String, dynamic>> _data() async {
    if (_cache != null) return _cache!;
    final md = await _mdFile();
    if (await md.exists()) {
      _cache = _parseMarkdown(await md.readAsString());
    } else {
      final legacy = await _jsonFile();
      if (await legacy.exists()) {
        try {
          _cache = (jsonDecode(await legacy.readAsString()) as Map).cast<String, dynamic>();
        } catch (_) {
          _cache = _empty();
        }
      } else {
        _cache = await _migrateFromPrefs();
      }
      await _flush(); // write the markdown file
    }
    return _cache!;
  }

  Map<String, dynamic> _empty() => {'events': [], 'axes': [], 'timers': []};

  Future<Map<String, dynamic>> _migrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> dec(String? raw) =>
        (raw == null || raw.isEmpty) ? [] : (jsonDecode(raw) as List);
    return {
      'events': dec(prefs.getString(_legacyEvents)),
      'axes': dec(prefs.getString(_legacyAxes)),
      'timers': dec(prefs.getString(_legacyTimers)),
    };
  }

  /// The JSON blocks (events, axes, timers in that order) are the source of
  /// truth; the human table above them is regenerated on write and ignored here.
  Map<String, dynamic> _parseMarkdown(String content) {
    final blocks = RegExp(r'```json\s*\n(.*?)\n```', dotAll: true)
        .allMatches(content)
        .map((m) => m.group(1) ?? '[]')
        .toList();
    List<dynamic> decode(int i) {
      if (i >= blocks.length) return [];
      try {
        return jsonDecode(blocks[i]) as List;
      } catch (_) {
        return [];
      }
    }

    return {'events': decode(0), 'axes': decode(1), 'timers': decode(2)};
  }

  String _renderMarkdown(Map<String, dynamic> data) {
    final events = (data['events'] as List).cast<Map<String, dynamic>>();
    final axes = (data['axes'] as List).cast<Map<String, dynamic>>();
    final labels = {for (final a in axes) a['key']: (a['label'] ?? a['key'])};
    String two(int n) => n.toString().padLeft(2, '0');
    String cell(Object? v) => v.toString().replaceAll('|', '/').replaceAll('\n', ' ');

    final sb = StringBuffer()
      ..writeln('# RPG_me — activity log\n')
      ..writeln('A human-readable log. The JSON blocks at the bottom are the '
          'source of truth — edit those (or use the app), not the table.\n')
      ..writeln('## Logged activities (${events.length})\n')
      ..writeln('| Date | Time | Category | Activity | Duration | Exp |')
      ..writeln('|------|------|----------|----------|----------|-----|');

    final sorted = [...events]
      ..sort((a, b) => (b['timestamp'] ?? '').toString().compareTo((a['timestamp'] ?? '').toString()));
    for (final e in sorted) {
      final ts = DateTime.tryParse((e['timestamp'] ?? '').toString());
      final date = ts == null ? '' : '${ts.year}-${two(ts.month)}-${two(ts.day)}';
      final time = ts == null ? '' : '${two(ts.hour)}:${two(ts.minute)}';
      final secs = (e['seconds'] ?? 0) as int;
      final dur = secs > 0 ? formatHms(secs) : '—';
      sb.writeln('| $date | $time | ${cell(labels[e['axis_key']] ?? e['axis_key'])} '
          '| ${cell(e['name'])} | $dur | ${e['exp']} |');
    }

    const enc = JsonEncoder.withIndent('  ');
    sb
      ..writeln('\n## Data (source of truth — do not hand-edit unless you know the schema)\n')
      ..writeln('### events\n```json\n${enc.convert(events)}\n```\n')
      ..writeln('### axes\n```json\n${enc.convert(axes)}\n```\n')
      ..writeln('### timers\n```json\n${enc.convert(data['timers'] ?? [])}\n```');
    return sb.toString();
  }

  Future<void> _flush() async => (await _mdFile()).writeAsString(_renderMarkdown(_cache!));

  /// The current data.md file (ensuring it exists), for export/back-up.
  Future<File> currentFile() async {
    await _data();
    return _mdFile();
  }

  /// Replace all data from exported Markdown content (parses its JSON blocks).
  Future<void> importMarkdown(String content) async {
    _cache = _parseMarkdown(content);
    await _flush();
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
