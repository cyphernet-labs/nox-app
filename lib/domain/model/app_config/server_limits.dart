import 'package:freezed_annotation/freezed_annotation.dart';

part 'server_limits.freezed.dart';

/// Server-declared payload bounds from the session.hello handshake
/// (contract v0 §3). Consumers (composer, picker) preflight against these
/// instead of discovering a payload_too_large on send. Until the WebSocket
/// transport lands (phase 027) the values stay at the contract defaults.
@freezed
abstract class ServerLimits with _$ServerLimits {
  const factory ServerLimits({required int maxMessageBytes, required int maxAttachmentBytes, required int maxFrameBytes}) = _ServerLimits;

  /// Contract v0 §3 defaults, served until a live handshake overrides them.
  static const ServerLimits contractDefaults = ServerLimits(maxMessageBytes: 65536, maxAttachmentBytes: 104857600, maxFrameBytes: 131072);
}
