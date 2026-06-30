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
  static const _kTrackNumber = 'track_number';
  static const _kTrackPercentage = 'track_percentage';
  static const _kLogBtn = 'show_log_button';
  static const _kAddCatBtn = 'show_add_category_button';
  static const _kAddSubBtn = 'show_add_subcategory_button';
  static const _kDayNumbers = 'show_day_numbers';
  static const _kOctagonScale = 'octagon_scale';

  final String baseUrl;
  final String user;
  final String period; // see OctagonPeriod keys
  final bool averagePerDay;
  final int firstDayOfWeek; // DateTime.monday(1)..DateTime.sunday(7)
  final bool showDashboardOnLog; // show a category dashboard atop the Log screen
  final bool trackNumber; // enable the "number" metric + log field
  final bool trackPercentage; // enable the "percentage" metric + log field
  final bool showLogButton; // bottom +Log button
  final bool showAddCategoryButton; // bottom +Category button
  final bool showAddSubcategoryButton; // bottom +Subcategory button
  final bool showDayNumbers; // day-of-month numbers in the activity heatmaps
  final String octagonScale; // 'linear' | 'log' | 'exp'

  const Settings({
    required this.baseUrl,
    required this.user,
    this.period = 'this_week',
    this.averagePerDay = false,
    this.firstDayOfWeek = DateTime.monday,
    this.showDashboardOnLog = false,
    this.trackNumber = false,
    this.trackPercentage = false,
    this.showLogButton = true,
    this.showAddCategoryButton = false,
    this.showAddSubcategoryButton = false,
    this.showDayNumbers = false,
    this.octagonScale = 'linear',
  });

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Settings copyWith({
    String? baseUrl,
    String? user,
    String? period,
    bool? averagePerDay,
    int? firstDayOfWeek,
    bool? showDashboardOnLog,
    bool? trackNumber,
    bool? trackPercentage,
    bool? showLogButton,
    bool? showAddCategoryButton,
    bool? showAddSubcategoryButton,
    bool? showDayNumbers,
    String? octagonScale,
  }) =>
      Settings(
        baseUrl: baseUrl ?? this.baseUrl,
        user: user ?? this.user,
        period: period ?? this.period,
        averagePerDay: averagePerDay ?? this.averagePerDay,
        firstDayOfWeek: firstDayOfWeek ?? this.firstDayOfWeek,
        showDashboardOnLog: showDashboardOnLog ?? this.showDashboardOnLog,
        trackNumber: trackNumber ?? this.trackNumber,
        trackPercentage: trackPercentage ?? this.trackPercentage,
        showLogButton: showLogButton ?? this.showLogButton,
        showAddCategoryButton:
            showAddCategoryButton ?? this.showAddCategoryButton,
        showAddSubcategoryButton:
            showAddSubcategoryButton ?? this.showAddSubcategoryButton,
        showDayNumbers: showDayNumbers ?? this.showDayNumbers,
        octagonScale: octagonScale ?? this.octagonScale,
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
      trackNumber: prefs.getBool(_kTrackNumber) ?? false,
      trackPercentage: prefs.getBool(_kTrackPercentage) ?? false,
      showLogButton: prefs.getBool(_kLogBtn) ?? true,
      showAddCategoryButton: prefs.getBool(_kAddCatBtn) ?? false,
      showAddSubcategoryButton: prefs.getBool(_kAddSubBtn) ?? false,
      showDayNumbers: prefs.getBool(_kDayNumbers) ?? false,
      octagonScale: prefs.getString(_kOctagonScale) ?? 'linear',
    );
  }

  static Future<void> saveOctagonScale(String scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOctagonScale, scale);
  }

  static Future<void> saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  // Keys for the boolean toggles, exposed for saveBool.
  static const kLogBtnKey = _kLogBtn;
  static const kAddCatBtnKey = _kAddCatBtn;
  static const kAddSubBtnKey = _kAddSubBtn;
  static const kDayNumbersKey = _kDayNumbers;

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

  static Future<void> saveTrackNumber(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTrackNumber, on);
  }

  static Future<void> saveTrackPercentage(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTrackPercentage, on);
  }
}

/// The selectable windows for the home octagon.
class OctagonPeriod {
  final String key;
  final String label;
  const OctagonPeriod(this.key, this.label);

  static const all = [
    OctagonPeriod('today', 'Today'),
    OctagonPeriod('this_week', 'This week'),
    OctagonPeriod('this_month', 'This month'),
    OctagonPeriod('this_year', 'This year'),
    OctagonPeriod('all', 'All time'),
    OctagonPeriod('custom_day', 'Custom: single day'),
    OctagonPeriod('custom_range', 'Custom: range of days'),
  ];

  /// Inclusive start datetime for a period key, or null for all-time.
  /// "This week" starts on [firstDayOfWeek] (DateTime.monday..sunday).
  static DateTime? since(String key, {int firstDayOfWeek = DateTime.monday}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (key) {
      case 'today':
        return today;
      case 'this_week':
        final delta = (today.weekday - firstDayOfWeek + 7) % 7;
        return today.subtract(Duration(days: delta));
      case 'last_7':
        return today.subtract(const Duration(days: 6));
      case 'this_month':
        return DateTime(now.year, now.month, 1);
      case 'this_year':
        return DateTime(now.year, 1, 1);
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
