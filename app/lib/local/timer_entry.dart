import 'dart:math';

/// One running/paused stopwatch. Multiple can run at once. Elapsed time is
/// derived from wall-clock (a [runningSince] timestamp) so it stays correct
/// even while the app is backgrounded or after a restart. Tracked at
/// millisecond precision so the display can tick fast.
class TimerEntry {
  final String id;
  String label; // activity name, e.g. "study"
  String axisKey; // category
  String subcategory; // optional subcategory within the category
  int accumulatedMs; // banked time while paused
  DateTime? runningSince; // non-null while running

  TimerEntry({
    required this.id,
    required this.label,
    required this.axisKey,
    this.subcategory = '',
    this.accumulatedMs = 0,
    this.runningSince,
  });

  bool get isRunning => runningSince != null;

  int get elapsedMs {
    var total = accumulatedMs;
    if (runningSince != null) {
      total += DateTime.now().difference(runningSince!).inMilliseconds;
    }
    return total;
  }

  int get elapsedSeconds => elapsedMs ~/ 1000;

  void start() {
    runningSince ??= DateTime.now();
  }

  void pause() {
    if (runningSince != null) {
      accumulatedMs += DateTime.now().difference(runningSince!).inMilliseconds;
      runningSince = null;
    }
  }

  /// Zero the elapsed time. Keeps running (from now) if it was running.
  void reset() {
    accumulatedMs = 0;
    if (runningSince != null) runningSince = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'axis_key': axisKey,
        if (subcategory.isNotEmpty) 'subcategory': subcategory,
        'accumulated_ms': accumulatedMs,
        'running_since': runningSince?.toIso8601String(),
      };

  factory TimerEntry.fromJson(Map<String, dynamic> j) => TimerEntry(
        id: j['id'] as String,
        label: (j['label'] ?? '') as String,
        axisKey: j['axis_key'] as String,
        subcategory: (j['subcategory'] ?? '') as String,
        // Migrate older entries that stored whole seconds in 'accumulated'.
        accumulatedMs: (j['accumulated_ms'] as int?) ??
            (((j['accumulated'] ?? 0) as int) * 1000),
        runningSince: j['running_since'] != null
            ? DateTime.parse(j['running_since'] as String)
            : null,
      );

  static final _rand = Random();
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_rand.nextInt(1 << 32).toRadixString(16)}';
}
