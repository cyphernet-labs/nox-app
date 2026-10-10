import 'package:nox_app/domain/model/device/pair_request.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// The requests to join this person's devices that wait for THIS device's
/// answer (contract §8A, phase 046): a new device presented an invite this
/// device issued, and nothing is paired until it is answered here.
///
/// Only while the app is open and connected (FR-008): the server asks the
/// device's greeted connections and asks again after every greeting, so a
/// request that waits through a break comes back with the connection, and one
/// that closed meanwhile does not.
abstract class PairRequestService {
  /// The requests waiting for this device's answer, oldest first. Emits the
  /// current list on listen, then every change.
  Stream<List<PairRequest>> watchRequests();

  /// Answers [requestId] (FR-009): [allow] pairs the new device, `false`
  /// refuses it, and either way the invite is spent. `true` when the answer
  /// was taken, `false` when there was nothing left to answer - the request
  /// closed meanwhile, by its time or by the new device - and an error when it
  /// did not get through and may be given again.
  Future<RepositoryResult<bool>> answer({required String requestId, required bool allow});

  /// The id of each request this device was asked about once it is over,
  /// whichever way it ended: the invite behind it is spent.
  Stream<String> watchClosed();
}
