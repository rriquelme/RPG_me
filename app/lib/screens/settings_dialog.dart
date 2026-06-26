import 'package:flutter/material.dart';

import '../settings.dart';

/// Dialog to enter the API base URL (the SAM stack's `ApiUrl`) and user id.
/// Returns the saved [Settings], or null if cancelled.
Future<Settings?> showSettingsDialog(BuildContext context, Settings current) {
  final urlController = TextEditingController(text: current.baseUrl);
  final userController = TextEditingController(text: current.user);

  return showDialog<Settings>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'The app works fully offline. Add an API URL only if you want to '
            'sync this device to a backend.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: urlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'API base URL (optional)',
              hintText: 'https://abc123.execute-api.us-east-1.amazonaws.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: userController,
            decoration: const InputDecoration(
              labelText: 'Character / user id',
              hintText: 'me',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            await Settings.save(urlController.text, userController.text);
            final saved = await Settings.load();
            if (context.mounted) Navigator.pop(context, saved);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
