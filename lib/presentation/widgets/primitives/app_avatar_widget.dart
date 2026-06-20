import 'package:flutter/material.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Generated chat avatar: deterministic background from the name hash, white
/// initials, or a white `forum` glyph fallback when there are no valid initials.
/// Always a circle. Source: primitives.md `NoxAvatar` (+ noxAvatarColor/noxInitials).
class AppAvatarWidget extends StatelessWidget {
  const AppAvatarWidget({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final background = noxAvatarColor(name);
    final initials = noxInitials(name);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: initials != null
          ? Text(
              initials,
              // Initials are brand-fixed white at ~40% of the avatar size (spec).
              style: textTheme.titleMedium?.copyWith(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.w500, height: 1),
            )
          : AppIconWidget(NoxIcons.forumFill, size: size * 0.5, color: Colors.white),
    );
  }
}
