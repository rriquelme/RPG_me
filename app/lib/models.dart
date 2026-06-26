import 'package:flutter/material.dart';

/// Parse a "#RRGGBB" string into a Flutter [Color].
Color colorFromHex(String hex) {
  var value = hex.replaceFirst('#', '');
  if (value.length == 6) value = 'FF$value'; // add full opacity
  return Color(int.parse(value, radix: 16));
}

/// One point of the octagon — mirrors an entry of the API's `octagon` list.
class AxisStat {
  final String key;
  final String label;
  final Color color;
  final int level;
  final int totalExp;
  final int expIntoLevel;
  final int expToNext;

  const AxisStat({
    required this.key,
    required this.label,
    required this.color,
    required this.level,
    required this.totalExp,
    required this.expIntoLevel,
    required this.expToNext,
  });

  factory AxisStat.fromJson(Map<String, dynamic> j) {
    return AxisStat(
      key: j['key'] as String,
      label: j['label'] as String,
      color: colorFromHex((j['color'] ?? '#4C72B0') as String),
      level: (j['level'] ?? 0) as int,
      totalExp: (j['total_exp'] ?? 0) as int,
      expIntoLevel: (j['exp_into_level'] ?? 0) as int,
      expToNext: (j['exp_to_next'] ?? 1) as int,
    );
  }

  double get progress => expToNext == 0 ? 0 : expIntoLevel / expToNext;
}

/// Format a duration in seconds as a compact "1h 15m" / "20m 5s" / "8s".
String formatHms(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// Tracked time within one period — mirrors an entry of the `/time` payload.
class TimeTotals {
  final Map<String, int> byActivity; // seconds
  final Map<String, int> byAxis; // seconds
  final int totalSeconds;

  const TimeTotals({
    required this.byActivity,
    required this.byAxis,
    required this.totalSeconds,
  });

  factory TimeTotals.fromJson(Map<String, dynamic> j) {
    Map<String, int> ints(dynamic m) =>
        (m as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, v as int));
    return TimeTotals(
      byActivity: ints(j['by_activity']),
      byAxis: ints(j['by_axis']),
      totalSeconds: (j['total_seconds'] ?? 0) as int,
    );
  }

  static const empty = TimeTotals(byActivity: {}, byAxis: {}, totalSeconds: 0);
}

/// All period buckets from `GET /time`, keyed today/this_week/this_month/ytd/all_time.
class TimePeriods {
  final Map<String, TimeTotals> periods;
  const TimePeriods(this.periods);

  factory TimePeriods.fromJson(Map<String, dynamic> j) {
    final raw = (j['periods'] ?? {}) as Map<String, dynamic>;
    return TimePeriods(raw.map(
        (k, v) => MapEntry(k, TimeTotals.fromJson(v as Map<String, dynamic>))));
  }

  TimeTotals operator [](String key) => periods[key] ?? TimeTotals.empty;

  /// Display order + human labels for the UI.
  static const ordered = [
    ('today', 'Today'),
    ('this_week', 'This week'),
    ('this_month', 'This month'),
    ('ytd', 'Year to date'),
    ('all_time', 'All time'),
  ];
}

/// The dashboard snapshot — mirrors `engine.summary()`.
class Summary {
  final String user;
  final List<AxisStat> octagon;
  final Map<String, int> countsAllTime;
  final Map<String, int> countsLast7Days;
  final int totalEvents;

  const Summary({
    required this.user,
    required this.octagon,
    required this.countsAllTime,
    required this.countsLast7Days,
    required this.totalEvents,
  });

  factory Summary.fromJson(Map<String, dynamic> j) {
    Map<String, int> ints(dynamic m) =>
        (m as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, v as int));
    return Summary(
      user: (j['user'] ?? 'me') as String,
      octagon: ((j['octagon'] ?? []) as List)
          .map((e) => AxisStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      countsAllTime: ints(j['counts_all_time']),
      countsLast7Days: ints(j['counts_last_7_days']),
      totalEvents: (j['total_events'] ?? 0) as int,
    );
  }
}
