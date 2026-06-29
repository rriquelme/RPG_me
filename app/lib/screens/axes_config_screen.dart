import 'dart:math';

import 'package:flutter/material.dart';

import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';

enum _EditMode { categories, subcategories }

/// Edit the octagon's axes and their subcategories. A toggle at the top switches
/// between editing the categories (rename, recolour, hide, add/remove, reorder)
/// and editing one category's subcategories (rename, recolour, add/remove,
/// reorder). Saved together.
class AxesConfigScreen extends StatefulWidget {
  final Repository repo;

  /// Open straight into the Subcategories tab.
  final bool startInSubcategories;

  /// When [startInSubcategories], focus this category's subcategories.
  final String? focusAxisKey;

  const AxesConfigScreen({
    super.key,
    required this.repo,
    this.startInSubcategories = false,
    this.focusAxisKey,
  });

  @override
  State<AxesConfigScreen> createState() => _AxesConfigScreenState();
}

class _AxesConfigScreenState extends State<AxesConfigScreen> {
  late List<AxisDef> _axes;
  final _rand = Random();
  bool _saving = false;
  String? _error;

  _EditMode _mode = _EditMode.categories;
  int _subAxisIndex = 0; // which category's subcategories we're editing
  bool _dirty = false; // unsaved edits → prompt on back

  @override
  void initState() {
    super.initState();
    _axes = List.of(widget.repo.axesConfig);
    if (widget.startInSubcategories) _mode = _EditMode.subcategories;
    final fk = widget.focusAxisKey;
    if (fk != null) {
      final idx = _axes.indexWhere((a) => a.key == fk);
      if (idx >= 0) _subAxisIndex = idx;
    }
  }

