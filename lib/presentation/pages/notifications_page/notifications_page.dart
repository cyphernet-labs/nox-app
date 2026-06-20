import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/widgets/app_theme_toggle.dart';
import 'package:nox_app/presentation/widgets/settings/app_info_banner_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_switch_row_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

/// Mocked OS push-permission state (real query/prompt is backend phase).
enum _PermissionStatus { granted, denied }

/// 7.2 Notifications — a single push on/off switch (push only for "own" chats) plus
/// a denied-permission banner that deep-links to system settings. No own BLoC
/// (UI-first exception, blueprint 05 §5.1). A dev control toggles the mocked
/// permission while previewing.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const NotificationsPage(),
    settings: const RouteSettings(name: '/settings/notifications'),
  );

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _enabled = true;
  // TODO(backend): real OS permission query + persistence + "own chats" push scope.
  _PermissionStatus _permission = _PermissionStatus.granted;

  bool get _granted => _permission == _PermissionStatus.granted;

  @override
  Widget build(BuildContext context) {
    return AppDetailScaffoldWidget(
      title: TextConstants.settingsNotificationsTitle,
      actions: const [AppThemeToggle()],
      body: ListView(
        children: [
          if (!_granted)
            AppInfoBannerWidget(
              icon: NoxIcons.error,
              message: TextConstants.notificationsDeniedMessage,
              actionLabel: TextConstants.actionOpenSettings,
              onAction: () {}, // TODO(backend): deep-link to system settings (app_settings plugin)
            ),
          AppSettingsSwitchRowWidget(
            title: TextConstants.notificationsPushTitle,
            supportingText: TextConstants.notificationsPushSubtitle,
            value: _granted && _enabled,
            onChanged: _granted ? (value) => setState(() => _enabled = value) : null,
          ),
          const Divider(height: 1),
          _PermissionDevControl(status: _permission, onChanged: (status) => setState(() => _permission = status)),
        ],
      ),
    );
  }
}

/// Dev-only control to flip the mocked OS permission while previewing.
class _PermissionDevControl extends StatelessWidget {
  const _PermissionDevControl({required this.status, required this.onChanged});

  final _PermissionStatus status;
  final ValueChanged<_PermissionStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('System permission (preview)', style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
          SizedBox(height: AppSpacingTokens.s8),
          SegmentedButton<_PermissionStatus>(
            segments: const [
              ButtonSegment<_PermissionStatus>(value: _PermissionStatus.granted, label: Text('Granted')),
              ButtonSegment<_PermissionStatus>(value: _PermissionStatus.denied, label: Text('Denied')),
            ],
            selected: {status},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ],
      ),
    );
  }
}
