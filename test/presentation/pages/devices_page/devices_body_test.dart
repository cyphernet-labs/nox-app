import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/device/device_model.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/devices_page/bloc/devices_bloc.dart';
import 'package:nox_app/presentation/pages/devices_page/devices_page.dart';

import 'package:nox_app/presentation/widgets/settings/app_settings_group_widget.dart';

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
    await pumpApp(tester, DevicesPage(initialState: _state().copyWith(actionFailedKey: 'k-desktop')));

    expect(find.text(l10nEn.devicesRevokeError), findsOneWidget);
    expect(find.text(l10nEn.devicesError), findsNothing);
  });

  testWidgets('a list that failed to load says THAT, over the rows it still has', (tester) async {
    await pumpApp(tester, DevicesPage(initialState: _state().copyWith(failed: true)));

    expect(find.text(l10nEn.devicesError), findsOneWidget);
    expect(find.text(l10nEn.devicesRevokeError), findsNothing);
  });

  testWidgets('every device sits in ONE group - this one first, and saying so', (tester) async {
    // It used to be two cards, the first holding a single row, with a gap
    // between them: two unrelated sections rather than one list of this
    // person's devices.
    await pumpApp(tester, DevicesPage(initialState: _state()));

    expect(find.byType(AppSettingsGroupWidget), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
    // First in the list, which is the other half of how the current one is told
    // apart now that it shares a card with the rest.
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(find.descendant(of: find.byWidget(tiles.first), matching: find.textContaining(l10nEn.devicesCurrent)), findsOneWidget);
  });

  testWidgets('Revoke is destructive, and rendered as destructive', (tester) async {
    // It was the brand accent - the same teal as `Add a device` directly below,
    // which is the colour this app uses for the thing it wants you to do. The
    // action cannot be undone without a new pairing link, and on this device it
    // signs you out.
    await pumpApp(tester, DevicesPage(initialState: _state()));

    final colors = Theme.of(tester.element(find.byType(AppSettingsGroupWidget))).colorScheme;
    for (final button in tester.widgetList<TextButton>(find.widgetWithText(TextButton, l10nEn.devicesRevoke))) {
      final foreground = button.style?.foregroundColor?.resolve(<WidgetState>{});
      expect(foreground, colors.error, reason: 'Revoke is not rendered in the error role');
    }
  });
}
