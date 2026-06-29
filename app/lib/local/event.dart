import 'dart:math';

/// A locally-stored activity event. Mirrors the backend event, plus a [synced]
/// flag tracking whether it has been pushed to the server yet.
class Event {
  final String id;
  final String axisKey;
  final String name;

  /// Optional subcategory within [axisKey] (empty if none).
  final String subcategory;

  /// When true, this entry is excluded from the octagon (axis graph) — it is
  /// still logged and counted everywhere else.
  final bool hidden;

  /// Optional free number for this log (null = not tracked).
  final double? number;

  /// Optional 0–100 percentage for this log (null = not tracked).
  final double? percentage;
  final int exp;
  final String note;
  final DateTime timestamp;
  final int seconds;
  bool synced;

  Event({
    required this.id,
    required this.axisKey,
    required this.name,
    required this.exp,
    required this.timestamp,
    this.subcategory = '',
    this.hidden = false,
    this.number,
    this.percentage,
    this.note = '',
    this.seconds = 0,
    this.synced = false,
  });

  /// Local storage form (keeps the [synced] flag).
  Map<String, dynamic> toStorageJson() => {
        'id': id,
        'axis_key': axisKey,
        'name': name,
        if (subcategory.isNotEmpty) 'subcategory': subcategory,
        if (hidden) 'hidden': true,
        if (number != null) 'number': number,
        if (percentage != null) 'percentage': percentage,
        'exp': exp,
        'note': note,
        'timestamp': timestamp.toIso8601String(),
        'seconds': seconds,
        'synced': synced,
      };

  factory Event.fromStorageJson(Map<String, dynamic> j) => Event(
        id: j['id'] as String,
        axisKey: j['axis_key'] as String,
        name: j['name'] as String,
        subcategory: (j['subcategory'] ?? '') as String,
        hidden: (j['hidden'] ?? false) as bool,
        number: (j['number'] as num?)?.toDouble(),
        percentage: (j['percentage'] as num?)?.toDouble(),
        exp: (j['exp'] ?? 0) as int,
        note: (j['note'] ?? '') as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        seconds: (j['seconds'] ?? 0) as int,
        synced: (j['synced'] ?? false) as bool,
      );

  /// Payload the server's POST /sync expects (no [synced] flag).
  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'axis': axisKey,
        'name': name,
        if (subcategory.isNotEmpty) 'subcategory': subcategory,
        if (hidden) 'hidden': true,
        if (number != null) 'number': number,
        if (percentage != null) 'percentage': percentage,
        'exp': exp,
        'note': note,
        'timestamp': timestamp.toIso8601String(),
        'seconds': seconds,
      };

  static final _rand = Random();

  /// A stable, collision-resistant id generated offline.
  static String newId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final salt = _rand.nextInt(1 << 32).toRadixString(16);
    return '$micros-$salt';
  }
}
