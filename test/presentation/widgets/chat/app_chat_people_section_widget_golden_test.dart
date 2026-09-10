@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_people_section_widget.dart';

import '../../../utils/fake_session_repository.dart';
import '../../../utils/golden.dart';

void main() {
  // The section reads the person from the session spine, so the fake has to be
  // in the container before the first frame or the name resolves to the
  // fallback halfway through the pump and the baseline records the transition.
  setUpAll(registerFakeSession);
  tearDownAll(getIt.reset);

  goldenTest('app_chat_people_section_widget', () => const Padding(padding: EdgeInsets.all(16), child: AppChatPeopleSectionWidget()));
}
