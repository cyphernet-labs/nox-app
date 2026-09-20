@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/media/app_video_player_widget.dart';

import '../../../utils/golden.dart';

/// The state a golden can pin deterministically. A real controller needs a
/// platform channel the test host does not answer, so what renders here is the
/// refusal — and that is the state worth locking: a file that arrives whole and
/// still cannot be played has to read as a sentence about the file, not as a
/// blank rectangle where a picture should be.
void main() {
  goldenTest(
    'app_video_player_widget_unplayable',
    () => const Padding(
      padding: EdgeInsets.all(16),
      child: AppVideoPlayerWidget(localPath: '/no/such/clip.mp4'),
    ),
    settle: false,
  );
}
