import 'package:flutter/material.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_opacity.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// The disabled invite action carried by both chat headers (5.2).
///
/// One widget rather than two copies. The mobile AppBar and the desktop
/// ThreadHeader show the same control, and hand-copying it is how the two widths
/// drift apart — a changed label or a changed glyph lands on one and not the
/// other, and only one of them has a test.
///
/// Disabled rather than absent, and silent rather than erroring: a missing
/// control answers "how do I add someone?" with silence, an error answers it
/// with a fault, and the truth is that the relay it needs does not exist yet.
///
/// Dimmed by hand because [AppIconWidget] paints its own colour filter and never
/// consults `IconTheme` — a null `onPressed` alone leaves the glyph at full
/// strength, identical to the live action beside it.
///
/// The glyph is the kit's own `add` rather than a person-add invented here: a
/// dedicated one belongs to the design corpus, and a control this provisional
/// has not earned an asset.
class AppInviteSeamActionWidget extends StatelessWidget {
  const AppInviteSeamActionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: null,
      // The name alone, as the Copy table pins it. The caption that says it
      // comes later lives under the button in the chat card, where there is room
      // for it; a disabled control is already announced as unavailable.
      tooltip: context.l10n.chatInvitePerson,
      icon: AppIconWidget(NoxIcons.add, color: colorScheme.onSurfaceVariant.withValues(alpha: NoxOpacity.disabled)),
    );
  }
}
