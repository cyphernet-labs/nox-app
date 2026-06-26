import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Transient feedback (§9.11). The neutral palette + float behavior come from
/// `snackBarTheme` (nox_component_themes.dart); only the error variant overrides
/// to `errorContainer`/`onErrorContainer`. [text] must already be translated
/// (never raw exception text). Source: nox_scaffold.dart `showNoxSnackBar`.
void showAppSnackBar(BuildContext context, {required String text, String? actionLabel, VoidCallback? onAction, bool error = false}) {
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: error ? colorScheme.errorContainer : null, // null → snackBarTheme.inverseSurface
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NoxRadius.xs)),
      content: error ? Text(text, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onErrorContainer)) : Text(text),
      action: actionLabel != null
          ? SnackBarAction(label: actionLabel, textColor: error ? colorScheme.onErrorContainer : null, onPressed: onAction ?? () {})
          : null,
    ),
  );
}

/// Persistent banner (offline / blocking notice): `surfaceContainer`, optional
/// leading glyph `onSurfaceVariant`, action `primary`, top of screen. The action
/// always dismisses the banner first, then runs [onAction] (if any), so a custom
/// handler can never leave the banner stuck. Source: nox_scaffold.dart `showNoxBanner`.
void showAppBanner(BuildContext context, {required String text, SvgGenImage? icon, String? actionLabel, VoidCallback? onAction}) {
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showMaterialBanner(
    MaterialBanner(
      backgroundColor: colorScheme.surfaceContainer,
      elevation: NoxElevation.level3,
      leading: icon == null ? null : AppIconWidget(icon, size: AppDimensionTokens.icon.base, color: colorScheme.onSurfaceVariant),
      content: Text(text, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface)),
      actions: [
        TextButton(
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            onAction?.call();
          },
          child: Text(actionLabel ?? TextConstants.actionDismiss),
        ),
      ],
    ),
  );
}
