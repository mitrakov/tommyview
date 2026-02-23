import "dart:io";
import "package:f_logs/f_logs.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:pasteboard/pasteboard.dart";
import "package:path/path.dart" as path;
import "package:image/image.dart" as img;
import "package:image_editor/image_editor.dart";
import "package:file_picker/file_picker.dart";
import "package:extended_image/extended_image.dart";
import "package:window_manager/window_manager.dart";
import "package:flutter_platform_alert/flutter_platform_alert.dart";
import "package:menubar/menubar.dart";
import "package:tommyview/inputbox.dart";
import "package:tommyview/settings.dart";
import "package:tommyview/settingsview.dart";
import "package:tommyview/moveto.dart";

/*
Build for MacOS:
  bump version in pubspec.yaml
  flutter build macos
  xCode: Product -> Destination -> Any Mac (arm64, x86_64)
  xCode: Product -> Archive -> Distribute App -> Direct Distribution -> wait for 30-40 sec for notarization service to complete
  copy "TommyView.app" to "installer/macos/App"
  run build-dmg.sh
  move *.dmg image to dist/

Build for Windows:
  insert RuToken and use PIN 12345678
  run installer\windows\build.bat

Build for Linux:
  run installer/linux/build.sh
 */
void main(List<String> args) async {
  await WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await Settings.ensureInitialized();
  runApp(MaterialApp(home: Scaffold(body: MyApp(args.firstOrNull))));
}

// should match the ones in Info.plist! (svg and other vector formats are not supported)
const _allowedExtensions = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "wbmp", "heic", "ico", "cur", "avif", "dng"];

class MyApp extends StatefulWidget {
  final String? arg0;
  const MyApp(this.arg0);
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final editorKey = GlobalKey<ExtendedImageEditorState>();
  final extImgKey = GlobalKey();         // key to access ExtendedImage widget
  final List<File> files = [];

  late File _currentFile;
  int _index = -1;                       // -1 means "No file selected"
  ExtendedImageMode _mode = .gesture;
  int _rotate = 0;                       // in quarters (0=0°, 1=90°, 2=180°, etc.)
  Uint8List _forceLoad = Uint8List(0);   // force load flag used in _saveFile() to reload the image
  bool _initDone = false;

  bool get isRotated => _rotate % 4 > 0; // result of "%" is always non-negative
  bool get isWebp => path.extension(_currentFile.path).toLowerCase() == ".webp";
  bool get isPng  => path.extension(_currentFile.path).toLowerCase() == ".png";

  @override
  void initState() {
    super.initState();
    if (!Platform.isMacOS) _createNativeMenu(); // tmp solution to create menu on Windows/Linux
    initStateAsync();
  }

  void initStateAsync() async {
    var startPath = widget.arg0; // take initial file from "args" list (Windows, Linux)

    if (Platform.isMacOS) {
      // in MacOS, we need to make a call to Swift native code to check if a file has been opened with our App
      const hostApi = MethodChannel("mitrakov");
      startPath = await hostApi.invokeMethod("getCurrentFile");
      FLog.info(text: "Filename from MacOS channel: $startPath");

      // race conditions (in rare cases "getCurrentFile" may return null from Swift code, let's retry in 500 msec.)
      if (startPath == null) {
        await Future.delayed(Duration(milliseconds: 500), () async {
          startPath = await hostApi.invokeMethod("getCurrentFile");
        });
        FLog.info(text: "Filename from MacOS channel (retry): $startPath");
      }
    }

    if (startPath == null) { // take initial file from Files dialog
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: "Select a picture",
        type: .custom,
        allowedExtensions: _allowedExtensions,
        lockParentWindow: true,
      );
      FLog.info(text: "Filename from FilePicker: ${result?.files.first.path}");
      startPath = result?.files.first.path;
    }

    // init code
    if (startPath != null) {
      files.addAll(Directory(path.dirname(startPath!))
        .listSync()                                                                                        // get all folder children
        .whereType<File>()                                                                                 // filter out directories
        .where((f) => _allowedExtensions.map((s) => ".$s").contains(path.extension(f.path).toLowerCase())) // filter by extension
        .toList()
        ..sort((a, b) => a.path.compareTo(b.path)));
      _currentFile = files.firstWhere((f) => f.path == startPath, orElse: () => files.first);
      _index = files.indexOf(_currentFile);
    }

