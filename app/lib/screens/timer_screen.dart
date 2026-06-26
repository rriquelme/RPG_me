import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

/// A stopwatch. Start it when you begin (e.g. studying); when you stop you get
/// a confirmation dialog to file the elapsed time under a category.
class TimerScreen extends StatefulWidget {
  final ApiClient api;
  final String? suggestedName;
  const TimerScreen({super.key, required this.api, this.suggestedName});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  List<AxisStat> _axes = [];

  @override
  void initState() {
    super.initState();
    widget.api.axes().then((a) {
      if (mounted) setState(() => _axes = a);
    }).catchError((_) {});
  }

  void _start() {
    _stopwatch.start();
    _ticker ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  void _pause() {
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    setState(() {});
  }

  void _reset() {
    _pause();
    _stopwatch.reset();
    setState(() {});
  }

  Future<void> _stopAndSave() async {
    _pause();
    final seconds = _stopwatch.elapsed.inSeconds;
    if (seconds < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start the timer first.')),
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SaveSessionDialog(
        api: widget.api,
        axes: _axes,
        seconds: seconds,
        suggestedName: widget.suggestedName,
      ),
    );
    if (saved == true && mounted) Navigator.of(context).pop(true);
  }

  String get _clock {
    final d = _stopwatch.elapsed;
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _stopwatch.isRunning;
    return Scaffold(
      appBar: AppBar(title: const Text('Timer')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _clock,
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: running ? _pause : _start,
                  icon: Icon(running ? Icons.pause : Icons.play_arrow),
                  label: Text(running ? 'Pause' : 'Start'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _stopwatch.elapsed.inSeconds == 0 ? null : _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: _stopAndSave,
              icon: const Icon(Icons.stop),
              label: const Text('Stop & save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation: file the elapsed time under an axis + activity name.
class _SaveSessionDialog extends StatefulWidget {
  final ApiClient api;
  final List<AxisStat> axes;
  final int seconds;
  final String? suggestedName;
  const _SaveSessionDialog({
    required this.api,
    required this.axes,
    required this.seconds,
    this.suggestedName,
  });

  @override
  State<_SaveSessionDialog> createState() => _SaveSessionDialogState();
}

class _SaveSessionDialogState extends State<_SaveSessionDialog> {
  late final TextEditingController _nameController;
  String? _axis;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.suggestedName ?? '');
    _axis = widget.axes.isNotEmpty ? widget.axes.first.key : null;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (_axis == null || name.isEmpty) {
      setState(() => _error = 'Pick a category and name the activity.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.log(_axis!, name, seconds: widget.seconds);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
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
    final mins = widget.seconds / 60;
    return AlertDialog(
      title: Text('Save ${formatHms(widget.seconds)}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'This session will be added to a category '
            '(+${mins.round()} exp).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _axis,
            decoration: const InputDecoration(labelText: 'Category'),
            items: widget.axes
                .map((a) => DropdownMenuItem(
                      value: a.key,
                      child: Row(children: [
                        Container(width: 12, height: 12, color: a.color),
                        const SizedBox(width: 8),
                        Text(a.label),
                      ]),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _axis = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Activity',
              hintText: 'study, deep work…',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
