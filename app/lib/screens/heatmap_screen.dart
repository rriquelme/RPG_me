import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';

import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';

enum _Metric { count, time }

/// Sentinel for the "All subcategories (inc. hidden)" dropdown item.
const String _kAllIncHidden = '__all_inc_hidden__';

/// GitHub-contributions-style calendars. A **Category** picker (defaulting to
/// **All**) drives the main grid; when a specific category has subcategories a
/// second **by subcategory** grid appears (all subcategories coloured by each
/// day's dominant, or a single picked one). Defaults to **frequency**; a single
/// log is a light cell, more are darker. Tap any day to see its frequency and
/// time spent. A toggle switches the shading to time spent.
class HeatmapScreen extends StatefulWidget {
  final Repository repo;
  const HeatmapScreen({super.key, required this.repo});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  _Metric _metric = _Metric.count; // frequency is primary
  List<AxisDef> _axes = [];
  String? _axisKey; // null = All (every category)
  Map<String, int> _filteredCounts = {};
  Map<String, int> _filteredSeconds = {};
  // "By subcategory" section (3rd chart), for the selected category.
  String? _subKey; // null = all subcategories, coloured by each day's dominant
  Map<String, int> _subCounts = {};
  Map<String, int> _subSeconds = {};
  Map<String, Color>? _subDayColors;
  bool _loading = true;
  // Debounce heavy grid reloads while the category/subcategory wheel is spinning.
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    super.dispose();
  }

  /// Reload the grids shortly after the wheel settles (keeps a fast fling from
  /// rebuilding the heatmaps on every tick).
  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 140), () {
      _loadFiltered();
      _loadSub();
    });
  }

  void _onCategoryWheel(int i) {
    final key = (i <= 0 || i - 1 >= _axes.length) ? null : _axes[i - 1].key;
    setState(() {
      _axisKey = key;
      _subKey = null; // subcategories are per-category
    });
    _scheduleReload();
  }

  /// One centred row in a picker wheel: an optional colour dot + a label.
  Widget _wheelRow(String label, {Color? dot, bool hidden = false}) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          if (hidden) ...[
            const SizedBox(width: 6),
            Icon(Icons.visibility_off_outlined,
                size: 14, color: Theme.of(context).disabledColor),
          ],
        ],
      ),
    );
  }

  AxisDef? _axisFor(String? key) {
    for (final a in _axes) {
      if (a.key == key) return a;
    }
    return null;
  }

  Color _subColor(AxisDef axis, String name, Color fallback) {
    final hex = axis.subcategoryByName(name)?.colorHex ?? '';
    return hex.isEmpty ? fallback : colorFromHex(hex);
  }

  Future<void> _loadAll() async {
    setState(() {
      _axes = widget.repo.axesConfig;
      _axisKey = null; // start on "All"
    });
    await _loadFiltered();
    await _loadSub();
    if (mounted) setState(() => _loading = false);
  }

  /// Daily counts/seconds for the selected category, or all (when _axisKey null).
  Future<void> _loadFiltered() async {
    final counts = await widget.repo.dailyCounts(axisKey: _axisKey);
    final seconds = await widget.repo.dailySeconds(axisKey: _axisKey);
    if (mounted) {
      setState(() {
        _filteredCounts = counts;
        _filteredSeconds = seconds;
      });
    }
  }

  /// Load the "By subcategory" chart for the selected category: all
  /// subcategories (dominant-by-day colouring) or a single picked one.
  Future<void> _loadSub() async {
    final key = _axisKey;
    final axis = _axisFor(key);
    if (key == null || axis == null || axis.subcategories.isEmpty) {
      if (mounted) {
        setState(() {
          _subCounts = {};
          _subSeconds = {};
          _subDayColors = null;
        });
      }
      return;
    }
    if (_subKey == null || _subKey == _kAllIncHidden) {
      final days = await widget.repo
          .subcategoryDays(key, includeHidden: _subKey == _kAllIncHidden);
      final fallback = colorFromHex(axis.colorHex);
      if (mounted) {
        setState(() {
          _subCounts = days.counts;
          _subSeconds = days.seconds;
          _subDayColors = {
            for (final e in days.dominant.entries)
              e.key: _subColor(axis, e.value, fallback),
          };
        });
      }
    } else {
      final counts =
          await widget.repo.dailyCounts(axisKey: key, subcategory: _subKey);
      final seconds =
          await widget.repo.dailySeconds(axisKey: key, subcategory: _subKey);
      if (mounted) {
        setState(() {
          _subCounts = counts;
          _subSeconds = seconds;
          _subDayColors = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Activity')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final isTime = _metric == _Metric.time;
    final subAxis = _axisFor(_axisKey);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_Metric>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Metric.count, label: Text('Frequency')),
              ButtonSegment(value: _Metric.time, label: Text('Time spent')),
            ],
            selected: {_metric},
            onSelectionChanged: (s) => setState(() => _metric = s.first),
          ),
          const SizedBox(height: 20),
          Text('Category', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          SizedBox(
            height: 132,
            child: CupertinoPicker(
              itemExtent: 32,
              magnification: 1.12,
              squeeze: 1.1,
              useMagnifier: true,
              onSelectedItemChanged: _onCategoryWheel,
              children: [
                _wheelRow('All'),
                ..._axes.map((a) =>
                    _wheelRow(a.label, dot: colorFromHex(a.colorHex))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          HeatGrid(
            counts: _filteredCounts,
            seconds: _filteredSeconds,
            isTime: isTime,
            baseColor: _axisKey == null
                ? const Color(0xFF2E9E4F)
                : colorFromHex(_axes.firstWhere((a) => a.key == _axisKey).colorHex),
            firstDayOfWeek: widget.repo.settings.firstDayOfWeek,
            showDayNumbers: widget.repo.settings.showDayNumbers,
          ),
          if (subAxis != null && subAxis.subcategories.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 12),
            Text('By subcategory',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            SizedBox(
              height: 132,
              // Keyed by category so the wheel resets to "All subcategories"
              // (index 0) whenever the selected category changes.
              child: CupertinoPicker(
                key: ValueKey('sub-$_axisKey'),
                itemExtent: 32,
                magnification: 1.12,
                squeeze: 1.1,
                useMagnifier: true,
                onSelectedItemChanged: (i) {
                  final String? v;
                  if (i == 0) {
                    v = null;
                  } else if (i == 1) {
                    v = _kAllIncHidden;
                  } else {
                    final subs = subAxis.subcategories;
                    v = (i - 2 < subs.length) ? subs[i - 2].name : null;
                  }
                  setState(() => _subKey = v);
                  _scheduleReload();
                },
                children: [
                  _wheelRow('All subcategories'),
                  _wheelRow('All subcategories (inc. hidden)'),
                  ...subAxis.subcategories.map((s) => _wheelRow(
                        s.name,
                        dot: _subColor(
                            subAxis, s.name, colorFromHex(subAxis.colorHex)),
                        hidden: s.hidden,
                      )),
                ],
              ),
            ),
            const SizedBox(height: 8),
            HeatGrid(
              counts: _subCounts,
              seconds: _subSeconds,
              isTime: isTime,
              baseColor: (_subKey == null || _subKey == _kAllIncHidden)
                  ? colorFromHex(subAxis.colorHex)
                  : _subColor(subAxis, _subKey!, colorFromHex(subAxis.colorHex)),
              firstDayOfWeek: widget.repo.settings.firstDayOfWeek,
              dayColors: _subDayColors,
              showDayNumbers: widget.repo.settings.showDayNumbers,
            ),
          ],
        ],
      ),
    );
  }
}

/// A month-by-month heatmap calendar: each day sits in its real weekday row,
/// with blank cells before the 1st and after the last day so months separate
/// naturally (no fake "every month starts Monday"). Weekday labels follow the
/// configured first day of week; auto-scrolls to the most recent month.
class HeatGrid extends StatefulWidget {
  final Map<String, int> counts;
  final Map<String, int> seconds;
  final bool isTime;
  final Color baseColor;
  final int firstDayOfWeek; // DateTime.monday..sunday

  /// Optional per-day colour override (dayKey -> colour). When set, each day's
  /// cell uses its mapped colour (e.g. the dominant subcategory's colour)
  /// instead of [baseColor], and the gradient legend is hidden.
  final Map<String, Color>? dayColors;

  /// Show the day-of-month number inside each cell.
  final bool showDayNumbers;

  const HeatGrid({
    super.key,
    required this.counts,
    required this.seconds,
    required this.isTime,
    required this.baseColor,
    required this.firstDayOfWeek,
    this.dayColors,
    this.showDayNumbers = false,
  });

  @override
  State<HeatGrid> createState() => _HeatGridState();
}

class _HeatGridState extends State<HeatGrid> {
  static const _monthsBack = 6; // months shown, including the current one
  static const _cell = 15.0;
  static const _margin = 2.0;
  static const _row = _cell + 2 * _margin;
  static const _gap = 10.0; // space between month blocks
  static const _monthH = 18.0;

  static const _letters = {1: 'M', 2: 'T', 3: 'W', 4: 'T', 5: 'F', 6: 'S', 7: 'S'};
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    // Show the most recent weeks first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  Color _color(BuildContext context, int count, int secs, int maxSecs, Color base) {
    final empty = Theme.of(context).colorScheme.surfaceContainerHighest;
    if (widget.isTime) {
      if (secs <= 0 || maxSecs <= 0) return empty;
      final r = secs / maxSecs;
      final o = r <= 0.25 ? 0.35 : (r <= 0.5 ? 0.55 : (r <= 0.75 ? 0.78 : 1.0));
      return base.withOpacity(o);
    }
    if (count <= 0) return empty;
    final o = count == 1 ? 0.32 : (count == 2 ? 0.52 : (count == 3 ? 0.74 : 1.0));
    return base.withOpacity(o);
  }

  void _showDay(BuildContext context, DateTime date, int count, int secs) {
    final label = '${_dayNames[date.weekday - 1]} ${date.day} ${_months[date.month - 1]} ${date.year}';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(label),
        content: Text('Logged $count time${count == 1 ? '' : 's'}'
            '${secs > 0 ? '\nTime spent: ${formatHms(secs)}' : ''}'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _blankCell() =>
      Container(width: _cell, height: _cell, margin: const EdgeInsets.all(_margin));

  Widget _dayCell(BuildContext context, DateTime date, int maxSecs) {
    final k = LocalEngine.dayKey(date);
    final c = widget.counts[k] ?? 0;
    final s = widget.seconds[k] ?? 0;
    final base = widget.dayColors != null
        ? (widget.dayColors![k] ?? widget.baseColor)
        : widget.baseColor;
    final cellColor = _color(context, c, s, maxSecs, base);
    return GestureDetector(
      onTap: () => _showDay(context, date, c, s),
      child: Container(
        width: _cell,
        height: _cell,
        margin: const EdgeInsets.all(_margin),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cellColor,
          borderRadius: BorderRadius.circular(3),
        ),
        child: widget.showDayNumbers
            ? Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 8,
                  height: 1,
                  color: ThemeData.estimateBrightnessForColor(cellColor) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
              )
            : null,
      ),
    );
  }

  /// One month as a calendar: columns are weeks, each day in its weekday row,
  /// with blanks padding the first and last weeks.
  Widget _monthBlock(BuildContext context, int year, int month, DateTime today,
      int maxSecs, TextStyle? labelStyle) {
    final fdow = widget.firstDayOfWeek;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final r1 = (DateTime(year, month, 1).weekday - fdow + 7) % 7; // row of the 1st
    final cols = ((r1 + daysInMonth) / 7).ceil();

    final columns = List.generate(cols, (c) {
      return Column(
        children: List.generate(7, (r) {
          final dayNum = c * 7 + r - r1 + 1;
          if (dayNum < 1 || dayNum > daysInMonth) return _blankCell();
          final date = DateTime(year, month, dayNum);
          if (date.isAfter(today)) return _blankCell();
          return _dayCell(context, date, maxSecs);
        }),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _monthH,
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              month == DateTime.january ? '${_months[month - 1]} $year' : _months[month - 1],
              style: labelStyle?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: columns),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fdow = widget.firstDayOfWeek;

    // Last N months, including the current one (oldest -> newest).
    final months = List.generate(
        _monthsBack, (i) => DateTime(today.year, today.month - (_monthsBack - 1 - i), 1));

    final maxSecs = widget.seconds.values.fold<int>(0, (a, b) => a > b ? a : b);
    final maxCount = widget.counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    final labelStyle = Theme.of(context).textTheme.bodySmall;

    final blocks = <Widget>[];
    for (var mi = 0; mi < months.length; mi++) {
      final fom = months[mi];
      blocks.add(_monthBlock(context, fom.year, fom.month, today, maxSecs, labelStyle));
      if (mi != months.length - 1) blocks.add(const SizedBox(width: _gap));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Weekday labels (ordered by first day of week), with a top spacer
            // to line up under the month labels.
            Column(
              children: [
                const SizedBox(height: _monthH),
                ...List.generate(7, (r) {
                  final weekday = ((fdow - 1 + r) % 7) + 1;
                  return SizedBox(
                    height: _row,
                    width: 22,
                    child: Center(child: Text(_letters[weekday]!, style: labelStyle)),
                  );
                }),
              ],
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SingleChildScrollView(
                controller: _sc,
                scrollDirection: Axis.horizontal,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: blocks),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (widget.dayColors == null) ...[
            Text('Less', style: labelStyle),
            const SizedBox(width: 6),
            ...[0.32, 0.52, 0.74, 1.0].map((o) => Container(
                  width: 13,
                  height: 13,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: widget.baseColor.withOpacity(o),
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
            const SizedBox(width: 6),
            Text('More', style: labelStyle),
          ],
          const Spacer(),
          Text(
            widget.isTime
                ? (maxSecs == 0 ? 'No data' : 'peak ${formatHms(maxSecs)}')
                : (maxCount == 0 ? 'No data' : 'peak $maxCount×'),
            style: labelStyle,
          ),
        ]),
      ],
    );
  }
}
