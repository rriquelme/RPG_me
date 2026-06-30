import 'package:flutter_test/flutter_test.dart';
import 'package:rpg_me/local/event.dart';
import 'package:rpg_me/local/local_engine.dart';

Event ev(String axis, String name,
    {int exp = 10, int seconds = 0, DateTime? at, bool hidden = false}) {
  return Event(
    id: Event.newId(),
    axisKey: axis,
    name: name,
    exp: exp,
    seconds: seconds,
    hidden: hidden,
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

  test('AxisDef round-trips hidden flag and subcategories with colours', () {
    const a = AxisDef('health', 'Health', '', '#DD5555', hidden: true,
        subcategories: [
          SubcategoryDef('gym', '#55883B'),
          SubcategoryDef('run'),
        ]);
    final back = AxisDef.fromJson(a.toJson());
    expect(back.hidden, true);
    expect(back.subcategoryNames, ['gym', 'run']);
    expect(back.subcategoryByName('gym')!.colorHex, '#55883B');
    expect(back.subcategoryByName('run')!.colorHex, ''); // inherits axis colour
    // Legacy: subcategories stored as plain strings still parse.
    final legacy = AxisDef.fromJson({
      'key': 'mind',
      'label': 'Mind',
      'color': '#4C72B0',
      'subcategories': ['read', 'study'],
    });
    expect(legacy.subcategoryNames, ['read', 'study']);
    expect(legacy.hidden, false);
    // And a config with no subcategories key at all.
    final none =
        AxisDef.fromJson({'key': 'x', 'label': 'X', 'color': '#000000'});
    expect(none.subcategories, isEmpty);
  });

  test('hidden subcategories are excluded from the octagon and breakdown', () {
    final day = DateTime(2026, 6, 1, 9);
    Event e(String id, String sub, {int secs = 0}) => Event(
        id: id, axisKey: 'health', name: 'x', exp: 10, timestamp: day,
        seconds: secs, subcategory: sub);
    final axes = const [
      AxisDef('health', 'Health', '', '#DD5555', subcategories: [
        SubcategoryDef('gym'),
        SubcategoryDef('junk', '', true), // hidden
      ]),
      AxisDef('mind', 'Mind', '', '#4C72B0'),
      AxisDef('career', 'Career', '', '#55883B'),
    ];
    final eng = LocalEngine([
      e('1', 'gym', secs: 600),
      e('2', 'junk', secs: 600), // hidden subcategory
      e('3', ''), // untagged, still counts
    ], axes);
    // Octagon excludes the hidden subcategory's event.
    expect(eng.countByAxis(excludeHidden: true)['health'], 2);
    expect(eng.timeTotals(excludeHidden: true).byAxis['health'], 600);
    // The default (heatmap/history) still includes everything.
    expect(eng.countByAxis()['health'], 3);
    // The "all subcategories" breakdown drops the hidden one...
    final sd = eng.subcategoryDays('health');
    expect(sd.counts[LocalEngine.dayKey(day)], 1); // only 'gym'
    expect(sd.dominant[LocalEngine.dayKey(day)], 'gym');
    // ...unless includeHidden is set (the "inc. hidden" view).
    final sdAll = eng.subcategoryDays('health', includeHidden: true);
    expect(sdAll.counts[LocalEngine.dayKey(day)], 2); // gym + junk
  });

  test('subcategoryDays finds the dominant subcategory per day', () {
    final day = DateTime(2026, 6, 1, 9);
    Event e(String id, String name, String sub) => Event(
        id: id, axisKey: 'health', name: name, exp: 10, timestamp: day, subcategory: sub);
    final eng = LocalEngine([
      e('1', 'a', 'gym'),
      e('2', 'b', 'gym'),
      e('3', 'c', 'run'),
      Event(id: '4', axisKey: 'health', name: 'd', exp: 10, timestamp: day), // untagged
    ]);
    final sd = eng.subcategoryDays('health');
    final k = LocalEngine.dayKey(day);
    expect(sd.counts[k], 3); // only tagged events count
    expect(sd.dominant[k], 'gym');
  });

  test('numberByAxis sums and percentByAxis sums / latest-wins per axis', () {
    Event e(
            {required String axis,
            double? number,
            double? percentage,
            DateTime? at}) =>
        Event(
            id: Event.newId(),
            axisKey: axis,
            name: 'x',
            exp: 10,
            timestamp: at ?? DateTime.now(),
            number: number,
            percentage: percentage);
    final eng = LocalEngine([
      e(axis: 'health', number: 10, percentage: 30, at: DateTime(2026, 1, 1)),
      e(axis: 'health', number: 5, percentage: 40, at: DateTime(2026, 1, 2)),
      e(axis: 'health'), // neither tracked — ignored by both
      e(axis: 'mind', number: 3),
    ]);
    expect(eng.numberByAxis()['health'], 15);
    expect(eng.numberByAxis()['mind'], 3);
    // sum mode adds every percentage (capped at 100).
    expect(eng.percentByAxis(mode: 'sum')['health'], 70); // 30 + 40
    expect(eng.percentByAxis(mode: 'sum').containsKey('mind'), false);
    // latest mode keeps the most recent record's percentage.
    expect(eng.percentByAxis(mode: 'latest')['health'], 40);
  });

  test('percentByAxis sum returns the raw total (UI applies the 100% cap)', () {
    Event e(double p, DateTime at) => Event(
        id: Event.newId(),
        axisKey: 'health',
        name: 'x',
        exp: 10,
        timestamp: at,
        percentage: p);
    final eng = LocalEngine([
      e(60, DateTime(2026, 1, 1)),
      e(70, DateTime(2026, 1, 2)),
    ]);
    // Uncapped so the "Avg / day" view can show the true per-day mean; the
    // 100% cap for the absolute view is applied in the home screen.
    expect(eng.percentByAxis(mode: 'sum')['health'], 130);
  });

  test('countByAxis/timeTotals honor a since..until window', () {
    final eng = LocalEngine([
      ev('health', 'a', seconds: 600, at: DateTime(2026, 6, 1, 9)),
      ev('health', 'b', seconds: 600, at: DateTime(2026, 6, 3, 9)),
      ev('health', 'c', seconds: 600, at: DateTime(2026, 6, 5, 9)),
    ]);
    // Window covering just Jun 3 (until = exclusive midnight Jun 4).
    final since = DateTime(2026, 6, 3);
    final until = DateTime(2026, 6, 4);
    expect(eng.countByAxis(since: since, until: until)['health'], 1);
    expect(eng.timeTotals(since: since, until: until).byAxis['health'], 600);
    // Open-ended (no until) from Jun 3 sees Jun 3 and Jun 5.
    expect(eng.countByAxis(since: since)['health'], 2);
  });

  test('hidden events are excluded from the octagon but counted elsewhere', () {
    final eng = LocalEngine([
      ev('health', 'gym', exp: 60, seconds: 3600),
      ev('health', 'secret', exp: 30, seconds: 1800, hidden: true),
    ]);
    // Octagon-feeding aggregates skip the hidden event...
    expect(eng.countByAxis(excludeHidden: true)['health'], 1);
    expect(eng.timeTotals(excludeHidden: true).byAxis['health'], 3600);
    expect(eng.expByAxis(excludeHidden: true)['health'], 60);
    // ...but the default (heatmap/time/history) still includes it.
    expect(eng.countByAxis()['health'], 2);
    expect(eng.timeTotals().byAxis['health'], 5400);
    expect(eng.dailyCounts(axisKey: 'health').values.first, 2);
  });

  test('Event round-trips the hidden flag', () {
    final e = ev('health', 'secret', hidden: true);
    final back = Event.fromStorageJson(e.toStorageJson());
    expect(back.hidden, true);
    final visible = Event.fromStorageJson(ev('health', 'gym').toStorageJson());
    expect(visible.hidden, false);
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
