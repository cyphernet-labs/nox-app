import 'package:nox_app/data/entity/base/error_wire_entity.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';

/// Turns a socket reply into the envelope the repositories already understand.
///
/// The whole error path was built in feature 025: `unwrapEnvelope` throws
/// `RepositoryException.fromWireCode(code)` and `execute()` re-emits it
/// unchanged. Producing the same envelope here is what lets the real data
/// sources drop in with no repository edits at all.
extension CommandReplyEnvelope on CommandReply {
  ResponseEntity<T> toEnvelope<T>(T Function(Map<String, dynamic> data) parse) {
    if (!ok) {
      return ResponseEntity<T>(
        success: false,
        error: ErrorWireEntity(code: errorCode ?? 'internal', message: errorMessage ?? 'command failed'),
      );
    }
    final payload = data;
    if (payload == null) return const ResponseEntity(success: true);
    return ResponseEntity<T>(success: true, data: parse(payload));
  }

  /// Unwraps a reply that nests its entity under [key] — `{chat: …}` for the
  /// chat commands, `{message: …}` for a send (contract §4/§5). Pages and events
  /// are flat and use [toEnvelope] directly.
  ResponseEntity<T> toWrappedEnvelope<T>(String key, T Function(Map<String, dynamic> data) parse) =>
      toEnvelope((payload) => parse(payload[key] as Map<String, dynamic>));
}
