import 'package:shared_preferences/shared_preferences.dart';

/// Persisted app settings: the API base URL (for optional sync), the user, and
/// the home octagon view preferences (period window + average-per-day).
class Settings {
  static const _kBaseUrl = 'base_url';
  static const _kUser = 'user';
  static const _kPeriod = 'octagon_period';
  static const _kAverage = 'octagon_average';

  final String baseUrl;
  final String user;
  final String period; // see OctagonPeriod keys
  final bool averagePerDay;

  const Settings({
    required this.baseUrl,
    required this.user,
    this.period = 'last_30',
    this.averagePerDay = false,
  });

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Settings copyWith({String? baseUrl, String? user, String? period, bool? averagePerDay}) =>
      Settings(
        baseUrl: baseUrl ?? this.baseUrl,
        user: user ?? this.user,
        period: period ?? this.period,
        averagePerDay: averagePerDay ?? this.averagePerDay,
      );

  static Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return Settings(
      baseUrl: prefs.getString(_kBaseUrl) ?? '',
      user: prefs.getString(_kUser) ?? 'me',
      period: prefs.getString(_kPeriod) ?? 'last_30',
      averagePerDay: prefs.getBool(_kAverage) ?? false,
    );
  }

  static Future<void> save(String baseUrl, String user) async {
    final prefs = await SharedPreferences.getInstance();
    // Strip a trailing slash so we can safely concatenate paths.
    final cleaned = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_kBaseUrl, cleaned);
    await prefs.setString(_kUser, user.trim().isEmpty ? 'me' : user.trim());
  }

  static Future<void> saveView(String period, bool averagePerDay) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPeriod, period);
    await prefs.setBool(_kAverage, averagePerDay);
  }
}

/// The selectable windows for the home octagon.
class OctagonPeriod {
  final String key;
  final String label;
  const OctagonPeriod(this.key, this.label);

  static const all = [
    OctagonPeriod('last_7', 'Last 7 days'),
    OctagonPeriod('this_month', 'This month'),
    OctagonPeriod('last_30', 'Last 30 days'),
    OctagonPeriod('ytd', 'Year to date'),
    OctagonPeriod('last_365', 'Last year'),
    OctagonPeriod('all', 'All time'),
  ];

  /// Inclusive start datetime for a period key, or null for all-time.
  static DateTime? since(String key) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (key) {
      case 'last_7':
        return today.subtract(const Duration(days: 6));
      case 'this_month':
        return DateTime(now.year, now.month, 1);
      case 'last_30':
        return today.subtract(const Duration(days: 29));
      case 'ytd':
        return DateTime(now.year, 1, 1);
      case 'last_365':
        return today.subtract(const Duration(days: 364));
      case 'all':
      default:
        return null;
    }
  }

  static String labelFor(String key) =>
      all.firstWhere((p) => p.key == key, orElse: () => all[2]).label;
}
