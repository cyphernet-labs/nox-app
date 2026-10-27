@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_people_section_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_chat_people_section_widget',
    () => const Padding(
      padding: EdgeInsets.all(16),
      child: AppChatPeopleSectionWidget(personLabel: 'Anna'),
    ),
  );
}
