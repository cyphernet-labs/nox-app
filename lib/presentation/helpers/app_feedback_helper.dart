import 'package:flutter/material.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Transient feedback (§9.11): neutral = `inverseSurface`/`onInverseSurface`,
/// action `inversePrimary`; error = `errorContainer`/`onErrorContainer`. Floats
/// above the bottom bar / FAB. [text] must already be translated (never raw
/// exception text). Source: nox_scaffold.dart `showNoxSnackBar`.
void showAppSnackBar(BuildContext context, {required String text, String? actionLabel, VoidCallback? onAction, bool error = false}) {
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  final background = error ? colorScheme.errorContainer : colorScheme.inverseSurface;
  final foreground = error ? colorScheme.onErrorContainer : colorScheme.onInverseSurface;
  final actionColor = error ? colorScheme.onErrorContainer : colorScheme.inversePrimary;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: background,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NoxRadius.xs)),
      content: Text(text, style: textTheme.bodyMedium?.copyWith(color: foreground)),
      action: actionLabel != null ? SnackBarAction(label: actionLabel, textColor: actionColor, onPressed: onAction ?? () {}) : null,
    ),
  );
}

/// Persistent banner (offline / blocking notice): `surfaceContainer`, leading
/// glyph `onSurfaceVariant`, action `primary`, top of screen. Source:
/// nox_scaffold.dart `showNoxBanner`. (Default leading uses the universal alert
/// glyph — there is no dedicated wifi-off SVG in the bundled set yet.)
void showAppBanner(BuildContext context, {required String text, SvgGenImage? icon, String? actionLabel, VoidCallback? onAction}) {
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showMaterialBanner(
    MaterialBanner(
      backgroundColor: colorScheme.surfaceContainer,
      elevation: NoxElevation.level3,
      leading: AppIconWidget(icon ?? NoxIcons.error, size: 22, color: colorScheme.onSurfaceVariant),
      content: Text(text, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface)),
      actions: [
        TextButton(onPressed: onAction ?? messenger.hideCurrentMaterialBanner, child: Text(actionLabel ?? TextConstants.actionDismiss)),
      ],
    ),
  );
}
