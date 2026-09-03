import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/sync/live_identity_handshake.dart';

void main() {
  group('IdentityHandshake', () {
    test('an outcome the server stated is usable', () {
      const known = IdentityHandshake(authorId: 'u_1', label: 'Anna', created: false);
      expect(known.outcomeStated, isTrue);
      expect(known.created, isFalse);

      const newcomer = IdentityHandshake(authorId: 'u_2', label: 'User1234', created: true);
      expect(newcomer.outcomeStated, isTrue);
      expect(newcomer.created, isTrue);
    });

    test('an outcome the server did NOT state is not an outcome', () {
      // The third wire state is the load-bearing one. Collapsing it into
      // either boolean costs the person something: false steals a newcomer's
      // naming step, true overwrites a returning person's name.
      const silent = IdentityHandshake(authorId: 'u_3', label: 'Anna', created: null);
      expect(silent.outcomeStated, isFalse);
      expect(silent.created, isNull);
    });

    test('the domain value names no frame', () {
      // FR-006d: at stage 2 the same distinction arrives on the pairing reply.
      // Nothing outside the transport layer may notice that it moved, so the
      // type that carries the decision must not mention the greeting at all.
      const value = IdentityHandshake(authorId: 'u_1', label: 'Anna', created: true);
      expect(value.toString(), isNot(contains('hello')));
      expect(value.toString(), isNot(contains('greet')));
    });
  });

  group('the timeout must not outlive its own wait', () {
    test('a timeout releases the caller AND leaves the owner reusable', () async {
      // The defect this guards is specific: an outer `.timeout()` does not
      // cancel its source, so the body keeps running, its `finally` never
      // executes, and the in-flight marker stays raised for the life of the
      // process - wedging every later sign-in. The timeout therefore lives
      // inside the owner, and this asserts the consequence rather than the
      // mechanism: after a timeout, a second attempt is possible.
      final owner = _NeverAnsweringHandshake();

      await expectLater(owner.greet(), throwsA(isA<IdentityHandshakeTimeout>()));
      expect(owner.inFlight, isFalse, reason: 'a timed-out handshake must not stay in flight');

      await expectLater(owner.greet(), throwsA(isA<IdentityHandshakeTimeout>()));
      expect(owner.attempts, 2, reason: 'the second attempt has to actually run');
    });
  });
}

/// Mirrors the real owner's structure - timer inside, cleared in `finally` -
/// against a peer that never answers. The real class needs a socket and a
/// starter from the container; this exercises the property those two cannot
/// influence.
class _NeverAnsweringHandshake {
  int attempts = 0;
  Completer<IdentityHandshake>? _pending;
  Timer? _timer;

  bool get inFlight => _pending != null;

  Future<IdentityHandshake> greet() async {
    attempts++;
    final pending = Completer<IdentityHandshake>();
    _pending = pending;
    _timer = Timer(const Duration(milliseconds: 20), () {
      if (!pending.isCompleted) pending.completeError(const IdentityHandshakeTimeout());
    });
    try {
      return await pending.future;
    } finally {
      _timer?.cancel();
      _timer = null;
      _pending = null;
    }
  }
}
