@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/state/app_connection_indicator_widget.dart';

import '../../../utils/fixed_connection_status.dart';
import '../../../utils/golden.dart';

/// The connection corner's four states (contracts/ui-states.md), light and
/// dark. Drawn in an app bar, which is where a person meets it on the narrow
/// branch.
Widget _inAppBar(Widget indicator) => Scaffold(appBar: AppBar(actions: [indicator]));

void main() {
  goldenTest(
    'app_connection_indicator_empty',
    () => _inAppBar(const AppConnectionIndicatorWidget(wide: false, status: FixedConnectionStatusService.direct)),
  );
  goldenTest(
    'app_connection_indicator_tor',
    () => _inAppBar(const AppConnectionIndicatorWidget(wide: false, status: FixedConnectionStatusService.tor)),
  );
  goldenTest(
    'app_connection_indicator_connecting',
    () => _inAppBar(const AppConnectionIndicatorWidget(wide: false, status: FixedConnectionStatusService.connecting)),
  );
  goldenTest(
    'app_connection_indicator_connecting_tor',
    () => _inAppBar(const AppConnectionIndicatorWidget(wide: false, status: FixedConnectionStatusService.connectingTor)),
  );
}
