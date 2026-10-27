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

  // R2 lock: the 80% own/other corridor MUST be a fraction of the LOCAL pane, not
  // the window. This renders long bubbles inside a narrow list-detail thread column
  // (560px) on the WIDE desktop surface — so a regression to window-based sizing would
  // let each bubble fill the whole 560 pane and collapse the corridor. The corridor
  // visible here (bubbles capped well short of the pane edge) is the invariant.
  goldenTestDesktop(
    'app_message_bubble_widget_narrow_pane',
    () => const Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 560, // a list-detail thread column inside the 1280 desktop window
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              AppMessageBubbleWidget(
                isOwn: false,
                text: 'A fairly long incoming message that must stay within eighty percent of the pane, not the window.',
                time: '09:00',
              ),
              AppMessageBubbleWidget(
                isOwn: true,
                text: 'And an equally long outgoing reply that also respects the eighty percent corridor of the local pane.',
                time: '09:01',
                status: MessageStatus.sent,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
