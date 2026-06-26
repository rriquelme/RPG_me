import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../repository.dart';
import '../widgets/octagon_chart.dart';
import 'axes_config_screen.dart';
import 'heatmap_screen.dart';
import 'log_screen.dart';
import 'settings_dialog.dart';
import 'time_screen.dart';
import 'timers_screen.dart';

enum OctagonMetric { hours, levels }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Repository? _repo;
  Future<Summary>? _summaryFuture;
  bool _syncing = false;
  OctagonMetric _metric = OctagonMetric.hours;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final repo = await Repository.create();
    setState(() {
      _repo = repo;
      _summaryFuture = repo.summary();
    });
  }

  void _refresh() {
    if (_repo != null) setState(() => _summaryFuture = _repo!.summary());
  }

  Future<void> _openSettings() async {
    if (_repo == null) return;
    final updated = await showSettingsDialog(context, _repo!.settings);
    if (updated != null) {
      await _repo!.updateSettings(updated);
      setState(() {});
    }
  }

  Future<void> _push(Widget screen) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (changed == true) _refresh();
  }

  Future<void> _sync() async {
    final repo = _repo;
    if (repo == null) return;
    if (!repo.settings.isConfigured) {
      await _openSettings();
      if (!repo.settings.isConfigured) return;
    }
    setState(() => _syncing = true);
    final result = await repo.sync();
    if (!mounted) return;
    setState(() => _syncing = false);
    final msg = result.ok
        ? (result.pushed == 0 ? 'Already up to date.' : 'Synced ${result.pushed} event(s).')
        : 'Sync failed: ${result.error}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    _refresh();
  }

  Future<void> _export() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final csv = repo.exportCsv();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/rpg_me_export.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')],
          subject: 'RPG_me export', text: 'My RPG_me activity log (CSV / Excel).');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  void _onMenu(String value) {
    final repo = _repo;
    if (repo == null) return;
    switch (value) {
      case 'time':
        _push(TimeScreen(repo: repo));
        break;
      case 'heatmap':
        _push(HeatmapScreen(repo: repo));
        break;
      case 'axes':
        _push(AxesConfigScreen(repo: repo));
        break;
      case 'export':
        _export();
        break;
      case 'settings':
        _openSettings();
        break;
    }
  }

  List<RadarPoint> _points(Summary s) {
    return s.octagon.map((a) {
      final value = _metric == OctagonMetric.hours
          ? (s.secondsByAxis[a.key] ?? 0) / 3600.0
          : a.level.toDouble();
      return RadarPoint(label: a.label, color: a.color, value: value);
    }).toList();
  }

  String _formatValue(double v) {
    if (_metric == OctagonMetric.levels) return 'L${v.toInt()}';
    if (v >= 1) return '${v.toStringAsFixed(v < 10 ? 1 : 0)}h';
    return '${(v * 60).round()}m';
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;
    final unsynced = repo?.unsyncedCount ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('RPG_me'),
        actions: repo == null
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.timer_outlined),
                  tooltip: 'Timers',
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TimersScreen(repo: repo)),
                    );
                    _refresh(); // a saved timer logs time
                  },
                ),
                _SyncButton(syncing: _syncing, unsynced: unsynced, onPressed: _sync),
                PopupMenuButton<String>(
                  onSelected: _onMenu,
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'heatmap', child: Text('Activity heatmap')),
                    PopupMenuItem(value: 'time', child: Text('Time tracked')),
                    PopupMenuItem(value: 'axes', child: Text('Edit axes')),
                    PopupMenuItem(value: 'export', child: Text('Export CSV (Excel)')),
                    PopupMenuItem(value: 'settings', child: Text('Settings')),
                  ],
                ),
              ],
      ),
      floatingActionButton: repo == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _push(LogScreen(repo: repo)),
              icon: const Icon(Icons.add),
              label: const Text('Log'),
            ),
      body: repo == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!repo.settings.isConfigured) _OfflineBanner(unsynced: unsynced),
                Expanded(child: _buildBody()),
              ],
            ),
    );
  }

  Widget _buildBody() {
    return FutureBuilder<Summary>(
      future: _summaryFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return Center(child: Text(snap.error.toString()));
        final summary = snap.data!;
        final weekly = summary.countsLast7Days.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${summary.user} · ${summary.totalEvents} events logged',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Center(
              child: SegmentedButton<OctagonMetric>(
                segments: const [
                  ButtonSegment(value: OctagonMetric.hours, label: Text('Hours')),
                  ButtonSegment(value: OctagonMetric.levels, label: Text('Levels')),
                ],
                selected: {_metric},
                onSelectionChanged: (s) => setState(() => _metric = s.first),
              ),
            ),
            const SizedBox(height: 8),
            OctagonChart(points: _points(summary), formatValue: _formatValue),
            const SizedBox(height: 24),
            Text('This week', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (weekly.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing logged in the last 7 days. Tap “Log”.'),
              )
            else
              ...weekly.map((e) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.repeat),
                    title: Text(e.key),
                    trailing: Text('×${e.value}',
                        style: Theme.of(context).textTheme.titleMedium),
                  )),
          ],
        );
      },
    );
  }
}

class _SyncButton extends StatelessWidget {
  final bool syncing;
  final int unsynced;
  final VoidCallback onPressed;
  const _SyncButton({required this.syncing, required this.unsynced, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final icon = syncing
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.sync);
    return IconButton(
      tooltip: unsynced > 0 ? 'Sync ($unsynced pending)' : 'Sync',
      onPressed: syncing ? null : onPressed,
      icon: unsynced > 0 ? Badge(label: Text('$unsynced'), child: icon) : icon,
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final int unsynced;
  const _OfflineBanner({required this.unsynced});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              unsynced > 0
                  ? 'Offline · $unsynced event(s) saved on this device'
                  : 'Offline · data saved on this device. Add an API URL to sync.',
              style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
