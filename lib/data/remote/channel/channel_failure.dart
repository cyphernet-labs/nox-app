import 'package:dio/dio.dart';
import 'package:nox_tor/channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

export 'package:nox_tor/channel.dart' show ChannelFailure, ChannelLostException, ChannelOpenException;

/// The channel failure behind [error], however the transports wrapped it; null
/// when the error says nothing about the channel.
///
/// A refusal is decided in the module, before HTTP exists, and both transports
/// then pass it up in their own envelopes: `web_socket_channel` as the `inner`
/// of a [WebSocketChannelException], Dio as the `error` of a [DioException].
/// Classifying by the envelope alone would read "the server proved another
/// key" as "the network is down" - the confusion phase 036 removed, and the
/// one that must never lead anywhere near a logout.
ChannelFailure? channelFailureOf(Object? error) {
  var current = error;
  // Bounded: an envelope that names itself would otherwise loop for ever.
  for (var depth = 0; depth < 8 && current != null; depth++) {
    switch (current) {
      case ChannelOpenException(:final failure):
        return failure;
      case ChannelLostException(:final failure):
        return failure;
      case WebSocketChannelException(:final inner):
        current = inner;
      case DioException(:final error):
        current = error;
      default:
        return null;
    }
  }
  return null;
}
