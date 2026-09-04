import 'dart:async';
import 'dart:convert';

import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';

/// An in-memory stand-in for the server side of the socket, so the transport's
/// behaviour is testable without a server, a network, or timing luck.
class FakeSocket implements SocketConnection {
  final StreamController<dynamic> _incoming = StreamController<dynamic>.broadcast();
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
  bool closed = false;

  @override
  Stream<dynamic> get frames => _incoming.stream;

  @override
  void add(String frame) => sent.add(jsonDecode(frame) as Map<String, dynamic>);

  @override
  Future<void> close() async => closed = true;

  /// The one-time greeting that precedes any command (contract §2).
  void pushGreeting() => _incoming.add(
    jsonEncode({
      'srv': {'schema_max': 1, 'challenge': 'x'},
    }),
  );

  void reply(int index, {bool ok = true, Map<String, dynamic>? data, String? code}) {
    final id = sent[index]['id'] as int;
    _incoming.add(
      jsonEncode({
        'id': id,
        'ok': ok,
        'data': ?data,
        'error': ?(code == null ? null : {'code': code, 'message': code}),
      }),
    );
  }

  /// A successful greeting reply carrying the catch-up cursor and identity.
  void replyToHello({required int cursor, String label = 'Anna', String journalId = 'j_test', bool? created = false}) => reply(
    sent.indexWhere((f) => f['cmd'] == 'session.hello'),
    data: {
      'schema': 1,
      'cursor': cursor,
      'journal_id': journalId,
      'limits': {'max_message_bytes': 65536, 'max_attachment_bytes': 104857600, 'max_frame_bytes': 131072},
      // Nullable, and stated with the ?-spread: the wire has THREE states and
      // the third one - the field absent, meaning "outcome not stated" - is the
      // one a test has to be able to reproduce. A non-nullable bool here would
      // make the very case FR-006 requires checking inexpressible.
      'identity': {'id': 'u_1', 'label': label, 'created': ?created},
    },
  );

  void refuseHello(String code) => reply(sent.indexWhere((f) => f['cmd'] == 'session.hello'), ok: false, code: code);

  void pushEvent({required int seq, String event = 'message.new', Map<String, dynamic>? data}) =>
      _incoming.add(jsonEncode({'seq': seq, 'event': event, 'data': data ?? const <String, dynamic>{}}));

  void pushRaw(String frame) => _incoming.add(frame);

  /// The peer goes away: the stream ends, which is what a real drop looks like
  /// to the client.
  Future<void> drop() => _incoming.close();

  Map<String, dynamic>? commandNamed(String cmd) {
    for (final f in sent) {
      if (f['cmd'] == cmd) return f;
    }
    return null;
  }
}

/// Hands out [FakeSocket]s and records every connect attempt, so reconnect
/// behaviour is observable as a count rather than by watching a clock.
class FakeSocketFactory implements SocketChannelFactory {
  final List<FakeSocket> created = <FakeSocket>[];

  FakeSocket get latest => created.last;

  @override
  SocketConnection connect(Uri url) {
    final socket = FakeSocket();
    created.add(socket);
    return socket;
  }
}
