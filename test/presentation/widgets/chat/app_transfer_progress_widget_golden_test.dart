@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/file/attachment_transfer.dart';
import 'package:nox_app/presentation/widgets/chat/app_attachment_placeholder_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_message_bubble_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';

import '../../../utils/golden.dart';

/// The three ways a bubble shows bytes on their way (5.2): a file being sent
/// (words over a bar, before and after its first byte), and a received picture
/// being fetched (its placeholder's spinner filling). The ring over a picture
/// being sent is locked by the image attachment golden, which can decode one.
void main() {
  goldenTest(
    'app_transfer_progress_widget',
    () => const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppMessageBubbleWidget(
            isOwn: true,
            time: '21:30',
            status: MessageStatus.pending,
            file: AppFileChipWidget(
              type: FileType.pdf,
              name: 'quarterly-report.pdf',
              size: '2.4 MB',
              inBubble: true,
              transfer: AttachmentTransfer(direction: TransferDirection.upload, fraction: 0.45),
            ),
          ),
          AppMessageBubbleWidget(
            isOwn: true,
            time: '21:30',
            status: MessageStatus.pending,
            file: AppFileChipWidget(
              type: FileType.archive,
              name: 'photos.zip',
              size: '18 MB',
              inBubble: true,
              transfer: AttachmentTransfer(direction: TransferDirection.upload),
            ),
          ),
          AppMessageBubbleWidget(
            isOwn: false,
            time: '21:31',
            file: AppAttachmentPlaceholderWidget(
              name: 'holiday.jpg',
              transfer: AttachmentTransfer(direction: TransferDirection.download, fraction: 0.3),
            ),
          ),
        ],
      ),
    ),
    // The bar with no fraction yet never settles.
    settle: false,
  );
}
