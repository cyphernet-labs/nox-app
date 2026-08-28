import 'package:injectable/injectable.dart';
import 'package:nox_app/data/local/sync/sync_dao.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';

@LazySingleton(as: SyncRepository, env: [Environment.dev, Environment.prod, Environment.test])
class SyncRepositoryImpl implements SyncRepository {
  SyncRepositoryImpl(this._dao);

  final SyncDao _dao;

  @override
  Future<int> getCursor() => _dao.readSince();

  @override
  Future<void> advanceCursor(int seq) async {
    // Monotonic max: duplicates at the replay/live boundary (contract §3)
    // and out-of-order applications never move the cursor backwards. The
    // check-then-write is atomic inside the DAO's transaction.
    await _dao.advanceSince(seq);
  }

  @override
  Future<void> clear() => _dao.cleanData();
}
