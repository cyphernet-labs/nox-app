import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// The mono, multi-line identifier input (Login 2.1) — a fixed ~120dp paste-target
/// box with a TOP-right `Paste` action (aligned with the label / first line, not
/// vertically centred). Open text (no mask), no client format validation (FR-011) —
/// the field accepts any input and scrolls internally for a very long ID. A definite
/// height (via `expands`) keeps it a clean box on both mobile and desktop and stops
/// an auto-growing field from ballooning to fill a loose-height parent (e.g. the
/// desktop OnboardCard's scroll view). Submit is the page's `Sign in` button.
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
    final textTheme = Theme.of(context).textTheme;
    final hasError = errorText != null;
    // M3 error outline driven manually: the message renders below the fixed-height
    // box (the Column child), so the field can't use InputDecoration.errorText (it
    // would overflow the SizedBox) — colour the border on error instead.
    OutlineInputBorder errorBorder(double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDimensionTokens.radius.xs),
      borderSide: BorderSide(color: colorScheme.error, width: width),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: AppDimensionTokens.size.idFieldH,
          // Stack so the Paste button sits at the TOP-right (a multiline/`expands`
          // field would otherwise vertically-centre a `suffixIcon`). The field's
          // right content padding reserves the icon column so wrapped text clears it.
          child: Stack(
            children: [
              TextField(
                controller: controller,
                enabled: enabled,
                onChanged: onChanged,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: AppTextStyleTokens.monoBody(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: context.l10n.loginIdLabel,
                  hintText: context.l10n.loginIdHint,
                  alignLabelWithHint: true,
                  contentPadding: EdgeInsets.fromLTRB(
                    AppSpacingTokens.s12,
                    AppSpacingTokens.s16,
                    AppSpacingTokens.s48,
                    AppSpacingTokens.s12,
                  ),
                  enabledBorder: hasError ? errorBorder(AppDimensionTokens.border.regular) : null,
                  focusedBorder: hasError ? errorBorder(AppDimensionTokens.border.thick) : null,
                ),
              ),
              Positioned(
                top: AppSpacingTokens.s4,
                right: AppSpacingTokens.s4,
                child: IconButton(
                  tooltip: context.l10n.actionPaste,
                  // Also gate on `enabled`: during an in-flight sign-in a Paste tap
                  // would dispatch IdChanged, reset the loading state and let a second
                  // concurrent signIn start.
                  onPressed: (enabled && canPaste) ? onPaste : null,
                  icon: AppIconWidget(NoxIcons.contentPaste),
                ),
              ),
            ],
          ),
        ),
        if (errorText != null)
          Padding(
            padding: EdgeInsets.only(top: AppSpacingTokens.s8, left: AppSpacingTokens.s12),
            // liveRegion so assistive tech announces the error when it appears (the
            // message is a sibling of the field, not its InputDecoration.errorText).
            child: Semantics(
              liveRegion: true,
              child: Text(errorText!, maxLines: 2, style: textTheme.bodySmall?.copyWith(color: colorScheme.error)),
            ),
          ),
      ],
    );
  }
}
