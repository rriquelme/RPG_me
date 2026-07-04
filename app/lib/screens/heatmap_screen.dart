import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';

import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';

enum _Metric { count, time, number, percent }

enum _ActivityView { heatmap, chart }

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
  _ActivityView _view = _ActivityView.heatmap; // heatmap by default
  List<AxisDef> _axes = [];
  String? _axisKey; // null = All (every category)
  Map<String, double> _filteredVals = {};
  // "By subcategory" section (3rd chart), for the selected category.
  String? _subKey; // null = all subcategories, coloured by each day's dominant
  Map<String, double> _subVals = {};
  Map<String, Color>? _subDayColors;
  // "By category" section (shown when All is selected): pick a category to
  // compare against All. null = All (every day coloured by its dominant
  // category); a key = that category's own heatmap.
  String? _catKey;
  Map<String, double> _catVals = {};
  Map<String, Color>? _catDayColors;
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
      _loadCategoryBreakdown();
    });
  }

  void _onCategoryWheel(int i) {
    final key = (i <= 0 || i - 1 >= _axes.length) ? null : _axes[i - 1].key;
    setState(() {
      _axisKey = key;
      _subKey = null; // subcategories are per-category
      _catKey = null; // reset the All-vs-category comparison picker
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

  Color _axisColorFor(String key) {
    final a = _axisFor(key);
    return a != null ? colorFromHex(a.colorHex) : kDefaultAxisColor;
  }

  String get _metricLabel {
    switch (_metric) {
      case _Metric.count:
        return 'Frequency';
      case _Metric.time:
        return 'Time';
      case _Metric.number:
        return 'Number';
      case _Metric.percent:
        return 'Percent';
    }
  }

  String _fmtMetric(double v) {
    switch (_metric) {
      case _Metric.count:
        return v.toStringAsFixed(0);
      case _Metric.time:
        final s = v.round();
        if (s >= 3600) {
          final h = s / 3600;
          return '${h.toStringAsFixed(s % 3600 == 0 ? 0 : 1)}h';
        }
        if (s >= 60) return '${(s / 60).round()}m';
        return '${s}s';
      case _Metric.number:
        return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
      case _Metric.percent:
        return '${v.toStringAsFixed(0)}%';
    }
  }

  /// One activity calendar in the current view (heatmap squares or day bars).
  Widget _activityChart({
    required Map<String, double> values,
    required Color baseColor,
    Map<String, Color>? dayColors,
  }) {
    if (_view == _ActivityView.chart) {
      return DayChart(
        values: values,
        format: _fmtMetric,
        metricLabel: _metricLabel,
        baseColor: baseColor,
        dayColors: dayColors,
      );
    }
    return HeatGrid(
      values: values,
      discrete: _metric == _Metric.count,
      format: _fmtMetric,
      metricLabel: _metricLabel,
      baseColor: baseColor,
      firstDayOfWeek: widget.repo.settings.firstDayOfWeek,
      dayColors: dayColors,
      showDayNumbers: widget.repo.settings.showDayNumbers,
    );
  }

  /// Load the "By category" chart. With no category picked it colours each day
  /// by its dominant category; with one picked it shows that category's own
  /// heatmap (to compare against the All grid above). Only relevant when All
  /// categories is selected up top.
  Future<void> _loadCategoryBreakdown() async {
    if (_axisKey != null) return; // section is hidden for a specific category
    if (_catKey == null) {
      // All: colour each day by its dominant category (frequency), size by the
      // active metric over everything.
      final days = await widget.repo.categoryDays();
      final vals = await _dailyMetric();
      if (mounted) {
        setState(() {
          _catVals = vals;
          _catDayColors = {
            for (final e in days.dominant.entries) e.key: _axisColorFor(e.value),
          };
        });
      }
    } else {
      final vals = await _dailyMetric(axisKey: _catKey);
      if (mounted) {
        setState(() {
          _catVals = vals;
          _catDayColors = null;
        });
      }
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _axes = widget.repo.axesConfig;
      _axisKey = null; // start on "All"
    });
    await _loadFiltered();
    await _loadSub();
    await _loadCategoryBreakdown();
    if (mounted) setState(() => _loading = false);
  }

  /// Per-day value of the active metric for the given filter (null axis = all).
  Future<Map<String, double>> _dailyMetric(
      {String? axisKey, String? subcategory}) async {
    switch (_metric) {
      case _Metric.count:
        final m =
            await widget.repo.dailyCounts(axisKey: axisKey, subcategory: subcategory);
        return m.map((k, v) => MapEntry(k, v.toDouble()));
      case _Metric.time:
        final m = await widget.repo
            .dailySeconds(axisKey: axisKey, subcategory: subcategory);
        return m.map((k, v) => MapEntry(k, v.toDouble()));
      case _Metric.number:
        return widget.repo
            .dailyNumbers(axisKey: axisKey, subcategory: subcategory);
      case _Metric.percent:
        return widget.repo.dailyPercent(
            axisKey: axisKey,
            subcategory: subcategory,
            mode: widget.repo.settings.percentageMode);
    }
  }

  /// Daily value for the selected category, or all (when _axisKey null).
  Future<void> _loadFiltered() async {
    final vals = await _dailyMetric(axisKey: _axisKey);
    if (mounted) setState(() => _filteredVals = vals);
  }

  /// Load the "By subcategory" chart for the selected category: all
  /// subcategories (dominant-by-day colouring) or a single picked one.
  Future<void> _loadSub() async {
    final key = _axisKey;
    final axis = _axisFor(key);
    if (key == null || axis == null || axis.subcategories.isEmpty) {
      if (mounted) {
        setState(() {
          _subVals = {};
          _subDayColors = null;
        });
      }
      return;
    }
    if (_subKey == null || _subKey == _kAllIncHidden) {
      // All subcategories: colour each day by its dominant subcategory (always
      // frequency-based), size by the active metric over the whole category.
      final days = await widget.repo
          .subcategoryDays(key, includeHidden: _subKey == _kAllIncHidden);
      final vals = await _dailyMetric(axisKey: key);
      final fallback = colorFromHex(axis.colorHex);
      if (mounted) {
        setState(() {
          _subVals = vals;
          _subDayColors = {
            for (final e in days.dominant.entries)
              e.key: _subColor(axis, e.value, fallback),
          };
        });
      }
    } else {
      final vals = await _dailyMetric(axisKey: key, subcategory: _subKey);
      if (mounted) {
        setState(() {
          _subVals = vals;
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
    final subAxis = _axisFor(_axisKey);
    final chartView = _view == _ActivityView.chart;
    final s = widget.repo.settings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
            icon: Icon(chartView ? Icons.grid_view_rounded : Icons.bar_chart),
            tooltip: chartView ? 'Heatmap view' : 'Chart view',
            onPressed: () => setState(() => _view = chartView
                ? _ActivityView.heatmap
                : _ActivityView.chart),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: SegmentedButton<_Metric>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(
                    value: _Metric.count, label: Text('Frequency')),
                const ButtonSegment(value: _Metric.time, label: Text('Time')),
                if (s.trackNumber)
                  const ButtonSegment(
                      value: _Metric.number, label: Text('Number')),
                if (s.trackPercentage)
                  const ButtonSegment(
                      value: _Metric.percent, label: Text('Percent')),
              ],
              selected: {_metric},
              onSelectionChanged: (sel) {
                setState(() => _metric = sel.first);
                _loadFiltered();
                _loadSub();
                _loadCategoryBreakdown();
              },
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Category', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              SizedBox(
                width: 190,
                height: 68,
                child: CupertinoPicker(
                  itemExtent: 26,
                  magnification: 1.1,
                  squeeze: 1.15,
                  useMagnifier: true,
                  onSelectedItemChanged: _onCategoryWheel,
                  children: [
                    _wheelRow('All'),
                    ..._axes.map((a) =>
                        _wheelRow(a.label, dot: colorFromHex(a.colorHex))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _activityChart(
            values: _filteredVals,
            baseColor: _axisKey == null
                ? const Color(0xFF2E9E4F)
                : colorFromHex(_axes.firstWhere((a) => a.key == _axisKey).colorHex),
          ),
          // "By category" — shown only when All categories is selected up top.
          // Pick a category here to compare it against the All grid above.
          if (_axisKey == null && _axes.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('By category',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                SizedBox(
                  width: 190,
                  height: 68,
                  child: CupertinoPicker(
                    itemExtent: 26,
                    magnification: 1.1,
                    squeeze: 1.15,
                    useMagnifier: true,
                    onSelectedItemChanged: (i) {
                      final key = (i <= 0 || i - 1 >= _axes.length)
                          ? null
                          : _axes[i - 1].key;
                      setState(() => _catKey = key);
                      _scheduleReload();
                    },
                    children: [
                      _wheelRow('All'),
                      ..._axes.map((a) =>
                          _wheelRow(a.label, dot: colorFromHex(a.colorHex))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _activityChart(
              values: _catVals,
              baseColor: _catKey == null
                  ? const Color(0xFF2E9E4F)
                  : _axisColorFor(_catKey!),
              dayColors: _catDayColors,
            ),
          ],
          if (subAxis != null && subAxis.subcategories.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('By subcategory',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                SizedBox(
                  width: 190,
                  height: 68,
                  // Keyed by category so the wheel resets to "All subcategories"
                  // (index 0) whenever the selected category changes.
                  child: CupertinoPicker(
                    key: ValueKey('sub-$_axisKey'),
                    itemExtent: 26,
                    magnification: 1.1,
                    squeeze: 1.15,
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
                            dot: _subColor(subAxis, s.name,
                                colorFromHex(subAxis.colorHex)),
                            hidden: s.hidden,
                          )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _activityChart(
              values: _subVals,
              baseColor: (_subKey == null || _subKey == _kAllIncHidden)
                  ? colorFromHex(subAxis.colorHex)
                  : _subColor(subAxis, _subKey!, colorFromHex(subAxis.colorHex)),
              dayColors: _subDayColors,
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
  /// Per-day value for the active metric (frequency, time, number, percent…).
  final Map<String, double> values;

  /// Discrete metrics (frequency) use GitHub-style step buckets; continuous
  /// metrics (time/number/percent) shade by ratio to the day-peak.
  final bool discrete;

  /// Formats a value for the tooltip / legend (e.g. "3", "1h", "45", "80%").
  final String Function(double) format;

  /// Metric name for the day tooltip (e.g. "Frequency", "Number").
  final String metricLabel;

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
    required this.values,
    required this.discrete,
    required this.format,
    required this.metricLabel,
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
  static const _gap = 5.0; // space between month blocks
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

  Color _color(BuildContext context, double v, double maxV, Color base) {
    final empty = Theme.of(context).colorScheme.surfaceContainerHighest;
    if (v <= 0) return empty;
    if (widget.discrete) {
      final n = v.round();
      final o = n == 1 ? 0.32 : (n == 2 ? 0.52 : (n == 3 ? 0.74 : 1.0));
      return base.withOpacity(o);
    }
    if (maxV <= 0) return empty;
    final r = v / maxV;
    final o = r <= 0.25 ? 0.35 : (r <= 0.5 ? 0.55 : (r <= 0.75 ? 0.78 : 1.0));
    return base.withOpacity(o);
  }

  void _showDay(BuildContext context, DateTime date, double v) {
    final label = '${_dayNames[date.weekday - 1]} ${date.day} ${_months[date.month - 1]} ${date.year}';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(label),
        content: Text(v > 0
            ? '${widget.metricLabel}: ${widget.format(v)}'
            : 'No activity'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _blankCell() =>
      Container(width: _cell, height: _cell, margin: const EdgeInsets.all(_margin));

  Widget _dayCell(BuildContext context, DateTime date, double maxV) {
    final k = LocalEngine.dayKey(date);
    final v = widget.values[k] ?? 0;
    final base = widget.dayColors != null
        ? (widget.dayColors![k] ?? widget.baseColor)
        : widget.baseColor;
    final cellColor = _color(context, v, maxV, base);
    return GestureDetector(
      onTap: () => _showDay(context, date, v),
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
      double maxV, TextStyle? labelStyle) {
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
          return _dayCell(context, date, maxV);
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

    final maxV = widget.values.values.fold<double>(0, (a, b) => a > b ? a : b);
    final labelStyle = Theme.of(context).textTheme.bodySmall;

    final blocks = <Widget>[];
    for (var mi = 0; mi < months.length; mi++) {
      final fom = months[mi];
      blocks.add(_monthBlock(context, fom.year, fom.month, today, maxV, labelStyle));
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
            maxV == 0 ? 'No data' : 'peak ${widget.format(maxV)}',
            style: labelStyle,
          ),
        ]),
      ],
    );
  }
}

/// The same daily data as [HeatGrid], drawn as a month-by-month bar chart:
/// one vertical bar per day (height ∝ count or time), grouped by month and
/// horizontally scrollable, auto-scrolled to the most recent month. Tapping a
/// bar shows that day's totals. Uses [dayColors] per day when provided.
class DayChart extends StatefulWidget {
  /// Per-day value for the active metric.
  final Map<String, double> values;

  /// Formats a value for the Y axis / peak / tooltip.
  final String Function(double) format;

  /// Metric name for the day tooltip.
  final String metricLabel;

  final Color baseColor;
  final Map<String, Color>? dayColors;

  const DayChart({
    super.key,
    required this.values,
    required this.format,
    required this.metricLabel,
    required this.baseColor,
    this.dayColors,
  });

  @override
  State<DayChart> createState() => _DayChartState();
}

class _DayChartState extends State<DayChart> {
  static const _monthsBack = 6;
  static const _barW = 12.0;
  static const _barGap = 4.0;
  static const _slot = _barW + _barGap;
  static const _chartH = 120.0;
  static const _dayH = 14.0; // X-axis day-number row height
  static const _monthGap = 12.0;
  static const _monthH = 18.0;
  // Horizontal gridline positions (fraction from the top).
  static const _gridFractions = [0.25, 0.5, 0.75];

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul',
    'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _showDay(BuildContext context, DateTime date, double v) {
    final label =
        '${_dayNames[date.weekday - 1]} ${date.day} ${_months[date.month - 1]} ${date.year}';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(label),
        content: Text(v > 0
            ? '${widget.metricLabel}: ${widget.format(v)}'
            : 'No activity'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Close'))
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, DateTime date, double maxV) {
    final k = LocalEngine.dayKey(date);
    final v = widget.values[k] ?? 0;
    final h = maxV <= 0 ? 0.0 : (v / maxV) * _chartH;
    final color = widget.dayColors?[k] ?? widget.baseColor;
    return GestureDetector(
      onTap: () => _showDay(context, date, v),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _barW + _barGap,
        height: _chartH,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: _barW,
            height: h < 2 && v > 0 ? 2 : h, // keep tiny values visible
            decoration: BoxDecoration(
              color: v > 0
                  ? color
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthBlock(BuildContext context, int year, int month, DateTime today,
      double maxV, TextStyle? labelStyle, Color gridColor) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final daySmall = labelStyle?.copyWith(
        fontSize: 8, color: Theme.of(context).textTheme.bodySmall?.color);
    final bars = <Widget>[];
    final dayNums = <Widget>[];
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(year, month, d);
      if (date.isAfter(today)) break;
      bars.add(_bar(context, date, maxV));
      dayNums.add(SizedBox(
        width: _slot,
        child: Center(child: Text('$d', style: daySmall)),
      ));
    }
    final blockW = bars.length * _slot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bars over horizontal gridlines.
        SizedBox(
          width: blockW,
          height: _chartH,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _GridPainter(gridColor)),
              ),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: bars),
            ],
          ),
        ),
        // X-axis day numbers, then the month name once (centred under the block).
        SizedBox(height: _dayH, child: Row(children: dayNums)),
        SizedBox(
          width: blockW,
          height: _monthH,
          child: Center(
            child: Text(
              month == DateTime.january
                  ? '${_months[month - 1]} $year'
                  : _months[month - 1],
              style: labelStyle?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final labelStyle = Theme.of(context).textTheme.bodySmall;

    final months = List.generate(_monthsBack,
        (i) => DateTime(today.year, today.month - (_monthsBack - 1 - i), 1));

    final maxV = widget.values.values.fold<double>(0, (a, b) => a > b ? a : b);
    final gridColor = Theme.of(context).dividerColor;

    final blocks = <Widget>[];
    for (var mi = 0; mi < months.length; mi++) {
      final fom = months[mi];
      blocks.add(_monthBlock(
          context, fom.year, fom.month, today, maxV, labelStyle, gridColor));
      if (mi != months.length - 1) blocks.add(const SizedBox(width: _monthGap));
    }

    // Right-hand Y axis, aligned to the bar area: max at the top, the gridline
    // values in between, and 0 at the baseline.
    final yAxis = SizedBox(
      height: _chartH,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(maxV == 0 ? '—' : widget.format(maxV), style: labelStyle),
          if (maxV > 3) Text(widget.format(maxV * 3 / 4), style: labelStyle),
          if (maxV > 1) Text(widget.format(maxV / 2), style: labelStyle),
          if (maxV > 3) Text(widget.format(maxV / 4), style: labelStyle),
          Text('0', style: labelStyle),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _sc,
            scrollDirection: Axis.horizontal,
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: blocks),
          ),
        ),
        const SizedBox(width: 6),
        yAxis,
      ],
    );
  }
}

/// Faint horizontal gridlines behind the bars, at [_DayChartState._gridFractions]
/// of the plot height, so you can read off value ranges.
class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1;
    for (final f in _DayChartState._gridFractions) {
      final y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.color != color;
}
