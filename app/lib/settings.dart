import 'package:shared_preferences/shared_preferences.dart';

/// Persisted app settings: the API base URL (from the SAM stack's `ApiUrl`
/// output) and which character/user to show.
class Settings {
  static const _kBaseUrl = 'base_url';
  static const _kUser = 'user';

  final String baseUrl;
  final String user;

  const Settings({required this.baseUrl, required this.user});

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  static Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return Settings(
      baseUrl: prefs.getString(_kBaseUrl) ?? '',
      user: prefs.getString(_kUser) ?? 'me',
    );
  }

  static Future<void> save(String baseUrl, String user) async {
    final prefs = await SharedPreferences.getInstance();
    // Strip a trailing slash so we can safely concatenate paths.
    final cleaned = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_kBaseUrl, cleaned);
    await prefs.setString(_kUser, user.trim().isEmpty ? 'me' : user.trim());
  }
}
