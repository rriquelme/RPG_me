import 'dart:convert';
import 'package:http/http.dart' as http;

import 'models.dart';

/// Thin client for the RPG_me HTTP API (the Phase 2 Lambda backend).
class ApiClient {
  final String baseUrl;
  final String user;
  final http.Client _http;

  ApiClient({required this.baseUrl, required this.user, http.Client? client})
      : _http = client ?? http.Client();

  Uri _uri(String path) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: {'user': user});

  Future<List<String>> axisKeys() async {
    final res = await _http.get(Uri.parse('$baseUrl/axes'));
    _check(res);
    final list = (jsonDecode(res.body)['axes'] as List).cast<Map<String, dynamic>>();
    return list.map((a) => a['key'] as String).toList();
  }

  Future<List<AxisStat>> axes() async {
    final res = await _http.get(Uri.parse('$baseUrl/axes'));
    _check(res);
    // /axes returns config (no levels); fall back to level 0 for the picker.
    final list = (jsonDecode(res.body)['axes'] as List).cast<Map<String, dynamic>>();
    return list.map(AxisStat.fromJson).toList();
  }

  Future<Summary> summary() async {
    final res = await _http.get(_uri('/summary'));
    _check(res);
    return Summary.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Log an activity. Pass [seconds] > 0 to record a timed session (exp then
  /// defaults to one point per tracked minute on the server).
  Future<void> log(String axis, String name,
      {int? exp, String note = '', int seconds = 0}) async {
    final payload = <String, dynamic>{
      'axis': axis,
      'name': name,
      'note': note,
      'seconds': seconds,
    };
    if (exp != null) payload['exp'] = exp;
    final res = await _http.post(
      _uri('/log'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    _check(res);
  }

  Future<TimePeriods> time() async {
    final res = await _http.get(_uri('/time'));
    _check(res);
    return TimePeriods.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<int> streak(String name) async {
    final res = await _http.get(_uri('/streak/$name'));
    _check(res);
    return (jsonDecode(res.body)['streak'] ?? 0) as int;
  }

  void _check(http.Response res) {
    if (res.statusCode >= 400) {
      String message = res.body;
      try {
        message = (jsonDecode(res.body)['error'] ?? res.body).toString();
      } catch (_) {}
      throw ApiException(res.statusCode, message);
    }
  }

  void close() => _http.close();
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'API $statusCode: $message';
}
