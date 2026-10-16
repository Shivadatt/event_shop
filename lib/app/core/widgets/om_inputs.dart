import 'dart:async';

import 'package:flutter/material.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';

/// Text field with the brand chrome and a mandatory label. A field that relies on a hint alone
/// loses its meaning once the user types.
final class OmTextField extends StatelessWidget {
  const OmTextField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.hint,
    this.helper,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.readOnly = false,
    this.prefixIcon,
    this.suffix,
    this.autofillHints,
    this.required = false,
    this.maxLength,
    this.counterText,
    this.focusNode,
    this.expands = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final String? helper;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int? minLines;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool readOnly;
  final IconData? prefixIcon;
  final Widget? suffix;
  final List<String>? autofillHints;
  final bool required;
  final int? maxLength;
  final String? counterText;
  final FocusNode? focusNode;
  final bool expands;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      focusNode: focusNode,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: obscure ? 1 : maxLines,
      minLines: minLines,
      expands: expands,
      enabled: enabled && !readOnly,
      readOnly: readOnly,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      autofillHints: autofillHints,
      maxLength: maxLength,
      textCapitalization: switch (keyboardType) {
        TextInputType.name || TextInputType.streetAddress => TextCapitalization.words,
        TextInputType.emailAddress => TextCapitalization.none,
        _ => TextCapitalization.sentences,
      },
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        helperText: helper,
        counterText: counterText ?? '',
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: 18, color: styles.muted.color),
        suffixIcon: suffix,
      ),
    );
  }
}

/// Numeric field for quantities, rupee inputs and thresholds. Pair with [OmValidators] — the
/// keyboard type discourages non-digits, the validator is what actually rejects them.
final class OmNumberField extends StatelessWidget {
  const OmNumberField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.suffixText,
    this.min = 0,
    this.max = 999999,
    this.decimal = false,
    this.validator,
    this.onChanged,
    this.required = false,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final String? suffixText;
  final int min;
  final int max;
  final bool decimal;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool required;
  final bool enabled;

  @override
  Widget build(BuildContext context) => OmTextField(
        label: label,
        controller: controller,
        hint: hint,
        helper: helper,
        keyboardType: decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
        validator: validator,
        onChanged: onChanged,
        required: required,
        enabled: enabled,
        suffix: suffixText == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: OmSpacing.md),
                child: Text(suffixText!, style: context.omText.muted),
              ),
      );
}

/// Stepper that enforces the product's minimum quantity and order multiple. Holding the button
/// repeats, because a 200-pack carton should not need 200 taps.
final class OmQuantityStepper extends StatefulWidget {
  const OmQuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.multiple = 1,
    this.max,
    this.enabled = true,
    this.dense = false,
    this.label,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int multiple;
  final int? max;
  final bool enabled;
  final bool dense;
  final String? label;

  @override
  State<OmQuantityStepper> createState() => _OmQuantityStepperState();
}

class _OmQuantityStepperState extends State<OmQuantityStepper> {
  Timer? _repeat;

  int _clamp(int candidate) {
    var next = candidate;
    if (widget.multiple > 1) {
      final steps = (next / widget.multiple).round();
      next = steps * widget.multiple;
    }
    if (next < widget.min) next = widget.min;
    final max = widget.max;
    if (max != null && next > max) next = max;
    return next;
  }

  void _startRepeat(int delta) {
    if (!widget.enabled) return;
    _apply(widget.value + delta);
    _repeat?.cancel();
    _repeat = Timer(const Duration(milliseconds: 500), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 90), (_) {
        _apply(widget.value + delta);
      });
    });
  }

  void _apply(int candidate) {
    final next = _clamp(candidate);
    if (next == widget.value) return;
    widget.onChanged(next);
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final height = widget.dense ? 34.0 : 44.0;
    final max = widget.max;
    final canDecrease = widget.enabled && widget.value > widget.min;
    final canIncrease = widget.enabled && (max == null || widget.value < max);

    return Semantics(
      label: widget.label ?? 'Quantity ${widget.value}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _stepButton(
            icon: Icons.remove,
            onTap: canDecrease ? () => _startRepeat(-widget.multiple) : null,
            tooltip: 'Decrease quantity',
            height: height,
            isDark: isDark,
          ),
          Container(
            constraints: BoxConstraints(minWidth: widget.dense ? 44 : 56),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: OmSpacing.sm),
            child: Text(
              '${widget.value}',
              style: context.omText.bodyStrong.copyWith(
                color: isDark ? OmColors.textOnDark : OmColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          _stepButton(
            icon: Icons.add,
            onTap: canIncrease ? () => _startRepeat(widget.multiple) : null,
            tooltip: 'Increase quantity',
            height: height,
            isDark: isDark,
          ),
        ],
      ).wrapWithBorder(context, height),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required VoidCallback? onTap,
    required String tooltip,
    required double height,
    required bool isDark,
  }) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            height: height,
            width: height,
            child: Icon(
              icon,
              size: 18,
              color: onTap == null
                  ? Theme.of(context).disabledColor
                  : (isDark ? OmColors.textOnDark : OmColors.textPrimary),
            ),
          ),
        ),
      );
}

extension on Widget {
  Widget wrapWithBorder(BuildContext context, double height) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: OmRadius.smAll,
        ),
        child: SizedBox(height: height, child: this),
      );
}

final class OmDropdown<T> extends StatelessWidget {
  const OmDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    this.onChanged,
    this.itemLabel,
    this.validator,
    this.hint,
    this.enabled = true,
  });

  final String label;
  final T? value;
  final List<T> items;
  final ValueChanged<T?>? onChanged;
  final String Function(T)? itemLabel;
  final String? Function(T?)? validator;
  final String? hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        initialValue: value,
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(itemLabel?.call(item) ?? '$item'),
              ),
            )
            .toList(growable: false),
        onChanged: enabled ? onChanged : null,
        validator: validator,
        hint: hint == null ? null : Text(hint!),
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
      );
}

final class OmSwitchRow extends StatelessWidget {
  const OmSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? description;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        title: Text(label, style: context.omText.bodyStrong),
        subtitle: description == null
            ? null
            : Text(description!, style: context.omText.caption),
        contentPadding: EdgeInsets.zero,
        activeThumbColor: OmColors.gold,
      );
}
