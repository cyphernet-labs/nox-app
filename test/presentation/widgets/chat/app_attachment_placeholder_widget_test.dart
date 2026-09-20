import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/presentation/widgets/chat/app_attachment_placeholder_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppAttachmentPlaceholderWidget', () {
    testWidgets('says the bytes are coming, and is named for a screen reader', (tester) async {
      // The state this replaced was a type chip - the same inert thing an
      // unopenable file shows - so nothing distinguished "arriving" from
      // "nothing is going to happen".
      await pumpApp(tester, const AppAttachmentPlaceholderWidget(name: 'holiday.png'), settle: false);

      expect(find.byType(AppSpinnerWidget), findsOneWidget);
      // An unlabelled grey box is what a screen reader would otherwise meet
      // where a picture is going to be.
      expect(find.bySemanticsLabel('holiday.png'), findsOneWidget);
    });

    testWidgets('occupies the thumbnail box it is standing in for', (tester) async {
      // The swap has to be the picture appearing, not the bubble rearranging
      // itself around a box that changed size.
      await pumpApp(tester, const AppAttachmentPlaceholderWidget(name: 'a.png', width: 64, height: 64), settle: false);

      final box = tester.getSize(find.byType(Container));
      expect(box, const Size(64, 64));
    });

    testWidgets('tapping it reaches the screen that reports a real failure', (tester) async {
      // Deliberately not a failure surface itself: a fetch that will never
      // succeed still shows a spinner here, and the honest report is one tap
      // away on the file screen.
      var taps = 0;
      await pumpApp(tester, AppAttachmentPlaceholderWidget(name: 'a.png', onTap: () => taps++), settle: false);

      await tester.tap(find.byType(AppAttachmentPlaceholderWidget));
      expect(taps, 1);
    });
  });

  group('wants (which of three things a bubble draws)', () {
    MessageAttachment att({required FileType type, required String name, String? localPath}) =>
        MessageAttachment(id: 'a', type: type, name: name, sizeBytes: 1, localPath: localPath);

    test('a picture on its way gets the placeholder', () {
      expect(AppAttachmentPlaceholderWidget.wants(att(type: FileType.image, name: 'a.png'), inBubble: true), isTrue);
    });

    test('a picture already here does NOT - the thumbnail wins', () {
      // Both predicates are true of a downloaded picture, so without the
      // canRender half the placeholder would shadow the thing it stands in for
      // and no picture would ever appear.
      final tmp = File('${Directory.systemTemp.path}/nox_wants.png')..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      addTearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);

      expect(AppAttachmentPlaceholderWidget.wants(att(type: FileType.image, name: 'a.png', localPath: tmp.path), inBubble: true), isFalse);
    });

    test('a file that will never be a thumbnail keeps its chip', () {
      expect(AppAttachmentPlaceholderWidget.wants(att(type: FileType.image, name: 'a.svg'), inBubble: true), isFalse);
      expect(AppAttachmentPlaceholderWidget.wants(att(type: FileType.pdf, name: 'a.pdf'), inBubble: true), isFalse);
      expect(AppAttachmentPlaceholderWidget.wants(att(type: FileType.video, name: 'a.mp4'), inBubble: true), isFalse);
    });

    test('a composer draft never waits for bytes nobody is fetching', () {
      expect(AppAttachmentPlaceholderWidget.wants(att(type: FileType.image, name: 'a.png'), inBubble: false), isFalse);
    });
  });
}
