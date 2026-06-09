// NOX · scaffold — shell-level widgets: bottom bar + docked FAB,
// the brand-splash hairline under app bars, snackbar/banner helpers.
// Hand-written to match src/m3.jsx + src/chats-parts.jsx.
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'nox_primitives.dart';
import 'nox_tokens.dart';

// ─────────────────────────────────────────────────────────────
// Brand-splash hairline — the C-direction signature. A 3dp gradient
// rule under the app bar. Put it directly below an AppBar (mobile:
// under each app bar; desktop: once under the title bar).
// Source: src/m3.jsx <AppBar> splash rule.
// ─────────────────────────────────────────────────────────────
class NoxSplashHairline extends StatelessWidget implements PreferredSizeWidget {
  const NoxSplashHairline({super.key});

  static const _gradient = LinearGradient(colors: [
    Color(0xFF12B4B4), // teal
    Color(0xFF8FA50C), // lime
    Color(0xFFF4C20C), // gold
    Color(0xFFFB7A12), // coral
    Color(0xFFE11D1D), // red
  ]);

  @override
  Size get preferredSize => const Size.fromHeight(3 + 14);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          NoxSpacing.s4, 0, NoxSpacing.s4, 14),
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          gradient: _gradient,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// Wordmark "NOX" for the chats app bar title.
// Source: src/m3.jsx <AppBar wordmark>.
class NoxWordmark extends StatelessWidget {
  const NoxWordmark({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      'NOX',
      style: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.12 * 22, // +0.12em
        color: color ?? cs.onSurface,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// NoxBottomBar — bottom app bar with a circular notch cradling a
// docked FAB (4.1 §9.1). Two tabs (Chats / Settings); the FAB "+"
// is an action visible on both, not a third tab.
// Use as Scaffold.bottomNavigationBar + Scaffold.floatingActionButton
// with FloatingActionButtonLocation.centerDocked.
// Source: src/chats-parts.jsx <BottomBar>.
// ─────────────────────────────────────────────────────────────
enum NoxTab { chats, settings }

class NoxBottomBar extends StatelessWidget {
  const NoxBottomBar({super.key, required this.active, required this.onSelect});
  final NoxTab active;
  final ValueChanged<NoxTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BottomAppBar(
      color: cs.surfaceContainer,
      elevation: NoxElevation.level2,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      height: 64,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: _Tab(
              icon: Symbols.forum,
              label: 'Chats',
              selected: active == NoxTab.chats,
              onTap: () => onSelect(NoxTab.chats),
            ),
          ),
          const SizedBox(width: 72), // notch gap for the FAB
          Expanded(
            child: _Tab(
              icon: Symbols.settings,
              label: 'Settings',
              selected: active == NoxTab.settings,
              onTap: () => onSelect(NoxTab.settings),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    return InkResponse(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          NoxIcon(icon, size: 24, color: color, fill: selected ? 1 : 0),
          const SizedBox(height: 3),
          Text(label, style: tt.labelMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}

// The docked "+" FAB that cradles into the notch.
// Source: src/chats-parts.jsx FAB inside <BottomBar>.
class NoxCreateFab extends StatelessWidget {
  const NoxCreateFab({super.key, this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      elevation: NoxElevation.level3,
      shape: const CircleBorder(),
      child: NoxIcon(Symbols.add, size: 26, color: cs.onPrimaryContainer),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Feedback helpers.
// Snackbar (§9.11): neutral = inverseSurface; error = errorContainer.
// Floats above the bottom bar / FAB. One optional action.
// Source: src/chats-parts.jsx <Snackbar>.
// ─────────────────────────────────────────────────────────────
void showNoxSnackBar(
  BuildContext context, {
  required String text,
  String? actionLabel,
  VoidCallback? onAction,
  bool error = false,
}) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  final bg = error ? cs.errorContainer : cs.inverseSurface;
  final fg = error ? cs.onErrorContainer : cs.onInverseSurface;
  final act = error ? cs.onErrorContainer : cs.inversePrimary;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoxRadius.xs)),
      content: Text(text, style: tt.bodyMedium?.copyWith(color: fg)),
      action: (actionLabel != null)
          ? SnackBarAction(
              label: actionLabel, textColor: act, onPressed: onAction ?? () {})
          : null,
    ),
  );
}

// MaterialBanner (persistent / offline). surfaceContainer, top of
// screen, action in primary. Source: src/chats-parts.jsx <MaterialBanner>.
void showNoxBanner(
  BuildContext context, {
  required String text,
  IconData icon = Symbols.wifi_off,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  ScaffoldMessenger.of(context).showMaterialBanner(
    MaterialBanner(
      backgroundColor: cs.surfaceContainer,
      elevation: NoxElevation.level3,
      leading: NoxIcon(icon, size: 22, color: cs.onSurfaceVariant),
      content: Text(text, style: tt.bodyMedium?.copyWith(color: cs.onSurface)),
      actions: [
        TextButton(
          onPressed: onAction ??
              () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
          child: Text(actionLabel ?? 'Dismiss',
              style: tt.labelLarge?.copyWith(color: cs.primary)),
        ),
      ],
    ),
  );
}
