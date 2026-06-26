import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
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
  Settings? _settings;
  ApiClient? _api;
  Future<Summary>? _summaryFuture;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final settings = await Settings.load();
    setState(() => _settings = settings);
    if (settings.isConfigured) {
      _rebuildApi(settings);
    } else if (mounted) {
      // First launch: ask for the backend URL.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSettings());
    }
  }

  void _rebuildApi(Settings settings) {
    _api?.close();
    _api = ApiClient(baseUrl: settings.baseUrl, user: settings.user);
    setState(() => _summaryFuture = _api!.summary());
  }

  Future<void> _refresh() async {
    if (_api != null) {
      setState(() => _summaryFuture = _api!.summary());
      await _summaryFuture;
    }
  }

  Future<void> _openSettings() async {
    final updated = await showSettingsDialog(context, _settings ?? const Settings(baseUrl: '', user: 'me'));
    if (updated != null) {
      setState(() => _settings = updated);
      if (updated.isConfigured) _rebuildApi(updated);
    }
  }

  Future<void> _openLog() async {
    if (_api == null) return;
    final logged = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LogScreen(api: _api!)),
    );
    if (logged == true) _refresh();
  }

  Future<void> _openTimer() async {
    if (_api == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TimerScreen(api: _api!)),
    );
    if (saved == true) _refresh();
  }

  void _openTime() {
    if (_api == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TimeScreen(api: _api!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RPG_me'),
        actions: [
          if (_api != null) ...[
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
          ],
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: _api == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _openLog,
              icon: const Icon(Icons.add),
              label: const Text('Log'),
            ),
      body: _settings == null
          ? const Center(child: CircularProgressIndicator())
          : !(_settings!.isConfigured)
              ? _NotConfigured(onConfigure: _openSettings)
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: _buildBody(),
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
          return _ErrorView(error: snap.error.toString(), onRetry: _refresh);
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

class _NotConfigured extends StatelessWidget {
  final VoidCallback onConfigure;
  const _NotConfigured({required this.onConfigure});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Connect the app to your RPG_me backend to get started.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onConfigure, child: const Text('Configure')),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline, size: 48),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(error, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 16),
        Center(child: FilledButton(onPressed: onRetry, child: const Text('Retry'))),
      ],
    );
  }
}
