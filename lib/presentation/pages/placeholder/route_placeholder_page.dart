import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

/// Dev placeholder for a navigation destination that does not exist yet (e.g. the
/// chats shell / login that Splash routes to during the UI-first phase). Shows the
/// intended destination label so the routing decision is observable. Replaced by
/// the real screen in a later milestone. Dev-only surface — copy is inline English
/// (same convention as the screens gallery), not product microcopy.
class RoutePlaceholderPage extends StatelessWidget {
  const RoutePlaceholderPage({super.key, required this.destinationLabel});

  final String destinationLabel;

  static Route<void> route({required String destinationLabel}) => MaterialPageRoute<void>(
    builder: (_) => RoutePlaceholderPage(destinationLabel: destinationLabel),
    settings: const RouteSettings(name: '/placeholder'),
  );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Destination')),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacingTokens.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Not built yet', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
              SizedBox(height: AppSpacingTokens.s8),
              Text(
                destinationLabel,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
