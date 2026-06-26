import 'package:flutter/material.dart';

import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';

/// A GitHub-contributions-style calendar: one square per day over the last
/// ~26 weeks, shaded by either how often you logged (count) or how long you
/// spent (time).
class HeatmapScreen extends StatefulWidget {
  final Repository repo;
  const HeatmapScreen({super.key, required this.repo});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

enum _Metric { count, time }

class _HeatmapScreenState extends State<HeatmapScreen> {
  static const _weeks = 26;
  _Metric _metric = _Metric.time;
  Map<String, int> _counts = {};
  Map<String, int> _seconds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = await widget.repo.dailyCounts();
    final seconds = await widget.repo.dailySeconds();
    if (mounted) {
      setState(() {
        _counts = counts;
        _seconds = seconds;
        _loading = false;
      });
    }
  }

  Map<String, int> get _data => _metric == _Metric.count ? _counts : _seconds;

  Color _cellColor(BuildContext context, int value, int max) {
    final scheme = Theme.of(context).colorScheme;
    if (value <= 0 || max <= 0) return scheme.surfaceContainerHighest;
    final r = value / max;
    final level = r <= 0.25 ? 0.30 : (r <= 0.5 ? 0.50 : (r <= 0.75 ? 0.72 : 1.0));
    return scheme.primary.withOpacity(level);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Activity')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final mondayThisWeek = today.subtract(Duration(days: today.weekday - 1));
    final start = mondayThisWeek.subtract(const Duration(days: (_weeks - 1) * 7));

    final data = _data;
    final maxVal = data.values.fold<int>(0, (a, b) => a > b ? a : b);

    String fmt(int v) =>
        _metric == _Metric.count ? '$v' : formatHms(v);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<_Metric>(
              segments: const [
                ButtonSegment(value: _Metric.time, label: Text('Time spent')),
                ButtonSegment(value: _Metric.count, label: Text('Frequency')),
              ],
              selected: {_metric},
              onSelectionChanged: (s) => setState(() => _metric = s.first),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true, // show the most recent weeks first
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(_weeks, (w) {
                  return Column(
                    children: List.generate(7, (d) {
                      final date = start.add(Duration(days: w * 7 + d));
                      final future = date.isAfter(today);
                      final value = future ? 0 : (data[LocalEngine.dayKey(date)] ?? 0);
                      return Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: future
                              ? Colors.transparent
                              : _cellColor(context, value, maxVal),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Less', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 6),
                ...[0.30, 0.50, 0.72, 1.0].map((o) => Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(o),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    )),
                const SizedBox(width: 6),
                Text('More', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              maxVal == 0
                  ? 'Nothing logged yet — start logging to fill the grid.'
                  : 'Busiest day: ${fmt(maxVal)} ${_metric == _Metric.count ? "events" : ""}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
