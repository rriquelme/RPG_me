import 'package:flutter/material.dart';

import '../local/event.dart';
import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';

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
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _nameController.text = ex.name;
      _hours = ex.seconds ~/ 3600;
      _minutes = (ex.seconds % 3600) ~/ 60;
      _when = ex.timestamp;
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
  }

  AxisDef? _axisFor(String? key) {
    for (final a in _axes) {
      if (a.key == key) return a;
    }
    return null;
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
        );
      } else {
        await widget.repo.log(
          _selectedAxis!,
          name,
          seconds: _seconds,
          at: _when,
          subcategory: sub,
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

  Future<void> _toggleHidden(bool hidden) async {
    final key = _selectedAxis;
    if (key == null) return;
    await widget.repo.setAxisHidden(key, hidden);
    if (mounted) setState(() => _axes = widget.repo.axesConfig);
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
              if (showDash && _selectedAxis != null) ...[
                _CategoryDashboard(
                    stats: widget.repo.categoryStats(_selectedAxis!)),
                if (axis != null && axis.subcategories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SubcategoryDashboard(
                    title: axis.label,
                    stats: widget.repo.subcategoryStats(_selectedAxis!),
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
                onChanged: (v) => setState(() {
                  _selectedAxis = v;
                  _selectedSub = null; // subcategories are per-category
                }),
              ),
              // Quick "hide from chart" tick for the selected category.
              if (axis != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text('Hide from chart'),
                  subtitle: const Text('Still logged, just not drawn on the octagon.'),
                  value: axis.hidden,
                  onChanged: _submitting ? null : (v) => _toggleHidden(v ?? false),
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
                  onChanged: (v) => setState(() => _selectedSub = v),
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

/// A compact dashboard card summarising the selected category: this week and
/// all-time counts/time, current level, and when it was last logged. Shown at
/// the top of the Log screen when "View dashboard on log creation" is enabled.
class _CategoryDashboard extends StatelessWidget {
  final CategoryStats stats;
  const _CategoryDashboard({required this.stats});

  String _lastLabel() {
    final last = stats.lastLogged;
    if (last == null) return 'never';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(last.year, last.month, last.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'today';
    if (diff == 1) return 'yesterday';
    if (diff < 7) return '$diff days ago';
    return '${last.year}-${last.month.toString().padLeft(2, '0')}-${last.day.toString().padLeft(2, '0')}';
  }

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
            Row(
              children: [
                Text(stats.label, style: theme.textTheme.titleMedium),
                const Spacer(),
                Chip(
                  label: Text('Lv ${stats.level}'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'This week',
                    value: '${stats.weekCount}×',
                    sub: stats.weekSeconds > 0 ? formatHms(stats.weekSeconds) : '—',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'All time',
                    value: '${stats.totalCount}×',
                    sub: stats.totalSeconds > 0 ? formatHms(stats.totalSeconds) : '—',
                  ),
                ),
                Expanded(
                  child: _Stat(label: 'Last', value: _lastLabel(), sub: ''),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A breakdown card listing each subcategory's this-week and all-time activity.
/// Shown beneath the category dashboard when the category has subcategories.
class _SubcategoryDashboard extends StatelessWidget {
  final String title;
  final List<SubcategoryStat> stats;
  const _SubcategoryDashboard({required this.title, required this.stats});

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
            Text('$title — subcategories', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(flex: 4, child: SizedBox()),
                Expanded(
                    flex: 3,
                    child: Text('This week',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline))),
                Expanded(
                    flex: 3,
                    child: Text('All time',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline))),
              ],
            ),
            const Divider(height: 16),
            for (final s in stats)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(flex: 4, child: Text(s.label)),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _cell(s.weekCount, s.weekSeconds),
                        textAlign: TextAlign.end,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _cell(s.totalCount, s.totalSeconds),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _cell(int count, int seconds) =>
      seconds > 0 ? '$count× · ${formatHms(seconds)}' : '$count×';
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  const _Stat({required this.label, required this.value, required this.sub});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleMedium),
        if (sub.isNotEmpty)
          Text(sub, style: theme.textTheme.bodySmall),
      ],
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
