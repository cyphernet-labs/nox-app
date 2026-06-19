import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// The two product tabs. The central `+` (create chat) is an action, not a tab —
/// see [AppCreateFabWidget].
enum AppTab { chats, settings }

/// Bottom app bar with a circular notch cradling the docked `+` FAB (4.1 §9.1).
/// Two tabs (Chats / Settings); selected = `primary` + filled glyph. Use as
/// `Scaffold.bottomNavigationBar` with `FloatingActionButtonLocation.centerDocked`.
/// Source: nox_scaffold.dart `NoxBottomBar`.
class AppBottomBarWidget extends StatelessWidget {
  const AppBottomBarWidget({super.key, required this.active, required this.onSelect});

  final AppTab active;
  final ValueChanged<AppTab> onSelect;

  static const double _height = 64;
  // Must track the FAB diameter in AppCreateFabWidget so the notch cradles it.
  static const double _notchGap = 72;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BottomAppBar(
      color: colorScheme.surfaceContainer,
      elevation: NoxElevation.level2,
      shape: const CircularNotchedRectangle(),
      notchMargin: AppSpacingTokens.s8,
      height: _height,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: _Tab(
              outlined: NoxIcons.forum,
              filled: NoxIcons.forumFill,
              label: TextConstants.chats,
              selected: active == AppTab.chats,
              onTap: () => onSelect(AppTab.chats),
            ),
          ),
          const SizedBox(width: _notchGap),
          Expanded(
            child: _Tab(
              outlined: NoxIcons.settings,
              filled: NoxIcons.settingsFill,
              label: TextConstants.settings,
              selected: active == AppTab.settings,
              onTap: () => onSelect(AppTab.settings),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.outlined, required this.filled, required this.label, required this.selected, required this.onTap});

  final SvgGenImage outlined;
  final SvgGenImage filled;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIconWidget(selected ? filled : outlined, color: color),
            SizedBox(height: AppSpacingTokens.s2),
            Text(label, style: textTheme.labelMedium?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
