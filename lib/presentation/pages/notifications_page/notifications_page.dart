import 'package:flutter/material.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_body.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

/// 7.2 Notifications — a single push on/off switch (push only for "own" chats) plus
/// a denied-permission banner that deep-links to system settings. No own BLoC
/// (UI-first exception, blueprint 05 §5.1). Content lives in [NotificationsBody] so
/// it can also fill the desktop Settings list-detail pane (7.1).
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const NotificationsPage(),
    settings: const RouteSettings(name: '/settings/notifications'),
  );

  @override
  Widget build(BuildContext context) {
    return AppDetailScaffoldWidget(title: TextConstants.settingsNotificationsTitle, body: const NotificationsBody());
  }
}
