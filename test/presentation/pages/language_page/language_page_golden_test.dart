@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/language_page/language_page.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest('language_page', () => const LanguagePage());
  goldenTestDesktop('language_page', () => const LanguagePage());
}
