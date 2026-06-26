import 'package:flutter/material.dart';

import '../models.dart';
import '../repository.dart';
import '../settings.dart';
import '../widgets/octagon_chart.dart';
import 'log_screen.dart';
import 'settings_dialog.dart';
import 'time_screen.dart';
import 'timer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Repository? _repo;
  Future<Summary>? _summaryFuture;
  bool _syncing = false;

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
    if (_repo != null) {
      setState(() => _summaryFuture = _repo!.summary());
    }
  }

  Future<void> _openSettings() async {
    if (_repo == null) return;
    final updated = await showSettingsDialog(context, _repo!.settings);
    if (updated != null) {
      await _repo!.updateSettings(updated);
      setState(() {});
    }
  }

  Future<void> _openLog() async {
    if (_repo == null) return;
    final logged = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LogScreen(repo: _repo!)),
    );
    if (logged == true) _refresh();
  }

  Future<void> _openTimer() async {
    if (_repo == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TimerScreen(repo: _repo!)),
    );
    if (saved == true) _refresh();
  }

  void _openTime() {
    if (_repo == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TimeScreen(repo: _repo!)),
    );
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
        ? (result.pushed == 0
            ? 'Already up to date.'
            : 'Synced ${result.pushed} event(s).')
        : 'Sync failed: ${result.error}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    _refresh();
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
                  tooltip: 'Timer',
                  onPressed: _openTimer,
                ),
                IconButton(
                  icon: const Icon(Icons.bar_chart),
                  tooltip: 'Time tracked',
                  onPressed: _openTime,
                ),
                _SyncButton(
                  syncing: _syncing,
                  unsynced: unsynced,
                  onPressed: _sync,
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
                  onPressed: _openSettings,
                ),
              ],
      ),
      floatingActionButton: repo == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _openLog,
              icon: const Icon(Icons.add),
              label: const Text('Log'),
            ),
      body: repo == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!repo.settings.isConfigured)
                  _OfflineBanner(unsynced: unsynced),
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
        if (snap.hasError) {
          return Center(child: Text(snap.error.toString()));
        }
        final summary = snap.data!;
        final weekly = summary.countsLast7Days.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${summary.user} · ${summary.totalEvents} events logged',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            OctagonChart(stats: summary.octagon),
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

/// Sync icon with an unsynced-count badge.
class _SyncButton extends StatelessWidget {
  final bool syncing;
  final int unsynced;
  final VoidCallback onPressed;
  const _SyncButton({
    required this.syncing,
    required this.unsynced,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final icon = syncing
        ? const SizedBox(
            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.sync);
    return IconButton(
      tooltip: unsynced > 0 ? 'Sync ($unsynced pending)' : 'Sync',
      onPressed: syncing ? null : onPressed,
      icon: unsynced > 0
          ? Badge(label: Text('$unsynced'), child: icon)
          : icon,
    );
  }
}

/// Shown when no backend is configured — the app is running purely offline.
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
