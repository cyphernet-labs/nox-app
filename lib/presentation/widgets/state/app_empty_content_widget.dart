import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';

/// Empty-list state: a real brand illustration (`Assets.svg.illustrations.*`) +
/// headline + message. Source: primitives.md `NoxEmptyState` (illustration swapped
/// in from the bundled SVG set per FR-008).
class AppEmptyContentWidget extends StatelessWidget {
  const AppEmptyContentWidget({super.key, required this.illustration, required this.title, required this.message});

  final SvgGenImage illustration;
  final String title;
  final String message;

  static const double _artSize = 132;
  static const double _messageMaxWidth = 260;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            illustration.svg(width: _artSize, height: _artSize),
            SizedBox(height: AppSpacingTokens.s14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(color: colorScheme.onSurface),
            ),
            SizedBox(height: AppSpacingTokens.s14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _messageMaxWidth),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