    setState(() {
      _initDone = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMacOS = Platform.isMacOS;
    if (!_initDone) return Center(child: CircularProgressIndicator());
    _changeWindowTitle();
    return PlatformMenuBar(
      menus: [
        PlatformMenu(label: "Hey-Hey", menus: [
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(label: "Settings       ⌘, or F4",       onSelected: () => showSettings(context)),
          ]),
          PlatformMenuItem(label: "Quit              ⌘W or ⌘Q",      onSelected: () => exit(0)),
        ]),
        PlatformMenu(label: "File", menus: [
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(label: "Next              →",           onSelected: _nextImage),
            PlatformMenuItem(label: "Previous       ←",              onSelected: _previousImage),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(label: "Save              ↩",           onSelected: _saveFile),
            PlatformMenuItem(label: "Rename        ⌘R or F2 or ⇧F6", onSelected: () => _renameFile(context)),
            PlatformMenuItem(label: "Delete           ⌫ or ⌦",       onSelected: _deleteFile),
            PlatformMenuItem(label: "Move To...     F6",             onSelected: _showMoveToDialog),
          ])
        ]),
        PlatformMenu(label: "Еdit", menus: [
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(label: "Copy         ⌘E",               onSelected: _copyImage),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(label: "Turn ⟳        ↑",               onSelected: _rotateClockwise),
            PlatformMenuItem(label: "Turn ⟲        ↓",               onSelected: _rotateCounterclockwise),
            PlatformMenuItem(label: "Bulk Turn ⟳   ⇧↑",              onSelected: _rotateClockwiseBulk),
            PlatformMenuItem(label: "Bulk Turn ⟲   ⇧↓",              onSelected: _rotateCounterclockwiseBulk),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(label: "Crop            ⌘E or F3",      onSelected: _switchMode),
          ])
        ]),
        PlatformMenu(label: "Help", menus: [
          PlatformMenuItem(label: "About        F1",                 onSelected: _showAboutDialog),
        ])
      ],
      child: Shortcuts(
        shortcuts: {
          SingleActivator(LogicalKeyboardKey.arrowRight):                             NextImageIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft):                              PreviousImageIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp):                                RotateClockwiseIntent(),
          SingleActivator(LogicalKeyboardKey.arrowDown):                              RotateCounterclockwiseIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):                   RotateClockwiseBulkIntent(),
          SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):                 RotateCounterclockwiseBulkIntent(),
          SingleActivator(LogicalKeyboardKey.delete):                                 DeleteFileIntent(),
          SingleActivator(LogicalKeyboardKey.backspace):                              DeleteFileIntent(),
          SingleActivator(LogicalKeyboardKey.enter):                                  SaveFileIntent(),
          SingleActivator(LogicalKeyboardKey.escape):                                 SetModeViewerIntent(),
          SingleActivator(LogicalKeyboardKey.keyQ, meta: isMacOS, control: !isMacOS): CloseWindowIntent(),
          SingleActivator(LogicalKeyboardKey.keyW, meta: isMacOS, control: !isMacOS): CloseWindowIntent(),
          SingleActivator(LogicalKeyboardKey.keyR, meta: isMacOS, control: !isMacOS): RenameFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyE, meta: isMacOS, control: !isMacOS): SwitchModeIntent(),
          SingleActivator(LogicalKeyboardKey.keyC, meta: isMacOS, control: !isMacOS): CopyIntent(),
          SingleActivator(LogicalKeyboardKey.comma,meta: isMacOS, control: !isMacOS): SettingsIntent(),
          SingleActivator(LogicalKeyboardKey.f1):                                     AboutDialogIntent(),
          SingleActivator(LogicalKeyboardKey.f2):                                     RenameFileIntent(),
          SingleActivator(LogicalKeyboardKey.f3):                                     SwitchModeIntent(),
          SingleActivator(LogicalKeyboardKey.f4):                                     SettingsIntent(),
          SingleActivator(LogicalKeyboardKey.f6):                                     MoveToIntent(),
          SingleActivator(LogicalKeyboardKey.f9, shift: true):                        SaveLogsIntent(),
          SingleActivator(LogicalKeyboardKey.f6, shift: true):                        RenameFileIntent(),
          SingleActivator(LogicalKeyboardKey.f12, shift: true):                       DebugIntent(),
        },
        child: Actions(
          actions: {
            NextImageIntent:                  CallbackAction(onInvoke: (_) => _nextImage()),
            PreviousImageIntent:              CallbackAction(onInvoke: (_) => _previousImage()),
            RotateClockwiseIntent:            CallbackAction(onInvoke: (_) => _rotateClockwise()),
            RotateCounterclockwiseIntent:     CallbackAction(onInvoke: (_) => _rotateCounterclockwise()),
            RotateClockwiseBulkIntent:        CallbackAction(onInvoke: (_) => _rotateClockwiseBulk()),
            RotateCounterclockwiseBulkIntent: CallbackAction(onInvoke: (_) => _rotateCounterclockwiseBulk()),
            DeleteFileIntent:                 CallbackAction(onInvoke: (_) => _deleteFile()),
            SaveFileIntent:                   CallbackAction(onInvoke: (_) => _saveFile()),
            RenameFileIntent:                 CallbackAction(onInvoke: (_) => _renameFile(context)),
            SwitchModeIntent:                 CallbackAction(onInvoke: (_) => _switchMode()),
            SetModeViewerIntent:              CallbackAction(onInvoke: (_) => _setModeToViewer()),
            AboutDialogIntent:                CallbackAction(onInvoke: (_) => _showAboutDialog()),
            SettingsIntent:                   CallbackAction(onInvoke: (_) => showSettings(context)),
            MoveToIntent:                     CallbackAction(onInvoke: (_) => _showMoveToDialog()),
            SaveLogsIntent:                   CallbackAction(onInvoke: (_) => _showSaveLogsDialog()),
            CopyIntent:                       CallbackAction(onInvoke: (_) => _copyImage()),
            DebugIntent:                      CallbackAction(onInvoke: (_) => _debug()),
            CloseWindowIntent:                CallbackAction(onInvoke: (_) => exit(0)),
          },
          child: Focus(              // needed for Shortcuts
            autofocus: true,         // focused by default
            child: RotatedBox(
              quarterTurns: _rotate,
              child: Builder(builder: (context) {
                // 1) for Editor mode BoxFit must be "contain"
                // 2) to access "rawImageData" in _saveFile() method, cacheRawData must be "true"
                if (_index < 0) return Center(child: Text("Welcome to TommyView!\nNo image files selected.", textAlign: .center));
                final result = _forceLoad.isNotEmpty
                  ? ExtendedImage.memory(
                      _forceLoad,   key: extImgKey, mode: _mode, fit: _mode == .editor ? .contain : null,
                      width: .infinity, height: .infinity, extendedImageEditorKey: editorKey, cacheRawData: true
                    )
                  : ExtendedImage.file(
                      _currentFile, key: extImgKey, mode: _mode, fit: _mode == .editor ? .contain : null,
                      width: .infinity, height: .infinity, extendedImageEditorKey: editorKey, cacheRawData: true
                    );
                _forceLoad = Uint8List(0);
                return result;
              })
            )
          )
        )
      )
    );
  }

  void _changeWindowTitle() {
    if (_index < 0) return;
    final title = "${path.basename(_currentFile.path)}${isRotated ? "*" : ""} ${_mode == .editor ? " [Crop Mode]" : ""}";
    windowManager.setTitle(title);
  }

  void _switchMode() {
    if (_index < 0) return;
    if (isWebp) _showWebpNotSupportedDialog();
    else setState(() {
      _mode = _mode == .editor ? .gesture : .editor;
      _rotate = 0;
    });
  }

  void _setModeToViewer() {
    setState(() {
      _mode = .gesture;
      _rotate = 0;
    });
  }

  void _nextImage() {
    if (_mode == .gesture) {
      if (_index < files.length - 1) {
        setState(() {
          _index++;
          _currentFile = files[_index];
          _rotate = 0;
        });
      }
    }
  }

  void _previousImage() {
    if (_mode == .gesture) {
      if (_index > 0) {
        setState(() {
          _index--;
          _currentFile = files[_index];
          _rotate = 0;
        });
      }
    }
  }

  void _rotateClockwise() {
    if (_index < 0) return;
    if (_mode == .gesture) {
      if (isWebp) _showWebpNotSupportedDialog();
      else setState(() {
        _rotate++;
      });
    }
  }

  void _rotateCounterclockwise() {
    if (_index < 0) return;
    if (_mode == .gesture) {
      if (isWebp) _showWebpNotSupportedDialog();
      else setState(() {
        _rotate--;
      });
    }
  }

  void _rotateClockwiseBulk() => _rotateBulkInternal(true);

  void _rotateCounterclockwiseBulk() => _rotateBulkInternal(false);

  void _rotateBulkInternal(bool clockwise) async {
    if (_index < 0) return;
    if (_mode == .gesture) {
      if (!isRotated) {
        if (isWebp) _showWebpNotSupportedDialog();
        else {
          const h = "Attention!";
          final c = clockwise ? "clockwise" : "counterclockwise";
          final t = "Are you sure you want to rotate and save ALL ${files.length} file(s) at this folder $c?";
          if (await FlutterPlatformAlert.showAlert(windowTitle: h, text: t, alertStyle: .yesNo, iconStyle: .warning) == .yesButton) {
            final ImageConverter converter = Platform.isMacOS ? _converterMacOs : _converterWinLinux;
            final int rotate = clockwise ? 90 : -90;
            files.forEach((file) async {
              final Uint8List image = file.readAsBytesSync();
              final Uint8List bytes = await converter.call(image, file.path, rotate, null);
              file.writeAsBytesSync(bytes, flush: true);
              if (file == _currentFile) {
                setState(() {
                  _forceLoad = bytes; // force reload current image from disk
                });
              }
            });
            clearMemoryImageCache();  // clear image cache, this is needed!!!
          }
        }
      }
    }
  }

  void _deleteFile() async {
    if (_mode == .gesture) {
      const h = "Delete file?";
      final text = 'Remove file "${path.basename(_currentFile.path)}"?';
      if (await FlutterPlatformAlert.showAlert(windowTitle: h, text: text, alertStyle: .yesNo, iconStyle: .warning) == .yesButton) {
        _currentFile.deleteSync();
        _updateCurrentFileAfterDelete();
      }
    }
  }

  void _updateCurrentFileAfterDelete() {
    files.removeAt(_index);
    if (files.isEmpty) exit(0);
    else setState(() {
      if (_index >= files.length) _index--; // if we deleted last file => switch pointer to previous
      _currentFile = files[_index];
    });
  }

  void _renameFile(BuildContext context, {String? initialText}) async {
    if (_index < 0) return;
    if (_mode == .gesture) {
      // for "prompt" function, make sure to pass a "context" that contains "MaterialApp" in its hierarchy;
      // also, set "barrierDismissible" to "true" to allow ESC button
      final currentName = path.basenameWithoutExtension(_currentFile.path);
      final extension = path.extension(_currentFile.path);
      final title = 'Rename file "$currentName" ($extension)?';
      final initialValue = initialText ?? currentName;
      final from = Settings.local.selectionFrom;
      final newName = await showInputBox(context, title, initialText: initialValue, validator: _validateFilename, selectedFrom: from);
      if (newName != null && newName.isNotEmpty && newName != currentName) {
        final newPath = path.join(path.dirname(_currentFile.path), "$newName$extension");
        if (File(newPath).existsSync()) {
          const h = "Overwrite file?";
          final text = 'Filename "$newName" already exists. Overwrite?';
          if (await FlutterPlatformAlert.showAlert(windowTitle: h, text: text, alertStyle: .yesNo, iconStyle: .warning) == .yesButton)
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
    files..removeAt(_index)..insert(_index, newFile);
    setState(() {
      _currentFile = files[_index];
    });
  }

  void _saveFile() async {
    int? rotateOption;
    Rect? cropOption;

    switch (_mode) {
      case .gesture:
        if (isRotated) {
          rotateOption = _rotate * 90;
        }
        break;
      case .editor:
        final state = editorKey.currentState!;
        final action = state.editAction!;
        final cropRect = state.getCropRect()!;
        if (action.needCrop) {
          cropOption = _fixRect(cropRect);
        }
        break;
      default:
    }

    if (rotateOption != null || cropOption != null) {
      final ImageConverter converter = Platform.isMacOS ? _converterMacOs : _converterWinLinux;
      final widget = extImgKey.currentWidget as ExtendedImage;         // editorKey cannot be used here!
      final imageProvider = widget.image as ExtendedFileImageProvider; // now it's always ExtendedFileImageProvider
      final Uint8List image = imageProvider.rawImageData;
      final Uint8List bytes = await converter.call(image, _currentFile.path, rotateOption, cropOption);
      _currentFile.writeAsBytesSync(bytes, flush: true);
      clearMemoryImageCache(); // clear image cache, this is needed!!!
      setState(() {
        _forceLoad = bytes;    // force reload current image from disk
        _setModeToViewer();
      });
    } // else user pressed Enter for no reason
  }

  void _copyImage() {
    if (_index < 0) return;
    Pasteboard.writeImage(_forceLoad.isNotEmpty ? _forceLoad : _currentFile.readAsBytesSync());
  }

  void _showWebpNotSupportedDialog() {
    const text = "Sorry, WebP format is not currently supported for editing";
    FlutterPlatformAlert.showAlert(windowTitle: "Unsupported format", text: text, iconStyle: .warning);
  }

  void _showAboutDialog() async {
    final info = await PackageInfo.fromPlatform();
    final text = "v${info.version} (build: ${info.buildNumber})\n\n© Artem Mitrakov. All rights reserved\nmitrakov-artem@yandex.ru";
    if (Platform.isWindows) // bug in Windows: F1.keyUp event is swallowed by ModalDialog event loop => let's wait for 300 msec.
      Future.delayed(Duration(milliseconds: 300), () =>
         FlutterPlatformAlert.showAlert(windowTitle: info.appName, text: text, iconStyle: .information));
    else FlutterPlatformAlert.showAlert(windowTitle: info.appName, text: text, iconStyle: .information);
  }

  void _showMoveToDialog() {
    if (_index < 0) return;
    showMoveToDialog(context, _currentFile.path, _updateCurrentFileAfterDelete);
  }

  void _showSaveLogsDialog() async {
    final filename = await FilePicker.platform.saveFile(dialogTitle: "Save logs", fileName: "tommyview.log", lockParentWindow: true);
    if (filename != null) {
      final f = File(filename);
      final logs = await FLog.getAllLogs();
      final sink = f.openWrite();
      sink.writeAll(logs.map((e) => e.toJson()), "\n");
      sink.close();
      FLog.clearLogs();
    }
  }

  /// converter that uses "image" library
  /// +: cross-platform: Windows, Linux, MacOS
  /// -: sometimes cuts off EXIF data: "Corrupt data. The data provided does not follow the specification.
  ///    ExifData: Tag data past end of buffer (1823 > 1915)" (v4.1.3)
  /// -: bug: https://github.com/brendan-duncan/image/issues/460
  /// -: bug: https://github.com/brendan-duncan/image/issues/462
  /// -: bug: https://github.com/brendan-duncan/image/issues/587
  /// -: no Webp support
  Future<Uint8List> _converterWinLinux(Uint8List image, String path, int? rotate, Rect? cropRect) {
    // https://github.com/brendan-duncan/image/issues/460
    // https://github.com/brendan-duncan/image/issues/462
    final image0 = img.decodeImage(image)!;
    final image1 = rotate == null ? image0 : img.copyRotate(image0, angle: rotate);
    final image2 = cropRect == null ? image1 : img.copyCrop(image1,
      x: cropRect.left.toInt(),
      y: cropRect.top.toInt(),
      width: cropRect.width.toInt(),
      height: cropRect.height.toInt()
    );
    return Future.value(img.encodeNamedImage(path, image2)!);
  }

  /// converter that uses "image_editor" library
  /// +: keeps EXIF data for JPG (partially, only 8 items), not for PNG
  /// -: only MacOS 10.15+
  /// -: no Webp support
  Future<Uint8List> _converterMacOs(Uint8List image, String path, int? rotate, Rect? cropRect) async {
    final quality = Settings.local.quality;
    FLog.info(text: "Save file with quality = $quality");

    // AddTextOption, ClipOption, ColorOption, DrawOption, FlipOption, MaxImageOption, RotateOption, ScaleOption
    final option = ImageEditorOption();
    if (rotate != null)
      option.addOption(RotateOption(rotate));
    if (cropRect != null)
      option.addOption(ClipOption(x: cropRect.left, y: cropRect.top, width: cropRect.width, height: cropRect.height));
    option.outputFormat = isPng ? .png(quality) : .jpeg(quality);
    final result = await ImageEditor.editImage(image: image, imageEditorOption: option);
    return result!;
  }

  String? _validateFilename(String? s) {
    // https://stackoverflow.com/a/31976060/2212849
    if (s == null || s.isEmpty) return "Filename cannot be empty";
    if (s.contains(Platform.pathSeparator)) return 'Filename cannot contain "${Platform.pathSeparator}"';
    if (s.contains(RegExp(r'[\x00-\x1F]'))) return "Filename cannot contain non-printable characters";
    if (Platform.isWindows) { // Windows has more strict rules for filenames
      if (s.contains(RegExp(r'[<>:"/\\|?*]'))) return 'Filename cannot contain the following characters: <>:"/\\|?*';
      if (s.endsWith(" ")) return 'Filename cannot end with space (" ")';
      if (s.endsWith(".")) return 'Filename cannot end with dot (".")';
      if ({"CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"}.contains(s))
        return "Filename cannot be a reserved Windows word";
    }
    return null;
  }

  void _createNativeMenu() {
    // This is a temp solution, until Flutter adds "PlatformMenuBar" support for Windows/Linux.
    // After that "menubar" dependency may also be removed
    setApplicationMenu([
      NativeSubmenu(label: "File", children: [
        NativeMenuItem(label: "Next              →",                    onSelected: _nextImage),
        NativeMenuItem(label: "Previous       ←",                       onSelected: _previousImage),
        const NativeMenuDivider(),
        NativeMenuItem(label: "Save              Enter",                onSelected: _saveFile),
        NativeMenuItem(label: "Rename        Ctrl+R or F2 or Shift+F6", onSelected: () => _renameFile(context)),
        NativeMenuItem(label: "Delete           Del or Backspace",      onSelected: _deleteFile),
        NativeMenuItem(label: "Move To...     F6",                      onSelected: _showMoveToDialog),
        const NativeMenuDivider(),
        NativeMenuItem(label: "Settings         Ctrl+, or F4",          onSelected: () => showSettings(context)),
        const NativeMenuDivider(),
        NativeMenuItem(label: "Quit              Ctrl+W or Alt+F4",     onSelected: () => exit(0)),
      ]),
      NativeSubmenu(label: "Еdit", children: [
        NativeMenuItem(label: "Copy          Ctrl+C",                   onSelected: _copyImage),
        const NativeMenuDivider(),
        NativeMenuItem(label: "Turn ⟳        ↑",                        onSelected: _rotateClockwise),
        NativeMenuItem(label: "Turn ⟲        ↓",                        onSelected: _rotateCounterclockwise),
        NativeMenuItem(label: "Bulk Turn ⟳   Shift+↑",                  onSelected: _rotateClockwiseBulk),
        NativeMenuItem(label: "Bulk Turn ⟲   Shift+↓",                  onSelected: _rotateCounterclockwiseBulk),
        const NativeMenuDivider(),
        NativeMenuItem(label: "Crop            Ctrl+E or F3",           onSelected: _switchMode),
      ]),
      NativeSubmenu(label: "Help", children: [
        NativeMenuItem(label: "About        F1",                        onSelected: _showAboutDialog),
      ])
    ]);
  }

  Rect _fixRect(Rect rect) {
    // extended_image: 7.0.2 has a bug when sometimes it provides "-0.0" values in Rect
    if (rect.left.isNegative || rect.right.isNegative || rect.top.isNegative || rect.bottom.isNegative) {
      final left   = rect.left.isNegative   ? 0.0 : rect.left;
      final right  = rect.right.isNegative  ? 0.0 : rect.right;
      final top    = rect.top.isNegative    ? 0.0 : rect.top;
      final bottom = rect.bottom.isNegative ? 0.0 : rect.bottom;
      return Rect.fromLTRB(left, top, right, bottom);
    }
    return rect;
  }

  void _debug() async {
    if (Platform.isMacOS) {
      const hostApi = MethodChannel("mitrakov");
      final String? currentFile = await hostApi.invokeMethod("getCurrentFile");
      FlutterPlatformAlert.showAlert(windowTitle: "mitrakov channel", text: "$currentFile");
    }
  }
}

// Typedefs
typedef ImageConverter = Future<Uint8List> Function(Uint8List curImage, String path, int? rotate, Rect? cropRect);

// Hotkey intents
class NextImageIntent extends Intent {}
class PreviousImageIntent extends Intent {}
class RotateClockwiseIntent extends Intent {}
class RotateCounterclockwiseIntent extends Intent {}
class RotateClockwiseBulkIntent extends Intent {}
class RotateCounterclockwiseBulkIntent extends Intent {}
class SaveFileIntent extends Intent {}
class RenameFileIntent extends Intent {}
class DeleteFileIntent extends Intent {}
class CloseWindowIntent extends Intent {}
class SwitchModeIntent extends Intent {}
class SetModeViewerIntent extends Intent {}
class SettingsIntent extends Intent {}
class MoveToIntent extends Intent {}
class SaveLogsIntent extends Intent {}
class CopyIntent extends Intent {}
class AboutDialogIntent extends Intent {}
class DebugIntent extends Intent {}
