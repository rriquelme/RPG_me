import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';
import '../settings.dart';
import '../widgets/octagon_chart.dart';
import 'axes_config_screen.dart';
import 'heatmap_screen.dart';
import 'log_screen.dart';
import 'logged_screen.dart';
import 'settings_screen.dart';
import 'time_screen.dart';
import 'timers_screen.dart';

enum OctagonMetric { hours, frequency, levels }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Repository? _repo;
  Summary? _summary;
  OctagonView? _octView;
  bool _syncing = false;
  OctagonMetric _metric = OctagonMetric.frequency; // frequency is the primary view

  // Custom time window (both null = use the period dropdown). Inclusive day
  // midnights; a single day has start == end.
  DateTime? _customStart;
  DateTime? _customEnd;
  bool get _customActive => _customStart != null && _customEnd != null;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final repo = await Repository.create();
    _repo = repo;
    _reload();
  }

  Future<void> _reload() async {
    final repo = _repo;
    if (repo == null) return;
    final summary = await repo.summary();
    final OctagonView view;
    if (_customActive) {
      view = repo.octagonView(_customStart,
          until: _customEnd!.add(const Duration(days: 1)));
    } else {
      final since = OctagonPeriod.since(repo.settings.period,
          firstDayOfWeek: repo.settings.firstDayOfWeek);
      view = repo.octagonView(since);
    }
    if (mounted) {
      setState(() {
        _summary = summary;
        _octView = view;
      });
    }
  }

  Future<void> _pickCustom() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Custom time'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'day'),
              child: const Text('A single day')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'range'),
              child: const Text('A range of days')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime d0(DateTime d) => DateTime(d.year, d.month, d.day);
    if (choice == 'day') {
      final d = await showDatePicker(
        context: context,
        initialDate: _customStart ?? today,
        firstDate: DateTime(2020),
        lastDate: today,
      );
      if (d == null) return;
      setState(() {
        _customStart = d0(d);
        _customEnd = d0(d);
      });
    } else {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: today,
        initialDateRange: _customActive
            ? DateTimeRange(start: _customStart!, end: _customEnd!)
            : null,
      );
      if (r == null) return;
      setState(() {
        _customStart = d0(r.start);
        _customEnd = d0(r.end);
      });
    }
    _reload();
  }

  /// Shift the custom window by its own length (‹ previous / › next).
  void _shiftCustom(int dir) {
    if (!_customActive) return;
    final span = _customEnd!.difference(_customStart!).inDays + 1;
    setState(() {
      _customStart = _customStart!.add(Duration(days: dir * span));
      _customEnd = _customEnd!.add(Duration(days: dir * span));
    });
    _reload();
  }

  void _clearCustom() {
    setState(() {
      _customStart = null;
      _customEnd = null;
    });
    _reload();
  }

  Future<void> _openSettings() async {
    if (_repo == null) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SettingsScreen(repo: _repo!)));
    _reload();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _reload();
  }

  Future<void> _setPeriod(String period) async {
    final repo = _repo!;
    // Choosing a preset period leaves custom mode.
    _customStart = null;
    _customEnd = null;
    await repo.updateSettings(repo.settings.copyWith(period: period));
    await Settings.saveView(period, repo.settings.averagePerDay);
    _reload();
  }

  Future<void> _setAverage(bool avg) async {
    final repo = _repo!;
    await repo.updateSettings(repo.settings.copyWith(averagePerDay: avg));
    await Settings.saveView(repo.settings.period, avg);
    _reload();
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
    _reload();
  }

  Future<void> _exportLogs() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final file = await repo.exportFile();
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/markdown')],
          subject: 'RPG_me logs', text: 'My RPG_me logs (Markdown).');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importLogs() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = res?.files.single.path;
      if (path == null) return;
      final content = await File(path).readAsString();
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import logs?'),
          content: const Text(
              'This replaces all current data on this device with the contents '
              'of the selected Markdown file. This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
          ],
        ),
      );
      if (ok != true) return;
      await repo.importMarkdown(content);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Logs imported.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  void _onMenu(String value) {
    final repo = _repo;
    if (repo == null) return;
    switch (value) {
      case 'logged':
        _push(LoggedScreen(repo: repo));
        break;
      case 'time':
        _push(TimeScreen(repo: repo));
        break;
      case 'categories':
        _push(AxesConfigScreen(repo: repo));
        break;
      case 'export':
        _exportLogs();
        break;
      case 'import':
        _importLogs();
        break;
      case 'settings':
        _openSettings();
        break;
    }
  }

  double _rawValue(OctagonView v, String key) {
    switch (_metric) {
      case OctagonMetric.hours:
        return (v.seconds[key] ?? 0) / 3600.0;
      case OctagonMetric.frequency:
        return (v.counts[key] ?? 0).toDouble();
      case OctagonMetric.levels:
        return levelForExp(v.exp[key] ?? 0).toDouble();
    }
  }

  List<RadarPoint> _points(OctagonView v, bool average) {
    return v.axes.where((a) => !a.hidden).map((a) {
      var value = _rawValue(v, a.key);
      if (average && v.days > 0) value = value / v.days;
      return RadarPoint(
        axisKey: a.key,
        label: a.label,
        color: colorFromHex(a.colorHex),
        value: value,
      );
    }).toList();
  }

  Future<void> _logForCategory(String axisKey) async {
    final repo = _repo;
    if (repo == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LogScreen(repo: repo, initialAxisKey: axisKey)),
    );
    // Always reload — the Log screen can also toggle a category's hidden flag.
    _reload();
  }

  String _formatValue(double v, bool average) {
    final suffix = average ? '/d' : '';
    switch (_metric) {
      case OctagonMetric.levels:
        return average ? v.toStringAsFixed(2) : 'L${v.toInt()}';
      case OctagonMetric.frequency:
        return average ? '${v.toStringAsFixed(1)}$suffix' : '${v.toInt()}×';
      case OctagonMetric.hours:
        if (v >= 1) return '${v.toStringAsFixed(v < 10 ? 1 : 0)}h$suffix';
        return '${(v * 60).round()}m$suffix';
    }
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
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => TimersScreen(repo: repo)));
                    _reload();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_month),
                  tooltip: 'Activity heatmap',
                  onPressed: () => _push(HeatmapScreen(repo: repo)),
                ),
                _SyncButton(syncing: _syncing, unsynced: unsynced, onPressed: _sync),
                PopupMenuButton<String>(
                  onSelected: _onMenu,
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'logged', child: Text('Logged activities')),
                    PopupMenuItem(value: 'time', child: Text('Time tracked')),
                    PopupMenuItem(value: 'categories', child: Text('Edit categories')),
                    PopupMenuItem(value: 'export', child: Text('Export logs (.md)')),
                    PopupMenuItem(value: 'import', child: Text('Import logs (.md)')),
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
                Expanded(child: _buildBody(repo)),
              ],
            ),
    );
  }

  Widget _buildBody(Repository repo) {
    final summary = _summary;
    final octView = _octView;
    if (summary == null || octView == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final average = repo.settings.averagePerDay;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${summary.user} · ${summary.totalEvents} events logged',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Center(
          child: SegmentedButton<OctagonMetric>(
            showSelectedIcon: false, // keep segment widths fixed (no resize on toggle)
            segments: const [
              ButtonSegment(value: OctagonMetric.frequency, label: Text('Frequency')),
              ButtonSegment(value: OctagonMetric.hours, label: Text('Hours')),
            ],
            selected: {_metric},
            onSelectionChanged: (s) => setState(() => _metric = s.first),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            DropdownButton<String>(
              value: repo.settings.period,
              // The preset period is ignored while a custom window is active.
              style: _customActive
                  ? TextStyle(color: Theme.of(context).disabledColor)
                  : null,
              items: OctagonPeriod.all
                  .map((p) => DropdownMenuItem(value: p.key, child: Text(p.label)))
                  .toList(),
              onChanged: (v) => v == null ? null : _setPeriod(v),
            ),
            FilterChip(
              label: const Text('Avg / day'),
              selected: average,
              onSelected: _setAverage,
            ),
            FilterChip(
              avatar: Icon(Icons.date_range,
                  size: 18,
                  color: _customActive
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : null),
              label: const Text('Custom'),
              selected: _customActive,
              onSelected: (_) => _pickCustom(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OctagonChart(
          points: _points(octView, average),
          formatValue: (v) => _formatValue(v, average),
          onTapAxis: _logForCategory,
        ),
        const SizedBox(height: 16),
        if (_customActive) _customNav(context),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => _push(LoggedScreen(repo: repo)),
            icon: const Icon(Icons.list_alt),
            label: const Text('View logs'),
          ),
        ),
      ],
    );
  }

  /// The ‹ label › navigation row shown under the chart in custom mode.
  Widget _customNav(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final canForward = _customEnd!.isBefore(today);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous',
          onPressed: () => _shiftCustom(-1),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_customLabel(), style: Theme.of(context).textTheme.titleSmall),
            InkWell(
              onTap: _clearCustom,
              child: Text('Clear',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next',
          onPressed: canForward ? () => _shiftCustom(1) : null,
        ),
      ],
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _fmtDay(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  String _customLabel() {
    final s = _customStart!, e = _customEnd!;
    if (s == e) return _fmtDay(s);
    return '${_fmtDay(s)} – ${_fmtDay(e)}';
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
