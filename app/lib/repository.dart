import 'dart:io';

import 'api.dart';
import 'local/event.dart';
import 'local/local_engine.dart';
import 'local/local_store.dart';
import 'local/timer_entry.dart';
import 'models.dart';
import 'settings.dart';

/// Result of a sync attempt, for surfacing in the UI.
class SyncResult {
  final int pushed;
  final bool ok;
  final String? error;
  const SyncResult({required this.pushed, required this.ok, this.error});
}

/// Per-axis data for the home octagon over a chosen period.
class OctagonView {
  final List<AxisDef> axes;
  final Map<String, int> seconds; // per axis, within the window
  final Map<String, int> exp; // per axis, within the window
  final Map<String, int> counts; // events per axis, within the window
  final int days; // days the window covers (for average-per-day)
  const OctagonView({
    required this.axes,
    required this.seconds,
    required this.exp,
    required this.counts,
    required this.days,
  });
}

/// Local-first data layer. All reads/writes hit the on-device event log so the
/// app works fully offline; [sync] optionally pushes unsynced events to the
/// backend when one is configured.
class Repository {
  final LocalStore _store;
  List<Event> _events;
  List<AxisDef> _axes;
  Settings settings;

  Repository._(this._store, this._events, this._axes, this.settings);

  static Future<Repository> create() async {
    final store = LocalStore();
    final events = await store.loadEvents();
    final axes = await store.loadAxes();
    final settings = await Settings.load();
    return Repository._(store, events, axes, settings);
  }

  LocalEngine get _engine => LocalEngine(_events, _axes);

  // --- axis config --------------------------------------------------------
  List<AxisDef> get axesConfig => List.unmodifiable(_axes);

  /// Persist an edited axis config. Enforces the 6–10 count and unique keys.
  Future<void> saveAxes(List<AxisDef> axes) async {
    if (axes.length < kMinAxes || axes.length > kMaxAxes) {
      throw ArgumentError('The octagon needs between $kMinAxes and $kMaxAxes axes.');
    }
    final keys = axes.map((a) => a.key).toSet();
    if (keys.length != axes.length) {
      throw ArgumentError('Axis keys must be unique.');
    }
    if (axes.any((a) => a.label.trim().isEmpty)) {
      throw ArgumentError('Every axis needs a name.');
    }
    _axes = List.of(axes);
    await _store.saveAxes(_axes);
  }

  // --- reads (async to fit the existing FutureBuilder screens) ------------
  Future<List<AxisStat>> axes() async => _engine.octagon();
  Future<Summary> summary() async => _engine.summary(user: settings.user);
  Future<TimePeriods> time() async => _engine.timePeriods();

  // --- writes -------------------------------------------------------------
  Future<void> log(
    String axisKey,
    String name, {
    int? exp,
    String note = '',
    int seconds = 0,
    DateTime? at,
    String subcategory = '',
    bool hidden = false,
  }) async {
    final perMinute = (seconds / 60).round();
    final resolvedExp = exp ?? (seconds > 0 ? (perMinute < 1 ? 1 : perMinute) : 10);
    _events.add(Event(
      id: Event.newId(),
      axisKey: axisKey,
      name: name.trim().toLowerCase(),
      subcategory: subcategory.trim(),
      hidden: hidden,
      exp: resolvedExp,
      note: note,
      timestamp: at ?? DateTime.now(),
      seconds: seconds,
      synced: false,
    ));
    await _store.saveEvents(_events);
  }

  Future<Map<String, int>> secondsByAxis() async => _engine.secondsByAxis();
  Future<Map<String, int>> dailyCounts({String? axisKey, String? subcategory}) async =>
      _engine.dailyCounts(axisKey: axisKey, subcategory: subcategory);
  Future<Map<String, int>> dailySeconds({String? axisKey, String? subcategory}) async =>
      _engine.dailySeconds(axisKey: axisKey, subcategory: subcategory);

  /// Per-day breakdown of an axis's subcategories (counts/seconds + the
  /// dominant subcategory each day), for the "all subcategories" heatmap.
  Future<SubcatDays> subcategoryDays(String axisKey) async =>
      _engine.subcategoryDays(axisKey);

