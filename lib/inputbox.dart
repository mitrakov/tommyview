import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// you can also use "adaptive_dialogs", but this solution is better (support Enter, Esc, etc.)
/** Shows simple input box with ENTER/ESC support, initialText, obscure chars (for passwords), selection range and validation */
Future<String?> showInputBox(BuildContext context, String title, {String? hint, String? initialText, bool obscure = false,
                             int selectedFrom = 0, int? selectedTo, String? Function(String?)? validator}) async {
  final node = FocusNode();
  final ctrl = TextEditingController(text: initialText);
  final GlobalKey<FormState> key = GlobalKey<FormState>();
  final void Function(String text) _ok = (String text) {
    if (key.currentState!.validate())
      Navigator.of(context).pop(text);
    else node.requestFocus();
  };

  if (initialText != null) {
    ctrl.selection = TextSelection(
      baseOffset: min(selectedFrom, initialText.length),
      extentOffset: min(selectedTo ?? initialText.length, initialText.length),
    );
  }

  final result = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Form(
          key: key,
          child: TextFormField(
            focusNode: node,
            autofocus: true,
            obscureText: obscure,
            controller: ctrl,
            decoration: InputDecoration(hintText: hint),
            onFieldSubmitted: _ok,
            validator: validator,
          ),
        ),
        actions: [
          TextButton(child: const Text("Cancel"), onPressed: Navigator.of(context).pop),
          ElevatedButton(child: const Text("OK"), onPressed: () => _ok(ctrl.text)),
        ],
      );
    },
  );

  Future.delayed(Duration(seconds: 1), () { // allow animation to finish before dispose()
    node.dispose();
    ctrl.dispose();
  });
  return result;
}

/** Show simple contextMenu with ENTER/ESC support, and with given actions */
Future<void> showContextMenuBox(BuildContext context, String title, String message, List<TrixAction> actions) async {
  final action = await showDialog<TrixAction>(
    context: context,
    builder: (BuildContext context) {
      return KeyboardListener(
        focusNode: FocusNode(),
        autofocus: true,
        onKeyEvent: (KeyEvent event) {
          if (event is KeyUpEvent && event.logicalKey == LogicalKeyboardKey.enter)
            Navigator.of(context).pop(actions.where((a) => a.isDefault).firstOrNull);
        },
        child: AlertDialog(
          title: Text(title, textAlign: .center, style: TextStyle(fontWeight: .bold)),
          content: Text(message, textAlign: .center),
          constraints: BoxConstraints(maxWidth: 360),
          actionsOverflowButtonSpacing: 8,
          actionsAlignment: .center,
          actionsOverflowAlignment: .center,
          actions: [
            ...actions.map((a) =>
                OutlinedButton(
                  child: Text(a.label, style: TextStyle(color: Colors.black)),
                  onPressed: () => Navigator.of(context).pop(a),
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(200, 40),
                    backgroundColor: a.isDanger? Colors.red[200] : a.isDefault ? Colors.blue[300] : Colors.grey[300],
                  ),
                ),
            ),
            Divider(thickness: 2),
            OutlinedButton(
              child: Text("Cancel", style: TextStyle(color: Colors.black)),
              style: OutlinedButton.styleFrom(minimumSize: Size(200, 40)),
              onPressed: Navigator.of(context).pop,
            ),
          ],
        ),
      );
    },
  );

  action?.f();
}

class TrixAction {
  final String label;
  final bool isDefault;
  final bool isDanger;
  final VoidCallback f;
  TrixAction(this.label, this.isDefault, this.isDanger, this.f);
}
