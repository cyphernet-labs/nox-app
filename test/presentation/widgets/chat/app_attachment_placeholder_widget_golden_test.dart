@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_attachment_placeholder_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_attachment_placeholder_widget',
    () => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // The bubble-sized box a received picture occupies while its bytes are
        // still coming - the state that used to be an inert type chip.
        const AppAttachmentPlaceholderWidget(name: 'holiday.png'),
        const SizedBox(height: 16),
        // The composer-sized square, for the same widget at the other size it
        // is asked for.
        const AppAttachmentPlaceholderWidget(name: 'shot.png', width: 72, height: 72),
      ],
    ),
    // The spinner never settles.
    settle: false,
  );
}
