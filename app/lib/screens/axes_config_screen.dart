import 'dart:math';

import 'package:flutter/material.dart';

import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';

/// One flat row in the merged list: a category, or a subcategory belonging to
/// the most recent category above it. Used for reordering.
class _FlatItem {
  final AxisDef? category;
  final SubcategoryDef? sub;
  _FlatItem.cat(AxisDef this.category) : sub = null;
  _FlatItem.subcat(SubcategoryDef this.sub) : category = null;
  bool get isCategory => category != null;
}

/// A single screen to administrate every category and its subcategories.
/// Subcategories are indented under their category; each category has a "+" to
/// add a subcategory to it. Anything can be dragged to reorder — a subcategory
/// can move within its category or to another one; a category moves with its
/// subcategories.
class AxesConfigScreen extends StatefulWidget {
  final Repository repo;

  /// Open and immediately prompt to add a subcategory (from the top "+" menu).
  final bool startInSubcategories;
  final String? focusAxisKey; // unused; kept for call-site compatibility

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
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Ensure every subcategory has a stable id (for inline-editable names).
    _axes = [
      for (final a in widget.repo.axesConfig)
        a.copyWith(subcategories: [
          for (final s in a.subcategories)
            s.id.isEmpty ? s.copyWith(id: _genSubId()) : s
        ])
    ];
    if (widget.startInSubcategories) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addSubBottom());
    }
  }

  String _genSubId() =>
      's${_rand.nextInt(1 << 32).toRadixString(16)}${_rand.nextInt(1 << 32).toRadixString(16)}';

  // --- flat row model (categories + indented subcategories) ---------------
  /// Each entry is [categoryIndex, subIndex] with subIndex < 0 for a category.
  List<List<int>> _rows() {
    final rows = <List<int>>[];
    for (var c = 0; c < _axes.length; c++) {
      rows.add([c, -1]);
      for (var s = 0; s < _axes[c].subcategories.length; s++) {
        rows.add([c, s]);
      }
    }
    return rows;
  }

  int _blockLen(List<_FlatItem> flat, int start) {
    var len = 1;
    var j = start + 1;
    while (j < flat.length && !flat[j].isCategory) {
      len++;
      j++;
    }
    return len;
  }

  void _onReorder(int oldIndex, int newIndex) {
    final rows = _rows();
    final flat = <_FlatItem>[
      for (final r in rows)
        r[1] < 0
            ? _FlatItem.cat(_axes[r[0]])
            : _FlatItem.subcat(_axes[r[0]].subcategories[r[1]])
    ];
    final l = flat[oldIndex].isCategory ? _blockLen(flat, oldIndex) : 1;
    final block = flat.sublist(oldIndex, oldIndex + l);
    flat.removeRange(oldIndex, oldIndex + l);
    int insertAt;
    if (newIndex <= oldIndex) {
      insertAt = newIndex;
    } else if (newIndex >= oldIndex + l) {
      insertAt = newIndex - l;
    } else {
      return; // dropped inside its own block — no-op
    }
    flat.insertAll(insertAt.clamp(0, flat.length), block);
    _rebuildFromFlat(flat);
  }

  void _rebuildFromFlat(List<_FlatItem> flat) {
    final newAxes = <AxisDef>[];
    final orphans = <SubcategoryDef>[];
    AxisDef? cur;
    var curSubs = <SubcategoryDef>[];
    for (final f in flat) {
      if (f.isCategory) {
        if (cur != null) newAxes.add(cur.copyWith(subcategories: curSubs));
        cur = f.category;
        curSubs = <SubcategoryDef>[];
      } else if (cur == null) {
        orphans.add(f.sub!);
      } else {
        curSubs.add(f.sub!);
      }
    }
    if (cur != null) newAxes.add(cur.copyWith(subcategories: curSubs));
    if (orphans.isNotEmpty && newAxes.isNotEmpty) {
      newAxes[0] = newAxes[0]
          .copyWith(subcategories: [...orphans, ...newAxes[0].subcategories]);
    }
    // Reject moves that would duplicate a subcategory name within a category.
    for (final a in newAxes) {
      final names = a.subcategoryNames;
      if (names.toSet().length != names.length) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('“${a.label}” already has a subcategory by that name.')));
        return;
      }
    }
    setState(() {
      _axes = newAxes;
      _dirty = true;
    });
  }

  // --- category ops -------------------------------------------------------
  String _newKey() {
    String key;
    do {
      key = 'axis_${_rand.nextInt(1 << 32).toRadixString(16)}';
    } while (_axes.any((a) => a.key == key));
    return key;
  }

  /// Add a category via a popup: name + colour.
  Future<void> _addCategory() async {
    if (_axes.length >= kMaxAxes) return;
    final controller = TextEditingController(text: 'New category');
    var colorHex = kAxisPalette[_axes.length % kAxisPalette.length];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Name'),
                onSubmitted: (_) => Navigator.pop(context, true),
              ),
              const SizedBox(height: 16),
              const Text('Colour'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final hex in kAxisPalette)
                    InkWell(
                      onTap: () => setLocal(() => colorHex = hex),
                      customBorder: const CircleBorder(),
                      child: CircleAvatar(
                        backgroundColor: colorFromHex(hex),
                        radius: 18,
                        child: colorHex == hex
                            ? const Icon(Icons.check, size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _axes.add(AxisDef(_newKey(), name, '', colorHex));
      _dirty = true;
    });
  }

  void _remove(int c) {
    if (_axes.length <= kMinAxes) return;
    setState(() {
      _axes.removeAt(c);
      _dirty = true;
    });
  }

  void _rename(int c, String label) {
    _axes[c] = _axes[c].copyWith(label: label);
    _dirty = true;
  }

  void _toggleHidden(int c) {
    setState(() {
      _axes[c] = _axes[c].copyWith(hidden: !_axes[c].hidden);
      _dirty = true;
    });
  }

  // --- subcategory ops ----------------------------------------------------
  void _setSubs(int c, List<SubcategoryDef> subs) {
    setState(() {
      _axes[c] = _axes[c].copyWith(subcategories: subs);
      _dirty = true;
    });
  }

  /// Add a subcategory directly under [c] (no dialog) — it gets a default name
  /// to rename inline.
  void _addSubTo(int c) {
    final existing = _axes[c].subcategories.map((s) => s.name).toSet();
    var name = 'New subcategory';
    var n = 2;
    while (existing.contains(name)) {
      name = 'New subcategory $n';
      n++;
    }
    final color = kAxisPalette[_axes[c].subcategories.length % kAxisPalette.length];
    _setSubs(c, [
      SubcategoryDef(name, color, false, _genSubId()),
      ..._axes[c].subcategories,
    ]);
  }

  /// Bottom "Add subcategory" button: pick a category, then add to it.
  Future<void> _addSubBottom() async {
    if (_axes.isEmpty) return;
    final c = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Add subcategory to…'),
        children: [
          for (var i = 0; i < _axes.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i),
              child: Row(children: [
                Container(
                    width: 12, height: 12, color: colorFromHex(_axes[i].colorHex)),
                const SizedBox(width: 8),
                Text(_axes[i].label),
              ]),
            ),
        ],
      ),
    );
    if (c != null) await _addSubTo(c);
  }

  /// Inline rename (tap the name) — mirrors category renaming. No setState so
  /// the field keeps focus while typing; the stable id keeps its reorder key.
  void _renameSubInline(int c, int s, String name) {
    final subs = List.of(_axes[c].subcategories)
      ..[s] = _axes[c].subcategories[s].copyWith(name: name);
    _axes[c] = _axes[c].copyWith(subcategories: subs);
    _dirty = true;
  }

  void _removeSub(int c, int s) =>
      _setSubs(c, List.of(_axes[c].subcategories)..removeAt(s));

  void _toggleSubHidden(int c, int s) {
    final cur = _axes[c].subcategories[s];
    final subs = List.of(_axes[c].subcategories)
      ..[s] = cur.copyWith(hidden: !cur.hidden);
    _setSubs(c, subs);
  }

  // --- colours ------------------------------------------------------------
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

  Future<void> _pickColor(int c) async {
    final hex = await _chooseColor();
    if (hex != null) {
      setState(() {
        _axes[c] = _axes[c].copyWith(colorHex: hex);
        _dirty = true;
      });
    }
  }

  Future<void> _pickSubColor(int c, int s) async {
    final hex = await _chooseColor();
    if (hex != null) {
      final subs = List.of(_axes[c].subcategories)
        ..[s] = _axes[c].subcategories[s].copyWith(colorHex: hex);
      _setSubs(c, subs);
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

  Future<void> _confirmExit() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save changes?'),
        content: const Text('You have unsaved changes to your categories.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, 'discard'), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (choice == 'save') {
      await _save();
    } else if (choice == 'discard') {
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  // --- build --------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final s = widget.repo.settings;
    final rows = _rows();
    return PopScope(
      canPop: !_dirty,
      onPopInvoked: (didPop) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          actions: [
            // Only categories get a "+" near Save (subcategories use the per-
            // category + in each row).
            if (!s.showAddCategoryButton)
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add category',
                onPressed: _axes.length < kMaxAxes ? _addCategory : null,
              ),
            TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Tap a colour to change it; drag ☰ to reorder. Use the + on a '
                'category to add a subcategory; drag a subcategory onto another '
                'category to move it. 👁 hides from the charts.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                onReorder: _onReorder,
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final c = rows[i][0], sub = rows[i][1];
                  return sub < 0
                      ? _categoryTile(i, c)
                      : _subcategoryTile(i, c, sub);
                },
              ),
            ),
          ],
        ),
        floatingActionButton: _fab(),
      ),
    );
  }

  Widget _categoryTile(int rowIndex, int c) {
    final axis = _axes[c];
    final canRemove = _axes.length > kMinAxes;
    return ListTile(
      key: ValueKey('c:${axis.key}'),
      leading: GestureDetector(
        onTap: () => _pickColor(c),
        child: CircleAvatar(backgroundColor: colorFromHex(axis.colorHex), radius: 14),
      ),
      title: TextFormField(
        initialValue: axis.label,
        style: axis.hidden ? TextStyle(color: Theme.of(context).disabledColor) : null,
        decoration: const InputDecoration(isDense: true, border: InputBorder.none),
        onChanged: (v) => _rename(c, v),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add),
            tooltip: 'Add subcategory',
            onPressed: () => _addSubTo(c),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(axis.hidden
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            tooltip: axis.hidden ? 'Hidden — tap to show' : 'Shown — tap to hide',
            onPressed: () => _toggleHidden(c),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline),
            tooltip: canRemove ? 'Remove' : 'Minimum $kMinAxes categories',
            onPressed: canRemove ? () => _remove(c) : null,
          ),
          ReorderableDragStartListener(
            index: rowIndex,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.drag_handle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subcategoryTile(int rowIndex, int c, int s) {
    final axis = _axes[c];
    final sub = axis.subcategories[s];
    final swatch = sub.colorHex.isNotEmpty
        ? colorFromHex(sub.colorHex)
        : colorFromHex(axis.colorHex);
    return Padding(
      key: ValueKey('s:${sub.id}'),
      padding: const EdgeInsets.only(left: 32),
      child: ListTile(
        dense: true,
        leading: GestureDetector(
          onTap: () => _pickSubColor(c, s),
          child: CircleAvatar(backgroundColor: swatch, radius: 11),
        ),
        title: TextFormField(
          initialValue: sub.name,
          style: sub.hidden ? TextStyle(color: Theme.of(context).disabledColor) : null,
          decoration: const InputDecoration(isDense: true, border: InputBorder.none),
          onChanged: (v) => _renameSubInline(c, s, v),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(sub.hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              tooltip: sub.hidden ? 'Hidden — tap to show' : 'Shown — tap to hide',
              onPressed: () => _toggleSubHidden(c, s),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: () => _removeSub(c, s),
            ),
            ReorderableDragStartListener(
              index: rowIndex,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_handle, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _fab() {
    final s = widget.repo.settings;
    final list = <Widget>[
      if (s.showAddSubcategoryButton)
        FloatingActionButton.extended(
          heroTag: 'fab_sub',
          onPressed: _addSubBottom,
          icon: const Icon(Icons.add),
          label: const Text('Add subcategory'),
        ),
      if (s.showAddCategoryButton)
        FloatingActionButton.extended(
          heroTag: 'fab_cat',
          onPressed: _axes.length < kMaxAxes ? _addCategory : null,
          icon: const Icon(Icons.add),
          label: Text(_axes.length < kMaxAxes ? 'Add category' : 'Max $kMaxAxes'),
        ),
    ];
    if (list.isEmpty) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          list[i],
        ],
      ],
    );
  }
}
