// ignore_for_file: constant_identifier_names, prefer_const_constructors, curly_braces_in_flow_control_structures
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:file_picker/file_picker.dart';
import 'package:prompt_dialog/prompt_dialog.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final startFile = await getStartFile(args);
  runApp(MaterialApp(home: Scaffold(body: MyApp(startFile))));
}

/// Returns a file that has been opened with our App (or "" if a user cancels OpenFileDialog)
Future<String> getStartFile(List<String> args) async {
  if (args.isNotEmpty) return args.first;
  if (Platform.isMacOS) {
    // in MacOS, we need to make a call to Swift native code to check if a file has been opened with our App
    const hostApi = MethodChannel("mitrakov");
    final String? currentFile = await hostApi.invokeMethod("getCurrentFile");
    if (currentFile != null) return currentFile;
  }
  FilePickerResult? result = await FilePicker.platform.pickFiles();
  return result?.files.first.path ?? "";
}

class MyApp extends StatefulWidget {
  final String startPath;
  late final List<File> files;

  MyApp(this.startPath, {Key? key}) : super(key: key) {
    final allowedExtensions = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".wbmp"}; // should match the ones in Info.plist!
    files = Directory(path.dirname(startPath))
      .listSync()                                                                      // get all folder children
      .whereType<File>()                                                               // filter out directories
      .where((f) => allowedExtensions.contains(path.extension(f.path).toLowerCase()))  // filter by extension
      .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final imageKey = GlobalKey();
  late File currentFile;
  late int index;
  int rotateAngleDegrees = 0;
  bool forceLoad = false;

  @override
  void initState() {
    super.initState();
    currentFile = widget.files.firstWhere((f) => f.path == widget.startPath, orElse: () => widget.files.first);
    index = widget.files.indexOf(currentFile);
  }

  @override
  Widget build(BuildContext context) {
    windowManager.setTitle(path.basename(currentFile.path) + (rotateAngleDegrees % 360 == 0 ? "" : "*"));
    final app = Shortcuts(
      shortcuts: {
        SingleActivator(LogicalKeyboardKey.arrowRight): NextImageIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): PreviousImageIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): RotateClockwiseIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown): RotateCounterclockwiseIntent(),
        SingleActivator(LogicalKeyboardKey.delete): DeleteFileIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: Platform.isMacOS, control: !Platform.isMacOS): SaveFileIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, meta: Platform.isMacOS, control: !Platform.isMacOS): RenameFileIntent()
      },
      child: Actions(
        actions: {
          NextImageIntent:              CallbackAction(onInvoke: (_) => _nextImage()),
          PreviousImageIntent:          CallbackAction(onInvoke: (_) => _previousImage()),
          RotateClockwiseIntent:        CallbackAction(onInvoke: (_) => setState(() {rotateAngleDegrees += 90;})),
          RotateCounterclockwiseIntent: CallbackAction(onInvoke: (_) => setState(() {rotateAngleDegrees -= 90;})),
          DeleteFileIntent:             CallbackAction(onInvoke: (_) => _deleteFile()),
          SaveFileIntent:               CallbackAction(onInvoke: (_) => _saveFile()),
          RenameFileIntent:             CallbackAction(onInvoke: (_) => _renameFile(context))
        },
        child: Focus(              // needed for Shortcuts
          autofocus: true,         // focused by default
          child: Transform.rotate(
            angle: rotateAngleDegrees * pi / 180,
            child: forceLoad
              ? Image.memory(currentFile.readAsBytesSync(), key: imageKey, fit: BoxFit.scaleDown, width: double.infinity, height: double.infinity, alignment: Alignment.center)
              : Image.file  (currentFile,                   key: imageKey, fit: BoxFit.scaleDown, width: double.infinity, height: double.infinity, alignment: Alignment.center)
          )
        )
      )
    );
    forceLoad = false;
    return app;
  }

  void _nextImage() {
    if (index < widget.files.length - 1) {
      setState(() {
        index++;
        currentFile = widget.files[index];
        rotateAngleDegrees = 0;
      });
    }
  }

  void _previousImage() {
    if (index > 0) {
      setState(() {
        index--;
        currentFile = widget.files[index];
        rotateAngleDegrees = 0;
      });
    }
  }

  void _deleteFile() async {
    const title = "Delete file?";
    final text = 'Remove file "${path.basename(currentFile.path)}"?';
    if (await FlutterPlatformAlert.showAlert(windowTitle: title, text: text, alertStyle: AlertButtonStyle.yesNo, iconStyle: IconStyle.warning) == AlertButton.yesButton) {
      print('Deleting file: "${currentFile.path}"');
      currentFile.deleteSync();
      widget.files.removeAt(index);
      if (widget.files.isEmpty) {
        print("Current directory is empty. Exit app...");
        exit(0);
      } else setState(() {
        if (index >= widget.files.length) index--; // if we deleted last file => switch pointer to previous
        currentFile = widget.files[index];
        rotateAngleDegrees = 0;
      });
    }
  }

  void _saveFile() {
    if (rotateAngleDegrees % 360 != 0) {
      print('Saving file: "${currentFile.path}"');
      (imageKey.currentWidget as Image).image.evict();    // reset cache for current image
      final oldImage = img.decodeImage(currentFile.readAsBytesSync())!;
      final newImage = img.copyRotate(oldImage, rotateAngleDegrees);
      final bytes = img.encodeNamedImage(newImage, currentFile.path)!;
      currentFile.writeAsBytesSync(bytes, flush: true);
      setState(() {
        forceLoad = true;                                 // force reload current image from disk
        rotateAngleDegrees = 0;
      });
    }
  }

  void _renameFile(BuildContext context) async {
    // comment 1
    final currentName = path.basename(currentFile.path);
    final newName = await prompt(context, title: Text('Rename file "$currentName"?'), initialValue: currentName, barrierDismissible: true, validator: _validateFilename ); // barrierDismissible=true to allow ESC button
    if (newName != null && newName.isNotEmpty && newName != currentName) {
      final newPath = path.join(path.dirname(currentFile.path), newName); // comment 2
      print('Renaming file: "${currentFile.path}" to "$newName"');
      final newFile = currentFile.renameSync(newPath);
      widget.files.removeAt(index);
      widget.files.insert(index, newFile);
      setState(() {
        currentFile = widget.files[index];
      });
    }
  }

  String? _validateFilename(String? s) {
    if (s == null || s.isEmpty) return "Filename cannot be empty";
    else if (Platform.isWindows) {
      if (s.contains(RegExp(r'<>:"/\\\|\?\*'))) return 'Filename cannot contain the following characters: <>:"/\\|?*';
      if ({"CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"}.contains(s)) return 'Filename cannot be a reserved Windows word';
    } else { // Linux, MacOS
      if (s.contains("/")) return 'Filename cannot contain "/"';
    }
    return null;
  }
}

// Hotkey intents
class NextImageIntent extends Intent {}
class PreviousImageIntent extends Intent {}
class RotateClockwiseIntent extends Intent {}
class RotateCounterclockwiseIntent extends Intent {}
class SaveFileIntent extends Intent {}
class RenameFileIntent extends Intent {}
class DeleteFileIntent extends Intent {}
