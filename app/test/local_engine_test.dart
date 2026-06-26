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
