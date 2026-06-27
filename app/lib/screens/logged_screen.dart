import 'package:flutter/material.dart';

import '../local/event.dart';
import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';
import 'log_screen.dart';

/// A history of every logged task/session — newest first — with the option to
/// delete one.
class LoggedScreen extends StatefulWidget {
  final Repository repo;
  const LoggedScreen({super.key, required this.repo});

  @override
  State<LoggedScreen> createState() => _LoggedScreenState();
}

class _LoggedScreenState extends State<LoggedScreen> {
  late List<Event> _events;

  @override
  void initState() {
    super.initState();
    _events = widget.repo.allEvents();
  }

  AxisDef? _axisOf(String key) {
    for (final a in widget.repo.axesConfig) {
      if (a.key == key) return a;
    }
    return null;
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
      setState(() => _events = widget.repo.allEvents());
    }
  }

  Future<void> _edit(Event e) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LogScreen(repo: widget.repo, existing: e)),
    );
    if (changed == true) setState(() => _events = widget.repo.allEvents());
  }

  String _subtitle(Event e) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = e.timestamp;
    final when = '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
    final cat = _axisOf(e.axisKey)?.label ?? e.axisKey;
    final dur = e.seconds > 0 ? ' · ${formatHms(e.seconds)}' : '';
    return '$when · $cat$dur';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Logged activities (${_events.length})')),
      body: _events.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nothing logged yet.', textAlign: TextAlign.center),
              ),
            )
          : ListView.separated(
              itemCount: _events.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final e = _events[i];
                final axis = _axisOf(e.axisKey);
                return ListTile(
                  onTap: () => _edit(e),
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor:
                        axis != null ? colorFromHex(axis.colorHex) : kDefaultAxisColor,
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
    );
  }
}
