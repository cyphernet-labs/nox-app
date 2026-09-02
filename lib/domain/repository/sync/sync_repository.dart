/// The device's synchronization cursor (contract v0 §3/§9.4): the highest
/// journal seq this device has applied. Fed to `session.hello` as `since`
/// once the transport lands (027); until then the mock world advances it on
/// seed and send so the semantics are real before the wire is.
abstract class SyncRepository {
  /// The persisted cursor; 0 when nothing was ever applied (fresh install
  /// or post-logout).
  Future<int> getCursor();

  /// Advances the cursor monotonically: values at or below the stored one
  /// are ignored (replay/live duplicates must not move it backwards).
  Future<void> advanceCursor(int seq);

  /// Drops the cursor with the rest of the local data (logout wipe).
  Future<void> clear();

  /// Which world the cached data came from — `mock`, or `live:<address>`.
  ///
  /// Mock and server journals are not comparable: mock seqs are minted from the
  /// clock (~1.8e15) while a server counts from 1, so carrying a cursor across
  /// would ask for history from the future and silently receive nothing.
  Future<String?> getEpoch();

  Future<void> setEpoch(String epoch);

  /// The server's own name for its store (contract §3 `journal_id`).
  ///
  /// Persisted, not just held in memory: the case that actually happens is
  /// "the server store was rebuilt and the app was restarted", and an in-memory
  /// value would be null by then — the client would adopt the new world while
  /// keeping a cursor from the old one and never receive anything again.
  Future<String?> getJournal();

  Future<void> setJournal(String journalId);
}
