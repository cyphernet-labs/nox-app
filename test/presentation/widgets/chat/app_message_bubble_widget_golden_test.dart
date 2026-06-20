@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_message_bubble_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_message_bubble_widget',
    () => const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppMessageBubbleWidget(isOwn: true, text: 'Sent this one', time: '09:00', status: MessageStatus.sent),
          AppMessageBubbleWidget(isOwn: false, text: 'Got it, thanks!', time: '09:01'),
          AppMessageBubbleWidget(
            isOwn: true,
            time: '09:02',
            status: MessageStatus.error,
            file: AppFileChipWidget(type: FileType.pdf, name: 'report.pdf', size: '2.4 MB', inBubble: true),
          ),
        ],
      ),
    ),
  );
}
