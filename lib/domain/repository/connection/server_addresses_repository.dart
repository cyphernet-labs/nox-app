import 'package:nox_app/domain/model/connection/server_addresses.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// The connection settings of this device's server (phases 040, 045): where
/// the server said it can be reached, what the person changed by hand, and
/// `Use Tor`. Kept across restarts and wiped with the session.
abstract class ServerAddressesRepository {
  Future<RepositoryResult<ServerAddresses>> read();

  /// What the server says about itself - the greeting's `addresses` and the
  /// `server.addresses` event (contract §3): its direct list, its public and
  /// its onion address. The server is the source of truth about its own
  /// addresses (FR-015): a value it states replaces the person's hand edit of
  /// the same field, and a field it leaves out keeps the edit and forgets the
  /// server's previous value. The last good direct address and `Use Tor` stay.
  Future<RepositoryResult<bool>> saveFromServer({required List<String> direct, String? public, String? onion});

  /// What a pairing link carried, with what the person set on the connection
  /// screen (phase 045): the link's direct addresses and onion address as the
  /// server's, the fields the person changed as hand edits, and `Use Tor` as
  /// chosen. Replaces whatever was stored - this is a new server.
  Future<RepositoryResult<bool>> saveFromLink({
    required List<String> direct,
    String? onion,
    String? manualAddress,
    String? manualOnion,
    required bool useTor,
  });

  /// The hand edits from Settings > Connection, as they are to stand: null
  /// for a field that shows what the server says, an empty [manualOnion] for
  /// an onion address the person cleared.
  Future<RepositoryResult<bool>> saveManual({required String? manualAddress, required String? manualOnion});

  /// `Use Tor`, as the person just set it.
  Future<RepositoryResult<bool>> setUseTor(bool useTor);

  /// The direct address that just answered with the right key.
  Future<RepositoryResult<bool>> recordLastGood(String address);

  /// A connection through Tor was just greeted: the device is away from home,
  /// and the next attempt starts Tor without waiting for the direct addresses.
  Future<RepositoryResult<bool>> recordGreetedViaTor();

  /// What is stored on listen, then every change - how the path selector
  /// learns of a new direct address while it is on Tor (US3), and of `Use
  /// Tor` turned off.
  Stream<ServerAddresses> watch();

  /// Forgets every address, AFTER any write already under way: a logout's
  /// wipe must not be overtaken by a greeting stored a moment before the
  /// channel stopped (FR-018).
  Future<RepositoryResult<bool>> clear();
}
