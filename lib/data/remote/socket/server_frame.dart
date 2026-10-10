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
      return SrvGreeting(schemaMax: srv['schema_max'] is int ? srv['schema_max'] as int : 0);
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

/// The server's one-time greeting, sent before any command is accepted
/// (contract §2): `{"srv": {"schema_max": 1}}`.
///
/// It carries nothing to sign any more (phase 044). Who connected was settled
/// below HTTP, by the Eidolon check of this very connection, before the
/// greeting could even be sent.
class SrvGreeting extends ServerFrame {
  const SrvGreeting({required this.schemaMax});

  final int schemaMax;
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

  /// Sent to the device being cut off, immediately before its socket closes
  /// (contract §8A). Not journal content: it carries seq 0 and describes THIS
  /// connection rather than the shared world.
  static const String deviceRevoked = 'device.revoked';

  /// Sent to the OTHER live connections of a person who has just added a
  /// device (contract §8A). Seq 0 and not journal content, like [deviceRevoked]
  /// above and [identityUpdated] below.
  ///
  /// Carries nothing: it says "the set of devices changed", not how, and the
  /// receiver re-reads `device.list`. Anything in the payload would either
  /// repeat what arrives a moment later or disagree with it.
  ///
  /// Does NOT survive a disconnect. A device that was offline learns the truth
  /// the next time its screen opens, which is enough for a device that was
  /// away; the screen that was ALREADY open when the channel dropped is the
  /// case this cannot reach, and it is covered by re-reading the list when the
  /// channel comes back.
  static const String devicePaired = 'device.paired';

  /// Sent to the OTHER live connections of a person who has just renamed
  /// (contract §8A). Also seq 0 and also not journal content, for the same
  /// reason: it describes who this connection is, not what happened in the
  /// shared world. Without it a second device holds the old name until
  /// something reconnects it, and a stable socket never re-greets.
  static const String identityUpdated = 'identity.updated';

  /// Where the server can be found, sent to greeted connections whenever the
  /// list changes (contract §8A, phase 039). Seq 0 and not journal content: it
  /// describes the machine, not the shared world. The payload is the same
  /// object as `addresses` in the greeting reply.
  static const String serverAddresses = 'server.addresses';

  /// How a request to join through an invite ended, sent to the NEW device on
  /// the connections it waits on before any greeting (contract §8A, phase
  /// 046): `allowed` with the identity it now speaks as, `denied`, `expired`
  /// or `cancelled`. Seq 0, and it does not survive a disconnect - its
  /// reliable half is presenting the same token again.
  static const String pairResolved = 'pair.resolved';

  /// A new device asks to join through an invite THIS device issued, sent to
  /// its greeted connections and again after each of its greetings for every
  /// request still waiting (contract §8A, phase 046). Seq 0. The payload names
  /// the request, the new device's OS family and the deadline - no key.
  static const String devicePairRequested = 'device.pairRequested';

  /// A request this device was asked about has closed, whichever way (contract
  /// §8A, phase 046): its question is over. Seq 0.
  static const String devicePairResolved = 'device.pairResolved';
}
