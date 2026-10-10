import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/connection/connection_settings.dart';

part 'pending_pairing.freezed.dart';

/// A pairing through an invite that waits for approval on the device that
/// issued it (phase 046), as this install remembers it across a restart
/// (FR-011): presenting the same link again from the same device is the same
/// request, so this is everything needed to go on waiting for it.
@freezed
abstract class PendingPairing with _$PendingPairing {
  const factory PendingPairing({
    /// The pairing link as it arrived. It carries the token - a credential -
    /// so it is kept only in secure storage, and only while the wait lasts.
    required String link,

    /// When this device stops waiting, on its own clock: the invite's ten
    /// minutes from the moment the request was first reported waiting, and a
    /// little more for the server to say so itself. A resumed wait keeps the
    /// first deadline rather than starting a new one.
    required DateTime waitUntil,

    /// What the person confirmed on the connection screen, so the wait goes
    /// on over the same path - Tor included, when they allowed it.
    ConnectionSettings? connection,
  }) = _PendingPairing;
}
