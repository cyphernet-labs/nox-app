import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/identity_mock_data.dart';

/// The signed-in own-identity resolved from the local session, with mock-phase
/// fallbacks for the no-session / degraded-read case.
typedef Identity = ({String id, String label});

/// Resolves the signed-in own-identity used for own-vs-other detection and own-message
/// authorship. Pure — no storage/clock reads.
///
/// - `id`: the server-assigned author id when present, else the session
///   identifier, else [IdentityMockData.fallbackOwnId].
///   Stable for the life of the local DB (changes only on logout, which wipes caches).
/// - `label`: the session display label when non-empty, else [Constants.defaultUserLabel].
///
/// An empty stored value is treated as absent. Both fields are always non-empty.
Identity resolveIdentity(SessionModel? session) {
  final identifier = session?.identifier;
  final authorId = session?.authorId;
  final label = session?.label;
  return (
    // The server's author id wins when the app is talking to one: it is what
    // stamps the messages coming back, so own-detection must key on it. Falls
    // back to the login identifier on the mock path, where no other id exists.
    id: (authorId != null && authorId.isNotEmpty)
        ? authorId
        : (identifier != null && identifier.isNotEmpty)
        ? identifier
        : IdentityMockData.fallbackOwnId,
    label: (label != null && label.isNotEmpty) ? label : Constants.defaultUserLabel,
  );
}
