import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/messages_wire_entity.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/model/file/file_type.dart';

/// SC-001: the wire layer is pinned by LIVE frames captured from the stage-1
/// server (`noxd`, contract v0) — see specs/025-client-wire-alignment/
/// quickstart.md for the capture procedure. A mismatch here is fixed in the
/// CLIENT code, never by editing a fixture (Principle VII: the contract is
/// law and the server is its reference implementation).
void main() {
  Map<String, dynamic> fixture(String name) => json.decode(File('test/fixtures/wire/$name').readAsStringSync()) as Map<String, dynamic>;

  final messageMapper = MessageWireMapper();
  final chatMapper = ChatWireMapper();

  /// Unwraps a command-reply `data` payload: chat.create/chat.rename replies
  /// wrap the entity as `{chat: ...}` and message.send as `{message: ...}`
  /// (contract §4/§5, noxd `chatReply`/`messageSendReply`) — events and list
  /// pages are flat. Asserts the wrapper carries EXACTLY the one key, so a
  /// contract drift in the reply shell fails here, not in phase 027.
  Map<String, dynamic> unwrapReply(Map<String, dynamic> raw, String key) {
    expect(raw.keys, [key], reason: 'a command reply wraps the entity as {$key: ...} and nothing else');
    return raw[key] as Map<String, dynamic>;
  }

  /// Parses [name] as a Message frame, maps it to the domain and back, and
  /// asserts the reserialized wire JSON matches the live frame field-exactly.
  /// [replyWrapped] unwraps the `{message: ...}` command-reply shell first.
  MessageWireEntity expectMessageRoundTrip(String name, {bool expectClientMessageId = false, bool replyWrapped = false}) {
    final raw = replyWrapped ? unwrapReply(fixture(name), 'message') : fixture(name);
    final entity = MessageWireEntity.fromJson(raw);

    final out = entity.toJson();
    if (entity.body != null) out['body'] = entity.body!.toJson();
    if (entity.attachment != null) out['attachment'] = entity.attachment!.toJson();
    expect(out, raw, reason: '$name must reserialize field-exactly');

    expect(entity.clientMessageId != null, expectClientMessageId, reason: '$name client_message_id presence');
    return entity;
  }

  group('live noxd fixtures (SC-001)', () {
    test('hello reply: limits parse into ServerLimits and match the contract defaults', () {
      final raw = fixture('hello.json');
      final limits = raw['limits'] as Map<String, dynamic>;
      final parsed = ServerLimits(
        maxMessageBytes: limits['max_message_bytes'] as int,
        maxAttachmentBytes: limits['max_attachment_bytes'] as int,
        maxFrameBytes: limits['max_frame_bytes'] as int,
      );
      expect(parsed, ServerLimits.contractDefaults);
      expect(raw['cursor'], isA<int>());
      expect((raw['identity'] as Map<String, dynamic>)['label'], 'Anna');
    });

    for (final name in ['chat_create_echo.json', 'chat_rename_echo.json', 'chat_created_event.json', 'chat_updated_event.json']) {
      test('$name: the Chat model parses and reserializes 1:1', () {
        // Command echoes arrive wrapped as {chat: ...}; events are flat (§6).
        final wrapped = name.endsWith('_echo.json');
        final raw = wrapped ? unwrapReply(fixture(name), 'chat') : fixture(name);
        final entity = ChatWireEntity.fromJson(raw);
        expect(entity.toJson(), raw, reason: '$name must reserialize field-exactly');

        final model = chatMapper.toModel(entity: entity);
        expect(model.id, entity.chatId);
        expect(model.createdByLabel, entity.createdByLabel);
        expect(model.unreadCount, 0); // device-local, never from the wire
      });
    }

    test('message_send_echo.json: the author echo carries client_message_id and a text body', () {
      final entity = expectMessageRoundTrip('message_send_echo.json', expectClientMessageId: true, replyWrapped: true);
      final model = messageMapper.toModel(entity: entity);
      expect(model.text, 'hello from the fixture');
      expect(model.seq, entity.seq);
      expect(model.attachment, isNull);
    });

    test('message_send_attachment_echo.json: the attachment assembles with the derived category', () {
      final entity = expectMessageRoundTrip('message_send_attachment_echo.json', expectClientMessageId: true, replyWrapped: true);
      final model = messageMapper.toModel(entity: entity);
      expect(model.text, isNull); // attachment-only: no body on the wire
      expect(model.attachment!.id, entity.attachment!.fileId);
      expect(model.attachment!.type, FileType.pdf); // derived from 'design-spec.pdf'
      expect(model.attachment!.mime, 'application/pdf');
      expect(model.attachment!.expiresAt, isNotNull);
      expect(model.attachment!.localPath, isNull); // never from the wire
    });

    test('message_new events: the recipient copy has NO client_message_id (contract §5)', () {
      expectMessageRoundTrip('message_new_text_event.json');
      expectMessageRoundTrip('message_new_attachment_event.json');
    });

    test('messages_list_page.json: {messages, has_more} parses ascending by seq', () {
      final page = MessagesWireEntity.fromJson(fixture('messages_list_page.json'));
      expect(page.messages, isNotEmpty);
      expect(page.hasMore, isA<bool>());
      for (var i = 1; i < page.messages.length; i++) {
        expect(page.messages[i].seq, greaterThan(page.messages[i - 1].seq));
      }
    });

    test('chats_list_page.json: {chats, has_more} parses with full cards', () {
      final page = ChatsWireEntity.fromJson(fixture('chats_list_page.json'));
      expect(page.chats, isNotEmpty);
      expect(page.chats.first.createdByLabel, isNotEmpty);
    });

    test('chat_files_page.json: rows carry the attachment plus its message anchor', () {
      final raw = fixture('chat_files_page.json');
      final files = (raw['files'] as List).cast<Map<String, dynamic>>();
      expect(files, isNotEmpty);
      final row = files.first;
      // The 028 consumer parses these; today the shape itself is pinned.
      expect(row['file_id'], isNotEmpty);
      expect(row['mime'], isNotEmpty);
      expect(row['expires_at'], isA<int>());
      expect(row['message_id'], isNotEmpty);
      expect(row['seq'], isA<int>());
    });

    test('an unknown sibling field in a live frame shape does not break parsing (v0 evolves)', () {
      final raw = Map<String, dynamic>.from(fixture('message_new_text_event.json'))..['future_field'] = {'x': 1};
      expect(() => MessageWireEntity.fromJson(raw), returnsNormally);
    });
  });
}
