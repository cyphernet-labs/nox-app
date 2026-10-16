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
      link: 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7',
      message: 'Scan this from the other device. The link works for 10 minutes.',
      onDismiss: _noop,
    ),
  );

  // An invite whose link carries neither an onion nor a public address (phase
  // 045): the same card with one more line under the message. The card without
  // it is the baseline above and must not move.
  goldenTest(
    'app_invite_card_widget_home_only',
    () => const AppInviteCardWidget(
      link: 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7',
      message: 'Scan this from the other device. The link works for 10 minutes.',
      homeOnly: true,
      onDismiss: _noop,
    ),
  );
}

void _noop() {}
