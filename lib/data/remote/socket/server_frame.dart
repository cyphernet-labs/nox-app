/// The three frame kinds the server can send (contract v0 §2). A frame is told
/// apart by which key it carries — `srv`, `event`, or an `id` with `ok` — so it
/// is parsed by hand rather than by a generated deserializer, which could not
/// express that choice.
sealed class ServerFrame {
  const ServerFrame();

  /// Parses one decoded JSON frame. Returns null for anything that does not
  /// match a known shape: contract v0 is expected to grow, and an unknown frame
  /// must be ignored rather than kill the connection (§2.1 evolution rule).
  static ServerFrame? parse(Map<String, dynamic> json) {
    final srv = json['srv'];
    if (srv is Map<String, dynamic>) {
      return SrvGreeting(schemaMax: srv['schema_max'] as int? ?? 0, challenge: srv['challenge'] as String? ?? '');
    }
    final event = json['event'];
    if (event is String) {
      return ServerEvent(
        seq: json['seq'] as int? ?? 0,
        event: event,
        data: (json['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      );
    }
    final id = json['id'];
    if (id is int) {
      final error = json['error'];
      return CommandReply(
        id: id,
        ok: json['ok'] as bool? ?? false,
        data: json['data'] as Map<String, dynamic>?,
        errorCode: error is Map<String, dynamic> ? error['code'] as String? : null,
        errorMessage: error is Map<String, dynamic> ? error['message'] as String? : null,
      );
    }
    return null;
  }
}

/// The server's one-time greeting, sent before any command is accepted.
class SrvGreeting extends ServerFrame {
  const SrvGreeting({required this.schemaMax, required this.challenge});

  final int schemaMax;

  /// Signed by the device key from stage 2 on; present but unverified today.
  final String challenge;
}

/// A reply to one command, correlated by the [id] the client issued.
class CommandReply extends ServerFrame {
  const CommandReply({required this.id, required this.ok, this.data, this.errorCode, this.errorMessage});

  final int id;
  final bool ok;
  final Map<String, dynamic>? data;
  final String? errorCode;
  final String? errorMessage;
}

/// A journal event. [seq] is the sync cursor coordinate: strictly increasing
/// across the whole server, and the key both replay and dedup are built on.
class ServerEvent extends ServerFrame {
  const ServerEvent({required this.seq, required this.event, required this.data});

  final int seq;
  final String event;
  final Map<String, dynamic> data;

  static const String chatCreated = 'chat.created';
  static const String chatUpdated = 'chat.updated';
  static const String messageNew = 'message.new';
}
