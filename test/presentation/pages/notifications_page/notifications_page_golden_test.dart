@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/notifications_page/notifications_page.dart';

import '../../../utils/golden.dart';

void main() {
  // Default (granted) state — the denied banner is covered by the widget test.
  goldenTest('notifications_page', () => const NotificationsPage());
}
