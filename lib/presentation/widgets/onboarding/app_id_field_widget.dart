import 'package:flutter/material.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// The mono, multi-line identifier input (Login 2.1) with a suffix `Paste` action.
/// Open text (no mask), grows by height as the long ID wraps; there is NO client
/// format validation (FR-011) — the field accepts any input. Submit is the page's
/// `Sign in` button (a multi-line field cannot submit on Enter).
class AppIdFieldWidget extends StatelessWidget {
  const AppIdFieldWidget({
    super.key,
    required this.controller,
    required this.canPaste,
    required this.onPaste,
    this.onChanged,
    this.errorText,
    this.enabled = true,
  });

  final TextEditingController controller;

  /// Clipboard has text → `Paste` enabled.
  final bool canPaste;
  final VoidCallback onPaste;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      minLines: 1,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: AppTextStyleTokens.monoBody(color: colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: TextConstants.loginIdLabel,
        hintText: TextConstants.loginIdHint,
        errorText: errorText,
        errorMaxLines: 2,
        suffixIcon: IconButton(
          tooltip: TextConstants.actionPaste,
          onPressed: canPaste ? onPaste : null,
          icon: AppIconWidget(NoxIcons.contentPaste),
        ),
      ),
    );
  }
}
