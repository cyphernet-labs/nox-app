@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/presentation/widgets/chat/app_author_header_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_date_separator_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_message_bubble_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_system_line_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_header_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_thread_widgets',
    () => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppThreadHeaderWidget(
          chat: ChatModel(id: 'c', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime(2024, 1, 1)),
          onInfo: () {},
        ),
        const AppSystemLineWidget(text: 'Chat created by Aria'),
        const AppDateSeparatorWidget(label: 'Yesterday'),
        const AppAuthorHeaderWidget(label: 'Mox'),
        const AppMessageBubbleWidget(isOwn: false, text: 'Did you see the new tokens?', time: '09:00'),
        const AppMessageBubbleWidget(isOwn: true, text: 'Yep, looks great.', time: '09:01', status: MessageStatus.sent),
      ],
    ),
  );
}
