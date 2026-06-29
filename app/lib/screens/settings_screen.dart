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
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saveApi,
              child: const Text('Save API settings'),
            ),
          ),
        ],
      ),
    );
  }
}
