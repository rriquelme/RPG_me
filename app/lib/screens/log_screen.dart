import 'package:flutter/material.dart';

import '../models.dart';
import '../repository.dart';

/// Log an activity: pick a category, name it, optionally record how long you
/// spent and on which day/time (so you can review it later).
class LogScreen extends StatefulWidget {
  final Repository repo;
  const LogScreen({super.key, required this.repo});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  List<AxisStat> _axes = [];
  String? _selectedAxis;
  int _hours = 0;
  int _minutes = 0;
  DateTime _when = DateTime.now();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.repo.axes().then((a) {
      if (mounted) {
        setState(() {
          _axes = a;
          _selectedAxis = a.isNotEmpty ? a.first.key : null;
        });
      }
    }).catchError((e) => setState(() => _error = e.toString()));
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
    if (!_formKey.currentState!.validate() || _selectedAxis == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repo.log(
        _selectedAxis!,
        _nameController.text.trim(),
        seconds: _seconds,
        at: _when,
      );
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
    return Scaffold(
      appBar: AppBar(title: const Text('Log an activity')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              DropdownButtonFormField<String>(
                value: _selectedAxis,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _axes
                    .map((a) => DropdownMenuItem(
                          value: a.key,
                          child: Row(children: [
                            Container(width: 12, height: 12, color: a.color),
                            const SizedBox(width: 8),
                            Text(a.label),
                          ]),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedAxis = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'What did you do?',
                  hintText: 'gym, read, meditate…',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
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
                label: const Text('Log it'),
              ),
            ],
          ),
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
