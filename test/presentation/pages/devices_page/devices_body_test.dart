import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/device/device_model.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/devices_page/bloc/devices_bloc.dart';
import 'package:nox_app/presentation/pages/devices_page/devices_page.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

/// Seeded through the page's test seam: the list comes from a server, and the
/// two failures below are answers a mock world cannot give.
DevicesState _state() => DevicesState(
  loading: false,
  devices: [
    DeviceModel(
      deviceKey: 'k-phone',
      platform: 'ios',
      pairedAt: DateTime.utc(2026, 6, 1),
      lastSeenAt: DateTime.utc(2026, 6, 15),
      isCurrent: true,
    ),
    DeviceModel(
      deviceKey: 'k-desktop',
      platform: 'macos',
      pairedAt: DateTime.utc(2026, 5, 10),
      lastSeenAt: DateTime.utc(2026, 6, 14),
      isCurrent: false,
    ),
  ],
);

void main() {
  // The two failures answer different questions and must not be told in the
  // same sentence: since 038 the screen re-reads the list on its own, so a
  // revoke can fail on a list that loaded perfectly well, and blaming the load
  // sends the person looking at their connection instead of trying again.
  testWidgets('a revoke that failed says so, and does not blame the list', (tester) async {
    await pumpApp(tester, DevicesPage(initialState: _state().copyWith(actionFailed: true)));

    expect(find.text(l10nEn.devicesRevokeError), findsOneWidget);
    expect(find.text(l10nEn.devicesError), findsNothing);
  });

  testWidgets('a list that failed to load says THAT, over the rows it still has', (tester) async {
    await pumpApp(tester, DevicesPage(initialState: _state().copyWith(failed: true)));

    expect(find.text(l10nEn.devicesError), findsOneWidget);
    expect(find.text(l10nEn.devicesRevokeError), findsNothing);
  });
}
