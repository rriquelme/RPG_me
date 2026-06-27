import 'package:flutter/material.dart';

import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';

enum _Metric { count, time }

/// GitHub-contributions-style calendars: one **global** grid for all activity,
/// and one below it that can be **filtered by category**. A single metric
/// toggle (time spent / frequency) applies to both.
class HeatmapScreen extends StatefulWidget {
  final Repository repo;
  const HeatmapScreen({super.key, required this.repo});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  _Metric _metric = _Metric.time;
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

  Map<String, int> _data(bool global) {
    if (_metric == _Metric.count) return global ? _globalCounts : _filteredCounts;
    return global ? _globalSeconds : _filteredSeconds;
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
            segments: const [
              ButtonSegment(value: _Metric.time, label: Text('Time spent')),
              ButtonSegment(value: _Metric.count, label: Text('Frequency')),
            ],
            selected: {_metric},
            onSelectionChanged: (s) => setState(() => _metric = s.first),
          ),
          const SizedBox(height: 20),
          Text('All activity', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          HeatGrid(data: _data(true), isTime: isTime),
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
          HeatGrid(data: _data(false), isTime: isTime),
        ],
      ),
    );
  }
}

/// A single 26-week heatmap grid + legend, scaled to its own max value.
class HeatGrid extends StatelessWidget {
  final Map<String, int> data;
  final bool isTime;
  static const _weeks = 26;

  const HeatGrid({super.key, required this.data, required this.isTime});

  Color _cell(BuildContext context, int value, int max) {
    final scheme = Theme.of(context).colorScheme;
    if (value <= 0 || max <= 0) return scheme.surfaceContainerHighest;
    final r = value / max;
    final o = r <= 0.25 ? 0.30 : (r <= 0.5 ? 0.50 : (r <= 0.75 ? 0.72 : 1.0));
    return scheme.primary.withOpacity(o);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final start = monday.subtract(const Duration(days: (_weeks - 1) * 7));
    final maxVal = data.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(_weeks, (w) {
              return Column(
                children: List.generate(7, (d) {
                  final date = start.add(Duration(days: w * 7 + d));
                  final future = date.isAfter(today);
                  final value = future ? 0 : (data[LocalEngine.dayKey(date)] ?? 0);
                  return Container(
                    width: 15,
                    height: 15,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: future ? Colors.transparent : _cell(context, value, maxVal),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text('Less', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 6),
          ...[0.30, 0.50, 0.72, 1.0].map((o) => Container(
                width: 13,
                height: 13,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(o),
                  borderRadius: BorderRadius.circular(3),
                ),
              )),
          const SizedBox(width: 6),
          Text('More', style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(
            maxVal == 0
                ? 'No data'
                : 'peak ${isTime ? formatHms(maxVal) : '$maxVal'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ],
    );
  }
}
