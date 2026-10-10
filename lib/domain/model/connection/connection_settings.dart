import 'package:freezed_annotation/freezed_annotation.dart';

part 'connection_settings.freezed.dart';

/// What the person confirmed on the connection screen before pairing (phase
/// 045, FR-013): where to reach the server and whether Tor may be used. The
/// server key is never among it - it comes from the link alone, and every
/// connection is checked against it whatever address it went to.
@freezed
abstract class ConnectionSettings with _$ConnectionSettings {
  const factory ConnectionSettings({
    /// `host:port`: the field "Server address".
    required String serverAddress,

    /// `<56>.onion:443`, or null for an empty field - no onion address.
    String? onionAddress,

    /// `Use Tor`.
    @Default(false) bool useTor,
  }) = _ConnectionSettings;
}
