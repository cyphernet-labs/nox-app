import 'package:nox_app/domain/exception/base_repository_exception.dart';

/// How a pairing through an invite ended when it did not end in one (phase
/// 046), beyond the refusals every link shares - an expired link is
/// `RepositoryException.notFound`, a spent one `authentication`.
///
/// Its own enum because neither is a general failure: both are answers, and
/// each asks something different of the screen.
enum PairingException implements BaseRepositoryException {
  /// The device that issued the invite answered Deny. The person asks for a
  /// new invite if they still want this device in.
  declined,

  /// The person withdrew the request themselves, with Cancel: back to where
  /// links are entered, with nothing to say about it.
  cancelled,
}
