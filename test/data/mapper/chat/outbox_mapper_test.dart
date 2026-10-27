import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/chat/outbox_entity.dart';
import 'package:nox_app/data/mapper/chat/outbox_mapper.dart';
import 'package:nox_app/domain/model/chat/outbox_entry.dart';
import 'package:nox_app/domain/model/chat/outbox_status.dart';
import 'package:nox_app/domain/model/file/unfinished_upload.dart';

/// The unfinished upload rides on the queue record (phase 043): three flat
/// fields on disk, one handle in the domain, and nothing at all for rows
/// written before the phase.
void main() {
  final mapper = OutboxMapper();
  final modified = DateTime.utc(2026, 10, 5, 9, 30, 12, 345);

  OutboxEntry entry({UnfinishedUpload? upload}) => OutboxEntry(
    clientMessageId: 'k1',
    chatId: 'c1',
    ordinal: 1,
    createdAt: DateTime.utc(2026, 10, 5).toLocal(),
    status: OutboxStatus.pending,
    upload: upload,
  );

  test('the handle survives the trip to disk and back, to the millisecond', () {
    final upload = UnfinishedUpload(fileId: 'f_77', sourceSize: 83886080, sourceModifiedAt: modified.toLocal());

    final stored = mapper.toEntity(model: entry(upload: upload));
    expect(stored.uploadFileId, 'f_77');
    expect(stored.uploadSourceSize, 83886080);
    expect(stored.uploadSourceModifiedAt, modified.millisecondsSinceEpoch);

    final read = mapper.toModel(entity: stored).upload!;
    expect(read.fileId, 'f_77');
    expect(read.sourceSize, 83886080);
    expect(read.sourceModifiedAt.isAtSameMomentAs(modified), isTrue);
  });

  test('a record without a handle stores none', () {
    final stored = mapper.toEntity(model: entry());

    expect(stored.uploadFileId, isNull);
    expect(stored.uploadSourceSize, isNull);
    expect(stored.uploadSourceModifiedAt, isNull);
    expect(mapper.toModel(entity: stored).upload, isNull);
  });

  test('a handle missing any of its fields is no handle - an unchecked one must not be continued', () {
    final base = mapper.toEntity(
      model: entry(
        upload: UnfinishedUpload(fileId: 'f_1', sourceSize: 10, sourceModifiedAt: modified),
      ),
    );

    expect(mapper.toModel(entity: base.copyWith(uploadFileId: null)).upload, isNull);
    expect(mapper.toModel(entity: base.copyWith(uploadSourceSize: null)).upload, isNull);
    expect(mapper.toModel(entity: base.copyWith(uploadSourceModifiedAt: null)).upload, isNull);
  });

  test('a row written before phase 043 still decodes, with no handle', () {
    final old = OutboxEntity.fromJson(<String, dynamic>{
      'client_message_id': 'k_old',
      'chat_id': 'c1',
      'ordinal': 3,
      'created_at': '2026-09-01T10:00:00.000Z',
      'status': 'pending',
      'attempts': 2,
      'refusals': 0,
      'file_id': null,
      'attachment_id': 'att_local',
      'attachment_type': 'image',
      'attachment_name': 'shot.png',
      'attachment_size_bytes': 64,
      'attachment_local_path': '/tmp/shot.png',
    });

    final read = mapper.toModel(entity: old);
    expect(read.upload, isNull);
    expect(read.attachment?.localPath, '/tmp/shot.png');
  });
}
