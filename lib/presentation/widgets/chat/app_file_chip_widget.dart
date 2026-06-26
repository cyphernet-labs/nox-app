import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';

/// Attachment chip (§9.7): type icon + name (ellipsis) + size. Standalone →
/// `surfaceContainerHighest`; inside a bubble (`inBubble: true, onColor: <bubble
/// text>`) → tint derived from the bubble text color. Optional remove ×.
/// Source: `NoxFileChip`.
class AppFileChipWidget extends StatelessWidget {
  const AppFileChipWidget({
    super.key,
    required this.type,
    required this.name,
    required this.size,
    this.inBubble = false,
    this.onColor,
    this.removable = false,
    this.onRemove,
  });

  final FileType type;
  final String name;
  final String size; // pre-formatted, e.g. "2.4 MB"
  final bool inBubble;
  final Color? onColor; // bubble text color when inBubble
  final bool removable;
  final VoidCallback? onRemove;

  static double get _iconSize => AppDimensionTokens.icon.xxl;
  static double get _removeIconSize => AppDimensionTokens.icon.lg;
  static const double _minWidth = 200;
  static const double _maxWidth = 260;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final on = onColor ?? colorScheme.onPrimaryContainer;
    final background = inBubble ? on.withValues(alpha: 0.12) : colorScheme.surfaceContainerHighest;
    final foreground = inBubble ? on : colorScheme.onSurface;
    final sub = inBubble ? on.withValues(alpha: 0.7) : colorScheme.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(minWidth: _minWidth, maxWidth: _maxWidth),
      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s12, vertical: AppSpacingTokens.s10),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(NoxRadius.xs)),
      child: Row(
        children: [
          AppIconWidget(noxFileIcon(type), size: _iconSize, color: sub),
          SizedBox(width: AppSpacingTokens.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(color: foreground),
                ),
                Text(size, style: textTheme.bodyMedium?.copyWith(color: sub)),
              ],
            ),
          ),
          if (removable)
            IconButton(
              onPressed: onRemove,
              tooltip: TextConstants.tooltipRemove,
              icon: AppIconWidget(NoxIcons.close, size: _removeIconSize, color: colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
