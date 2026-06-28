import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../local/local_engine.dart';
import '../local/timer_entry.dart';
import '../models.dart';
import '../repository.dart';

/// A list of stopwatches you can run at the same time. Each banks time against
/// a category; "Stop & save" logs the elapsed time as a session.
class TimersScreen extends StatefulWidget {
  final Repository repo;
  const TimersScreen({super.key, required this.repo});

  @override
  State<TimersScreen> createState() => _TimersScreenState();
}

class _TimersScreenState extends State<TimersScreen> {
  List<TimerEntry> _timers = [];
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.repo.loadTimers().then((t) {
      if (mounted) setState(() => _timers = t);
    });
    // Fast tick so the milliseconds move and it feels alive.
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && _timers.any((t) => t.isRunning)) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _persist() => widget.repo.saveTimers(_timers);

  AxisDef? _axisOf(String key) {
    for (final a in widget.repo.axesConfig) {
      if (a.key == key) return a;
    }
    return null;
  }

  String _display(int ms) {
    String two(int n) => n.toString().padLeft(2, '0');
    final totalSec = ms ~/ 1000;
    final h = totalSec ~/ 3600, m = (totalSec % 3600) ~/ 60, s = totalSec % 60;
    final millis = (ms % 1000).toString().padLeft(3, '0');
    final base = h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
    return '$base.$millis';
  }

  Future<void> _add() async {
    final axes = widget.repo.axesConfig;
    if (axes.isEmpty) return;
    String axisKey = axes.first.key;
    final nameController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New timer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: axisKey,
                decoration: const InputDecoration(labelText: 'Category'),
                items: axes
                    .map((a) => DropdownMenuItem(
                          value: a.key,
                          child: Row(children: [
                            Container(width: 12, height: 12, color: colorFromHex(a.colorHex)),
                            const SizedBox(width: 8),
                            Text(a.label),
                          ]),
                        ))
                    .toList(),
                onChanged: (v) => setLocal(() => axisKey = v ?? axisKey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: 'Activity (optional)', hintText: 'study, deep work…'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start')),
          ],
        ),
      ),
    );
    if (created == true) {
      var name = nameController.text.trim();
      if (name.isEmpty) name = (_axisOf(axisKey)?.label ?? axisKey).toLowerCase();
      setState(() {
        _timers.add(TimerEntry(
          id: TimerEntry.newId(),
          label: name,
          axisKey: axisKey,
          runningSince: DateTime.now(),
        ));
      });
      await _persist();
    }
  }

  Future<void> _toggle(TimerEntry t) async {
    setState(() => t.isRunning ? t.pause() : t.start());
    await _persist();
  }

  Future<void> _reset(TimerEntry t) async {
    setState(() => t.reset());
    await _persist();
  }

  Future<void> _discard(TimerEntry t) async {
    setState(() => _timers.remove(t));
    await _persist();
  }

  /// Pressing stop pauses the timer and asks whether to save or discard it.
  Future<void> _stopConfirm(TimerEntry t) async {
    setState(() => t.pause());
    await _persist();
    final seconds = t.elapsedSeconds;
    if (seconds < 1) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Timer has no time yet.')));
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stop “${t.label}”?'),
        content: Text('Save ${formatHms(seconds)} to this category, or discard it?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Keep timer')),
          TextButton(onPressed: () => Navigator.pop(context, 'discard'), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (choice == 'save') {
      await widget.repo.log(t.axisKey, t.label, seconds: seconds);
      setState(() => _timers.remove(t));
      await _persist();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${formatHms(seconds)} to ${t.label}.')),
        );
      }
    } else if (choice == 'discard') {
      await _discard(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('New timer'),
      ),
      body: _timers.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No timers yet.\n\nTap “New timer” to start one — you can run '
                  'several at the same time. Each timer banks time against a '
                  'category; press Stop to save it.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: _timers.length,
              itemBuilder: (context, i) => _timerCard(_timers[i]),
            ),
    );
  }

  Widget _timerCard(TimerEntry t) {
    final theme = Theme.of(context);
    final axis = _axisOf(t.axisKey);
    final color = axis != null ? colorFromHex(axis.colorHex) : Colors.grey;
    return Slidable(
      key: ValueKey(t.id),
      // Swipe left to delete (kept out of easy reach).
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.3,
        children: [
          SlidableAction(
            onPressed: (_) => _discard(t),
            backgroundColor: Colors.red.shade600,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Delete',
          ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(backgroundColor: color, radius: 8),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.label,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${axis?.label ?? t.axisKey} · ${t.isRunning ? "running" : "paused"}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _display(t.elapsedMs),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: t.isRunning ? theme.colorScheme.primary : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () => _reset(t),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reset'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _toggle(t),
                    icon: Icon(t.isRunning ? Icons.pause : Icons.play_arrow),
                    label: Text(t.isRunning ? 'Pause' : 'Resume'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _stopConfirm(t),
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
