import 'api.dart';
import 'local/event.dart';
import 'local/local_engine.dart';
import 'local/local_store.dart';
import 'models.dart';
import 'settings.dart';

/// Result of a sync attempt, for surfacing in the UI.
class SyncResult {
  final int pushed;
  final bool ok;
  final String? error;
  const SyncResult({required this.pushed, required this.ok, this.error});
}

/// Local-first data layer. All reads/writes hit the on-device event log so the
/// app works fully offline; [sync] optionally pushes unsynced events to the
/// backend when one is configured.
class Repository {
  final LocalStore _store;
  List<Event> _events;
  Settings settings;

  Repository._(this._store, this._events, this.settings);

  static Future<Repository> create() async {
    final store = LocalStore();
    final events = await store.loadEvents();
    final settings = await Settings.load();
    return Repository._(store, events, settings);
  }

  LocalEngine get _engine => LocalEngine(_events);

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
  }) async {
    final perMinute = (seconds / 60).round();
    final resolvedExp = exp ?? (seconds > 0 ? (perMinute < 1 ? 1 : perMinute) : 10);
    _events.add(Event(
      id: Event.newId(),
      axisKey: axisKey,
      name: name.trim().toLowerCase(),
      exp: resolvedExp,
      note: note,
      timestamp: DateTime.now(),
      seconds: seconds,
      synced: false,
    ));
    await _store.saveEvents(_events);
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
