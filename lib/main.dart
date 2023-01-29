// ignore_for_file: prefer_const_constructors, curly_braces_in_flow_control_structures, use_build_context_synchronously
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:file_picker/file_picker.dart';
import 'package:prompt_dialog/prompt_dialog.dart';
import 'package:extended_image/extended_image.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';

/// Bugs and Feature requests:
/// –
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final startFile = await getStartFile(args);
  runApp(MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: MyApp(startFile))));
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
  final editorKey = GlobalKey<ExtendedImageEditorState>();
  late File currentFile;
  late int index;
  ExtendedImageMode mode = ExtendedImageMode.gesture;
  bool forceLoad = false; // force load flag used in _saveFile() to reload the image

  @override
  void initState() {
    super.initState();
    currentFile = widget.files.firstWhere((f) => f.path == widget.startPath, orElse: () => widget.files.first);
    index = widget.files.indexOf(currentFile);
  }

  @override
  Widget build(BuildContext context) {
    changeWindowTitle();
    return Shortcuts( // Use Flutter v3.3.0+ to have the bug with non-English layouts fixed. Otherwise hotkeys combination (⌘+S) will work only on English layouts.
      shortcuts: {
        SingleActivator(LogicalKeyboardKey.arrowRight):                                               NextImageIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft):                                                PreviousImageIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp):                                                  RotateClockwiseIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown):                                                RotateCounterclockwiseIntent(),
        SingleActivator(LogicalKeyboardKey.delete):                                                   DeleteFileIntent(),
        SingleActivator(LogicalKeyboardKey.backspace):                                                DeleteFileIntent(),
        SingleActivator(LogicalKeyboardKey.enter):                                                    SaveFileIntent(),
        SingleActivator(LogicalKeyboardKey.escape):                                                   SetModeViewerIntent(),
        SingleActivator(LogicalKeyboardKey.keyW, meta: Platform.isMacOS, control: !Platform.isMacOS): CloseWindowIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, meta: Platform.isMacOS, control: !Platform.isMacOS): RenameFileIntent(),
        SingleActivator(LogicalKeyboardKey.keyE, meta: Platform.isMacOS, control: !Platform.isMacOS): SwitchModeIntent(),
        SingleActivator(LogicalKeyboardKey.f6, shift: true):                                          RenameFileIntent(),
        SingleActivator(LogicalKeyboardKey.f2):                                                       RenameFileIntent(),
        SingleActivator(LogicalKeyboardKey.f3):                                                       SwitchModeIntent(),
      },
      child: Actions(
        actions: {
          NextImageIntent:              CallbackAction(onInvoke: (_) => _nextImage()),
          PreviousImageIntent:          CallbackAction(onInvoke: (_) => _previousImage()),
          RotateClockwiseIntent:        CallbackAction(onInvoke: (_) => _rotateClockwise()),
          RotateCounterclockwiseIntent: CallbackAction(onInvoke: (_) => _rotateCounterclockwise()),
          DeleteFileIntent:             CallbackAction(onInvoke: (_) => _deleteFile()),
          SaveFileIntent:               CallbackAction(onInvoke: (_) => _saveFile()),
          RenameFileIntent:             CallbackAction(onInvoke: (_) => _renameFile(context)),
          SwitchModeIntent:             CallbackAction(onInvoke: (_) => _switchMode()),
          SetModeViewerIntent:          CallbackAction(onInvoke: (_) => _setModeToViewer()),
          CloseWindowIntent:            CallbackAction(onInvoke: (_) => exit(0)),
        },
        child: Focus(              // needed for Shortcuts
          autofocus: true,         // focused by default
          child: Builder(builder: (c) {
            // 1) for Editor mode BoxFit must be "contain"
            // 2) to access "rawImageData" in _saveFile() method, cacheRawData must be "true"
            final result = forceLoad
              ? ExtendedImage.memory(currentFile.readAsBytesSync(), mode: mode, fit: mode == ExtendedImageMode.editor ? BoxFit.contain : null, width: double.infinity, height: double.infinity, extendedImageEditorKey: editorKey, cacheRawData: true)
              : ExtendedImage.file  (currentFile,                   mode: mode, fit: mode == ExtendedImageMode.editor ? BoxFit.contain : null, width: double.infinity, height: double.infinity, extendedImageEditorKey: editorKey, cacheRawData: true);
            forceLoad = false;
            return result;
          })
        )
      )
    );
  }

  // SWITCH MODE
  void _switchMode() {
    setState(() {
      mode = mode == ExtendedImageMode.editor ? ExtendedImageMode.gesture : ExtendedImageMode.editor;
    });
  }

  void _setModeToViewer() {
    if (mode == ExtendedImageMode.editor) {
      setState(() {
        mode = ExtendedImageMode.gesture;
      });
    }
  }

  // VIEW MODE FUNCTIONS
  void _nextImage() {
    if (mode == ExtendedImageMode.gesture) {
      if (index < widget.files.length - 1) {
        setState(() {
          index++;
          currentFile = widget.files[index];
        });
      }
    }
  }

  void _previousImage() {
    if (mode == ExtendedImageMode.gesture) {
      if (index > 0) {
        setState(() {
          index--;
          currentFile = widget.files[index];
        });
      }
    }
  }

  void _deleteFile() async {
    if (mode == ExtendedImageMode.gesture) {
      const title = "Delete file?";
      final text = 'Remove file "${path.basename(currentFile.path)}"?';
      if (await FlutterPlatformAlert.showAlert(windowTitle: title, text: text, alertStyle: AlertButtonStyle.yesNo, iconStyle: IconStyle.warning) == AlertButton.yesButton) {
        currentFile.deleteSync();
        widget.files.removeAt(index);
        if (widget.files.isEmpty) exit(0);
        else setState(() {
          if (index >= widget.files.length) index--; // if we deleted last file => switch pointer to previous
          currentFile = widget.files[index];
        });
      }
    }
  }

  void _renameFile(BuildContext context, {String? initialText}) async {
    if (mode == ExtendedImageMode.gesture) {
      // for "prompt" function, make sure to pass a "context" that contains "MaterialApp" in its hierarchy;
      // also, set "barrierDismissible" to 'true' to allow ESC button
      final currentName = path.basenameWithoutExtension(currentFile.path);
      final extension = path.extension(currentFile.path);
      final initialValue = initialText ?? currentName;
      final newName = await prompt(context, title: Text('Rename file "$currentName" ($extension)?'), initialValue: initialValue, barrierDismissible: true, validator: _validateFilename );
      if (newName != null && newName.isNotEmpty && newName != currentName) {
        final newPath = path.join(path.dirname(currentFile.path), "$newName$extension");
        if (File(newPath).existsSync()) {
          const title = "Overwrite file?";
          final text = "Filename '$newName' already exists. Overwrite?";
          if (await FlutterPlatformAlert.showAlert(windowTitle: title, text: text, alertStyle: AlertButtonStyle.yesNo, iconStyle: IconStyle.warning) == AlertButton.yesButton)
            _renameFileImpl(newPath);
          else _renameFile(context, initialText: newName);
        } else _renameFileImpl(newPath);
      }
    }
  }

  void _renameFileImpl(String newPath) {
    // Note: pass "/the/full/path.jpg" to "renameSync()" (not "newName.jpg").
    // Although "newName" is also supported by Dart (just renaming a file), it will work out only if
    // the working directory is the same as the file location, which is not always the case.
    // E.g. if you run this App from IntelliJ IDEA, working directory will be different.
    final newFile = currentFile.renameSync(newPath);
    widget.files.removeAt(index);
    widget.files.insert(index, newFile);
    setState(() {
      currentFile = widget.files[index];
    });
  }

  // EDITOR MODE FUNCTIONS
  bool get isChanged {
    // TODO smth wrong! Check!
    if (mode == ExtendedImageMode.editor) {
      final ExtendedImageEditorState? state = editorKey.currentState;
      if (state != null) { // may be NULL
        final EditActionDetails action = state.editAction!;
        return action.hasEditAction || action.needCrop;
      }
    }
    return false;
  }

  void _rotateClockwise() {
    if (mode == ExtendedImageMode.editor) {
      editorKey.currentState!.rotate(right: true);
      changeWindowTitle();
    }
  }

  void _rotateCounterclockwise() {
    if (mode == ExtendedImageMode.editor) {
      editorKey.currentState!.rotate(right: false);
      changeWindowTitle();
    }
  }

  void _saveFile() {
    if (mode == ExtendedImageMode.editor) {
      if (isChanged) {
        final ExtendedImageEditorState state = editorKey.currentState!;
        final EditActionDetails action = state.editAction!;
        final Rect cropRect = state.getCropRect()!;
        final Uint8List data = state.rawImageData; // set "cacheRawData: true" in ExtendedImage to access this field

        img.Image image = img.decodeImage(data)!;  // use v4.0.11+, because: https://github.com/brendan-duncan/image/issues/460
        if (action.needCrop) {
          image = img.copyCrop(image, x: cropRect.left.toInt(), y: cropRect.top.toInt(), width: cropRect.width.toInt(), height: cropRect.height.toInt());
        }
        if (action.hasRotateAngle) {
          image = img.copyRotate(image, angle: action.rotateAngle);
        }

        final Uint8List bytes = img.encodeNamedImage(currentFile.path, image)!;
        currentFile.writeAsBytesSync(bytes, flush: true);
        clearMemoryImageCache(); // clear image cache
        forceLoad = true;        // force reload current image from disk
        _setModeToViewer();      // go back to "View" mode
      }
    }
  }

  // OTHER FUNCTIONS
  void changeWindowTitle() {
    final title = "${path.basename(currentFile.path)} ${mode == ExtendedImageMode.editor ? " [Editor Mode]" : ""} ${isChanged ? "*" : ""}";
    windowManager.setTitle(title);
  }

  String? _validateFilename(String? s) {
    // https://stackoverflow.com/a/31976060/2212849
    if (s == null || s.isEmpty) return "Filename cannot be empty";
    if (s.contains(Platform.pathSeparator)) return 'Filename cannot contain "${Platform.pathSeparator}"';
    if (s.contains(RegExp(r'[\x00-\x1F]'))) return 'Filename cannot contain non-printable characters';
    if (Platform.isWindows) {
      if (s.contains(RegExp(r'[<>:"/\\|?*]'))) return 'Filename cannot contain the following characters: <>:"/\\|?*';
      if (s.endsWith(" ")) return 'Filename cannot end with space (" ")';
      if (s.endsWith(".")) return 'Filename cannot end with dot (".")';
      if ({"CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"}.contains(s)) return 'Filename cannot be a reserved Windows word';
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
class CloseWindowIntent extends Intent {}
class SwitchModeIntent extends Intent {}
class SetModeViewerIntent extends Intent {}
