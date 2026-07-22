@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';

import '../../../utils/golden.dart';

void main() {
  // Mobile design surface (full-screen form) + the desktop modal Dialog body (N5).
  goldenTest('create_chat_page', () => const CreateChatPage());
  goldenTestDesktop('create_chat_page', () => const CreateChatPage(dialog: true));
}
