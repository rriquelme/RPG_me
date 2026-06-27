import '../models.dart';
import 'event.dart';

/// The octagon supports between 4 and 10 axes.
const int kMinAxes = 4;
const int kMaxAxes = 10;

/// One configured octagon axis (mirrors the backend's data/config.json).
class AxisDef {
  final String key;
  final String label;
  final String description;
  final String colorHex;
  const AxisDef(this.key, this.label, this.description, this.colorHex);

  AxisDef copyWith({String? label, String? description, String? colorHex}) =>
      AxisDef(key, label ?? this.label, description ?? this.description,
          colorHex ?? this.colorHex);

  Map<String, dynamic> toJson() =>
      {'key': key, 'label': label, 'description': description, 'color': colorHex};

  factory AxisDef.fromJson(Map<String, dynamic> j) => AxisDef(
        j['key'] as String,
        (j['label'] ?? j['key']) as String,
        (j['description'] ?? '') as String,
        (j['color'] ?? '#4C72B0') as String,
      );
}

/// The default 8 axes — kept in sync with the backend defaults so an offline
/// session and a synced backend agree.
const List<AxisDef> kDefaultAxes = [
  AxisDef('health', 'Health', 'Body, fitness, sleep, nutrition', '#DD5555'),
  AxisDef('mind', 'Mind', 'Learning, focus, reading', '#4C72B0'),
  AxisDef('career', 'Career', 'Work, projects, professional growth', '#55883B'),
  AxisDef('social', 'Social', 'Friends, family, relationships', '#E8A33D'),
  AxisDef('finance', 'Finance', 'Saving, budgeting, investing', '#2E8B8B'),
  AxisDef('creativity', 'Creativity', 'Making, art, music, writing', '#9457A0'),
  AxisDef('discipline', 'Discipline', 'Habits, consistency, willpower', '#555555'),
  AxisDef('spirit', 'Spirit', 'Meaning, mindfulness, rest', '#C77DB0'),
];

/// Palette offered when picking an axis colour (keeps a color-picker dep out).
const List<String> kAxisPalette = [
  '#DD5555', '#4C72B0', '#55883B', '#E8A33D', '#2E8B8B',
  '#9457A0', '#555555', '#C77DB0', '#E0658A', '#3DA5D9',
  '#6AA84F', '#B5651D',
];

const int kBaseExpPerLevel = 50;

/// Exp needed to advance *from* [level] to the next (matches models.py).
int expToNext(int level) {
  if (level < 1) level = 1;
  return (kBaseExpPerLevel * level * 1.5).toInt();
}

int levelForExp(int totalExp) {
  var level = 1;
  var remaining = totalExp < 0 ? 0 : totalExp;
  while (remaining >= expToNext(level)) {
    remaining -= expToNext(level);
    level += 1;
  }
  return level;
}

int expIntoLevel(int totalExp) {
  var level = 1;
  var remaining = totalExp < 0 ? 0 : totalExp;
  while (remaining >= expToNext(level)) {
    remaining -= expToNext(level);
    level += 1;
  }
  return remaining;
}

/// Pure, offline port of the Python engine: derives the octagon, counts,
/// streaks, and time totals from a list of [Event]s.
class LocalEngine {
  final List<Event> events;
  final List<AxisDef> axes;
  LocalEngine(this.events, [this.axes = kDefaultAxes]);

  // --- skills / octagon ---------------------------------------------------
  int _totalExp(String axisKey) =>
      events.where((e) => e.axisKey == axisKey).fold(0, (a, e) => a + e.exp);

  List<AxisStat> octagon() {
    return axes.map((axis) {
      final total = _totalExp(axis.key);
      return AxisStat(
        key: axis.key,
        label: axis.label,
        color: colorFromHex(axis.colorHex),
        level: levelForExp(total),
        totalExp: total,
        expIntoLevel: expIntoLevel(total),
        expToNext: expToNext(levelForExp(total)),
      );
    }).toList();
  }

