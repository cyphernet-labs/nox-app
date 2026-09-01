import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/outbox_entity.dart';
import 'package:nox_app/data/local/chat/outbox_dao.dart';
import 'package:nox_app/data/mapper/chat/outbox_mapper.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/outbox_entry.dart';
import 'package:nox_app/domain/model/chat/outbox_status.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:uuid/uuid.dart';

/// Local-only repository: the queue never leaves the device until the drain
/// sends it. Bound in every environment because the thread reads it everywhere —
/// unlike the socket-bound services, which only the dev flavor has.
@LazySingleton(as: OutboxRepository, env: [Environment.dev, Environment.prod, Environment.test])
class OutboxRepositoryImpl with BaseRepositoryHelper implements OutboxRepository {
  OutboxRepositoryImpl(this._dao, this._mapper);

  final OutboxDao _dao;
  final OutboxMapper _mapper;

  static const Uuid _uuid = Uuid();

  @override
  Future<RepositoryResult<OutboxEntry>> enqueue({required String chatId, String? text, MessageAttachment? attachment}) {
    return execute<OutboxEntry>(() async {
      // A BARE uuid, because contract §5 says the key is a UUID and the contract
      // is taken verbatim. The old `local_` prefix answered "is this row still
      // local?" in the string itself; the queue answers that by holding the
      // record, so the prefix bought nothing and put a non-UUID on the wire.
      final entry = OutboxEntry(
        clientMessageId: _uuid.v4(),
        chatId: chatId,
        ordinal: 0, // replaced inside the enqueue transaction
        createdAt: AppClock.now(),
        status: OutboxStatus.pending,
        text: text,
        attachment: attachment,
      );
      final placed = await _dao.enqueue(_mapper.toEntity(model: entry));
      return RepositoryResult<OutboxEntry>.success(data: _mapper.toModel(entity: placed));
    });
  }

  @override
  Stream<List<OutboxEntry>> watchQueue({String? chatId}) {
    return _dao.watch(chatId: chatId).map((entities) => [for (final entity in entities) _mapper.toModel(entity: entity)]);
  }

  @override
  Future<List<OutboxEntry>> pending() async {
    final entities = await _dao.getAllSorted();
    return [
      for (final entity in entities)
        if (entity.status == OutboxStatus.pending.name) _mapper.toModel(entity: entity),
    ];
  }

  @override
  Future<OutboxEntry?> find({required String clientMessageId}) async {
    final entity = await _dao.getById(clientMessageId);
    return entity == null ? null : _mapper.toModel(entity: entity);
  }

  @override
  Future<void> recordFailure({
    required String clientMessageId,
    required String code,
    required bool terminal,
    required bool serverAnswered,
  }) async {
    await _mutate(clientMessageId, (entity) {
      return entity.copyWith(
        attempts: entity.attempts + 1,
        refusals: serverAnswered ? entity.refusals + 1 : entity.refusals,
        lastErrorCode: code,
        status: terminal ? OutboxStatus.error.name : entity.status,
      );
    });
  }

  @override
  Future<void> attachFile({required String clientMessageId, required String? fileId}) async {
    await _mutate(clientMessageId, (entity) => entity.copyWith(fileId: fileId));
  }

  @override
  Future<void> markPending({required String clientMessageId}) async {
    await _mutate(clientMessageId, (entity) => entity.copyWith(status: OutboxStatus.pending.name, attempts: 0, refusals: 0));
  }

  @override
  Future<void> remove({required String clientMessageId}) => _dao.remove(clientMessageId);

  @override
  Future<void> removeForChat({required String chatId}) => _dao.removeForChat(chatId);

  @override
  Future<void> clean() => _dao.cleanData();

  /// Read-modify-write of one record, delegated to the DAO so it happens in a
  /// single transaction. A vanished record is a no-op rather than an error: the
  /// drain can finish and delete an entry while a slower failure path is still
  /// on its way to marking it — and, more sharply, the user can discard one
  /// between the two halves of a read-then-write.
  Future<void> _mutate(String clientMessageId, OutboxEntity Function(OutboxEntity entity) change) async {
    await _dao.updateIfPresent(clientMessageId, change);
  }
}
