import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_size/window_size.dart' as window;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final startFile = await getStartFile(args);
  runApp(MyApp(startFile));
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
  late File currentFile;
  late int index;

  @override
  void initState() {
    super.initState();
    currentFile = widget.files.firstWhere((f) => f.path == widget.startPath, orElse: () => widget.files.first);
    index = widget.files.indexOf(currentFile);
  }

  // handler for ⬅️ and ➡️ buttons
  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (index > 0) {
          setState(() {
            index--;
            currentFile = widget.files[index];
          });
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (index < widget.files.length - 1) {
          setState(() {
            index++;
            currentFile = widget.files[index];
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    window.setWindowTitle(path.basename(currentFile.path));
    return MaterialApp(
      title: 'Tommy Viewer',
      theme: ThemeData(primarySwatch: Colors.blueGrey),
      home: Scaffold(
        body: KeyboardListener(
          focusNode: FocusNode(),
          child: Image.file(
            currentFile,
            fit: BoxFit.scaleDown,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
          ),
          onKeyEvent: _handleKeyEvent
        )
      )
    );
  }
}
