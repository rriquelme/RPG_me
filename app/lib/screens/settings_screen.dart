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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
