@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_invite_card_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // The widget had no baseline at all, which is why `Copy` could be added beside
  // `Hide` without a single pixel moving in the suite. A fixed link, so the QR is
  // the same modules every run.
  goldenTest(
    'app_invite_card_widget',
    () => const AppInviteCardWidget(
      link: 'https://nox.app/p/#AQHAqAF0H5Bu9MxFvebDjR3m5IXKoY5in1tvLC3A_q4eLtiegalexq6xJeRSWnT-Aa6tOIPffos',
      message: 'Scan this from the other device. The link works for 10 minutes.',
      onDismiss: _noop,
    ),
  );
}

void _noop() {}
