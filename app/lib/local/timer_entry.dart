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
  int targetMs; // countdown length in ms; 0 = plain count-up stopwatch

  TimerEntry({
    required this.id,
    required this.label,
    required this.axisKey,
    this.subcategory = '',
    this.accumulatedMs = 0,
    this.runningSince,
    this.targetMs = 0,
  });

  bool get isRunning => runningSince != null;

  /// Whether this is a countdown timer.
  bool get isCountdown => targetMs > 0;

  /// Remaining ms until zero (negative once it's into overtime). Only meaningful
  /// for a countdown timer.
  int get remainingMs => targetMs - elapsedMs;

  /// The moment this countdown hits zero given the current run, or null if it's
  /// not a running countdown that still has time left.
  DateTime? get zeroAt {
    if (!isCountdown || runningSince == null) return null;
    final left = remainingMs;
    if (left <= 0) return null;
    return DateTime.now().add(Duration(milliseconds: left));
  }

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
        if (targetMs > 0) 'target_ms': targetMs,
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
        targetMs: (j['target_ms'] as int?) ?? 0,
      );

  static final _rand = Random();
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_rand.nextInt(1 << 32).toRadixString(16)}';
}
