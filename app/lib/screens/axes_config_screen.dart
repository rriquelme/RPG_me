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
    setState(() => _axes.add(AxisDef(_newKey(), 'New category', '', color)));
  }

  void _remove(int i) {
    if (_axes.length <= kMinAxes) return;
    setState(() => _axes.removeAt(i));
  }

  void _rename(int i, String label) {
    _axes[i] = _axes[i].copyWith(label: label);
  }

  void _toggleHidden(int i) {
    setState(() => _axes[i] = _axes[i].copyWith(hidden: !_axes[i].hidden));
  }

  Future<void> _editSubcategories(int i) async {
    final subs = List<String>.of(_axes[i].subcategories);
    final controller = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          void add() {
            final t = controller.text.trim();
            if (t.isNotEmpty && !subs.contains(t)) setLocal(() => subs.add(t));
            controller.clear();
          }

          return AlertDialog(
            title: Text('Subcategories · ${_axes[i].label}'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Add a subcategory',
                            isDense: true,
                          ),
                          onSubmitted: (_) => add(),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.add), onPressed: add),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (subs.isEmpty)
                    const Text('None yet — subcategories are optional.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final s in subs)
                          InputChip(
                            label: Text(s),
                            onDeleted: () => setLocal(() => subs.remove(s)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, subs),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) {
      setState(() => _axes[i] = _axes[i].copyWith(subcategories: result));
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = _axes.removeAt(oldIndex);
      _axes.insert(newIndex, moved);
    });
  }

  Future<void> _pickColor(int i) async {
    // A sentinel for "no custom colour" (colours are optional).
    const none = '__none__';
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Pick a colour (optional)'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // "Default" = no custom colour.
                InkWell(
                  onTap: () => Navigator.pop(context, none),
                  child: CircleAvatar(
                    backgroundColor: kDefaultAxisColor,
                    radius: 18,
                    child: const Icon(Icons.format_color_reset, size: 18, color: Colors.white),
                  ),
                ),
                ...kAxisPalette.map((hex) => InkWell(
                      onTap: () => Navigator.pop(context, hex),
                      child: CircleAvatar(backgroundColor: colorFromHex(hex), radius: 18),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
    if (chosen != null) {
      setState(() => _axes[i] = _axes[i].copyWith(colorHex: chosen == none ? '' : chosen));
    }
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
        title: const Text('Edit categories'),
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
                    '${_axes.length} categories (allowed: $kMinAxes–$kMaxAxes). '
                    'Tap a colour to change it; drag ☰ to reorder; tap 👁 to hide '
                    'from the chart (still loggable); tap the subcategories line '
                    'to edit them.',
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
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              onReorder: _reorder,
              itemCount: _axes.length,
              itemBuilder: (context, i) {
                final axis = _axes[i];
                final subs = axis.subcategories;
                return ListTile(
                  key: ValueKey(axis.key),
                  leading: GestureDetector(
                    onTap: () => _pickColor(i),
                    child: CircleAvatar(
                        backgroundColor: colorFromHex(axis.colorHex), radius: 14),
                  ),
                  title: TextFormField(
                    initialValue: axis.label,
                    style: axis.hidden
                        ? TextStyle(color: Theme.of(context).disabledColor)
                        : null,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => _rename(i, v),
                  ),
                  subtitle: InkWell(
                    onTap: () => _editSubcategories(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.account_tree_outlined, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              subs.isEmpty
                                  ? 'No subcategories — tap to add'
                                  : 'Subcategories: ${subs.join(', ')}',
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(axis.hidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        tooltip: axis.hidden
                            ? 'Hidden from chart — tap to show'
                            : 'Shown on chart — tap to hide',
                        onPressed: () => _toggleHidden(i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: canRemove ? 'Remove' : 'Minimum $kMinAxes categories',
                        onPressed: canRemove ? () => _remove(i) : null,
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.drag_handle), // the "3 lines"
                        ),
                      ),
                    ],
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
        label: Text(canAdd ? 'Add category' : 'Max $kMaxAxes'),
      ),
    );
  }
}
