@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';

import '../../../utils/golden.dart';

Future<void> _noop() async {}

void main() {
  // Mobile design surface (360x779) + the desktop `_wide` branch (window title bar).
  goldenTest(
    'error_page_embedded',
    () => AppErrorPage(
      params: ErrorPageParams.network(mode: ErrorPageMode.embedded, onRetry: _noop),
    ),
  );
  goldenTestDesktop(
    'error_page_embedded',
    () => AppErrorPage(
      params: ErrorPageParams.network(mode: ErrorPageMode.embedded, onRetry: _noop),
    ),
  );
  goldenTest('error_page_blocking', () => AppErrorPage(params: ErrorPageParams.fatal(mode: ErrorPageMode.blocking)));
  goldenTestDesktop('error_page_blocking', () => AppErrorPage(params: ErrorPageParams.fatal(mode: ErrorPageMode.blocking)));
}
