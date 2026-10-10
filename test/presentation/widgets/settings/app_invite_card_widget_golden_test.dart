@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_invite_card_widget.dart';

import '../../../utils/golden.dart';

/// A version-3 link as the server issues one - the address it listens on, then
/// its onion address - and a fixed one, so the QR is the same modules every run.
const String _link =
    'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7BCAXy3n7K0Eg8rHsZeQZjW4Iso6BP-sB5KQAg5uF4YCAzg';

void main() {
  // The widget had no baseline at all, which is why `Copy` could be added beside
  // `Hide` without a single pixel moving in the suite.
  goldenTest(
    'app_invite_card_widget',
    () => const AppInviteCardWidget(
      link: _link,
      message: 'Scan this from the other device. The link works for 10 minutes.',
      onDismiss: _noop,
    ),
  );

  // An invite that pairs only at home - every invite until phase 045 (040,
  // FR-019): the same card with one more line under the message. The card
  // without it is the baseline above and must not move.
  goldenTest(
    'app_invite_card_widget_home_only',
    () => const AppInviteCardWidget(
      link: _link,
      message: 'Scan this from the other device. The link works for 10 minutes.',
      homeOnly: true,
      onDismiss: _noop,
    ),
  );
}

void _noop() {}
