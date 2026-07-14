import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../local/local_engine.dart';
import '../local/timer_entry.dart';
import '../models.dart';
import '../repository.dart';
import '../widgets/subcategory_dialogs.dart';

/// Mutable selection state shared with the New/Edit timer dialog fields.
class _DialogSel {
  List<AxisDef> axes;
  String axisKey;
  String? subKey;
  _DialogSel(this.axes, this.axisKey, [this.subKey]);

  AxisDef get axis =>
      axes.firstWhere((a) => a.key == axisKey, orElse: () => axes.first);
}

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

  Widget _labeledWheel(String label, Widget wheel) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          SizedBox(height: 92, child: wheel),
        ],
      );

  /// The category scroll wheel shared by the New/Edit timer dialogs. Scrolling
  /// selects directly (no tap-to-open). Resets the subcategory wheel to None.
  Widget _categoryWheel(_DialogSel st, StateSetter setLocal,
      FixedExtentScrollController ctrl, FixedExtentScrollController subCtrl) {
    return _labeledWheel(
      'Category',
      CupertinoPicker(
        scrollController: ctrl,
        itemExtent: 28,
        magnification: 1.1,
        squeeze: 1.15,
        useMagnifier: true,
        onSelectedItemChanged: (i) {
          if (i < 0 || i >= st.axes.length) return;
          setLocal(() {
            st.axisKey = st.axes[i].key;
            st.subKey = null; // subcategories are per-category
          });
          if (subCtrl.hasClients) subCtrl.jumpToItem(0);
        },
        children: st.axes
            .map((a) => _wheelRow(a.label, dot: colorFromHex(a.colorHex)))
            .toList(),
      ),
    );
  }

  /// The subcategory scroll wheel — None + the category's subcategories, with a
  /// "New" button to create one on the fly.
  Widget _subcategoryWheel(
      _DialogSel st, StateSetter setLocal, FixedExtentScrollController subCtrl) {
    final axis = st.axis;
    final subs = axis.subcategories;
    Color colorOf(SubcategoryDef s) => s.colorHex.isNotEmpty
        ? colorFromHex(s.colorHex)
        : colorFromHex(axis.colorHex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('Subcategory', style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New'),
              onPressed: () async {
                final created = await showCreateSubcategoryDialog(
                    context: context, repo: widget.repo, axis: axis);
                if (created == null) return;
                setLocal(() {
                  st.axes = widget.repo.axesConfig; // pick up the new one
                  st.subKey = created;
                });
                final idx = st.axis.subcategories
                    .indexWhere((s) => s.name == created);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (subCtrl.hasClients && idx >= 0) subCtrl.jumpToItem(idx + 1);
                });
              },
            ),
          ],
        ),
        SizedBox(
          height: 92,
          child: CupertinoPicker(
            scrollController: subCtrl,
            itemExtent: 28,
            magnification: 1.1,
            squeeze: 1.15,
            useMagnifier: true,
            onSelectedItemChanged: (i) =>
                setLocal(() => st.subKey = i == 0 ? null : subs[i - 1].name),
            children: [
              _wheelRow('None'),
              ...subs.map((s) =>
                  _wheelRow(s.name, dot: colorOf(s), hidden: s.hidden)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _add() async {
    final axes = widget.repo.axesConfig;
    if (axes.isEmpty) return;
    final st = _DialogSel(axes, axes.first.key);
    final nameController = TextEditingController();
    final catCtrl = FixedExtentScrollController();
    final subCtrl = FixedExtentScrollController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New timer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _categoryWheel(st, setLocal, catCtrl, subCtrl),
                const SizedBox(height: 8),
                _subcategoryWheel(st, setLocal, subCtrl),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                      labelText: 'Activity (optional)',
                      hintText: 'study, deep work…'),
                ),
              ],
            ),
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
    catCtrl.dispose();
    subCtrl.dispose();
    if (created == true) {
      var name = nameController.text.trim();
      // Fall back to the category's own label (keeping its capitalisation).
      if (name.isEmpty) name = _axisOf(st.axisKey)?.label ?? st.axisKey;
      setState(() {
        _timers.add(TimerEntry(
          id: TimerEntry.newId(),
          label: name,
          axisKey: st.axisKey,
          subcategory: st.subKey ?? '',
          runningSince: DateTime.now(),
        ));
      });
      await _persist();
    }
  }

  /// The "shadow" quick timer: start a running stopwatch immediately with no
  /// category set, so you can time first and label it later via Edit.
  Future<void> _quickStart() async {
    setState(() {
      _timers.add(TimerEntry(
        id: TimerEntry.newId(),
        label: '',
        axisKey: '',
        subcategory: '',
        runningSince: DateTime.now(),
      ));
    });
    await _persist();
  }

  Future<void> _toggle(TimerEntry t) async {
    setState(() => t.isRunning ? t.pause() : t.start());
    await _persist();
  }

  Future<void> _reset(TimerEntry t) async {
    setState(() => t.reset());
    await _persist();
  }

  /// Change a (possibly running) timer's category, subcategory and/or name —
  /// keeps elapsed.
  Future<void> _edit(TimerEntry t) async {
    final axes = widget.repo.axesConfig;
    final axisKey = axes.any((a) => a.key == t.axisKey)
        ? t.axisKey
        : (axes.isNotEmpty ? axes.first.key : t.axisKey);
    final st = _DialogSel(axes, axisKey);
    final startAxis = _axisOf(axisKey);
    if (t.subcategory.isNotEmpty &&
        (startAxis?.subcategoryNames.contains(t.subcategory) ?? false)) {
      st.subKey = t.subcategory;
    }
    final nameController = TextEditingController(text: t.label);
    final catIndex = axes.indexWhere((a) => a.key == axisKey);
    final subs = startAxis?.subcategories ?? const <SubcategoryDef>[];
    final subIndex =
        st.subKey == null ? 0 : subs.indexWhere((s) => s.name == st.subKey) + 1;
    final catCtrl =
        FixedExtentScrollController(initialItem: catIndex < 0 ? 0 : catIndex);
    final subCtrl =
        FixedExtentScrollController(initialItem: subIndex < 0 ? 0 : subIndex);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Edit timer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _categoryWheel(st, setLocal, catCtrl, subCtrl),
                const SizedBox(height: 8),
                _subcategoryWheel(st, setLocal, subCtrl),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration:
                      const InputDecoration(labelText: 'Activity (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    catCtrl.dispose();
    subCtrl.dispose();
    if (ok == true) {
      var name = nameController.text.trim();
      // Fall back to the category's own label (keeping its capitalisation).
      if (name.isEmpty) name = _axisOf(st.axisKey)?.label ?? st.axisKey;
      setState(() {
        t.axisKey = st.axisKey;
        t.subcategory = st.subKey ?? '';
        t.label = name;
      });
      await _persist();
    }
  }

  Future<void> _discard(TimerEntry t) async {
    setState(() => _timers.remove(t));
    await _persist();
  }

  /// Pressing stop pauses the timer and asks whether to save or discard it.
  /// A zero-time timer is fine — it just logs a no-duration tally, like a Log
  /// entry with no time. The Keep / Discard / Save menu always shows.
  Future<void> _stopConfirm(TimerEntry t) async {
    setState(() => t.pause());
    await _persist();
    final seconds = t.elapsedSeconds;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stop “${t.label}”?'),
        content: Text(seconds > 0
            ? 'Save ${formatHms(seconds)} to this category, or discard it?'
            : 'Log this session with no time to this category, or discard it?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Keep timer')),
          TextButton(onPressed: () => Navigator.pop(context, 'discard'), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (choice == 'save') {
      // A quick/shadow timer may have no category yet — set one before logging.
      if (_axisOf(t.axisKey) == null) {
        await _edit(t);
        if (_axisOf(t.axisKey) == null) return; // still none — keep the timer
      }
      await widget.repo.log(t.axisKey, t.label,
          seconds: seconds, subcategory: t.subcategory);
      setState(() => _timers.remove(t));
      await _persist();
      if (mounted) {
        final what = seconds > 0 ? formatHms(seconds) : 'a session';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved $what to ${t.label}.')),
        );
      }
    } else if (choice == 'discard') {
      await _discard(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New timer',
            onPressed: _add,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('New timer'),
      ),
      body: _timers.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                _shadowCard(),
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Tap the play button above to start timing right away (no '
                    'category — set it later with Edit), or “New timer” to pick '
                    'a category first. You can run several at once; press Stop '
                    'to save.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: _timers.length,
              itemBuilder: (context, i) => _timerCard(_timers[i]),
            ),
    );
  }

  /// A greyed-out 0:00 card shown when there are no timers: press play to
  /// quick-start one with no category.
  Widget _shadowCard() {
    final theme = Theme.of(context);
    final faded = theme.disabledColor;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: faded, radius: 8),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Quick timer',
                      style: theme.textTheme.titleMedium?.copyWith(color: faded)),
                ),
                Text('no category', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _display(0),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: faded,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: FilledButton.icon(
                onPressed: _quickStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
            ),
          ],
        ),
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
                      t.label.isEmpty ? 'Untitled timer' : t.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: t.label.isEmpty ? theme.disabledColor : null),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${axis?.label ?? (t.axisKey.isEmpty ? "no category" : t.axisKey)}'
                    '${t.subcategory.isNotEmpty ? " › ${t.subcategory}" : ""}'
                    ' · ${t.isRunning ? "running" : "paused"}',
                    style: theme.textTheme.bodySmall,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit category / name',
                    onPressed: () => _edit(t),
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
