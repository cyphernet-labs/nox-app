@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';

import '../../../utils/golden.dart';

void main() {
  // Mobile design surface (full-screen form) + the desktop modal Dialog body (N5).
  // The desktop golden locks the Dialog CARD; the scrim/barrier + list-behind are a
  // standard Material runtime overlay (showDialog), not part of the card, so they are
  // intentionally not captured here (the end-to-end modal is covered by widget tests).
  goldenTest('create_chat_page', () => const CreateChatPage());
  goldenTestDesktop('create_chat_page', () => const CreateChatPage(dialog: true));
}
