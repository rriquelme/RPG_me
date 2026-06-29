import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rpg_me/settings.dart';

void main() {
  test('this_week start respects the first day of the week', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final monStart = OctagonPeriod.since('this_week', firstDayOfWeek: DateTime.monday)!;
    expect(monStart.weekday, DateTime.monday);
    expect(monStart.isAfter(today), false);
    expect(today.difference(monStart).inDays, lessThan(7));

    final sunStart = OctagonPeriod.since('this_week', firstDayOfWeek: DateTime.sunday)!;
    expect(sunStart.weekday, DateTime.sunday);
    expect(today.difference(sunStart).inDays, lessThan(7));
  });

  test('all-time period is null', () {
    expect(OctagonPeriod.since('all'), isNull);
  });
}
