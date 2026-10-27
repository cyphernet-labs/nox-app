import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nox_app/design/gen/assets.gen.dart';

/// Registers the licences of the fonts the app bundles, so they travel with the
/// fonts and show in any licence page: Roboto (Apache 2.0) and Roboto Mono
/// (SIL Open Font License 1.1), as each file's own name table states. Both
/// licences ask that their text accompany the font wherever it is distributed.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['Roboto'], await rootBundle.loadString(Assets.licenses.robotoApache));
    yield LicenseEntryWithLineBreaks(const ['Roboto Mono'], await rootBundle.loadString(Assets.licenses.robotoMonoOfl));
  });
}
