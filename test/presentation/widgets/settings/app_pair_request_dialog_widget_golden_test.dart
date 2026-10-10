@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/device/pair_request.dart';
import 'package:nox_app/presentation/widgets/settings/app_pair_request_dialog_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // The question as it is asked (phase 046): the family of the new device, Deny
  // and Allow. AppRoot shows it over whatever screen is up, on both widths. The
  // answer on its way (a spinner in the button pressed) is the widget test's.
  goldenTest(
    'app_pair_request_dialog_widget',
    () => Center(
      child: AppPairRequestDialogWidget(platform: DevicePlatform.windows, onAnswer: (_) {}),
    ),
  );
  goldenTestDesktop(
    'app_pair_request_dialog_widget',
    () => Center(
      child: AppPairRequestDialogWidget(platform: DevicePlatform.windows, onAnswer: (_) {}),
    ),
  );

  // An answer that did not get through: said under the question, both buttons
  // still there.
  goldenTest(
    'app_pair_request_dialog_widget_failed',
    () => Center(
      child: AppPairRequestDialogWidget(platform: DevicePlatform.ios, failed: true, onAnswer: (_) {}),
    ),
  );
  goldenTestDesktop(
    'app_pair_request_dialog_widget_failed',
    () => Center(
      child: AppPairRequestDialogWidget(platform: DevicePlatform.ios, failed: true, onAnswer: (_) {}),
    ),
  );
}
