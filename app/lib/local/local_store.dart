import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'event.dart';

/// Persists the offline event log to device storage (shared_preferences).
class LocalStore {
  static const _kEvents = 'events_v1';

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
}
