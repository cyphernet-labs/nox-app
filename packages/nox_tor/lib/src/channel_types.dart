import 'dart:async';
import 'dart:typed_data';

/// Where a channel goes.
sealed class ChannelTarget {
  const ChannelTarget();

  String get host;
  int get port;
}

/// TCP to [host] - an IP literal or a name - and [port].
final class DirectTarget extends ChannelTarget {
  const DirectTarget(this.host, this.port);

  @override
  final String host;

  @override
  final int port;

  @override
  bool operator ==(Object other) => other is DirectTarget && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => 'DirectTarget($host:$port)';
}

/// A Tor stream to the onion service [host] (`<56>.onion`), always port 443.
final class OnionTarget extends ChannelTarget {
  const OnionTarget(this.host);

  @override
  final String host;

  @override
  int get port => 443;

  @override
  bool operator ==(Object other) => other is OnionTarget && other.host == host;

  @override
  int get hashCode => host.hashCode;

  /// Without the host: an onion address is never written anywhere it could
  /// be read back from.
  @override
  String toString() => 'OnionTarget([onion])';
}

/// Why a channel did not open, or why it closed: the `code` of the contract's
/// CLOSED event, in its order (`network` is 1).
enum ChannelFailure {
  /// The transport did not come up, or broke.
  network,

  /// Not done within the open's timeout.
  timeout,

  /// The TLS handshake failed.
  tls,

  /// An Eidolon message of the wrong length or with a bad signature - which is
  /// what a machine in the middle looks like - or a peer that does not speak
  /// the channel at all.
  protocol,

  /// The server proved a key other than the one the pairing link named.
  wrongServer,

  /// Tor is not up.
  torNotReady,

  /// The onion address is malformed.
  torOnionInvalid,

  /// The onion service was not found.
  torOnionNotFound,

  /// The onion service exists but does not answer.
  torOnionUnreachable,

  /// The onion service refused the Tor access key (until phase 045).
  torClientAuth,

  /// Something failed inside the module.
  internal;

  /// The kind a CLOSED `code` names; null for 0, closed normally. A code this
  /// build does not know is [internal].
  static ChannelFailure? fromCode(int code) {
    if (code == 0) return null;
    if (code < 1 || code > values.length) return internal;
    return values[code - 1];
  }
}

/// A channel that did not open. Carries the kind only - never an address, a
/// key or anything the module said about them.
class ChannelOpenException implements Exception {
  const ChannelOpenException(this.failure);

  final ChannelFailure failure;

  @override
  String toString() => 'ChannelOpenException(${failure.name})';
}

/// A channel that opened and then failed - reported on [NoxChannel.incoming]
/// after every byte that arrived before the failure.
class ChannelLostException implements Exception {
  const ChannelLostException(this.failure);

  final ChannelFailure failure;

  @override
  String toString() => 'ChannelLostException(${failure.name})';
}

/// The window of a channel, each way: the module holds at most this much
/// unacknowledged incoming data, and [NoxChannel.writable] holds a writer back
/// while more than this is queued to go out.
const int channelWindowBytes = 1 << 20;

/// Opens channels.
abstract interface class NoxChannelApi {
  /// Opens a channel to [target]; completes once it is verified (the server
  /// proved [serverKey], and this device proved the key of [deviceSeed]), or
  /// fails with [ChannelOpenException].
  ///
  /// [timeout] bounds transport, TLS and the check together. [cancel], when it
  /// completes first, abandons the open: the module drops it at once rather
  /// than at the end of [timeout] - how a caller that has stopped waiting, a
  /// connection pool timing a connect out, keeps nothing open behind its
  /// back.
  Future<NoxChannel> open(
    ChannelTarget target, {
    required Uint8List deviceSeed,
    required Uint8List serverKey,
    required Duration timeout,
    Future<void>? cancel,
  });
}

/// One verified connection to the server.
abstract interface class NoxChannel {
  /// The bytes the server sent. Done at the server's end of sending; an error
  /// ([ChannelLostException]) when the channel failed first. Single
  /// subscription; pausing it stops the module reading after one window.
  Stream<Uint8List> get incoming;

  /// Queues [bytes] to go out and returns how much is queued after the write.
  /// Throws [StateError] once the channel is closed or its sending is shut.
  int write(Uint8List bytes);

  /// Completes at once while the queue is within the window, else as soon as
  /// it has drained back within it - after about one chunk, so a slow upload
  /// keeps moving in small steps rather than half a window at a time.
  Future<void> get writable;

  /// Completes once everything queued before the call is written out; fails
  /// if the channel closes first.
  Future<void> flush();

  /// Ends sending after the queue (TLS `close_notify`); reading goes on.
  void shutdownWrite();

  /// Ends the channel at once.
  void close();

  /// Completes when the channel is gone: null when it closed normally, the
  /// kind when it failed.
  Future<ChannelFailure?> get closed;
}
