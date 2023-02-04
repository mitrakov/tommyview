// ignore_for_file: prefer_const_constructors, curly_braces_in_flow_control_structures, use_build_context_synchronously
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:image_editor/image_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:prompt_dialog/prompt_dialog.dart';
import 'package:extended_image/extended_image.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';

/// Bugs and Feature requests:
/// rm prompt_dialog
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
  final extImgKey = GlobalKey(); // key to access ExtendedImage widget
  late File _currentFile;
  late int _index;
  ExtendedImageMode _mode = ExtendedImageMode.gesture;
  int _rotate = 0;                     // in quarters (0=0°, 1=90°, 2=180°, etc.)
  Uint8List _forceLoad = Uint8List(0); // force load flag used in _saveFile() to reload the image
  bool get isRotated => _rotate % 4 > 0;

  @override
  void initState() {
    super.initState();
    _currentFile = widget.files.firstWhere((f) => f.path == widget.startPath, orElse: () => widget.files.first);
    _index = widget.files.indexOf(_currentFile);
  }

  @override
  Widget build(BuildContext context) {
    _changeWindowTitle();
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
          child: RotatedBox(
            quarterTurns: _rotate,
            child: Builder(builder: (c) {
              // 1) for Editor mode BoxFit must be "contain"
              // 2) to access "rawImageData" in _saveFile() method, cacheRawData must be "true"
              final result = _forceLoad.isNotEmpty
                ? ExtendedImage.memory(key: extImgKey, _forceLoad,   mode: _mode, fit: _mode == ExtendedImageMode.editor ? BoxFit.contain : null, width: double.infinity, height: double.infinity, extendedImageEditorKey: editorKey, cacheRawData: true)
                : ExtendedImage.file  (key: extImgKey, _currentFile, mode: _mode, fit: _mode == ExtendedImageMode.editor ? BoxFit.contain : null, width: double.infinity, height: double.infinity, extendedImageEditorKey: editorKey, cacheRawData: true);
              _forceLoad = Uint8List(0);
              return result;
            })
          )
        )
      )
    );
  }

  void _changeWindowTitle() {
    final title = "${path.basename(_currentFile.path)}${isRotated ? "*" : ""} ${_mode == ExtendedImageMode.editor ? " [Crop Mode]" : ""}";
    windowManager.setTitle(title);
  }

  void _switchMode() {
    setState(() {
      _mode = _mode == ExtendedImageMode.editor ? ExtendedImageMode.gesture : ExtendedImageMode.editor;
      _rotate = 0;
    });
  }

  void _setModeToViewer() {
    setState(() {
      _mode = ExtendedImageMode.gesture;
      _rotate = 0;
    });
  }

  void _nextImage() {
    if (_mode == ExtendedImageMode.gesture) {
      if (_index < widget.files.length - 1) {
        setState(() {
          _index++;
          _currentFile = widget.files[_index];
          _rotate = 0;
        });
      }
    }
  }

  void _previousImage() {
    if (_mode == ExtendedImageMode.gesture) {
      if (_index > 0) {
        setState(() {
          _index--;
          _currentFile = widget.files[_index];
          _rotate = 0;
        });
      }
    }
  }

  void _rotateClockwise() {
    if (_mode == ExtendedImageMode.gesture) {
      setState(() {
        _rotate++;
      });
    }
  }

  void _rotateCounterclockwise() {
    if (_mode == ExtendedImageMode.gesture) {
      setState(() {
        _rotate--;
      });
    }
  }

  void _deleteFile() async {
    if (_mode == ExtendedImageMode.gesture) {
      const title = "Delete file?";
      final text = 'Remove file "${path.basename(_currentFile.path)}"?';
      if (await FlutterPlatformAlert.showAlert(windowTitle: title, text: text, alertStyle: AlertButtonStyle.yesNo, iconStyle: IconStyle.warning) == AlertButton.yesButton) {
        _currentFile.deleteSync();
        widget.files.removeAt(_index);
        if (widget.files.isEmpty) exit(0);
        else setState(() {
          if (_index >= widget.files.length) _index--; // if we deleted last file => switch pointer to previous
          _currentFile = widget.files[_index];
        });
      }
    }
  }

  void _renameFile(BuildContext context, {String? initialText}) async {
    if (_mode == ExtendedImageMode.gesture) {
      // for "prompt" function, make sure to pass a "context" that contains "MaterialApp" in its hierarchy;
      // also, set "barrierDismissible" to 'true' to allow ESC button
      final currentName = path.basenameWithoutExtension(_currentFile.path);
      final extension = path.extension(_currentFile.path);
      final initialValue = initialText ?? currentName;
      final newName = await prompt(context, title: Text('Rename file "$currentName" ($extension)?'), initialValue: initialValue, barrierDismissible: true, validator: _validateFilename );
      if (newName != null && newName.isNotEmpty && newName != currentName) {
        final newPath = path.join(path.dirname(_currentFile.path), "$newName$extension");
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
    final newFile = _currentFile.renameSync(newPath);
    widget.files.removeAt(_index);
    widget.files.insert(_index, newFile);
    setState(() {
      _currentFile = widget.files[_index];
    });
  }

  void _saveFile() async {
    final option = ImageEditorOption(); // AddTextOption, ClipOption, ColorOption, DrawOption, FlipOption, MaxImageOption, RotateOption, ScaleOption
    switch (_mode) {
      case ExtendedImageMode.gesture:
        if (isRotated) {
          option.addOption(RotateOption(_rotate * 90));
        }
        break;
      case ExtendedImageMode.editor:
        final state = editorKey.currentState!;
        final action = state.editAction!;
        final cropRect = state.getCropRect()!;
        if (action.needCrop) {
          option.addOption(ClipOption(x: cropRect.left, y: cropRect.top, width: cropRect.width, height: cropRect.height));
        }
        break;
      default:
    }
    if (option.options.isNotEmpty) {
      final widget = extImgKey.currentWidget as ExtendedImage;         // editorKey cannot be used here!
      final imageProvider = widget.image as ExtendedFileImageProvider; // now it's always ExtendedFileImageProvider, but theoretically might be ExtendedMemoryImageProvider
      final bytes = await ImageEditor.editImage(image: imageProvider.rawImageData, imageEditorOption: option);
      _currentFile.writeAsBytesSync(bytes!, flush: true);
      clearMemoryImageCache(); // clear image cache
      setState(() {
        _forceLoad = bytes;    // force reload current image from disk
        _setModeToViewer();
      });
    } // else user pressed Enter for no reason
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
