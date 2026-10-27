import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/nox_opacity.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/presentation/widgets/primitives/app_avatar_widget.dart';

/// A generated [AppAvatarWidget] wrapped in the subtle ring every NOX avatar
/// carries (design: `0 0 0 2px onSurface@0.06`) — a circular `boxShadow` at the
/// `border.thick` spread. The single source for the chat-row, chat-card-header and
/// account (mobile app-bar + desktop rail) avatars. [initials] overrides the
/// name-derived initials (used by account avatars via `noxAccountInitials`); leave
/// null for chat avatars, which derive their own from [name].
class AppRingedAvatarWidget extends StatelessWidget {
  const AppRingedAvatarWidget({super.key, required this.name, required this.size, this.initials});

  final String name;
  final double size;
  final String? initials;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: colorScheme.onSurface.withValues(alpha: NoxOpacity.ring),
            spreadRadius: AppDimensionTokens.border.thick,
          ),
        ],
      ),
      child: AppAvatarWidget(name: name, initials: initials, size: size),
    );
  }
}
