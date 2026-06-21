import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

/// Desktop two-pane list-detail container (4.1 §desktop): a fixed-width list pane
/// on the left, a vertical divider, and an expanded detail pane on the right.
/// Selecting a row in [listPane] swaps [detailPane] in place — there is NO
/// Navigator push (the caller holds the selection state and rebuilds the detail).
/// Used by 5.1 (chat list pane + thread pane) and 7.1 (settings menu pane +
/// detail pane). Row highlight (`secondaryContainer`) lives on the list-pane item.
class AppListDetailWidget extends StatelessWidget {
  const AppListDetailWidget({super.key, required this.listPane, required this.detailPane, this.listPaneWidth = 360});

  final Widget listPane;
  final Widget detailPane;

  /// 5.1 = 360, 7.1 = 340 (per the desktop corpus).
  final double listPaneWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: listPaneWidth, child: listPane),
        const VerticalDivider(width: 1),
        Expanded(child: detailPane),
      ],
    );
  }
}

/// No-selection / empty-detail placeholder for the detail pane (e.g. 5.1
/// "Select a chat", or the M4 thread placeholder). Centered title + message
/// capped to a readable width.
class AppDetailEmptyWidget extends StatelessWidget {
  const AppDetailEmptyWidget({super.key, required this.title, required this.message});

  final String title;
  final String message;

  static const double _maxWidth = 320;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Padding(
          padding: EdgeInsets.all(AppSpacingTokens.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacingTokens.s8),
              Text(
                message,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
