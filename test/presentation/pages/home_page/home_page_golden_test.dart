@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/home_page/home_page.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest('home_page', () => const HomePage());
}
