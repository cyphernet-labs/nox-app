@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';

import '../../../utils/golden.dart';

void main() {
  // Mobile design surface + the desktop `_wide` branch (centered dialog-style card).
  goldenTest('create_chat_page', () => const CreateChatPage());
  goldenTestDesktop('create_chat_page', () => const CreateChatPage());
}
