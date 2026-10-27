import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';

/// Material Symbols Rounded glyph rendered from the [NoxIcons] SVG registry
/// (the icons ship `fill="currentColor"`, so the tint is applied via a
/// [ColorFilter]). Outlined vs filled = the SVG variant the caller passes
/// (e.g. `NoxIcons.forum` vs `NoxIcons.forumFill`) — there is no numeric fill
/// axis. Default color is `onSurfaceVariant`. Source: primitives.md `NoxIcon`.
class AppIconWidget extends StatelessWidget {
  const AppIconWidget(this.icon, {super.key, this.size, this.color});

  final SvgGenImage icon;

  /// Render size; null falls back to `icon.xl` (24) — a token getter can't be a
  /// const default.
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dimension = size ?? AppDimensionTokens.icon.xl;
    final resolved = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return icon.svg(width: dimension, height: dimension, colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn));
  }
}
