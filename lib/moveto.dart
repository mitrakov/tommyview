// ignore_for_file: curly_braces_in_flow_control_structures

import "dart:io";
import "package:path/path.dart" as path;
import "package:file_picker/file_picker.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:flutter_platform_alert/flutter_platform_alert.dart";
import "package:flutter/material.dart";
import "package:tommyview/mylistview.dart";

Future showMoveToDialog(BuildContext context, String oldFilePath, VoidCallback onSelect) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) => _MoveToDialog(oldFilePath, onSelect),
  );
}

class _MoveToDialog extends StatefulWidget {
  final String filepath;
  final VoidCallback onSelect;

  const _MoveToDialog(this.filepath, this.onSelect);

  @override
  _MoveToDialogState createState() => _MoveToDialogState();
}

class _MoveToDialogState extends State<_MoveToDialog> {
  static const String moveToSettingKey = "moveToList";

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final settings = snapshot.data!;
          final moveToList = settings.getStringList(moveToSettingKey) ?? [];
          final filename = path.basename(widget.filepath);
          return AlertDialog(
            title: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text('Move file "$filename" to...', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 600,
                  width: 900,
                  child: Focus(
                    focusNode: FocusNode(),                     // TODO: bug: sometimes focus goes to the buttons instead of MyListView
                    child: MyListView(moveToList, _onSelected), // TODO: bug: "moveToList" may change, this will cause errors on "add new location"
                  ),
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () async {
                  String? path = await FilePicker.platform.getDirectoryPath(dialogTitle: "Select a folder", lockParentWindow: true);
                  if (path != null) {
                    if (!moveToList.contains(path))
                      moveToList.add(path);
                    settings.setStringList(moveToSettingKey, moveToList);
                    setState(() {});
                  }
                },
                child: const Text("Add new location"),
              ),
              OutlinedButton(
                onPressed: () async {
                  await settings.setStringList(moveToSettingKey, []);
                  setState(() {});
                },
                child: const Text("Clear list"),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          );
        }
        return const CircularProgressIndicator();
      },
    );
  }

  void _onSelected(String selected) async {
    if (await _renameFile(selected)) {
      widget.onSelect();
      Navigator.pop(context);
    }
  }

  Future<bool> _renameFile(String newDir) async {
    final newPath = path.join(newDir, path.basename(widget.filepath));
    if (File(newPath).existsSync()) {
      const title = "Overwrite file?";
      final text = 'Filename "$newPath" already exists. Overwrite?';
      if (await FlutterPlatformAlert.showAlert(windowTitle: title, text: text, alertStyle: AlertButtonStyle.yesNo, iconStyle: IconStyle.warning) == AlertButton.yesButton)
        return _renameFileImpl(newPath);
      else return false;
    } else return _renameFileImpl(newPath);
  }

  bool _renameFileImpl(String newPath) {
    final newFolder = path.dirname(newPath);
    if (Directory(newFolder).existsSync()) {
      print("Moving from ${widget.filepath} to ${newPath}");
      File(widget.filepath).renameSync(newPath);
      return true;
    } else {
      FlutterPlatformAlert.showAlert(windowTitle: "ERROR", text: 'Folder "$newFolder" doesn\'t exist!', iconStyle: IconStyle.error);
      return false;
    }
  }
}
