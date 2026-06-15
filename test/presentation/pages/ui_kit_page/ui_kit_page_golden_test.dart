@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/ui_kit_page/ui_kit_page.dart';

import '../../../utils/golden.dart';

void main() {
  // settle: false — the gallery renders an endless spinner.
  goldenTest('ui_kit_page', () => const UiKitPage(), settle: false);
}
