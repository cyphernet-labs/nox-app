@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_item_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_chat_item_widget',
    () => const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppChatItemWidget(name: 'Cyphernet Labs', preview: 'Latest build is green', time: '09:24'),
        AppChatItemWidget(name: 'Ann Lee', preview: 'See you tomorrow', time: '08:10', unread: 5),
        AppChatItemWidget(name: 'Releases', preview: 'v26.1 shipped', time: 'Mon', unread: 120),
      ],
    ),
  );
}
