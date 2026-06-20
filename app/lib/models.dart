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
