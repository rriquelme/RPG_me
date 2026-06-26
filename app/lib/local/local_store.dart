import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'event.dart';
import 'local_engine.dart';

/// Persists the offline event log and axis config to device storage.
class LocalStore {
  static const _kEvents = 'events_v1';
  static const _kAxes = 'axes_v1';

  Future<List<Event>> loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kEvents);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(Event.fromStorageJson).toList();
  }

  Future<void> saveEvents(List<Event> events) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(events.map((e) => e.toStorageJson()).toList());
    await prefs.setString(_kEvents, raw);
  }

  /// Loads the saved axis config, or the defaults on first run.
  Future<List<AxisDef>> loadAxes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAxes);
    if (raw == null || raw.isEmpty) return List.of(kDefaultAxes);
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final axes = list.map(AxisDef.fromJson).toList();
    return axes.isEmpty ? List.of(kDefaultAxes) : axes;
  }

  Future<void> saveAxes(List<AxisDef> axes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAxes, jsonEncode(axes.map((a) => a.toJson()).toList()));
  }
}
