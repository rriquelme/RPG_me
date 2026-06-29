import 'package:flutter/material.dart';

import '../local/local_engine.dart';
import '../models.dart';
import '../repository.dart';

/// Sentinel value for the "Create new…" item in a subcategory dropdown.
const String kCreateSubcategory = '__create_subcategory__';

/// Shows the "create subcategory" dialog (name + optional colour), persists it
/// on [axis] via [repo], and returns the new subcategory name — or null if the
/// dialog was cancelled or the name was blank. Duplicate names are not
/// re-added but are still returned (so the caller can just select them).
Future<String?> showCreateSubcategoryDialog({
  required BuildContext context,
  required Repository repo,
  required AxisDef axis,
}) async {
  final nameController = TextEditingController();
  var colorHex = ''; // empty = inherit the category colour
  final created = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text('New subcategory · ${axis.label}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Name'),
              onSubmitted: (_) => Navigator.pop(context, true),
            ),
            const SizedBox(height: 16),
            const Text('Colour (optional)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ColorDot(
                  color: colorFromHex(axis.colorHex),
                  selected: colorHex.isEmpty,
                  icon: Icons.format_color_reset,
                  onTap: () => setLocal(() => colorHex = ''),
                ),
                ...kAxisPalette.map((hex) => _ColorDot(
                      color: colorFromHex(hex),
                      selected: colorHex == hex,
                      onTap: () => setLocal(() => colorHex = hex),
                    )),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create')),
        ],
      ),
    ),
  );
  if (created != true) return null;
  final name = nameController.text.trim();
  if (name.isEmpty) return null;
  if (axis.subcategoryByName(name) == null) {
    await repo.addSubcategory(axis.key, SubcategoryDef(name, colorHex));
  }
  return name;
}

/// A selectable colour swatch used by the "create subcategory" dialog.
class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: CircleAvatar(
        backgroundColor: color,
        radius: 18,
        child: selected
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : (icon != null
                ? Icon(icon, size: 18, color: Colors.white)
                : null),
      ),
    );
  }
}
