import 'package:flutter/material.dart';

import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';

enum _Metric { count, time }

/// GitHub-contributions-style calendars: a **global** grid for all activity and
/// one below it filtered by category. Defaults to **frequency** (how many times
/// per day); a single log is a light cell, more are darker. Tap any day to see
/// its frequency and time spent. A toggle switches the shading to time spent.
class HeatmapScreen extends StatefulWidget {
  final Repository repo;
  const HeatmapScreen({super.key, required this.repo});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  _Metric _metric = _Metric.count; // frequency is primary
  Map<String, int> _globalCounts = {};
  Map<String, int> _globalSeconds = {};
  List<AxisDef> _axes = [];
  String? _axisKey;
  Map<String, int> _filteredCounts = {};
  Map<String, int> _filteredSeconds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final counts = await widget.repo.dailyCounts();
    final seconds = await widget.repo.dailySeconds();
    final axes = widget.repo.axesConfig;
    setState(() {
      _globalCounts = counts;
      _globalSeconds = seconds;
      _axes = axes;
      _axisKey = axes.isNotEmpty ? axes.first.key : null;
    });
    await _loadFiltered();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadFiltered() async {
    if (_axisKey == null) return;
    final counts = await widget.repo.dailyCounts(axisKey: _axisKey);
    final seconds = await widget.repo.dailySeconds(axisKey: _axisKey);
    if (mounted) {
      setState(() {
        _filteredCounts = counts;
        _filteredSeconds = seconds;
      });
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
          Text('All activity', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          HeatGrid(
            counts: _globalCounts,
            seconds: _globalSeconds,
            isTime: isTime,
            baseColor: const Color(0xFF2E9E4F),
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('By category', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              DropdownButton<String>(
                value: _axisKey,
                items: _axes
                    .map((a) => DropdownMenuItem(
                          value: a.key,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 12, height: 12, color: colorFromHex(a.colorHex)),
                            const SizedBox(width: 8),
                            Text(a.label),
                          ]),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() => _axisKey = v);
                  _loadFiltered();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          HeatGrid(
            counts: _filteredCounts,
            seconds: _filteredSeconds,
            isTime: isTime,
            baseColor: _axisKey == null
                ? Theme.of(context).colorScheme.primary
                : colorFromHex(_axes.firstWhere((a) => a.key == _axisKey).colorHex),
          ),
        ],
      ),
    );
  }
}

/// A single 26-week heatmap grid with weekday labels and tappable days.
class HeatGrid extends StatelessWidget {
  final Map<String, int> counts;
  final Map<String, int> seconds;
  final bool isTime;
  final Color baseColor;
  static const _weeks = 26;
  static const _cell = 15.0;
  static const _margin = 2.0;
  static const _row = _cell + 2 * _margin; // total height of one day row

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  const HeatGrid({
    super.key,
    required this.counts,
    required this.seconds,
    required this.isTime,
    required this.baseColor,
  });

  /// Frequency: absolute buckets (1 light → 4+ darkest). Time: relative to max.
  Color _color(BuildContext context, int count, int secs, int maxSecs) {
    final empty = Theme.of(context).colorScheme.surfaceContainerHighest;
    if (isTime) {
      if (secs <= 0 || maxSecs <= 0) return empty;
      final r = secs / maxSecs;
      final o = r <= 0.25 ? 0.35 : (r <= 0.5 ? 0.55 : (r <= 0.75 ? 0.78 : 1.0));
      return baseColor.withOpacity(o);
    }
    if (count <= 0) return empty;
    final o = count == 1 ? 0.32 : (count == 2 ? 0.52 : (count == 3 ? 0.74 : 1.0));
    return baseColor.withOpacity(o);
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final start = monday.subtract(const Duration(days: (_weeks - 1) * 7));
    final maxSecs = seconds.values.fold<int>(0, (a, b) => a > b ? a : b);
    final maxCount = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    final labelStyle = Theme.of(context).textTheme.bodySmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Weekday labels on the left.
            Column(
              children: List.generate(
                7,
                (d) => SizedBox(
                  height: _row,
                  width: 22,
                  child: Center(child: Text(_weekdays[d], style: labelStyle)),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(_weeks, (w) {
                    return Column(
                      children: List.generate(7, (d) {
                        final date = start.add(Duration(days: w * 7 + d));
                        final future = date.isAfter(today);
                        final k = LocalEngine.dayKey(date);
                        final c = future ? 0 : (counts[k] ?? 0);
                        final s = future ? 0 : (seconds[k] ?? 0);
                        return GestureDetector(
                          onTap: future ? null : () => _showDay(context, date, c, s),
                          child: Container(
                            width: _cell,
                            height: _cell,
                            margin: const EdgeInsets.all(_margin),
                            decoration: BoxDecoration(
                              color: future
                                  ? Colors.transparent
                                  : _color(context, c, s, maxSecs),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        );
                      }),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text('Less', style: labelStyle),
          const SizedBox(width: 6),
          ...[0.32, 0.52, 0.74, 1.0].map((o) => Container(
                width: 13,
                height: 13,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: baseColor.withOpacity(o),
                  borderRadius: BorderRadius.circular(3),
                ),
              )),
          const SizedBox(width: 6),
          Text('More', style: labelStyle),
          const Spacer(),
          Text(
            isTime
                ? (maxSecs == 0 ? 'No data' : 'peak ${formatHms(maxSecs)}')
                : (maxCount == 0 ? 'No data' : 'peak $maxCount×'),
            style: labelStyle,
          ),
        ]),
      ],
    );
  }
}
