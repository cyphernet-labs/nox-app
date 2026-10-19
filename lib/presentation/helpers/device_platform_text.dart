import 'package:nox_app/domain/model/device/pair_request.dart';
import 'package:nox_app/l10n/app_localizations.dart';

/// The ONE place a device's OS family is worded - the devices list (7.8) and
/// the request dialog (8.2) name a system with the same words.
abstract final class DevicePlatformText {
  static String of(AppLocalizations l10n, DevicePlatform platform) => switch (platform) {
    DevicePlatform.ios => l10n.devicePlatformIos,
    DevicePlatform.android => l10n.devicePlatformAndroid,
    DevicePlatform.macos => l10n.devicePlatformMacos,
    DevicePlatform.windows => l10n.devicePlatformWindows,
    DevicePlatform.linux => l10n.devicePlatformLinux,
    DevicePlatform.unknown => l10n.devicePlatformUnknown,
  };
}
