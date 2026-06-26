import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/settings/app_info_banner_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_group_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_switch_row_widget.dart';

/// Mocked OS push-permission state (real query/prompt is backend phase).
enum NotificationsPermission { granted, denied }

/// 7.2 Notifications content — push on/off switch + denied-permission banner. No
/// Scaffold/AppBar, so it embeds in both the mobile leaf chrome (NotificationsPage)
/// and the desktop Settings list-detail pane (7.1). No own BLoC (UI-first exception).
class NotificationsBody extends StatefulWidget {
  const NotificationsBody({super.key});

  @override
  State<NotificationsBody> createState() => _NotificationsBodyState();
}

class _NotificationsBodyState extends State<NotificationsBody> {
  bool _enabled = true;
  // TODO(backend): real OS permission query + persistence + "own chats" push scope.
  NotificationsPermission _permission = NotificationsPermission.granted;

  bool get _granted => _permission == NotificationsPermission.granted;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        if (!_granted)
          AppInfoBannerWidget(
            icon: NoxIcons.notificationsOff,
            title: TextConstants.notificationsDeniedTitle,
            message: TextConstants.notificationsDeniedMessage,
            actionLabel: TextConstants.actionOpenSettings,
            onAction: () {}, // TODO(backend): deep-link to system settings (app_settings plugin)
          ),
        AppSettingsGroupWidget(
          children: [
            AppSettingsSwitchRowWidget(
              leadingIcon: NoxIcons.notifications,
              title: TextConstants.notificationsPushTitle,
              supportingText: TextConstants.notificationsPushSubtitle,
              value: _granted && _enabled,
              onChanged: _granted ? (value) => setState(() => _enabled = value) : null,
            ),
          ],
        ),
        // Dev-only permission toggle (debug builds only); real OS permission is backend phase.
        if (kDebugMode) Divider(height: AppDimensionTokens.border.hairline),
        if (kDebugMode) _PermissionDevControl(status: _permission, onChanged: (status) => setState(() => _permission = status)),
      ],
    );
  }
}

/// Dev-only control to flip the mocked OS permission while previewing.
class _PermissionDevControl extends StatelessWidget {
  const _PermissionDevControl({required this.status, required this.onChanged});

  final NotificationsPermission status;
  final ValueChanged<NotificationsPermission> onChanged;

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
          SegmentedButton<NotificationsPermission>(
            segments: const [
              ButtonSegment<NotificationsPermission>(value: NotificationsPermission.granted, label: Text('Granted')),
              ButtonSegment<NotificationsPermission>(value: NotificationsPermission.denied, label: Text('Denied')),
            ],
            selected: {status},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ],
      ),
    );
  }
}
