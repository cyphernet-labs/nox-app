import 'package:freezed_annotation/freezed_annotation.dart';

part 'pair_request.freezed.dart';

/// The OS family a device names itself by (contract §8A) - the five a device
/// may name, and [unknown] for anything else, so that no text from the wire
/// ever reaches the screen: a leaked invite must not be able to call itself
/// whatever it likes in the dialog that asks to let it in.
enum DevicePlatform { ios, android, macos, windows, linux, unknown }

/// A new device asks to join this person's devices through an invite THIS
/// device issued (contract §8A, phase 046), and waits for its answer.
///
/// What the issuing device is told, and no more: the request, the new
/// device's OS family and the deadline. No key, and no model - the family is
/// enough to recognise a laptop the person is holding.
@freezed
abstract class PairRequest with _$PairRequest {
  const factory PairRequest({
    required String requestId,
    required DevicePlatform platform,

    /// The request's deadline by the server's clock, as it stated it; null
    /// when it did not. The server closes the request itself when it passes.
    DateTime? expiresAt,
  }) = _PairRequest;
}
