import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rpg_me/models.dart';

void main() {
  test('colorFromHex parses #RRGGBB', () {
    expect(colorFromHex('#4C72B0'), const Color(0xFF4C72B0));
    expect(colorFromHex('DD5555'), const Color(0xFFDD5555));
  });

  test('AxisStat.fromJson maps the octagon payload', () {
    final stat = AxisStat.fromJson({
      'key': 'health',
      'label': 'Health',
      'color': '#DD5555',
      'level': 3,
      'total_exp': 200,
      'exp_into_level': 25,
      'exp_to_next': 150,
    });
    expect(stat.key, 'health');
    expect(stat.level, 3);
    expect(stat.color, const Color(0xFFDD5555));
    expect(stat.progress, closeTo(25 / 150, 1e-9));
  });

  test('Summary.fromJson maps counts and octagon', () {
    final summary = Summary.fromJson({
      'user': 'ramon',
      'total_events': 3,
      'octagon': [
        {'key': 'mind', 'label': 'Mind', 'color': '#4C72B0', 'level': 1,
         'total_exp': 20, 'exp_into_level': 20, 'exp_to_next': 75},
      ],
      'counts_all_time': {'gym': 2, 'read': 1},
      'counts_last_7_days': {'gym': 2},
    });
    expect(summary.user, 'ramon');
    expect(summary.totalEvents, 3);
    expect(summary.octagon.single.label, 'Mind');
    expect(summary.countsAllTime['gym'], 2);
    expect(summary.countsLast7Days['gym'], 2);
  });
}
