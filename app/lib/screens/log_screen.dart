import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

/// Form to log one routine/activity: pick an axis, name it, set exp.
class LogScreen extends StatefulWidget {
  final ApiClient api;
  const LogScreen({super.key, required this.api});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  List<AxisStat> _axes = [];
  String? _selectedAxis;
  int _exp = 10;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAxes();
  }

  Future<void> _loadAxes() async {
    try {
      final axes = await widget.api.axes();
      setState(() {
        _axes = axes;
        _selectedAxis = axes.isNotEmpty ? axes.first.key : null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedAxis == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.api.log(_selectedAxis!, _nameController.text.trim(), exp: _exp);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Log a routine')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              DropdownButtonFormField<String>(
                value: _selectedAxis,
                decoration: const InputDecoration(labelText: 'Life area'),
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
              Text('Experience: $_exp', style: Theme.of(context).textTheme.titleMedium),
              Slider(
                value: _exp.toDouble(),
                min: 5,
                max: 100,
                divisions: 19,
                label: '$_exp',
                onChanged: (v) => setState(() => _exp = v.round()),
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
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add),
                label: const Text('Log it (+exp)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
