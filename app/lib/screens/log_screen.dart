import 'package:flutter/material.dart';

import '../local/event.dart';
import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';
import 'heatmap_screen.dart' show HeatGrid;

/// Log an activity: pick a category, name it, optionally record how long you
/// spent and on which day/time. Pass [existing] to edit a logged entry instead.
class LogScreen extends StatefulWidget {
  final Repository repo;
  final Event? existing;

  /// Pre-select this category when opening a fresh log (e.g. from tapping an
  /// octagon axis). Ignored when editing an [existing] entry.
  final String? initialAxisKey;
  const LogScreen({
    super.key,
    required this.repo,
    this.existing,
    this.initialAxisKey,
  });

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  List<AxisDef> _axes = [];
  String? _selectedAxis;
  String? _selectedSub; // optional subcategory within the selected category
  int _hours = 0;
  int _minutes = 0;
  DateTime _when = DateTime.now();
  bool _hidden = false; // hide THIS entry from the octagon (axis graph)
  bool _submitting = false;
  String? _error;

  // Activity heatmaps shown at the top when the setting is on: one for the
  // whole category, and (when a subcategory is picked) one for that subcategory.
  Map<String, int> _catCounts = {};
  Map<String, int> _catSeconds = {};
  Map<String, int> _subCounts = {};
  Map<String, int> _subSeconds = {};

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _nameController.text = ex.name;
      _hours = ex.seconds ~/ 3600;
      _minutes = (ex.seconds % 3600) ~/ 60;
      _when = ex.timestamp;
      _hidden = ex.hidden;
    }
    final a = widget.repo.axesConfig;
    _axes = a;
    final initial = widget.initialAxisKey;
    if (ex != null && a.any((x) => x.key == ex.axisKey)) {
      _selectedAxis = ex.axisKey;
    } else if (initial != null && a.any((x) => x.key == initial)) {
      _selectedAxis = initial;
    } else {
      _selectedAxis = a.isNotEmpty ? a.first.key : null;
    }
    final axis = _axisFor(_selectedAxis);
    if (ex != null &&
        ex.subcategory.isNotEmpty &&
        (axis?.subcategories.contains(ex.subcategory) ?? false)) {
      _selectedSub = ex.subcategory;
    }
    if (widget.repo.settings.showDashboardOnLog) _loadActivity();
  }

  AxisDef? _axisFor(String? key) {
    for (final a in _axes) {
      if (a.key == key) return a;
    }
    return null;
  }

  /// Refresh both activity heatmaps for the current selection. The category
  /// chart always shows the whole category; the subcategory chart reflects the
  /// picked subcategory (empty until one is chosen). The "last click" wins.
  Future<void> _loadActivity() async {
    final key = _selectedAxis;
    if (key == null) return;
    final cat = await widget.repo.dailyCounts(axisKey: key);
    final catS = await widget.repo.dailySeconds(axisKey: key);
    final sub = _selectedSub;
    final subC = sub == null
        ? <String, int>{}
        : await widget.repo.dailyCounts(axisKey: key, subcategory: sub);
    final subS = sub == null
        ? <String, int>{}
        : await widget.repo.dailySeconds(axisKey: key, subcategory: sub);
    if (mounted) {
      setState(() {
        _catCounts = cat;
        _catSeconds = catS;
        _subCounts = subC;
        _subSeconds = subS;
      });
    }
  }

  int get _seconds => _hours * 3600 + _minutes * 60;

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    setState(() {
      _when = DateTime(date.year, date.month, date.day,
          time?.hour ?? _when.hour, time?.minute ?? _when.minute);
    });
  }

  Future<void> _submit() async {
    if (_selectedAxis == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // Name is optional — fall back to the category's label.
      var name = _nameController.text.trim();
      if (name.isEmpty) {
        final axis = _axes.firstWhere((a) => a.key == _selectedAxis,
            orElse: () => _axes.first);
        name = axis.label.toLowerCase();
      }
      final ex = widget.existing;
      final sub = _selectedSub ?? '';
      if (ex != null) {
        await widget.repo.updateEvent(
          ex.id,
          axisKey: _selectedAxis!,
          name: name,
          seconds: _seconds,
          at: _when,
          note: ex.note,
          subcategory: sub,
          hidden: _hidden,
        );
      } else {
        await widget.repo.log(
          _selectedAxis!,
          name,
          seconds: _seconds,
          at: _when,
          subcategory: sub,
          hidden: _hidden,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    final whenLabel =
        '${_when.year}-${two(_when.month)}-${two(_when.day)}  ${two(_when.hour)}:${two(_when.minute)}';
    final editing = widget.existing != null;
    final axis = _axisFor(_selectedAxis);
    final showDash = !editing && widget.repo.settings.showDashboardOnLog;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit activity' : 'Log an activity')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (showDash && axis != null) ...[
                // Dashboard 1: the whole category's activity.
                _ActivityCard(
                  title: 'Activity · ${axis.label}',
                  counts: _catCounts,
                  seconds: _catSeconds,
                  baseColor: colorFromHex(axis.colorHex),
                  firstDayOfWeek: widget.repo.settings.firstDayOfWeek,
                  selectionKey: 'cat/$_selectedAxis',
                ),
                // Dashboard 2 (the "3rd"): only when the category has
                // subcategories — the selected subcategory's activity. By
                // default no subcategory is picked, so it prompts to choose one.
                if (axis.subcategories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  if (_selectedSub == null)
                    _ActivityPlaceholder(label: axis.label)
                  else
                    _ActivityCard(
                      title: 'Activity · ${axis.label} › $_selectedSub',
                      counts: _subCounts,
                      seconds: _subSeconds,
                      baseColor: colorFromHex(axis.colorHex),
                      firstDayOfWeek: widget.repo.settings.firstDayOfWeek,
                      selectionKey: 'sub/$_selectedAxis/$_selectedSub',
                    ),
                ],
                const SizedBox(height: 20),
              ],
              DropdownButtonFormField<String>(
                value: _selectedAxis,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _axes
                    .map((a) => DropdownMenuItem(
                          value: a.key,
                          child: Row(children: [
                            Container(
                                width: 12,
                                height: 12,
                                color: colorFromHex(a.colorHex)),
                            const SizedBox(width: 8),
                            Text(a.label),
                            if (a.hidden) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.visibility_off_outlined,
                                  size: 14,
                                  color: Theme.of(context).disabledColor),
                            ],
                          ]),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedAxis = v;
                    _selectedSub = null; // subcategories are per-category
                  });
                  _loadActivity(); // last click refreshes the dashboard
                },
              ),
              // Per-entry tick: keep THIS log out of the octagon (axis graph).
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text('Hide this entry from the chart'),
                subtitle: const Text(
                    "It's still logged; it just won't count on the octagon."),
                value: _hidden,
                onChanged:
                    _submitting ? null : (v) => setState(() => _hidden = v ?? false),
              ),
              // Subcategory picker (only when the category has subcategories).
              if (axis != null && axis.subcategories.isNotEmpty) ...[
                const SizedBox(height: 4),
                DropdownButtonFormField<String?>(
                  value: _selectedSub,
                  decoration: const InputDecoration(labelText: 'Subcategory (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('None')),
                    ...axis.subcategories.map((s) =>
                        DropdownMenuItem<String?>(value: s, child: Text(s))),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedSub = v);
                    _loadActivity(); // last click refreshes the dashboard
                  },
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'What did you do? (optional)',
                  hintText: 'gym, read, meditate…',
                ),
              ),
              const SizedBox(height: 24),
              Text('Time spent', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: _Stepper(label: 'Hours', value: _hours, max: 24, onChanged: (v) => setState(() => _hours = v))),
                  const SizedBox(width: 12),
                  Expanded(child: _Stepper(label: 'Minutes', value: _minutes, max: 59, step: 5, onChanged: (v) => setState(() => _minutes = v))),
                ],
              ),
              Text(
                _seconds == 0
                    ? 'No duration — logs a one-off tally.'
                    : 'Logs ${formatHms(_seconds)}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('When'),
                subtitle: Text(whenLabel),
                trailing: TextButton(onPressed: _pickWhen, child: const Text('Change')),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(editing ? 'Save changes' : 'Log it'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The activity dashboard shown at the top of the Log screen when "View
/// dashboard on log creation" is enabled: the GitHub-style heatmap of the
/// selected category — or, if a subcategory is chosen, of that subcategory.
/// Rebuilds whenever the selection changes (keyed on [selectionKey]).
class _ActivityCard extends StatelessWidget {
  final String title;
  final Map<String, int> counts;
  final Map<String, int> seconds;
  final Color baseColor;
  final int firstDayOfWeek;
  final String selectionKey;
  const _ActivityCard({
    required this.title,
    required this.counts,
    required this.seconds,
    required this.baseColor,
    required this.firstDayOfWeek,
    required this.selectionKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            HeatGrid(
              // A fresh key per selection so the grid re-scrolls to the latest.
              key: ValueKey(selectionKey),
              counts: counts,
              seconds: seconds,
              isTime: false,
              baseColor: baseColor,
              firstDayOfWeek: firstDayOfWeek,
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for the subcategory activity dashboard before a subcategory is
/// picked (it defaults to none).
class _ActivityPlaceholder extends StatelessWidget {
  final String label;
  const _ActivityPlaceholder({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.account_tree_outlined,
                size: 18, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pick a $label subcategory below to see its activity.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small +/- stepper for hours/minutes.
class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  const _Stepper({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: value <= 0 ? null : () => onChanged((value - step).clamp(0, max)),
            ),
            Text('$value', style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: value >= max ? null : () => onChanged((value + step).clamp(0, max)),
            ),
          ],
        ),
      ],
    );
  }
}
