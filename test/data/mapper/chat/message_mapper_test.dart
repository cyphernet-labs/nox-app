import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/chat/message_entity.dart';
import 'package:nox_app/data/mapper/chat/message_mapper.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/app_clock.dart';

void main() {
  final mapper = MessageMapper();

  // Pinned "now" so the unparseable-sentAt fallback (AppClock.now()) is deterministic.
  final frozenNow = DateTime(2026, 6, 1, 12, 30, 45);

  setUp(() => AppClock.freeze(frozenNow));
  tearDown(() => AppClock.reset());

  MessageEntity buildEntity({
    String id = 'm1',
    String chatId = 'c1',
    String authorId = 'a1',
    String authorLabel = 'Alice',
    String? text = 'hello',
    String sentAt = '2026-01-02T03:04:05.000Z',
    String status = 'sent',
    bool isSystem = false,
    String? attachmentId,
    String? attachmentType,
    String? attachmentName,
    int? attachmentSizeBytes,
    String? attachmentLocalPath,
  }) => MessageEntity(
    id: id,
    chatId: chatId,
    authorId: authorId,
    authorLabel: authorLabel,
    text: text,
    sentAt: sentAt,
    status: status,
    isSystem: isSystem,
    attachmentId: attachmentId,
    attachmentType: attachmentType,
    attachmentName: attachmentName,
    attachmentSizeBytes: attachmentSizeBytes,
    attachmentLocalPath: attachmentLocalPath,
  );

  group('MessageMapper attachment coercion', () {
    test('round-trips a message WITH an attachment losslessly (flat <-> nested)', () {
      final entity = buildEntity(attachmentId: 'att1', attachmentType: 'image', attachmentName: 'photo.png', attachmentSizeBytes: 2048);

      final model = mapper.toModel(entity: entity);
      final back = mapper.toEntity(model: model);

      // Flat -> nested.
      expect(model.attachment, isNotNull);
      expect(model.attachment!.id, 'att1');
      expect(model.attachment!.type, FileType.image);
      expect(model.attachment!.name, 'photo.png');
      expect(model.attachment!.sizeBytes, 2048);
      expect(model.status, MessageStatus.sent);
      expect(model.text, 'hello');

      // Nested -> flat.
      expect(back.attachmentId, 'att1');
      expect(back.attachmentType, 'image');
      expect(back.attachmentName, 'photo.png');
      expect(back.attachmentSizeBytes, 2048);
      expect(back.id, entity.id);
      expect(back.chatId, entity.chatId);
      expect(back.authorId, entity.authorId);
      expect(back.authorLabel, entity.authorLabel);
      expect(back.status, entity.status);
      expect(back.isSystem, entity.isSystem);
      expect(DateTime.parse(back.sentAt), DateTime.parse(entity.sentAt));
    });

    test('null attachmentId yields a null attachment in toModel, and null flat fields in toEntity', () {
      final entity = buildEntity(); // no attachment* set -> all null

      final model = mapper.toModel(entity: entity);
      final back = mapper.toEntity(model: model);

      expect(model.attachment, isNull);
      expect(back.attachmentId, isNull);
      expect(back.attachmentType, isNull);
      expect(back.attachmentName, isNull);
      expect(back.attachmentSizeBytes, isNull);
    });

    test('unknown attachmentType falls back to FileType.other (attachmentId non-null reaches the lookup)', () {
      final entity = buildEntity(attachmentId: 'att1', attachmentType: 'bogus', attachmentName: 'blob.bin', attachmentSizeBytes: 10);

      final model = mapper.toModel(entity: entity);

      expect(model.attachment, isNotNull);
      expect(model.attachment!.type, FileType.other);
    });

    test('partial attachment: null name becomes empty string and null size becomes zero', () {
      final entity = buildEntity(attachmentId: 'att1', attachmentType: 'pdf', attachmentName: null, attachmentSizeBytes: null);

      final model = mapper.toModel(entity: entity);

      expect(model.attachment, isNotNull);
      expect(model.attachment!.type, FileType.pdf);
      expect(model.attachment!.name, '');
      expect(model.attachment!.sizeBytes, 0);
    });
  });

  group('MessageMapper status coercion', () {
    test('unknown status string falls back to MessageStatus.none', () {
      final entity = buildEntity(status: 'bogus');
      expect(mapper.toModel(entity: entity).status, MessageStatus.none);
    });

    test('each known status name round-trips', () {
      for (final status in MessageStatus.values) {
        final entity = buildEntity(status: status.name);
        expect(mapper.toModel(entity: entity).status, status);
      }
    });
  });

  group('MessageMapper sentAt coercion', () {
    test('unparseable sentAt falls back to the pinned AppClock.now()', () {
      final entity = buildEntity(sentAt: 'not-a-date');
      expect(mapper.toModel(entity: entity).sentAt, frozenNow);
    });

    test('stored UTC is handed to the domain as local wall-clock but round-trips to the same instant', () {
      final entity = buildEntity(sentAt: '2026-01-02T03:04:05.000Z');

      final model = mapper.toModel(entity: entity);
      final back = mapper.toEntity(model: model);

      expect(model.sentAt.isUtc, isFalse);
      expect(DateTime.parse(back.sentAt), DateTime.parse(entity.sentAt));
    });
  });

  group('MessageMapper text passthrough', () {
    test('null text passes through both directions', () {
      final entity = buildEntity(text: null);

      final model = mapper.toModel(entity: entity);
      final back = mapper.toEntity(model: model);

      expect(model.text, isNull);
      expect(back.text, isNull);
    });

    test('non-null text passes through both directions', () {
      final entity = buildEntity(text: 'hey there');

      final model = mapper.toModel(entity: entity);
      final back = mapper.toEntity(model: model);

      expect(model.text, 'hey there');
      expect(back.text, 'hey there');
    });

    test('the attachment localPath round-trips (persists in Sembast) — F4/F2', () {
      final entity = buildEntity(
        attachmentId: 'att1',
        attachmentType: 'image',
        attachmentName: 'shot.png',
        attachmentSizeBytes: 2048,
        attachmentLocalPath: '/tmp/shot.png',
      );

      final model = mapper.toModel(entity: entity);
      expect(model.attachment!.localPath, '/tmp/shot.png'); // flat -> nested

      final back = mapper.toEntity(model: model);
      expect(back.attachmentLocalPath, '/tmp/shot.png'); // nested -> flat (survives restart)
    });

    test('an attachment without a localPath keeps it null (seeded/backend)', () {
      final entity = buildEntity(attachmentId: 'a', attachmentType: 'pdf', attachmentName: 'd.pdf', attachmentSizeBytes: 1);
      expect(mapper.toModel(entity: entity).attachment!.localPath, isNull);
    });
  });
}
