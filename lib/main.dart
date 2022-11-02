// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_size/window_size.dart' as window;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  setWindowSize();

  if (args.isNotEmpty) runApp(MyApp(args.first));
  else {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    runApp(MyApp(result?.files.first.path ?? ""));
  }
}

Future<void> setWindowSize() async {
  final screen = await window.getCurrentScreen();
  window.setWindowFrame(screen?.frame ?? const Rect.fromLTWH(0, 0, 1024, 768));
}

class MyApp extends StatefulWidget {
  final String startPath;
  late final List<File> files;

  MyApp(this.startPath, {Key? key}) : super(key: key) {
    final allowedExtensions = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".wbmp"};
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

  @override
  Widget build(BuildContext context) {
    window.setWindowTitle(path.basename(currentFile.path));
    return MaterialApp(
      title: 'Flutter Demo',
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
          onKeyEvent: (event) {
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
        )
      )
    );
  }
}