  // --- logged activity history -------------------------------------------
  /// All logged events, most recent first.
  List<Event> allEvents() {
    final list = [..._events]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Future<void> deleteEvent(String id) async {
    _events.removeWhere((e) => e.id == id);
    await _store.saveEvents(_events);
  }

  /// Edit an existing logged event. Keeps its id, recomputes exp from the new
  /// duration, and marks it unsynced so the change re-syncs.
  Future<void> updateEvent(
    String id, {
    required String axisKey,
    required String name,
    int seconds = 0,
    DateTime? at,
    String note = '',
    String subcategory = '',
    bool hidden = false,
  }) async {
    final i = _events.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final perMinute = (seconds / 60).round();
    final exp = seconds > 0 ? (perMinute < 1 ? 1 : perMinute) : 10;
    _events[i] = Event(
      id: id,
      axisKey: axisKey,
      name: name.trim().toLowerCase(),
      subcategory: subcategory.trim(),
      hidden: hidden,
      exp: exp,
      note: note,
      timestamp: at ?? _events[i].timestamp,
      seconds: seconds,
      synced: false,
    );
    await _store.saveEvents(_events);
  }

  // --- period-aware octagon data -----------------------------------------
  /// Per-axis seconds + exp within [since] (null = all time) and the number of
  /// days the window covers (for "average per day").
  OctagonView octagonView(DateTime? since) {
    int days;
    if (since == null) {
      final first = _engine.firstEventDate();
      days = first == null
          ? 1
          : DateTime.now().difference(DateTime(first.year, first.month, first.day)).inDays + 1;
    } else {
      days = DateTime.now().difference(since).inDays + 1;
    }
    if (days < 1) days = 1;
    return OctagonView(
      axes: _axes,
      seconds: _engine.timeTotals(since: since, excludeHidden: true).byAxis,
      exp: _engine.expByAxis(since: since, excludeHidden: true),
      counts: _engine.countByAxis(since: since, excludeHidden: true),
      days: days,
    );
  }

  // --- timers (multiple, concurrent) --------------------------------------
  Future<List<TimerEntry>> loadTimers() => _store.loadTimers();
  Future<void> saveTimers(List<TimerEntry> timers) => _store.saveTimers(timers);

  // --- Markdown export / import ------------------------------------------
  /// The on-disk Markdown log file (`rpg_me/data.md`) to share/back up.
  Future<File> exportFile() => _store.currentFile();

  /// Replace all data from a previously exported Markdown log, then reload.
  Future<void> importMarkdown(String content) async {
    await _store.importMarkdown(content);
    _events = await _store.loadEvents();
    _axes = await _store.loadAxes();
  }

  // --- sync ---------------------------------------------------------------
  int get unsyncedCount => _events.where((e) => !e.synced).length;

  Future<void> updateSettings(Settings s) async {
    settings = s;
  }

  /// Push all unsynced events to the backend (idempotent). Marks them synced
  /// on success and persists. Throws nothing — returns a [SyncResult].
  Future<SyncResult> sync() async {
    if (!settings.isConfigured) {
      return const SyncResult(
          pushed: 0, ok: false, error: 'No backend configured. Add an API URL in Settings.');
    }
    final pending = _events.where((e) => !e.synced).toList();
    if (pending.isEmpty) return const SyncResult(pushed: 0, ok: true);

    final api = ApiClient(baseUrl: settings.baseUrl, user: settings.user);
    try {
      // Push the axis config first so the server recognizes custom axes.
      await api.putConfig(_axes.map((a) => a.toJson()).toList());
      final acked = await api.sync(pending.map((e) => e.toSyncJson()).toList());
      for (final e in _events) {
        if (acked.contains(e.id)) e.synced = true;
      }
      await _store.saveEvents(_events);
      return SyncResult(pushed: acked.length, ok: true);
    } on ApiException catch (e) {
      return SyncResult(pushed: 0, ok: false, error: e.message);
    } catch (e) {
      return SyncResult(pushed: 0, ok: false, error: e.toString());
    } finally {
      api.close();
    }
  }
}
