import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

/// Shows tracked time per period (today / week / month / YTD / all-time),
/// either across all activities or drilled into one.
class TimeScreen extends StatefulWidget {
  final ApiClient api;
  const TimeScreen({super.key, required this.api});

  @override
  State<TimeScreen> createState() => _TimeScreenState();
}

class _TimeScreenState extends State<TimeScreen> {
  Future<TimePeriods>? _future;
  String? _activity; // null = all activities

  @override
  void initState() {
    super.initState();
    _future = widget.api.time();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.api.time());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Time tracked')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<TimePeriods>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                const SizedBox(height: 80),
                Center(child: Text(snap.error.toString())),
              ]);
            }
            final data = snap.data!;
            // Activity names known across all-time, for the filter.
            final activities = data['all_time'].byActivity.keys.toList()..sort();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String?>(
                  value: _activity,
                  decoration: const InputDecoration(labelText: 'Activity'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All activities')),
                    ...activities.map(
                        (a) => DropdownMenuItem(value: a, child: Text(a))),
                  ],
                  onChanged: (v) => setState(() => _activity = v),
                ),
                const SizedBox(height: 8),
                ...TimePeriods.ordered.map((entry) {
                  final (key, label) = entry;
                  final totals = data[key];
                  final seconds = _activity == null
                      ? totals.totalSeconds
                      : (totals.byActivity[_activity] ?? 0);
                  return Card(
                    child: ListTile(
                      title: Text(label),
                      trailing: Text(
                        formatHms(seconds),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      subtitle: _activity == null
                          ? _topActivities(context, totals)
                          : null,
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget? _topActivities(BuildContext context, TimeTotals totals) {
    if (totals.byActivity.isEmpty) return null;
    final top = totals.byActivity.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final text = top
        .take(3)
        .map((e) => '${e.key} ${formatHms(e.value)}')
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
