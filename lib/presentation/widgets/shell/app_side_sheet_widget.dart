import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';

/// Desktop right side-sheet (5.4 chat card / chat info drawer, corpus `09-drawer`):
/// a fixed-width panel that slides in from the right over a scrim. Mobile uses a
/// full-screen push instead, so this is desktop-only. Built on `showGeneralDialog`
/// so it overlays the whole window (the thread pane lives inside the 5.1 list-detail).
Future<T?> showRightSideSheet<T>(BuildContext context, {required Widget child, double? width}) {
  final colorScheme = Theme.of(context).colorScheme;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: colorScheme.scrim.withValues(alpha: 0.5),
    transitionDuration: NoxDuration.sheet,
    pageBuilder: (context, animation, secondaryAnimation) => Align(
      alignment: Alignment.centerRight,
      child: AppSideSheetPanel(width: width, child: child),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final offset = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: NoxEasing.emphasizedDecelerate));
      return SlideTransition(position: offset, child: child);
    },
  );
}

/// The right side-sheet panel surface (fixed width, full height, elevated `surface`).
/// Shared by [showRightSideSheet] (the desktop overlay) and the standalone desktop
/// preview of the chat card so the panel chrome is defined once.
class AppSideSheetPanel extends StatelessWidget {
  const AppSideSheetPanel({super.key, required this.child, this.width});

  final Widget child;

  /// Null falls back to `layout.sideSheetW` (380) — a token getter can't be a const default.
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: NoxElevation.level5,
      child: SizedBox(
        width: width ?? AppDimensionTokens.layout.sideSheetW,
        height: double.infinity,
        child: SafeArea(child: child),
      ),
    );
  }
}
