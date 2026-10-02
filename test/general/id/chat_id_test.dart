import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/id/chat_id.dart';

void main() {
  test('a minted id has the shape the server accepts', () {
    for (var i = 0; i < 100; i++) {
      expect(deviceChatIdPattern.hasMatch(mintChatId()), isTrue);
    }
  });

  test('ids do not repeat', () {
    // 128 random bits: a repeat in a thousand would mean the source is broken.
    final ids = {for (var i = 0; i < 1000; i++) mintChatId()};
    expect(ids, hasLength(1000));
  });

  test('the same source gives the same id, so a test can pin one', () {
    expect(mintChatId(Random(7)), mintChatId(Random(7)));
  });

  test('a server-minted id is not taken for a device one', () {
    expect(deviceChatIdPattern.hasMatch('c_9f2a1b3c4d5e6f70'), isFalse);
    expect(deviceChatIdPattern.hasMatch('c_5F0E9C1D2A3B4C5D6E7F8091A2B3C4D5'), isFalse, reason: 'uppercase');
  });
}
