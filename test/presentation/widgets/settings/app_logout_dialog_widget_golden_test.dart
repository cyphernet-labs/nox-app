@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_logout_dialog_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // Renders the resting dialog (destructive Log out styled with the error color, Cancel).
  // The spinner/`_loading` state is exercised by the widget test, not a static golden.
  goldenTest('app_logout_dialog_widget', () => const Center(child: AppLogoutDialogWidget()));
}
