import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// Labeled single-line input with a built-in counter, helper / error text and an
/// optional suffix availability spinner. The input-field family member used by
/// Set username (2.3, maxLength 32) and Create chat (6.1, maxLength 64). Borders,
/// counter and helper styling come from the themed `noxInputDecorationTheme`.
class AppLabeledFieldWidget extends StatelessWidget {
  const AppLabeledFieldWidget({
    super.key,
    required this.controller,
    required this.label,
    required this.maxLength,
    this.focusNode,
    this.helperText,
    this.placeholder,
    this.errorText,
    this.checking = false,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final int maxLength;
  final String? helperText;
  final String? placeholder;
  final String? errorText;

  /// Shows the suffix spinner (Checking-availability).
  final bool checking;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      maxLength: maxLength,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: InputDecoration(
        labelText: label,
        hintText: placeholder,
        helperText: helperText,
        helperMaxLines: 2,
        errorText: errorText,
        errorMaxLines: 2,
        suffixIcon: checking ? Padding(padding: EdgeInsets.all(AppSpacingTokens.s12), child: const AppSpinnerWidget(size: 18)) : null,
      ),
    );
  }
}