  // --- counts / streaks ---------------------------------------------------
  Map<String, int> counts({DateTime? since}) {
    final c = <String, int>{};
    for (final e in events) {
      if (since != null && e.timestamp.isBefore(since)) continue;
      c[e.name] = (c[e.name] ?? 0) + 1;
    }
    return c;
  }

  int streak(String name) {
    name = name.trim().toLowerCase();
    final days = events
        .where((e) => e.name == name)
        .map((e) => DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day))
        .toSet();
    if (days.isEmpty) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var start = days.contains(today) ? today : today.subtract(const Duration(days: 1));
    if (!days.contains(start)) return 0;
    var streak = 0;
    var cursor = start;
    while (days.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // --- time tracking ------------------------------------------------------
  DateTime? periodStart(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'today':
        return today;
      case 'this_week':
        return today.subtract(Duration(days: today.weekday - 1)); // Monday
      case 'this_month':
        return DateTime(now.year, now.month, 1);
      case 'ytd':
        return DateTime(now.year, 1, 1);
      case 'all_time':
        return null;
      default:
        return null;
    }
  }

  TimeTotals timeTotals({DateTime? since}) {
    final byActivity = <String, int>{};
    final byAxis = <String, int>{};
    var total = 0;
    for (final e in events) {
      if (e.seconds <= 0) continue;
      if (since != null && e.timestamp.isBefore(since)) continue;
      byActivity[e.name] = (byActivity[e.name] ?? 0) + e.seconds;
      byAxis[e.axisKey] = (byAxis[e.axisKey] ?? 0) + e.seconds;
      total += e.seconds;
    }
    return TimeTotals(byActivity: byActivity, byAxis: byAxis, totalSeconds: total);
  }

  TimePeriods timePeriods() {
    final periods = <String, TimeTotals>{};
    for (final entry in TimePeriods.ordered) {
      final key = entry.$1;
      periods[key] = timeTotals(since: periodStart(key));
    }
    return TimePeriods(periods);
  }

  /// Total tracked seconds per axis (all time) — used for the hours octagon.
  Map<String, int> secondsByAxis() => timeTotals().byAxis;

  /// Exp earned per axis, optionally within a window (period-filtered octagon).
  Map<String, int> expByAxis({DateTime? since}) {
    final m = <String, int>{};
    for (final e in events) {
      if (since != null && e.timestamp.isBefore(since)) continue;
      m[e.axisKey] = (m[e.axisKey] ?? 0) + e.exp;
    }
    return m;
  }

  /// The earliest event date, or null if there are no events.
  DateTime? firstEventDate() {
    DateTime? min;
    for (final e in events) {
      if (min == null || e.timestamp.isBefore(min)) min = e.timestamp;
    }
    return min;
  }

  // --- heatmap (GitHub-squares) -------------------------------------------
  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Events logged per calendar day (frequency heatmap), optionally for one axis.
  Map<String, int> dailyCounts({String? axisKey}) {
    final m = <String, int>{};
    for (final e in events) {
      if (axisKey != null && e.axisKey != axisKey) continue;
      final k = dayKey(e.timestamp);
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  /// Tracked seconds per calendar day (time-spent heatmap), optionally per axis.
  Map<String, int> dailySeconds({String? axisKey}) {
    final m = <String, int>{};
    for (final e in events) {
      if (e.seconds <= 0) continue;
      if (axisKey != null && e.axisKey != axisKey) continue;
      final k = dayKey(e.timestamp);
      m[k] = (m[k] ?? 0) + e.seconds;
    }
    return m;
  }

  // --- snapshot -----------------------------------------------------------
  Summary summary({String user = 'me'}) {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return Summary(
      user: user,
      octagon: octagon(),
      countsAllTime: counts(),
      countsLast7Days: counts(since: weekAgo),
      totalEvents: events.length,
      secondsByAxis: secondsByAxis(),
    );
  }
}
