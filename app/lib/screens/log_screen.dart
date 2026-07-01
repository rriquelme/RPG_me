import 'package:flutter/cupertino.dart' show CupertinoTimerPicker, CupertinoTimerPickerMode;
import 'package:flutter/material.dart';

import '../local/event.dart';
import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';
import '../widgets/subcategory_dialogs.dart';
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
  final _numberController = TextEditingController();
  final _percentController = TextEditingController();
  List<AxisDef> _axes = [];
  String? _selectedAxis;
  String? _selectedSub; // optional subcategory within the selected category
  int _hours = 0;
  int _minutes = 0;
  DateTime _when = DateTime.now();
  bool _hidden = false; // hide THIS entry from the octagon (axis graph)
  bool _submitting = false;
  String? _error;

  // Activity heatmap shown at the top when the setting is on. With no
  // subcategory picked (None) it shows the whole category; pick a subcategory
  // and it shows just that subcategory instead.
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
      if (ex.number != null) _numberController.text = _fmtNum(ex.number!);
      if (ex.percentage != null) _percentController.text = _fmtNum(ex.percentage!);
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
        (axis?.subcategoryNames.contains(ex.subcategory) ?? false)) {
      _selectedSub = ex.subcategory;
    }
    if (widget.repo.settings.showDashboardOnLog) _loadActivity();
  }

  /// Resolve a subcategory's colour, falling back to [fallback] when it has no
  /// custom colour set.
  Color _subColor(AxisDef axis, String subName, Color fallback) {
    final hex = axis.subcategoryByName(subName)?.colorHex ?? '';
    return hex.isEmpty ? fallback : colorFromHex(hex);
  }

  /// Create a subcategory in place, persist it on the category, then
  /// auto-select it. Used by the dropdown's "Create new…" item.
  Future<void> _createSubcategory(AxisDef axis) async {
    final name = await showCreateSubcategoryDialog(
        context: context, repo: widget.repo, axis: axis);
    if (name == null || !mounted) return;
    setState(() {
      _axes = widget.repo.axesConfig; // pick up the new subcategory
      _selectedSub = name; // auto-select it
    });
    _loadActivity();
  }

  AxisDef? _axisFor(String? key) {
    for (final a in _axes) {
      if (a.key == key) return a;
    }
    return null;
  }

  /// Refresh the activity heatmap for the current selection. With no
  /// subcategory picked (None) we show the whole category; with one picked we
  /// show just that subcategory. The "last click" wins.
  Future<void> _loadActivity() async {
    final key = _selectedAxis;
    if (key == null) return;
    final sub = _selectedSub;
    final cat = await widget.repo.dailyCounts(axisKey: key);
    final catS = await widget.repo.dailySeconds(axisKey: key);
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
      final settings = widget.repo.settings;
      final number = settings.trackNumber
          ? double.tryParse(_numberController.text.trim().replaceAll(',', '.'))
          : null;
      double? percentage;
      if (settings.trackPercentage) {
        final p =
            double.tryParse(_percentController.text.trim().replaceAll(',', '.'));
        if (p != null) percentage = p.clamp(0, 100).toDouble();
      }
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
          number: number,
          percentage: percentage,
        );
      } else {
        await widget.repo.log(
          _selectedAxis!,
          name,
          seconds: _seconds,
          at: _when,
          subcategory: sub,
          hidden: _hidden,
          number: number,
          percentage: percentage,
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

  /// Format a stored double without a trailing ".0".
  String _fmtNum(double n) =>
      n % 1 == 0 ? n.toInt().toString() : n.toString();

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _percentController.dispose();
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
                // A single activity dashboard: the whole category when no
                // subcategory is picked (None), or just the picked subcategory
                // (replacing the category one) when one is chosen.
                if (_selectedSub == null)
                  _ActivityCard(
                    title: 'Activity · ${axis.label}',
                    counts: _catCounts,
                    seconds: _catSeconds,
                    baseColor: colorFromHex(axis.colorHex),
                    firstDayOfWeek: widget.repo.settings.firstDayOfWeek,
                    selectionKey: 'cat/$_selectedAxis',
                  )
                else
                  _ActivityCard(
                    title: 'Activity · ${axis.label} › $_selectedSub',
                    counts: _subCounts,
                    seconds: _subSeconds,
                    baseColor: _subColor(
                        axis, _selectedSub!, colorFromHex(axis.colorHex)),
                    firstDayOfWeek: widget.repo.settings.firstDayOfWeek,
                    selectionKey: 'sub/$_selectedAxis/$_selectedSub',
                  ),
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
              // Subcategory picker — always available so a new one can be
              // created in place even when the category has none yet.
              if (axis != null) ...[
                const SizedBox(height: 4),
                DropdownButtonFormField<String?>(
                  value: _selectedSub,
                  decoration: const InputDecoration(labelText: 'Subcategory'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None'),
                    ),
                    ...axis.subcategories.map((s) => DropdownMenuItem<String?>(
                          value: s.name,
                          child: Row(children: [
                            Container(
                                width: 12,
                                height: 12,
                                color: _subColor(
                                    axis, s.name, colorFromHex(axis.colorHex))),
                            const SizedBox(width: 8),
                            Text(s.name),
                            if (s.hidden) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.visibility_off_outlined,
                                  size: 14,
                                  color: Theme.of(context).disabledColor),
                            ],
                          ]),
                        )),
                    const DropdownMenuItem<String?>(
                      value: kCreateSubcategory,
                      child: Row(children: [
                        Icon(Icons.add, size: 16),
                        SizedBox(width: 8),
                        Text('Create new…'),
                      ]),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == kCreateSubcategory) {
                      _createSubcategory(axis);
                      return;
                    }
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
              if (widget.repo.settings.trackNumber) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _numberController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Number (optional)',
                    hintText: 'e.g. 12',
                  ),
                ),
              ],
              if (widget.repo.settings.trackPercentage) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _percentController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Percentage (optional)',
                    hintText: '0–100',
                    suffixText: '%',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text('Time spent', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              // Scroll the hours/minutes wheels like a clock/alarm app.
              SizedBox(
                height: 110,
                child: CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.hm,
                  initialTimerDuration:
                      Duration(hours: _hours, minutes: _minutes),
                  onTimerDurationChanged: (d) => setState(() {
                    _hours = d.inHours;
                    _minutes = d.inMinutes % 60;
                  }),
                ),
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
/// dashboard on log creation" is enabled: a GitHub-style heatmap. Used for the
/// category, a single subcategory, or — with [dayColors] — all subcategories
/// coloured by each day's dominant one. Rebuilds when [selectionKey] changes.
class _ActivityCard extends StatelessWidget {
  final String title;
  final Map<String, int> counts;
  final Map<String, int> seconds;
  final Color baseColor;
  final int firstDayOfWeek;
  final String selectionKey;
  final Map<String, Color>? dayColors;
  const _ActivityCard({
    required this.title,
    required this.counts,
    required this.seconds,
    required this.baseColor,
    required this.firstDayOfWeek,
    required this.selectionKey,
    this.dayColors,
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
              dayColors: dayColors,
            ),
          ],
        ),
      ),
    );
  }
}

