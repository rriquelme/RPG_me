import 'package:flutter/material.dart';

import '../local/event.dart';
import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';
import 'log_screen.dart';

/// A history of every logged task/session, with sorting (date / category) and
/// filtering (date range, category, subcategory), plus edit and delete.
class LoggedScreen extends StatefulWidget {
  final Repository repo;
  const LoggedScreen({super.key, required this.repo});

  @override
  State<LoggedScreen> createState() => _LoggedScreenState();
}

class _LoggedScreenState extends State<LoggedScreen> {
  String _sort = 'newest'; // newest | oldest | category
  String? _filterAxis; // null = all categories
  String? _filterSub; // null = all subcategories
  DateTime? _from; // inclusive day
  DateTime? _to; // inclusive day

  AxisDef? _axisOf(String key) {
    for (final a in widget.repo.axesConfig) {
      if (a.key == key) return a;
    }
    return null;
  }

  List<Event> _visible() {
    var list = widget.repo.allEvents();
    if (_filterAxis != null) {
      list = list.where((e) => e.axisKey == _filterAxis).toList();
    }
    if (_filterSub != null) {
      list = list.where((e) => e.subcategory == _filterSub).toList();
    }
    if (_from != null) {
      list = list.where((e) => !e.timestamp.isBefore(_from!)).toList();
    }
    if (_to != null) {
      final endExcl = _to!.add(const Duration(days: 1));
      list = list.where((e) => e.timestamp.isBefore(endExcl)).toList();
    }
    switch (_sort) {
      case 'oldest':
        list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        break;
      case 'category':
        list.sort((a, b) {
          final ca = (_axisOf(a.axisKey)?.label ?? a.axisKey).toLowerCase();
          final cb = (_axisOf(b.axisKey)?.label ?? b.axisKey).toLowerCase();
          final c = ca.compareTo(cb);
          return c != 0 ? c : b.timestamp.compareTo(a.timestamp);
        });
        break;
      case 'newest':
      default:
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    return list;
  }

  Future<void> _delete(Event e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text('${e.name} · ${_subtitle(e)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await widget.repo.deleteEvent(e.id);
      setState(() {});
    }
  }

  Future<void> _edit(Event e) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LogScreen(repo: widget.repo, existing: e)),
    );
    if (changed == true) setState(() {});
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: (_from != null && _to != null)
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
        _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
      });
    }
  }

  String _dateLabel() {
    if (_from == null || _to == null) return 'Any date';
    String f(DateTime d) => '${d.day}/${d.month}/${d.year % 100}';
    return _from == _to ? f(_from!) : '${f(_from!)} – ${f(_to!)}';
  }

  String _subtitle(Event e) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = e.timestamp;
    final when = '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
    final cat = _axisOf(e.axisKey)?.label ?? e.axisKey;
    final sub = e.subcategory.isNotEmpty ? ' › ${e.subcategory}' : '';
    final dur = e.seconds > 0 ? ' · ${formatHms(e.seconds)}' : '';
    return '$when · $cat$sub$dur';
  }

  @override
  Widget build(BuildContext context) {
    final events = _visible();
    final axis = _filterAxis == null ? null : _axisOf(_filterAxis);
    final dateActive = _from != null && _to != null;
    return Scaffold(
      appBar: AppBar(title: Text('Logged activities (${events.length})')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _sort,
                  items: const [
                    DropdownMenuItem(value: 'newest', child: Text('Newest first')),
                    DropdownMenuItem(value: 'oldest', child: Text('Oldest first')),
                    DropdownMenuItem(value: 'category', child: Text('By category')),
                  ],
                  onChanged: (v) => setState(() => _sort = v ?? _sort),
                ),
                DropdownButton<String?>(
                  value: _filterAxis,
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('All categories')),
                    ...widget.repo.axesConfig.map((a) => DropdownMenuItem<String?>(
                          value: a.key,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 12, height: 12, color: colorFromHex(a.colorHex)),
                            const SizedBox(width: 8),
                            Text(a.label),
                          ]),
                        )),
                  ],
                  onChanged: (v) => setState(() {
                    _filterAxis = v;
                    _filterSub = null; // subcategories are per-category
                  }),
                ),
                if (axis != null && axis.subcategories.isNotEmpty)
                  DropdownButton<String?>(
                    value: _filterSub,
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('All subcategories')),
                      ...axis.subcategories.map((s) => DropdownMenuItem<String?>(
                            value: s.name,
                            child: Text(s.name),
                          )),
                    ],
                    onChanged: (v) => setState(() => _filterSub = v),
                  ),
                InputChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text(_dateLabel()),
                  selected: dateActive,
                  onPressed: _pickDateRange,
                  onDeleted: dateActive
                      ? () => setState(() {
                            _from = null;
                            _to = null;
                          })
                      : null,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: events.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No entries match these filters.',
                          textAlign: TextAlign.center),
                    ),
                  )
                : ListView.separated(
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = events[i];
                      final a = _axisOf(e.axisKey);
                      return ListTile(
                        onTap: () => _edit(e),
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: a != null
                              ? colorFromHex(a.colorHex)
                              : kDefaultAxisColor,
                        ),
                        title: Text(e.name),
                        subtitle: Text(_subtitle(e)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit',
                              onPressed: () => _edit(e),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete',
                              onPressed: () => _delete(e),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
