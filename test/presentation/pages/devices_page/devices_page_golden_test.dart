@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/device/device_model.dart';
import 'package:nox_app/presentation/pages/devices_page/bloc/devices_bloc.dart';
import 'package:nox_app/presentation/pages/devices_page/devices_page.dart';

import '../../../utils/golden.dart';

/// The list comes from a server, and there is none under test, so the state is
/// seeded through the page's test seam - the same way the chats-list scenarios
/// pin states the mock world cannot reach.
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
  goldenTest('devices_page', () => DevicesPage(initialState: _state()));
  goldenTestDesktop('devices_page', () => DevicesPage(initialState: _state()));

  // Nothing but this device: the sentence has to say so rather than showing a
  // blank pane.
  goldenTest('devices_page_alone', () => DevicesPage(initialState: _state().copyWith(devices: [_state().devices.first])));
  goldenTestDesktop('devices_page_alone', () => DevicesPage(initialState: _state().copyWith(devices: [_state().devices.first])));
}
