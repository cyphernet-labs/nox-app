import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nox_app/presentation/widgets/primitives/app_hairline_divider_widget.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/service/notification_permission_service.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/helpers/app_feedback_helper.dart';
import 'package:nox_app/presentation/widgets/settings/app_info_banner_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_group_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_switch_row_widget.dart';

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
  // Real OS notification-permission (P5), queried on open; the push SCOPE ("own chats")
  // still lands in the backend phase.
  NotificationPermissionStatus _permission = NotificationPermissionStatus.granted;

  bool get _granted => _permission == NotificationPermissionStatus.granted;

  @override
  void initState() {
    super.initState();
    _loadEnabled();
    _loadPermission();
  }

  Future<void> _loadPermission() async {
    final status = await notificationPermissionService.status();
    if (mounted) setState(() => _permission = status);
  }

  Future<void> _loadEnabled() async {
    final result = await settingsRepository.readNotificationsEnabled();
    result.match<void>(
      onData: (value) {
        if (mounted) setState(() => _enabled = value);
      },
      onError: (_) {},
    );
  }

  // Optimistic toggle: persist, and on a save failure revert the switch and show the
  // "Could not save. Try again." notice.
  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    final result = await settingsRepository.setNotificationsEnabled(value);
    result.match<void>(
      onData: (_) {},
      onError: (_) {
        if (!mounted) return;
        setState(() => _enabled = !value);
        showAppSnackBar(context, text: context.l10n.settingsSaveError, error: true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        if (!_granted)
          AppInfoBannerWidget(
            icon: NoxIcons.notificationsOff,
            title: context.l10n.notificationsDeniedTitle,
            message: context.l10n.notificationsDeniedMessage,
            actionLabel: context.l10n.actionOpenSettings,
            onAction: () => notificationPermissionService.openSettings(),
          ),
        AppSettingsGroupWidget(
          children: [
            AppSettingsSwitchRowWidget(
              leadingIcon: NoxIcons.notifications,
              title: context.l10n.notificationsPushTitle,
              supportingText: context.l10n.notificationsPushSubtitle,
              value: _granted && _enabled,
              onChanged: _granted ? _setEnabled : null,
            ),
          ],
        ),
        // Dev-only override to preview the denied state (real OS permission is queried on
        // open); the push SCOPE ("own chats") still lands in the backend phase.
        if (kDebugMode) const AppHairlineDividerWidget(),
        if (kDebugMode) _PermissionDevControl(status: _permission, onChanged: (status) => setState(() => _permission = status)),
      ],
    );
  }
}

/// Dev-only control to flip the OS-permission preview while designing.
class _PermissionDevControl extends StatelessWidget {
  const _PermissionDevControl({required this.status, required this.onChanged});

  final NotificationPermissionStatus status;
  final ValueChanged<NotificationPermissionStatus> onChanged;

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
          SegmentedButton<NotificationPermissionStatus>(
            segments: const [
              ButtonSegment<NotificationPermissionStatus>(value: NotificationPermissionStatus.granted, label: Text('Granted')),
              ButtonSegment<NotificationPermissionStatus>(value: NotificationPermissionStatus.denied, label: Text('Denied')),
            ],
            selected: {status},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ],
      ),
    );
  }
}
