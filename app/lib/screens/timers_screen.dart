import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../local/local_engine.dart';
import '../local/timer_entry.dart';
import '../models.dart';
import '../repository.dart';

/// A list of stopwatches you can run at the same time. Each one banks time
/// against a category; "Stop & save" logs the elapsed time as a session.
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
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
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

  String _clock(int seconds) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
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
                    labelText: 'Activity', hintText: 'study, deep work…'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Start')),
          ],
        ),
      ),
    );
    if (created == true) {
      final name = nameController.text.trim();
      if (name.isEmpty) return;
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
          TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Keep timer')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save')),
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
    // 'cancel' / null: leave the (now paused) timer in place.
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
                  'No timers running. Tap “New timer” to start one — you can '
                  'run several at once.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  Icon(Icons.swipe, size: 16, color: Theme.of(context).hintColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Swipe right to stop & save · swipe left to delete',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88, top: 4),
                  itemCount: _timers.length,
              itemBuilder: (context, i) {
                final t = _timers[i];
                final axis = _axisOf(t.axisKey);
                return Slidable(
                  key: ValueKey(t.id),
                  // Slide right → reveal "Stop & save".
                  startActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    extentRatio: 0.3,
                    children: [
                      SlidableAction(
                        onPressed: (_) => _stopConfirm(t),
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        icon: Icons.stop,
                        label: 'Stop & save',
                      ),
                    ],
                  ),
                  // Slide left → reveal "Delete" (kept out of easy reach).
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
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            axis != null ? colorFromHex(axis.colorHex) : Colors.grey,
                        radius: 14,
                      ),
                      title: Text(t.label),
                      subtitle: Text(
                        '${axis?.label ?? t.axisKey} · ${_clock(t.elapsedSeconds)}'
                        '${t.isRunning ? ' • running' : ' • paused'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(t.isRunning ? Icons.pause : Icons.play_arrow),
                            tooltip: t.isRunning ? 'Pause' : 'Resume',
                            onPressed: () => _toggle(t),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Reset',
                            onPressed: () => _reset(t),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
                ),
              ),
            ]),
    );
  }
}
