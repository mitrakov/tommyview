import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:tommyview/settings.dart";

Future showSettings(BuildContext context) => showDialog(context: context, builder: (_) => _SettingsDialog());

class _SettingsDialog extends StatefulWidget {
  @override
  _SettingsDialogState createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  final ctrl = TextEditingController(text: Settings.local.selectionFrom.toString());
  int quality = Settings.local.quality;

  void _ok() {
    Settings.local.setQuality(quality);
    Settings.local.setSelectionFrom(int.tryParse(ctrl.text) ?? 0);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
          _ok();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        title: const Row(mainAxisAlignment: .center, children: [Text("Settings", style: TextStyle(fontSize: 20, fontWeight: .bold))]),
        content: Column(
          mainAxisSize: .min,
          children: [
            Row(children: [
              const Text("Save quality:"),
              Slider(value: quality.toDouble(), min: 1, max: 100, divisions: 100, label: "Save quality", onChanged: (value) =>
                setState(() => quality = value.toInt()),
              ),
              SizedBox(width: 40, child: Text(quality.toString())),
            ]),
            Row(spacing: 10, children: [
              const Text("Default start position on Rename:"),
              SizedBox(width: 66, child: TextField(controller: ctrl, decoration: InputDecoration(border: OutlineInputBorder()))),
            ]),
          ],
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          OutlinedButton(onPressed: _ok, child: const Text("OK")),
        ],
      ),
    );
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }
}
