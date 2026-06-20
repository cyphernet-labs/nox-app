@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';

import '../../../utils/golden.dart';

void main() {
  // Golden surface is the mobile design width; the desktop dialog branch is
  // covered by a wide-surface widget test.
  goldenTest('create_chat_page', () => const CreateChatPage());
}
