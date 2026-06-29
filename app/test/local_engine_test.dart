import 'package:flutter_test/flutter_test.dart';
import 'package:rpg_me/local/event.dart';
import 'package:rpg_me/local/local_engine.dart';

Event ev(String axis, String name,
    {int exp = 10, int seconds = 0, DateTime? at}) {
  return Event(
    id: Event.newId(),
    axisKey: axis,
    name: name,
    exp: exp,
    seconds: seconds,
    timestamp: at ?? DateTime.now(),
  );
}

void main() {
  test('exp curve matches the backend', () {
    expect(expToNext(1), 75); // int(50 * 1 * 1.5)
    expect(expToNext(2), 150);
    expect(levelForExp(0), 1);
    expect(levelForExp(75), 2);
    expect(expIntoLevel(80), 5);
  });

  test('octagon has 8 axes and reflects exp', () {
    final eng = LocalEngine([ev('health', 'gym', exp: 75)]);
    final oct = {for (final a in eng.octagon()) a.key: a};
    expect(oct.length, 8);
    expect(oct['health']!.level, 2);
    expect(oct['mind']!.level, 1);
  });

  test('counts and streak', () {
    final today = DateTime.now();
    final eng = LocalEngine([
      ev('health', 'gym', at: today),
      ev('health', 'gym', at: today.subtract(const Duration(days: 1))),
      ev('mind', 'read', at: today),
    ]);
    expect(eng.counts()['gym'], 2);
    expect(eng.streak('gym'), 2);
    expect(eng.streak('read'), 1);
  });

  test('time periods group by activity and exclude count-only events', () {
    final eng = LocalEngine([
      ev('mind', 'study', exp: 45, seconds: 2700),
      ev('mind', 'read'), // no duration
    ]);
    final today = eng.timePeriods()['today'];
    expect(today.byActivity['study'], 2700);
    expect(today.byActivity.containsKey('read'), false);
    expect(today.totalSeconds, 2700);
  });

  test('octagon honors a custom 6-axis config', () {
    final axes = const [
      AxisDef('a', 'A', '', '#DD5555'),
      AxisDef('b', 'B', '', '#4C72B0'),
      AxisDef('c', 'C', '', '#55883B'),
      AxisDef('d', 'D', '', '#E8A33D'),
      AxisDef('e', 'E', '', '#2E8B8B'),
      AxisDef('f', 'F', '', '#9457A0'),
    ];
    final eng = LocalEngine([ev('c', 'thing', exp: 75)], axes);
    final oct = eng.octagon();
    expect(oct.length, 6);
    expect({for (final a in oct) a.key: a.level}['c'], 2);
  });

  test('AxisDef round-trips through json', () {
    const a = AxisDef('study', 'Study', 'desc', '#4C72B0');
    final back = AxisDef.fromJson(a.toJson());
    expect(back.key, 'study');
    expect(back.label, 'Study');
    expect(back.colorHex, '#4C72B0');
    // Defaults: visible, no subcategories.
    expect(back.hidden, false);
    expect(back.subcategories, isEmpty);
  });

  test('AxisDef round-trips hidden flag and subcategories', () {
    const a = AxisDef('health', 'Health', '', '#DD5555',
        hidden: true, subcategories: ['gym', 'run', 'sleep']);
    final back = AxisDef.fromJson(a.toJson());
    expect(back.hidden, true);
    expect(back.subcategories, ['gym', 'run', 'sleep']);
    // Older configs without the keys default cleanly.
    final legacy = AxisDef.fromJson(
        {'key': 'mind', 'label': 'Mind', 'color': '#4C72B0'});
    expect(legacy.hidden, false);
    expect(legacy.subcategories, isEmpty);
  });

  test('secondsByAxis and daily aggregates for octagon/heatmap', () {
    final today = DateTime.now();
    final eng = LocalEngine([
      ev('mind', 'study', exp: 30, seconds: 1800, at: today),
      ev('mind', 'read', exp: 10, at: today), // count-only
      ev('health', 'gym', exp: 60, seconds: 3600, at: today),
    ]);
    expect(eng.secondsByAxis()['mind'], 1800);
    expect(eng.secondsByAxis()['health'], 3600);
    // daily counts include the count-only event; daily seconds do not
    final dk = LocalEngine.dayKey(today);
    expect(eng.dailyCounts()[dk], 3);
    expect(eng.dailySeconds()[dk], 5400);
  });

  test('summary carries secondsByAxis', () {
    final eng = LocalEngine([ev('mind', 'study', seconds: 1200)]);
    expect(eng.summary().secondsByAxis['mind'], 1200);
  });

  test('expByAxis respects the period window', () {
    final now = DateTime.now();
    final eng = LocalEngine([
      ev('mind', 'study', exp: 30, at: now),
      ev('mind', 'old', exp: 100, at: now.subtract(const Duration(days: 60))),
    ]);
    expect(eng.expByAxis()['mind'], 130); // all time
    final since = now.subtract(const Duration(days: 7));
    expect(eng.expByAxis(since: since)['mind'], 30); // last week only
  });

  test('countByAxis counts events incl. duration-less tallies', () {
    final now = DateTime.now();
    final eng = LocalEngine([
      ev('health', 'gym', exp: 10, at: now), // count-only, no duration
      ev('health', 'gym', exp: 10, at: now),
      ev('mind', 'study', seconds: 1800, at: now),
      ev('health', 'old', at: now.subtract(const Duration(days: 40))),
    ]);
    expect(eng.countByAxis()['health'], 3); // all time
    expect(eng.countByAxis()['mind'], 1);
    final since = now.subtract(const Duration(days: 7));
    expect(eng.countByAxis(since: since)['health'], 2); // window excludes the old one
  });

  test('daily aggregates can be filtered by axis', () {
    final today = DateTime.now();
    final eng = LocalEngine([
      ev('mind', 'study', seconds: 1800, at: today),
      ev('health', 'gym', seconds: 3600, at: today),
    ]);
    final dk = LocalEngine.dayKey(today);
    expect(eng.dailySeconds(axisKey: 'mind')[dk], 1800);
    expect(eng.dailySeconds(axisKey: 'health')[dk], 3600);
    expect(eng.dailyCounts(axisKey: 'mind')[dk], 1);
  });

  test('ytd excludes prior-year events', () {
    final now = DateTime.now();
    final lastYear = DateTime(now.year - 1, 6, 1, 12);
    final eng = LocalEngine([
      ev('health', 'gym', seconds: 3600, at: lastYear),
    ]);
    expect(eng.timePeriods()['ytd'].totalSeconds, 0);
    expect(eng.timePeriods()['all_time'].totalSeconds, 3600);
  });
}
