import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/service/attachment_transfer_service_impl.dart';
import 'package:nox_app/domain/model/file/attachment_transfer.dart';

/// The map the thread draws its rings and bars from. What matters is what it
/// publishes: every publish redraws the thread, and a transfer that outlives
/// its bytes would show a ring over a message long since sent.
void main() {
  late AttachmentTransferServiceImpl transfers;
  late List<Map<String, AttachmentTransfer>> published;
  late StreamSubscription<Map<String, AttachmentTransfer>> subscription;

  setUp(() async {
    transfers = AttachmentTransferServiceImpl();
    published = <Map<String, AttachmentTransfer>>[];
    subscription = transfers.watch().listen(published.add);
    await pumpEventQueue();
    published.clear(); // the replay of the empty map on listen
  });

  tearDown(() => subscription.cancel());

  test('a transfer starts with no bytes moved', () async {
    transfers.begin('m1', TransferDirection.upload, chatId: 'c1');
    await pumpEventQueue();

    expect(transfers.current, {'m1': const AttachmentTransfer(chatId: 'c1', direction: TransferDirection.upload)});
    expect(published, hasLength(1));
  });

  test('progress is published once per whole percent, not once per callback', () async {
    transfers.begin('m1', TransferDirection.download, chatId: 'c1');
    for (final fraction in [0.001, 0.004, 0.009, 0.01, 0.012, 0.5, 0.501]) {
      transfers.report('m1', fraction);
    }
    await pumpEventQueue();

    // begin, 0%, 1%, 50% - the other four reports changed nothing on screen.
    expect(published.map((m) => m['m1']?.percent).toList(), [null, 0, 1, 50]);
  });

  test('a fraction past the ends is clamped, so the ring never reads over 100%', () async {
    transfers.begin('m1', TransferDirection.upload, chatId: 'c1');
    transfers.report('m1', 1.7);

    expect(transfers.current['m1']?.fraction, 1.0);
    expect(transfers.current['m1']?.percent, 100);
  });

  test('a report after the end does not bring the transfer back', () async {
    // Dio can deliver a last progress callback after the request settled.
    transfers.begin('m1', TransferDirection.upload, chatId: 'c1');
    transfers.end('m1');
    transfers.report('m1', 0.9);

    expect(transfers.current, isEmpty);
  });

  test('ending one transfer leaves the others running', () async {
    transfers.begin('m1', TransferDirection.upload, chatId: 'c1');
    transfers.begin('m2', TransferDirection.download, chatId: 'c1');
    transfers.end('m1');

    expect(transfers.current.keys, ['m2']);
  });

  test('ending a transfer that is not running publishes nothing', () async {
    transfers.end('nobody');
    await pumpEventQueue();

    expect(published, isEmpty);
  });

  test('a new listener is handed what is moving now', () async {
    transfers.begin('m1', TransferDirection.upload, chatId: 'c1');

    expect(await transfers.watch().first, {'m1': const AttachmentTransfer(chatId: 'c1', direction: TransferDirection.upload)});
  });
}
