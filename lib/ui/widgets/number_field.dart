import 'package:flutter/material.dart';

/// A numeric text field that reports its value when editing finishes.
///
/// Settings are persisted and the reminder schedule is rebuilt on every save,
/// so committing on focus loss rather than on each keystroke keeps typing a
/// weight from firing a dozen writes.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
    this.helper,
    this.decimals = 1,
    this.allowEmpty = false,
    this.onCleared,
  });

  final String label;
  final double? value;
  final ValueChanged<double> onChanged;
  final String? suffix;
  final String? helper;
  final int decimals;

  /// When true an empty field is valid and reports through [onCleared].
  final bool allowEmpty;
  final VoidCallback? onCleared;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    // Only adopt an external change while the user is not typing into it.
    if (!_focus.hasFocus && widget.value != old.value) {
      _controller.text = _format(widget.value);
    }
  }

  String _format(double? v) {
    if (v == null) return '';
    final String s = v.toStringAsFixed(widget.decimals);
    if (widget.decimals > 0 && s.endsWith('.${'0' * widget.decimals}')) {
      return s.substring(0, s.length - widget.decimals - 1);
    }
    return s;
  }

  void _onFocusChange() {
    if (_focus.hasFocus) return;
    _commit();
  }

  void _commit() {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      if (widget.allowEmpty) {
        widget.onCleared?.call();
      } else {
        _controller.text = _format(widget.value);
      }
      return;
    }
    final double? parsed = double.tryParse(text);
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }
    widget.onChanged(parsed);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffix,
        helperText: widget.helper,
        helperMaxLines: 3,
      ),
    );
  }
}
