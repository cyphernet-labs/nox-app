import 'package:nox_app/domain/model/connection/server_addresses.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// The server's addresses as it last stated them, kept across restarts and
/// wiped with the session (phase 040).
abstract class ServerAddressesRepository {
  Future<RepositoryResult<ServerAddresses>> read();

  /// Replaces what the server said - the direct list and the onion address -
  /// and keeps the last good direct address.
  Future<RepositoryResult<bool>> saveFromServer({required List<String> direct, required String? onion});

  /// The direct address that just answered with the right key.
  Future<RepositoryResult<bool>> recordLastGood(String address);

  /// What is stored on listen, then every change - how the path selector
  /// learns of a new direct address while it is on Tor (US3).
  Stream<ServerAddresses> watch();

  /// Forgets every address, AFTER any write already under way: a logout's
  /// wipe must not be overtaken by a greeting stored a moment before the
  /// channel stopped (FR-018).
  Future<RepositoryResult<bool>> clear();
}
