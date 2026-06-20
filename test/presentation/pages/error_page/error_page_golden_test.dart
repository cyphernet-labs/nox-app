@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';

import '../../../utils/golden.dart';

Future<void> _noop() async {}

void main() {
  // The shared harness renders on the mobile design surface (360x779); the desktop
  // title-bar branch is covered by the widget test (wide surface).
  goldenTest(
    'error_page_embedded',
    () => AppErrorPage(
      params: ErrorPageParams.network(mode: ErrorPageMode.embedded, onRetry: _noop),
    ),
  );
  goldenTest('error_page_blocking', () => AppErrorPage(params: ErrorPageParams.fatal(mode: ErrorPageMode.blocking)));
}
