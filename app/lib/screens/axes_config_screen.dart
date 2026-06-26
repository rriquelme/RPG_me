import 'dart:math';

import 'package:flutter/material.dart';

import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';

/// Edit the octagon's axes: rename, recolor, add or remove (between 6 and 10).
class AxesConfigScreen extends StatefulWidget {
  final Repository repo;
  const AxesConfigScreen({super.key, required this.repo});

  @override
  State<AxesConfigScreen> createState() => _AxesConfigScreenState();
}

class _AxesConfigScreenState extends State<AxesConfigScreen> {
  late List<AxisDef> _axes;
  final _rand = Random();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _axes = List.of(widget.repo.axesConfig);
  }

  String _newKey() {
    String key;
    do {
      key = 'axis_${_rand.nextInt(1 << 32).toRadixString(16)}';
    } while (_axes.any((a) => a.key == key));
    return key;
  }

  void _add() {
    if (_axes.length >= kMaxAxes) return;
    final color = kAxisPalette[_axes.length % kAxisPalette.length];
    setState(() => _axes.add(AxisDef(_newKey(), 'New axis', '', color)));
  }

  void _remove(int i) {
    if (_axes.length <= kMinAxes) return;
    setState(() => _axes.removeAt(i));
  }

  void _rename(int i, String label) {
    _axes[i] = _axes[i].copyWith(label: label);
  }

  Future<void> _pickColor(int i) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Pick a colour'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: kAxisPalette
                  .map((hex) => InkWell(
                        onTap: () => Navigator.pop(context, hex),
                        child: CircleAvatar(
                            backgroundColor: colorFromHex(hex), radius: 18),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
    if (chosen != null) setState(() => _axes[i] = _axes[i].copyWith(colorHex: chosen));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.saveAxes(_axes);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e is ArgumentError ? e.message.toString() : e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = _axes.length < kMaxAxes;
    final canRemove = _axes.length > kMinAxes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit octagon axes'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_axes.length} axes (allowed: $kMinAxes–$kMaxAxes). '
                    'Tap a colour to change it.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _axes.length,
              itemBuilder: (context, i) {
                final axis = _axes[i];
                return ListTile(
                  leading: GestureDetector(
                    onTap: () => _pickColor(i),
                    child: CircleAvatar(
                        backgroundColor: colorFromHex(axis.colorHex), radius: 14),
                  ),
                  title: TextFormField(
                    initialValue: axis.label,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => _rename(i, v),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: canRemove ? 'Remove' : 'Minimum $kMinAxes axes',
                    onPressed: canRemove ? () => _remove(i) : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: canAdd ? _add : null,
        icon: const Icon(Icons.add),
        label: Text(canAdd ? 'Add axis' : 'Max $kMaxAxes'),
      ),
    );
  }
}
