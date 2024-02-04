// by prompt_dialog: ^1.0.9
import "package:flutter/material.dart";

Future<String?> prompt(
    BuildContext context, {
      Widget? title,
      Widget? textOK,
      Widget? textCancel,
      String? initialValue,
      bool isSelectedInitialValue = true,
      String? hintText,
      String? Function(String?)? validator,
      int minLines = 1,
      int maxLines = 1,
      bool autoFocus = true,
      TextInputType? keyboardType,
      TextInputAction? textInputAction,
      bool obscureText = false,
      String obscuringCharacter = "•",
      bool showPasswordIcon = false,
      bool barrierDismissible = false,
      TextCapitalization textCapitalization = TextCapitalization.none,
      TextAlign textAlign = TextAlign.start,
    }) {
  return showDialog(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext context) {
      return _PromptDialog(
        title: title,
        textOK: textOK,
        textCancel: textCancel,
        initialValue: initialValue,
        isSelectedInitialValue: isSelectedInitialValue,
        hintText: hintText,
        validator: validator,
        minLines: minLines,
        maxLines: maxLines,
        autoFocus: autoFocus,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        obscureText: obscureText,
        obscuringCharacter: obscuringCharacter,
        showPasswordIcon: showPasswordIcon,
        textCapitalization: textCapitalization,
        textAlign: textAlign,
      );
    },
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    Key? key,
    this.title,
    this.textOK,
    this.textCancel,
    this.initialValue,
    required this.isSelectedInitialValue,
    this.hintText,
    this.validator,
    required this.minLines,
    required this.maxLines,
    required this.autoFocus,
    this.keyboardType,
    this.textInputAction,
    required this.obscureText,
    required this.obscuringCharacter,
    required this.showPasswordIcon,
    required this.textCapitalization,
    required this.textAlign,
  }) : super(key: key);

  final Widget? title;
  final Widget? textOK;
  final Widget? textCancel;
  final String? initialValue;
  final bool isSelectedInitialValue;
  final String? hintText;
  final String? Function(String?)? validator;
  final int minLines;
  final int maxLines;
  final bool autoFocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final String obscuringCharacter;
  final bool showPasswordIcon;
  final TextCapitalization textCapitalization;
  final TextAlign textAlign;

  @override
  _PromptDialogState createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late TextEditingController controller;
  late bool stateObscureText = widget.obscureText;

  String? value;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialValue);
    value = widget.initialValue;
    if (widget.isSelectedInitialValue) { // by: @mitrakov
      controller.selection = TextSelection(baseOffset: 0, extentOffset: value?.length ?? 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, null);
        return true;
      },
      child: AlertDialog(
        title: widget.title,
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              hintText: widget.hintText,
              suffixIcon: widget.showPasswordIcon
                  ? IconButton(
                icon: Icon(
                  Icons.remove_red_eye,
                  color: stateObscureText ? Colors.grey : Colors.blueGrey,
                ),
                onPressed: () {
                  stateObscureText = !stateObscureText;
                  setState(() {
                    controller.selection = TextSelection.fromPosition(
                      const TextPosition(offset: 0),
                    );
                    controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: controller.text.length),
                    );
                  });
                },
              )
                  : null,
            ),
            validator: widget.validator,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            autofocus: widget.autoFocus,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onChanged: (String text) => value = text,
            obscureText: stateObscureText,
            obscuringCharacter: widget.obscuringCharacter,
            textCapitalization: widget.textCapitalization,
            onEditingComplete: () {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, value);
              }
            },
            textAlign: widget.textAlign,
          ),
        ),
        actions: <Widget>[
          OutlinedButton(
            onPressed: () => Navigator.pop(context, null),
            child: (widget.textCancel != null)
                ? widget.textCancel!
                : const Text("Cancel"),
          ),
          OutlinedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, value);
              }
            },
            child: (widget.textOK != null) ? widget.textOK! : const Text("OK"),
          ),
        ],
      ),
    );
  }
}
