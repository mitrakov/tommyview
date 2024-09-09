// ignore_for_file: use_key_in_widget_constructors, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// https://stackoverflow.com/a/78104804/2212849
class MyListView extends StatefulWidget {
  final List<String> items;
  final ValueChanged<String> onSelect;

  const MyListView(this.items, this.onSelect);

  @override
  _MyListViewState createState() => _MyListViewState();
}

class _MyListViewState extends State<MyListView> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    focus = List.generate(widget.items.length, (index) => FocusNode());
    _previousAction = _CallbackAction<PreviousIntent>(onInvoke: handlePreviousKeyPress);
    _nextAction =     _CallbackAction<NextIntent>    (onInvoke: handleNextKeyPress);
    _selectAction =   _CallbackAction<SelectIntent>  (onInvoke: handleSelectKeyPress);
  }

  void handlePreviousKeyPress(PreviousIntent intent) {
    if (selected == null) return;
    if (selected! > 0) {
      selected = selected! - 1;
      focus[selected!].requestFocus();
    }
  }

  void handleNextKeyPress(NextIntent intent) {
    if (selected == null) {
      selected = 0;
      focus[selected!].requestFocus();
      return;
    }
    if (selected! < widget.items.length - 1) {
      selected = selected! + 1;
      if (selected! < focus.length)
        focus[selected!].requestFocus();
    }
  }

  void handleSelectKeyPress(SelectIntent intent) {
    if (selected != null) {
      widget.onSelect(widget.items[selected!]);
    }
  }

  int? selected;
  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  late final _CallbackAction<PreviousIntent> _previousAction;
  late final _CallbackAction<NextIntent> _nextAction;
  late final _CallbackAction<SelectIntent> _selectAction;
  List<FocusNode> focus = [];
  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.arrowDown): NextIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowUp):   PreviousIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter):     SelectIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape):    UnFocusIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          NextIntent: _nextAction,
          PreviousIntent: _previousAction,
          SelectIntent: _selectAction,
        },
        child: Focus(
          autofocus: true,
          focusNode: _focusNode,
          child: ListView.builder(
            itemCount: widget.items.length, // Change this to the number of items in your list
            itemBuilder: (context, index) {
              return ListTile(
                focusNode: index < focus.length ? focus[index] : FocusNode(),
                tileColor: selected == index ? Colors.blue : null, // Change the color for the focused item
                title: Text(widget.items[index]),
                onTap: () {
                  // Handle item tap
                },
                onFocusChange: (hasFocus) {
                  if (hasFocus) {
                    _focusNode.debugLabel = index.toString();
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CallbackAction<T extends Intent> extends CallbackAction<T> {
  _CallbackAction({required void Function(T) onInvoke}) : super(onInvoke: onInvoke);
}
class NextIntent extends Intent {} // action to move to the next suggestion
class PreviousIntent extends Intent {} // action to move to the previous suggestion
class SelectIntent extends Intent {} // action to select the suggestion
class UnFocusIntent extends Intent {} // action to hide the suggestions
