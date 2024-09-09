import "package:flutter/material.dart";

Future showSettings(BuildContext context, int currentQuality, ValueSetter<int> qualitySetter) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) => _SettingsDialog(currentQuality, qualitySetter),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog(this.currentQuality, this.qualitySetter);

  final int currentQuality;
  final ValueSetter<int> qualitySetter;

  @override
  _SettingsDialogState createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late int quality = widget.currentQuality;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text("Settings", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Text("Save quality:"),
            Slider(
              value: quality.toDouble(),
              min: 1,
              max: 100,
              divisions: 100,
              autofocus: true,
              label: "Save quality",
              onChanged: (value) => setState(() => quality = value.toInt()),
            ),
            SizedBox(width: 40, child: Text(quality.toString())),
          ])
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        OutlinedButton(
          onPressed: () {
            widget.qualitySetter(quality);
            Navigator.pop(context);
          },
          child: const Text("OK"),
        ),
      ],
    );
  }
}
