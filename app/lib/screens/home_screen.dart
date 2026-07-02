import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';
import '../settings.dart';
import '../widgets/octagon_chart.dart';
import 'axes_config_screen.dart';
import 'heatmap_screen.dart';
import 'log_screen.dart';
import 'logged_screen.dart';
import 'settings_screen.dart';
import 'time_screen.dart';
import 'timers_screen.dart';

enum OctagonMetric { hours, frequency, levels, number, percentage }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Repository? _repo;
  Summary? _summary;
  OctagonView? _octView;
  OctagonMetric _metric = OctagonMetric.frequency; // frequency is the primary view

  // Period navigation. [_periodKey] is the dropdown selection; [_navOffset]
  // steps the window back (negative) / forward by one unit of that period.
  // Custom day/range use [_customStart]/[_customEnd] as the offset-0 base.
  String _periodKey = 'this_week';
  int _navOffset = 0;
  DateTime? _customStart;
  DateTime? _customEnd;

  static const _simplePeriods = {
    'today', 'this_week', 'this_month', 'this_year', 'all'
  };

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final repo = await Repository.create();
    _repo = repo;
    final saved = repo.settings.period;
    _periodKey = _simplePeriods.contains(saved) ? saved : 'this_week';
    _reload();
  }

  Future<void> _reload() async {
    final repo = _repo;
    if (repo == null) return;
    // Fall back to Frequency if the selected metric was just disabled.
    if (!_availableMetrics(repo.settings).contains(_metric)) {
      _metric = OctagonMetric.frequency;
    }
    final summary = await repo.summary();
    final w = _windowFor(_navOffset);
    // Don't query into the future: cap the end at the end of today.
    DateTime? end = w.end;
    if (end != null) {
      final now = DateTime.now();
      final todayExcl =
          DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
      if (end.isAfter(todayExcl)) end = todayExcl;
    }
    final view = repo.octagonView(w.start, until: end);
    if (mounted) {
      setState(() {
        _summary = summary;
        _octView = view;
      });
    }
  }

  /// The [start, end) window and a label for the current period at [offset]
  /// (0 = current/base). 'all' has null bounds (no navigation).
  ({DateTime? start, DateTime? end, String label}) _windowFor(int offset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fdow = _repo?.settings.firstDayOfWeek ?? DateTime.monday;
    switch (_periodKey) {
      case 'today':
        final d = today.add(Duration(days: offset));
        return (start: d, end: d.add(const Duration(days: 1)), label: _fmtDay(d));
      case 'this_week':
        final w0 = today.subtract(Duration(days: (today.weekday - fdow + 7) % 7));
        final ws = w0.add(Duration(days: offset * 7));
        return (
          start: ws,
          end: ws.add(const Duration(days: 7)),
          label: '${_fmtDay(ws)} – ${_fmtDay(ws.add(const Duration(days: 6)))}'
        );
      case 'this_month':
        final m = DateTime(now.year, now.month + offset, 1);
        return (
          start: m,
          end: DateTime(m.year, m.month + 1, 1),
          label: '${_months[m.month - 1]} ${m.year}'
        );
      case 'this_year':
        return (
          start: DateTime(now.year + offset, 1, 1),
          end: DateTime(now.year + offset + 1, 1, 1),
          label: '${now.year + offset}'
        );
      case 'custom_day':
        final base = _customStart ?? today;
        final d = base.add(Duration(days: offset));
        return (start: d, end: d.add(const Duration(days: 1)), label: _fmtDay(d));
      case 'custom_range':
        final cs = _customStart ?? today, ce = _customEnd ?? today;
        final span = ce.difference(cs).inDays + 1;
        final start = cs.add(Duration(days: offset * span));
        final endIncl = ce.add(Duration(days: offset * span));
        return (
          start: start,
          end: endIncl.add(const Duration(days: 1)),
          label: '${_fmtDay(start)} – ${_fmtDay(endIncl)}'
        );
      case 'all':
      default:
        return (start: null, end: null, label: 'All time');
    }
  }

  bool get _navigable => _periodKey != 'all';

  /// Forward is allowed only while the next window doesn't start in the future.
  bool get _canForward {
    if (!_navigable) return false;
    final next = _windowFor(_navOffset + 1).start;
    if (next == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !next.isAfter(today);
  }

  void _shift(int dir) {
    setState(() => _navOffset += dir);
    _reload();
  }

  /// Jump the window back to the present (the one that includes today): offset 0
  /// for the calendar periods, re-anchored to today for the custom ones.
  void _resetToPresent() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      if (_periodKey == 'custom_day') {
        _customStart = today;
        _customEnd = today;
      } else if (_periodKey == 'custom_range' &&
          _customStart != null &&
          _customEnd != null) {
        final span = _customEnd!.difference(_customStart!).inDays + 1;
        _customEnd = today;
        _customStart = today.subtract(Duration(days: span - 1));
      }
      _navOffset = 0;
    });
    _reload();
  }

  Future<void> _pickCustomDay() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: _customStart ?? today,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (d == null) return;
    setState(() {
      _periodKey = 'custom_day';
      _customStart = DateTime(d.year, d.month, d.day);
      _customEnd = _customStart;
      _navOffset = 0;
    });
    _reload();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: (_customStart != null && _customEnd != null)
          ? DateTimeRange(start: _customStart!, end: _customEnd!)
          : null,
    );
    if (r == null) return;
    setState(() {
      _periodKey = 'custom_range';
      _customStart = DateTime(r.start.year, r.start.month, r.start.day);
      _customEnd = DateTime(r.end.year, r.end.month, r.end.day);
      _navOffset = 0;
    });
    _reload();
  }

  Future<void> _openSettings() async {
    if (_repo == null) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SettingsScreen(repo: _repo!)));
    _reload();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _reload();
  }

  Future<void> _setPeriod(String key) async {
    if (key == 'custom_day') return _pickCustomDay();
    if (key == 'custom_range') return _pickCustomRange();
    final repo = _repo!;
    setState(() {
      _periodKey = key;
      _navOffset = 0;
    });
    await repo.updateSettings(repo.settings.copyWith(period: key));
    await Settings.saveView(key, repo.settings.averagePerDay);
    _reload();
  }

  Future<void> _setAverage(bool avg) async {
    final repo = _repo!;
    await repo.updateSettings(repo.settings.copyWith(averagePerDay: avg));
    await Settings.saveView(repo.settings.period, avg);
    _reload();
  }

  Future<void> _exportLogs() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final file = await repo.exportFile();
      final bytes = await file.readAsBytes();
      // Android asks where to save (the system folder picker doubles as the
      // storage permission for that location); the file is written there.
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save RPG_me logs',
        fileName: 'rpg_me_data.md',
        type: FileType.any,
        bytes: bytes,
      );
      if (!mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Saved to $savedPath')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importLogs() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = res?.files.single.path;
      if (path == null) return;
      final content = await File(path).readAsString();
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import logs?'),
          content: const Text(
              'This replaces all current data on this device with the contents '
              'of the selected Markdown file. This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
          ],
        ),
      );
      if (ok != true) return;
      await repo.importMarkdown(content);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Logs imported.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  void _onMenu(String value) {
    final repo = _repo;
    if (repo == null) return;
    switch (value) {
      case 'categories':
        _openCategories();
        break;
      case 'settings':
        _openSettings();
        break;
      case 'logged':
        _push(LoggedScreen(repo: repo));
        break;
      case 'time':
        _push(TimeScreen(repo: repo));
        break;
      case 'export':
        _exportLogs();
        break;
      case 'import':
        _importLogs();
        break;
    }
  }

  Future<void> _openCategories({bool subMode = false}) async {
    final repo = _repo;
    if (repo == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            AxesConfigScreen(repo: repo, startInSubcategories: subMode)));
    _reload();
  }

  double _rawValue(OctagonView v, String key) {
    switch (_metric) {
      case OctagonMetric.hours:
        return (v.seconds[key] ?? 0) / 3600.0;
      case OctagonMetric.frequency:
        return (v.counts[key] ?? 0).toDouble();
      case OctagonMetric.levels:
        return levelForExp(v.exp[key] ?? 0).toDouble();
      case OctagonMetric.number:
        return v.numbers[key] ?? 0;
      case OctagonMetric.percentage:
        return v.percentAvg[key] ?? 0;
    }
  }

  OctagonScale _octagonScale(String key) {
    switch (key) {
      case 'log':
        return OctagonScale.logarithmic;
      case 'log2':
        return OctagonScale.logStrong;
      default:
        return OctagonScale.linear;
    }
  }

  List<RadarPoint> _points(OctagonView v, bool average) {
    final isPct = _metric == OctagonMetric.percentage;
    final capSum = isPct && (_repo?.settings.percentageMode ?? 'sum') == 'sum';
    return v.axes.where((a) => !a.hidden).map((a) {
      var value = _rawValue(v, a.key);
      if (average && v.days > 0) {
        // Avg / day = mean daily contribution (axis value spread over the
        // window). Applies to the % axis too — in both Sum and Last-wins modes
        // — and stays uncapped so the true per-day mean shows.
        value = value / v.days;
      } else if (capSum && value > 100) {
        // Absolute Sum of percentages is capped at 100%.
        value = 100;
      }
      return RadarPoint(
        axisKey: a.key,
        label: a.label,
        color: colorFromHex(a.colorHex),
        value: value,
      );
    }).toList();
  }

  /// The metrics available given the enabled settings (Levels stays hidden).
  Set<OctagonMetric> _availableMetrics(Settings s) =>
      _orderedMetrics(s).toSet();

  /// Available metrics in the same order as the toggle segments — used by the
  /// left/right swipe on the chart.
  List<OctagonMetric> _orderedMetrics(Settings s) => [
        OctagonMetric.frequency,
        OctagonMetric.hours,
        if (s.trackNumber) OctagonMetric.number,
        if (s.trackPercentage) OctagonMetric.percentage,
      ];

  /// Cycle the octagon metric by [dir] (+1 next, -1 previous), wrapping around.
  /// Driven by swiping the chart left/right.
  void _cycleMetric(int dir) {
    final repo = _repo;
    if (repo == null) return;
    final list = _orderedMetrics(repo.settings);
    final i = list.indexOf(_metric);
    if (i < 0 || list.length < 2) return;
    final n = (i + dir + list.length) % list.length;
    setState(() => _metric = list[n]);
  }

  Future<void> _logForCategory(String axisKey) async {
    final repo = _repo;
    if (repo == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LogScreen(repo: repo, initialAxisKey: axisKey)),
    );
    // Always reload — the Log screen can also toggle a category's hidden flag.
    _reload();
  }

  String _formatValue(double v, bool average) {
    final suffix = average ? '/d' : '';
    switch (_metric) {
      case OctagonMetric.levels:
        return average ? v.toStringAsFixed(2) : 'L${v.toInt()}';
      case OctagonMetric.frequency:
        return average ? '${v.toStringAsFixed(1)}$suffix' : '${v.toInt()}×';
      case OctagonMetric.hours:
        if (v >= 1) return '${v.toStringAsFixed(v < 10 ? 1 : 0)}h$suffix';
        return '${(v * 60).round()}m$suffix';
      case OctagonMetric.number:
        final s = (v % 1 == 0) ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
        return '$s$suffix';
      case OctagonMetric.percentage:
        // Absolute % when off; mean %/day (one decimal) under Avg / day.
        return '${v.toStringAsFixed(average ? 1 : 0)}%$suffix';
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;
    return Scaffold(
      appBar: AppBar(
        actions: repo == null
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Log activity',
                  onPressed: () => _push(LogScreen(repo: repo)),
                ),
                IconButton(
                  icon: const Icon(Icons.timer_outlined),
                  tooltip: 'Timers',
                  onPressed: () async {
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => TimersScreen(repo: repo)));
                    _reload();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_month),
                  tooltip: 'Activity',
                  onPressed: () => _push(HeatmapScreen(repo: repo)),
                ),
                IconButton(
                  icon: const Icon(Icons.category_outlined),
                  tooltip: 'Edit categories',
                  onPressed: () => _openCategories(),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
                  onPressed: _openSettings,
                ),
                PopupMenuButton<String>(
                  onSelected: _onMenu,
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'categories', child: Text('Edit categories')),
                    PopupMenuItem(value: 'settings', child: Text('Settings')),
                    PopupMenuItem(value: 'logged', child: Text('Logged activities')),
                    PopupMenuItem(value: 'time', child: Text('Time tracked')),
                    PopupMenuItem(value: 'export', child: Text('Export logs (.md)')),
                    PopupMenuItem(value: 'import', child: Text('Import logs (.md)')),
                  ],
                ),
              ],
      ),
      floatingActionButton: repo == null ? null : _bottomButtons(repo),
      body: repo == null
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(repo),
    );
  }

  /// The home screen's only bottom button is Log (toggleable in Settings). The
  /// category/subcategory buttons live on the Edit categories screen instead.
  Widget? _bottomButtons(Repository repo) {
    if (!repo.settings.showLogButton) return null;
    return FloatingActionButton.extended(
      onPressed: () => _push(LogScreen(repo: repo)),
      icon: const Icon(Icons.add),
      label: const Text('Log'),
    );
  }

  Widget _buildBody(Repository repo) {
    final summary = _summary;
    final octView = _octView;
    if (summary == null || octView == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final average = repo.settings.averagePerDay;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${summary.totalEvents} events logged',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<OctagonMetric>(
              showSelectedIcon: false, // keep segment widths fixed (no resize on toggle)
              // Thinner on the Y axis: trim vertical padding and the tap target.
              style: SegmentedButton.styleFrom(
                visualDensity: const VisualDensity(vertical: -4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: [
                const ButtonSegment(
                    value: OctagonMetric.frequency, label: Text('Frequency')),
                const ButtonSegment(
                    value: OctagonMetric.hours, label: Text('Time')),
                if (repo.settings.trackNumber)
                  const ButtonSegment(
                      value: OctagonMetric.number, label: Text('Number')),
                if (repo.settings.trackPercentage)
                  const ButtonSegment(
                      value: OctagonMetric.percentage, label: Text('Percent')),
              ],
              selected: {_metric},
              onSelectionChanged: (s) => setState(() => _metric = s.first),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            DropdownButton<String>(
              value: _periodKey,
              items: OctagonPeriod.all
                  .map((p) => DropdownMenuItem(value: p.key, child: Text(p.label)))
                  .toList(),
              onChanged: (v) => v == null ? null : _setPeriod(v),
            ),
            FilterChip(
              label: const Text('Avg / day'),
              selected: average,
              onSelected: _setAverage,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Swipe the chart left/right to switch metric (Frequency · Time ·
        // Number · Percent), wrapping around.
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < 0) {
              _cycleMetric(1); // swipe left -> next metric
            } else if (v > 0) {
              _cycleMetric(-1); // swipe right -> previous metric
            }
          },
          child: OctagonChart(
            points: _points(octView, average),
            formatValue: (v) => _formatValue(v, average),
            onTapAxis: _logForCategory,
            scale: _octagonScale(repo.settings.octagonScale),
          ),
        ),
        const SizedBox(height: 12),
        _periodNav(context),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => _push(LoggedScreen(repo: repo)),
            icon: const Icon(Icons.list_alt),
            label: const Text('View logs'),
          ),
        ),
      ],
    );
  }

  /// The ‹ label › navigation row under the chart. The arrows step the window
  /// by one unit of the selected period (disabled for All time).
  Widget _periodNav(BuildContext context) {
    final label = _windowFor(_navOffset).label;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous',
          onPressed: _navigable ? () => _shift(-1) : null,
        ),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              // Shown only when the window is in the past — jumps to now.
              if (_canForward)
                InkWell(
                  onTap: _resetToPresent,
                  child: Text('Now',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary)),
                ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next',
          onPressed: _canForward ? () => _shift(1) : null,
        ),
      ],
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _fmtDay(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
}
