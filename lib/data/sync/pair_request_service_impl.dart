import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/device/pair_request.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/service/pair_request_service.dart';
import 'package:rxdart/rxdart.dart';

/// The requests to join that wait for this device's answer, as the live
/// socket tells them (contract §8A, phase 046).
///
/// Built from the two off-journal events: `device.pairRequested` adds a
/// request - once, however many times it is repeated, since the server asks
/// again after every greeting - and `device.pairResolved` takes it away. A
/// request lives here only while the connection that told of it is greeted
/// (FR-008: the question is asked while the app is open and connected): the
/// list empties when the connection goes, and the next greeting brings back
/// exactly the requests that still wait - one that closed during the break is
/// never told of again, and would otherwise stay up for good.
///
/// Eager rather than lazy: the server asks right after a greeting, and the
/// first greeting can come before anything on screen has asked for this.
@Singleton(as: PairRequestService, env: [Environment.dev])
class PairRequestServiceImpl with BaseRepositoryHelper implements PairRequestService {
  PairRequestServiceImpl(this._socket) {
    _events = _socket.events.listen(_onEvent);
    _phases = _socket.phase.listen(_onPhase);
  }

  final NoxSocketClient _socket;

  final BehaviorSubject<List<PairRequest>> _requests = BehaviorSubject<List<PairRequest>>.seeded(const <PairRequest>[]);
  final PublishSubject<String> _closed = PublishSubject<String>();

  late final StreamSubscription<ServerEvent> _events;
  late final StreamSubscription<SessionPhase> _phases;

  @override
  Stream<List<PairRequest>> watchRequests() => _requests.stream;

  @override
  Stream<String> watchClosed() => _closed.stream;

  @override
  Future<RepositoryResult<bool>> answer({required String requestId, required bool allow}) {
    return execute<bool>(() async {
      // Only over the greeted connection: a request is on screen only while
      // there is one, and an answer queued for a later connection could reach
      // a request that closed in between.
      final reply = await _socket.send('device.approve', <String, dynamic>{
        'request_id': requestId,
        'allow': allow,
      }, waitForConnection: false);
      if (reply.ok) {
        // Not waiting for device.pairResolved, which is on its way: the
        // dialog closes on the answer.
        _close(requestId);
        return const RepositoryResult<bool>.success(data: true);
      }
      if (reply.errorCode == 'not_found') {
        // Closed already - its time, the new device's Cancel, or an answer
        // from this device's other connection. Nothing is left to ask.
        _close(requestId);
        return const RepositoryResult<bool>.success(data: false);
      }
      throw RepositoryException.fromWireCode(reply.errorCode ?? '');
    });
  }

  void _onEvent(ServerEvent event) {
    switch (event.event) {
      case ServerEvent.devicePairRequested:
        _asked(event.data);
      case ServerEvent.devicePairResolved:
        final id = event.data['request_id'];
        if (id is String) _close(id);
    }
  }

  void _asked(Map<String, dynamic> data) {
    final id = data['request_id'];
    if (id is! String || id.isEmpty) return;
    final request = PairRequest(requestId: id, platform: _platformOf(data['platform']), expiresAt: _instant(data['expires_at']));
    final current = _requests.value;
    final at = current.indexWhere((r) => r.requestId == id);
    if (at >= 0) {
      // Asked again after a greeting: the same request, in the same place.
      if (current[at] == request) return;
      _requests.add([...current]..[at] = request);
      return;
    }
    // The family is never logged, nor anything else the request carries: who
    // asked to join this person's devices is nobody's business but theirs.
    logRepository.debug(target: this, message: 'pairing: a new device asks to join');
    _requests.add([...current, request]);
  }

  void _close(String requestId) {
    final current = _requests.value;
    if (current.any((r) => r.requestId == requestId)) _requests.add(current.where((r) => r.requestId != requestId).toList());
    _closed.add(requestId);
  }

  void _onPhase(SessionPhase phase) {
    if (phase == SessionPhase.catchingUp || phase == SessionPhase.live) return;
    if (_requests.value.isNotEmpty) _requests.add(const <PairRequest>[]);
  }

  /// One of the five families, and nothing else ever: the dialog shows a
  /// word of the app's own for whatever this is.
  static DevicePlatform _platformOf(Object? value) => switch (value) {
    'ios' => DevicePlatform.ios,
    'android' => DevicePlatform.android,
    'macos' => DevicePlatform.macos,
    'windows' => DevicePlatform.windows,
    'linux' => DevicePlatform.linux,
    _ => DevicePlatform.unknown,
  };

  /// Unix seconds as an instant; null for anything that is not a number.
  static DateTime? _instant(Object? seconds) {
    if (seconds is! num || !seconds.isFinite) return null;
    return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true);
  }

  /// Stops listening. The app keeps this for its whole life; a test that
  /// builds its own does not.
  @visibleForTesting
  Future<void> dispose() async {
    await _events.cancel();
    await _phases.cancel();
    await _requests.close();
    await _closed.close();
  }
}
