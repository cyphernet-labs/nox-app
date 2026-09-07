import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/domain/model/person/pair_request.dart';
import 'package:rxdart/rxdart.dart';

/// The questions waiting for the owner: somebody has presented an invite and is
/// standing at the door (contract §8B).
///
/// A service rather than state inside a screen, because the question must reach
/// the owner wherever they are — in a chat, in the list, in settings. A
/// subscription living in the People screen would show it only to somebody
/// already looking at the People screen.
///
/// Only the owner is ever sent these events, so nothing here checks the role: a
/// second place that reasons about ownership is a second place to disagree with
/// the server about it.
@LazySingleton(env: [Environment.dev])
class PairRequestService {
  PairRequestService(this._socket) {
    _events = _socket.events.listen(_onEvent);
  }

  final NoxSocketClient _socket;
  late final StreamSubscription<ServerEvent> _events;

  /// Open requests, oldest first. Replays to a new listener, so a screen built
  /// after the frame arrived still sees the question.
  final BehaviorSubject<List<PairRequest>> _open = BehaviorSubject<List<PairRequest>>.seeded(const <PairRequest>[]);

  Timer? _expiry;

  Stream<List<PairRequest>> get open => _open.stream;

  void _onEvent(ServerEvent event) {
    switch (event.event) {
      case ServerEvent.personPairRequested:
        final request = _parse(event.data);
        if (request == null) return;
        // The same request can arrive twice — once when it is presented and
        // again on the next greeting, which re-sends everything still waiting.
        // Keyed by id so the second copy replaces rather than duplicates.
        final next = <PairRequest>[
          for (final open in _open.value)
            if (open.requestId != request.requestId) open,
          request,
        ];
        _emit(next);
      case ServerEvent.personPairResolved:
        final id = event.data['request_id'];
        if (id is! String) return;
        _emit(<PairRequest>[
          for (final open in _open.value)
            if (open.requestId != id) open,
        ]);
    }
  }

  /// Publishes the list with anything already past its deadline dropped, and
  /// arms a timer for the next one.
  ///
  /// The server says so too, with an `expired` outcome — but only if there is a
  /// channel to say it on. A question left on screen after the moment it could
  /// have been answered would invite an answer that does nothing.
  void _emit(List<PairRequest> requests) {
    final now = DateTime.now();
    final live = <PairRequest>[
      for (final request in requests)
        if (request.expiresAt.isAfter(now)) request,
    ]..sort((a, b) => a.invitedAt.compareTo(b.invitedAt));
    _open.add(live);

    _expiry?.cancel();
    _expiry = null;
    if (live.isEmpty) return;
    var soonest = live.first.expiresAt;
    for (final request in live) {
      if (request.expiresAt.isBefore(soonest)) soonest = request.expiresAt;
    }
    final remaining = soonest.difference(now);
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () => _emit(_open.value));
  }

  static PairRequest? _parse(Map<String, dynamic> data) {
    final id = data['request_id'];
    if (id is! String || id.isEmpty) return null;
    return PairRequest(requestId: id, invitedAt: _seconds(data['invited_at']), expiresAt: _seconds(data['expires_at']));
  }

  static DateTime _seconds(Object? value) =>
      DateTime.fromMillisecondsSinceEpoch((value is num && value.isFinite ? value.toInt() : 0) * 1000, isUtc: true).toLocal();

  Future<void> dispose() async {
    _expiry?.cancel();
    await _events.cancel();
    await _open.close();
  }
}
