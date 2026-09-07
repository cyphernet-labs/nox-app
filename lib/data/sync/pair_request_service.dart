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

  /// Forgets every open question. Called by logout, alongside the other wipes.
  ///
  /// A question belongs to the session that received it. Without this it
  /// outlives one: the socket stops, so no outcome ever arrives to remove it,
  /// and the next sign-in — possibly as a GUEST of the same server — is shown a
  /// full-screen "someone wants to join" it has no right to answer and, since
  /// `not_owner` is a refusal rather than a resolution, no way to dismiss.
  void clear() {
    _expiry?.cancel();
    _expiry = null;
    _open.add(const <PairRequest>[]);
  }

  /// The open questions right now. Read after a surface closes, to find the one
  /// that was waiting behind it — nothing emits again at that moment.
  List<PairRequest> get current => _open.value;

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
        // A request whose deadline could not be read is KEPT. The server is the
        // authority on when a question dies and says so with an `expired`
        // outcome; dropping one here because a field was missing - or because
        // this device's clock runs ahead of the server's - would swallow the
        // question silently and leave the person at the door waiting out the
        // full window for nothing.
        // Measured from when the frame ARRIVED, never against the server's
        // absolute deadline. The server is the authority on when a question
        // dies and says so with an `expired` outcome; this is only the fallback
        // for a device that loses the channel before hearing it.
        //
        // Comparing local now against a server timestamp made that fallback
        // wrong in the one direction that matters: a device whose clock runs a
        // few minutes fast discarded every question the instant it arrived, the
        // owner was never asked, and every guest timed out with nothing on
        // either side saying why.
        if (now.difference(request.receivedAt) < _localWindow) request,
      // Oldest question first. A request with no stated moment sorts last
      // rather than to 1970: it is the newest thing we know nothing about.
    ]..sort((a, b) => (a.invitedAt ?? _far).compareTo(b.invitedAt ?? _far));
    _open.add(live);

    _expiry?.cancel();
    _expiry = null;
    if (live.isEmpty) return;
    var soonest = live.first.receivedAt.add(_localWindow);
    for (final request in live) {
      final ends = request.receivedAt.add(_localWindow);
      if (ends.isBefore(soonest)) soonest = ends;
    }
    final remaining = soonest.difference(now);
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () => _emit(_open.value));
  }

  /// Stands in for an unstated moment when ordering. Far enough ahead that it
  /// always sorts last, and never rendered.
  static final DateTime _far = DateTime.utc(9999);

  /// How long a question stays on screen without the server saying anything.
  ///
  /// A little longer than the server's own five-minute window, so the answer
  /// that closes a question is the server's whenever there is a channel to
  /// carry it. Immune to clock skew because it is measured from arrival.
  static const Duration _localWindow = Duration(minutes: 6);

  static PairRequest? _parse(Map<String, dynamic> data) {
    final id = data['request_id'];
    if (id is! String || id.isEmpty) return null;
    return PairRequest(
      requestId: id,
      invitedAt: _seconds(data['invited_at']),
      expiresAt: _seconds(data['expires_at']),
      receivedAt: DateTime.now(),
    );
  }

  /// A wire second, or null when the field is missing or not a usable number.
  /// Null means "not stated", never epoch zero: a zero here would read as a
  /// deadline that passed in 1970 and drop the question on the floor.
  static DateTime? _seconds(Object? value) {
    if (value is! num || !value.isFinite) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000, isUtc: true).toLocal();
  }

  @disposeMethod
  Future<void> dispose() async {
    _expiry?.cancel();
    await _events.cancel();
    await _open.close();
  }
}
