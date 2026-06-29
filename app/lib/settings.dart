import 'package:shared_preferences/shared_preferences.dart';

/// Persisted app settings: the API base URL (for optional sync), the user, the
/// home octagon view preferences (period + average-per-day), and the first day
/// of the week.
class Settings {
  static const _kBaseUrl = 'base_url';
  static const _kUser = 'user';
  static const _kPeriod = 'octagon_period';
  static const _kAverage = 'octagon_average';
  static const _kFirstDay = 'first_day_of_week';
  static const _kShowDash = 'show_dashboard_on_log';

  final String baseUrl;
  final String user;
  final String period; // see OctagonPeriod keys
  final bool averagePerDay;
  final int firstDayOfWeek; // DateTime.monday(1)..DateTime.sunday(7)
  final bool showDashboardOnLog; // show a category dashboard atop the Log screen

  const Settings({
    required this.baseUrl,
    required this.user,
    this.period = 'this_week',
    this.averagePerDay = false,
    this.firstDayOfWeek = DateTime.monday,
    this.showDashboardOnLog = false,
  });

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Settings copyWith({
    String? baseUrl,
    String? user,
    String? period,
    bool? averagePerDay,
    int? firstDayOfWeek,
    bool? showDashboardOnLog,
  }) =>
      Settings(
        baseUrl: baseUrl ?? this.baseUrl,
        user: user ?? this.user,
        period: period ?? this.period,
        averagePerDay: averagePerDay ?? this.averagePerDay,
        firstDayOfWeek: firstDayOfWeek ?? this.firstDayOfWeek,
        showDashboardOnLog: showDashboardOnLog ?? this.showDashboardOnLog,
      );

  static Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return Settings(
      baseUrl: prefs.getString(_kBaseUrl) ?? '',
      user: prefs.getString(_kUser) ?? 'me',
      period: prefs.getString(_kPeriod) ?? 'this_week',
      averagePerDay: prefs.getBool(_kAverage) ?? false,
      firstDayOfWeek: prefs.getInt(_kFirstDay) ?? DateTime.monday,
      showDashboardOnLog: prefs.getBool(_kShowDash) ?? false,
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

  static Future<void> saveFirstDayOfWeek(int day) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFirstDay, day);
  }

  static Future<void> saveShowDashboardOnLog(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowDash, show);
  }
}

/// The selectable windows for the home octagon.
class OctagonPeriod {
  final String key;
  final String label;
  const OctagonPeriod(this.key, this.label);

  static const all = [
    OctagonPeriod('this_week', 'This week'),
    OctagonPeriod('last_7', 'Last 7 days'),
    OctagonPeriod('this_month', 'This month'),
    OctagonPeriod('last_30', 'Last 30 days'),
    OctagonPeriod('ytd', 'Year to date'),
    OctagonPeriod('last_365', 'Last year'),
    OctagonPeriod('all', 'All time'),
  ];

  /// Inclusive start datetime for a period key, or null for all-time.
  /// "This week" starts on [firstDayOfWeek] (DateTime.monday..sunday).
  static DateTime? since(String key, {int firstDayOfWeek = DateTime.monday}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (key) {
      case 'this_week':
        final delta = (today.weekday - firstDayOfWeek + 7) % 7;
        return today.subtract(Duration(days: delta));
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
      all.firstWhere((p) => p.key == key, orElse: () => all[0]).label;
}

/// Weekday names for the "first day of week" setting (index 1..7 = Mon..Sun).
const Map<int, String> kWeekdayNames = {
  DateTime.monday: 'Monday',
  DateTime.tuesday: 'Tuesday',
  DateTime.wednesday: 'Wednesday',
  DateTime.thursday: 'Thursday',
  DateTime.friday: 'Friday',
  DateTime.saturday: 'Saturday',
  DateTime.sunday: 'Sunday',
};
