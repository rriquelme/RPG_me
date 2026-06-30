import 'package:flutter/material.dart';

import '../repository.dart';
import '../settings.dart';

/// Settings: API settings (for optional sync).
class SettingsScreen extends StatefulWidget {
  final Repository repo;
  const SettingsScreen({super.key, required this.repo});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _user;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.repo.settings.baseUrl);
    _user = TextEditingController(text: widget.repo.settings.user);
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    super.dispose();
  }

  Future<void> _saveApi() async {
    await Settings.save(_url.text, _user.text);
    final saved = await Settings.load();
    await widget.repo.updateSettings(saved);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('API settings saved.')));
    }
  }

  Future<void> _syncNow() async {
    final repo = widget.repo;
    if (!repo.settings.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add an API URL first, then Save API settings.')));
      return;
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
  }

  Future<void> _setFirstDay(int day) async {
    await Settings.saveFirstDayOfWeek(day);
    await widget.repo.updateSettings(widget.repo.settings.copyWith(firstDayOfWeek: day));
    setState(() {});
  }

  Future<void> _setShowDashboard(bool show) async {
    await Settings.saveShowDashboardOnLog(show);
    await widget.repo
        .updateSettings(widget.repo.settings.copyWith(showDashboardOnLog: show));
    setState(() {});
  }

  Future<void> _setTrackNumber(bool on) async {
    await Settings.saveTrackNumber(on);
    await widget.repo
        .updateSettings(widget.repo.settings.copyWith(trackNumber: on));
    setState(() {});
  }

  Future<void> _setTrackPercentage(bool on) async {
    await Settings.saveTrackPercentage(on);
    await widget.repo
        .updateSettings(widget.repo.settings.copyWith(trackPercentage: on));
    setState(() {});
  }

  Future<void> _setLogButton(bool on) async {
    await Settings.saveBool(Settings.kLogBtnKey, on);
    await widget.repo
        .updateSettings(widget.repo.settings.copyWith(showLogButton: on));
    setState(() {});
  }

  Future<void> _setAddCategoryButton(bool on) async {
    await Settings.saveBool(Settings.kAddCatBtnKey, on);
    await widget.repo
        .updateSettings(widget.repo.settings.copyWith(showAddCategoryButton: on));
    setState(() {});
  }

  Future<void> _setAddSubcategoryButton(bool on) async {
    await Settings.saveBool(Settings.kAddSubBtnKey, on);
    await widget.repo.updateSettings(
        widget.repo.settings.copyWith(showAddSubcategoryButton: on));
    setState(() {});
  }

  Future<void> _setDayNumbers(bool on) async {
    await Settings.saveBool(Settings.kDayNumbersKey, on);
    await widget.repo
        .updateSettings(widget.repo.settings.copyWith(showDayNumbers: on));
    setState(() {});
  }

  Future<void> _setOctagonScale(String scale) async {
    await Settings.saveOctagonScale(scale);
    await widget.repo
        .updateSettings(widget.repo.settings.copyWith(octagonScale: scale));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Week', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              const Expanded(child: Text('First day of the week')),
              DropdownButton<int>(
                value: widget.repo.settings.firstDayOfWeek,
                items: kWeekdayNames.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => v == null ? null : _setFirstDay(v),
              ),
            ],
          ),
          const Text(
            'Used by the “This week” view and the activity heatmap.',
            style: TextStyle(fontSize: 13),
          ),
          const Divider(height: 40),
          Text('Logging', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('View dashboard on log creation'),
            subtitle: const Text(
              'Show a summary of the selected category at the top of the Log '
              'screen.',
            ),
            value: widget.repo.settings.showDashboardOnLog,
            onChanged: _setShowDashboard,
          ),
          const Divider(height: 40),
          Text('Extra metrics', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Track an extra number and/or a percentage per log. Each adds a '
            'field on the Log screen and a metric to the octagon toggle.',
            style: TextStyle(fontSize: 13),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Track number'),
            subtitle: const Text('A free number per log (summed on the octagon).'),
            value: widget.repo.settings.trackNumber,
            onChanged: _setTrackNumber,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Track percentage'),
            subtitle: const Text('A 0–100% per log (averaged on the octagon).'),
            value: widget.repo.settings.trackPercentage,
            onChanged: _setTrackPercentage,
          ),
          const Divider(height: 40),
          Text('Add buttons', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Log button'),
            subtitle: const Text('Show the Log button on the home screen.'),
            value: widget.repo.settings.showLogButton,
            onChanged: _setLogButton,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Add category button'),
            subtitle: const Text(
                'Show it at the bottom of Edit categories (otherwise a + sits '
                'next to Save).'),
            value: widget.repo.settings.showAddCategoryButton,
            onChanged: _setAddCategoryButton,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Add subcategory button'),
            subtitle: const Text(
                'Show it at the bottom of the Subcategories tab (otherwise a + '
                'next to Save).'),
            value: widget.repo.settings.showAddSubcategoryButton,
            onChanged: _setAddSubcategoryButton,
          ),
          const Divider(height: 40),
          Text('Octagon', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'How values map to distance from the centre — for trying out the '
            'chart’s feel.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'linear', label: Text('Linear')),
              ButtonSegment(value: 'log', label: Text('Log')),
              ButtonSegment(value: 'exp', label: Text('Exp')),
            ],
            selected: {widget.repo.settings.octagonScale},
            onSelectionChanged: (s) => _setOctagonScale(s.first),
          ),
          const Divider(height: 40),
          Text('Activity', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show day numbers'),
            subtitle: const Text(
                'Show the day of the month in each activity heatmap cell.'),
            value: widget.repo.settings.showDayNumbers,
            onChanged: _setDayNumbers,
          ),
          const Divider(height: 40),
          Text('API settings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'The app works fully offline. Add an API URL only if you want to '
            'sync this device to a backend.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'API base URL (optional)',
              hintText: 'https://abc123.execute-api.us-east-1.amazonaws.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _user,
            decoration: const InputDecoration(
              labelText: 'Character / user id',
              hintText: 'me',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _syncing ? null : _syncNow,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: const Text('Sync now'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saveApi,
                child: const Text('Save API settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