  // --- category ops -------------------------------------------------------
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
    setState(() {
      _axes.add(AxisDef(_newKey(), 'New category', '', color));
      _dirty = true;
    });
  }

  void _remove(int i) {
    if (_axes.length <= kMinAxes) return;
    setState(() {
      _axes.removeAt(i);
      if (_subAxisIndex >= _axes.length) _subAxisIndex = _axes.length - 1;
      _dirty = true;
    });
  }

  void _rename(int i, String label) {
    _axes[i] = _axes[i].copyWith(label: label);
    _dirty = true;
  }

  void _toggleHidden(int i) {
    setState(() {
      _axes[i] = _axes[i].copyWith(hidden: !_axes[i].hidden);
      _dirty = true;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = _axes.removeAt(oldIndex);
      _axes.insert(newIndex, moved);
      _dirty = true;
    });
  }

  // --- subcategory ops ----------------------------------------------------
  List<SubcategoryDef> get _subs => _axes[_subAxisIndex].subcategories;

  void _setSubs(List<SubcategoryDef> subs) {
    setState(() {
      _axes[_subAxisIndex] =
          _axes[_subAxisIndex].copyWith(subcategories: subs);
      _dirty = true;
    });
  }

  Future<void> _addSub() async {
    final name = await _promptName(title: 'Add subcategory');
    if (name == null) return;
    if (_subs.any((s) => s.name == name)) return;
    final color = kAxisPalette[_subs.length % kAxisPalette.length];
    _setSubs([..._subs, SubcategoryDef(name, color)]);
  }

  Future<void> _renameSub(int j) async {
    final name = await _promptName(title: 'Rename subcategory', initial: _subs[j].name);
    if (name == null) return;
    if (name != _subs[j].name && _subs.any((s) => s.name == name)) return;
    final next = List.of(_subs)..[j] = _subs[j].copyWith(name: name);
    _setSubs(next);
  }

  void _removeSub(int j) => _setSubs(List.of(_subs)..removeAt(j));

  void _toggleSubHidden(int j) =>
      _setSubs(List.of(_subs)..[j] = _subs[j].copyWith(hidden: !_subs[j].hidden));

  void _reorderSub(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final next = List.of(_subs);
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    _setSubs(next);
  }

  Future<String?> _promptName({required String title, String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((v) => (v == null || v.isEmpty) ? null : v);
  }

  // --- colours ------------------------------------------------------------
  /// Returns a hex string, '' for "default" (no custom colour), or null if the
  /// dialog was dismissed.
  Future<String?> _chooseColor() async {
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
    if (chosen == null) return null;
    return chosen == none ? '' : chosen;
  }

  Future<void> _pickColor(int i) async {
    final hex = await _chooseColor();
    if (hex != null) {
      setState(() {
        _axes[i] = _axes[i].copyWith(colorHex: hex);
        _dirty = true;
      });
    }
  }

  Future<void> _pickSubColor(int j) async {
    final hex = await _chooseColor();
    if (hex != null) {
      _setSubs(List.of(_subs)..[j] = _subs[j].copyWith(colorHex: hex));
    }
  }

  // --- save / discard -----------------------------------------------------
  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.saveAxes(_axes);
      _dirty = false;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e is ArgumentError ? e.message.toString() : e.toString();
        _saving = false;
      });
    }
  }

  /// On back with unsaved edits, offer Save / Discard / Cancel.
  Future<void> _confirmExit() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save changes?'),
        content: const Text('You have unsaved changes to your categories.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel')),
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
      await _save();
    } else if (choice == 'discard') {
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subMode = _mode == _EditMode.subcategories;
    return PopScope(
      canPop: !_dirty,
      onPopInvoked: (didPop) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Edit categories'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<_EditMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _EditMode.categories, label: Text('Categories')),
                ButtonSegment(value: _EditMode.subcategories, label: Text('Subcategories')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(child: subMode ? _buildSubcategories() : _buildCategories()),
        ],
      ),
      floatingActionButton: subMode
          ? FloatingActionButton.extended(
              onPressed: _addSub,
              icon: const Icon(Icons.add),
              label: const Text('Add subcategory'),
            )
          : FloatingActionButton.extended(
              onPressed: _axes.length < kMaxAxes ? _add : null,
              icon: const Icon(Icons.add),
              label: Text(_axes.length < kMaxAxes ? 'Add category' : 'Max $kMaxAxes'),
            ),
      ),
    );
  }

  // --- categories list ----------------------------------------------------
  Widget _buildCategories() {
    final canRemove = _axes.length > kMinAxes;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '${_axes.length} categories (allowed: $kMinAxes–$kMaxAxes). '
            'Tap a colour to change it; drag ☰ to reorder; tap 👁 to hide from '
            'the chart (still loggable); tap the subcategories line to edit them.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
                  onTap: () => setState(() {
                    _mode = _EditMode.subcategories;
                    _subAxisIndex = i;
                  }),
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
                                : 'Subcategories: ${axis.subcategoryNames.join(', ')}',
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 16),
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
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- subcategories list -------------------------------------------------
  Widget _buildSubcategories() {
    final axis = _axes[_subAxisIndex];
    final subs = axis.subcategories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Text('Category'),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _subAxisIndex,
                  items: [
                    for (var i = 0; i < _axes.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                              width: 12, height: 12, color: colorFromHex(_axes[i].colorHex)),
                          const SizedBox(width: 8),
                          Text(_axes[i].label),
                        ]),
                      ),
                  ],
                  onChanged: (v) => v == null ? null : setState(() => _subAxisIndex = v),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            subs.isEmpty
                ? 'No subcategories yet — they are optional. Tap “Add subcategory”.'
                : 'Tap a colour to change it; drag ☰ to reorder. A blank colour '
                    'uses the category colour.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            onReorder: _reorderSub,
            itemCount: subs.length,
            itemBuilder: (context, j) {
              final sub = subs[j];
              final swatch = sub.colorHex.isNotEmpty
                  ? colorFromHex(sub.colorHex)
                  : colorFromHex(axis.colorHex);
              return ListTile(
                key: ValueKey('sub:${sub.name}'),
                leading: GestureDetector(
                  onTap: () => _pickSubColor(j),
                  child: CircleAvatar(backgroundColor: swatch, radius: 14),
                ),
                title: Text(
                  sub.name,
                  style: sub.hidden
                      ? TextStyle(color: Theme.of(context).disabledColor)
                      : null,
                ),
                subtitle: sub.colorHex.isEmpty
                    ? Text('Uses ${axis.label} colour',
                        style: Theme.of(context).textTheme.bodySmall)
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(sub.hidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      tooltip: sub.hidden
                          ? 'Hidden from charts — tap to show'
                          : 'Shown on charts — tap to hide',
                      onPressed: () => _toggleSubHidden(j),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Rename',
                      onPressed: () => _renameSub(j),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () => _removeSub(j),
                    ),
                    ReorderableDragStartListener(
                      index: j,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
