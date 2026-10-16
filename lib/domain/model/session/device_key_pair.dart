import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_key_pair.freezed.dart';

/// This device's key pair, as RustSecureBox made it (phase 050): base64 of 32
/// bytes each. Made once, on the way into the first pairing after an install
/// or a logout, and kept in the secure store for this device only.
///
/// [publicKey] is what the server knows the device by - `device_key` in the
/// device list, the key `device.revoke` names - and is kept beside the private
/// half rather than worked out again, because the two disagreeing is how the
/// app tells a pair made by another implementation of the check (FR-019).
@freezed
abstract class DeviceKeyPair with _$DeviceKeyPair {
  const factory DeviceKeyPair({
    /// The private half. Goes to the channel at every open, and nowhere else.
    required String privateKey,

    /// The public half.
    required String publicKey,
  }) = _DeviceKeyPair;
}
