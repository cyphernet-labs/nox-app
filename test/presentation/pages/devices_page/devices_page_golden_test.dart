@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/device/device_invite.dart';
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

/// A version-3 link as the server issues one: the address it listens on, then
/// its onion address, kept for after the pairing.
const DeviceInvite _homeOnlyInvite = DeviceInvite(
  link:
      'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7BCAXy3n7K0Eg8rHsZeQZjW4Iso6BP-sB5KQAg5uF4YCAzg',
  onion: false,
);

void main() {
  goldenTest('devices_page', () => DevicesPage(initialState: _state()));
  goldenTestDesktop('devices_page', () => DevicesPage(initialState: _state()));

  // A revoke that did not happen. Pinned on both widths because it is the one
  // thing 038 added to the LAYOUT of this screen - its own sentence above the
  // list, deliberately not the list's own "Couldn't load your devices."
  goldenTest('devices_page_action_error', () => DevicesPage(initialState: _state().copyWith(actionFailedKey: 'k-desktop')));
  goldenTestDesktop('devices_page_action_error', () => DevicesPage(initialState: _state().copyWith(actionFailedKey: 'k-desktop')));

  // An invite that pairs only at home (040, FR-019) - every invite until phase
  // 045, since the onion service opens only for a paired device's key (044,
  // FR-019): the card says the link works only on the home network. Pinned on
  // both widths because the card sits above the list and the extra line moves
  // everything under it.
  goldenTest('devices_page_invite_home_only', () => DevicesPage(initialState: _state().copyWith(invite: _homeOnlyInvite)));
  goldenTestDesktop('devices_page_invite_home_only', () => DevicesPage(initialState: _state().copyWith(invite: _homeOnlyInvite)));

  // Nothing but this device: the sentence has to say so rather than showing a
  // blank pane.
  goldenTest('devices_page_alone', () => DevicesPage(initialState: _state().copyWith(devices: [_state().devices.first])));
  goldenTestDesktop('devices_page_alone', () => DevicesPage(initialState: _state().copyWith(devices: [_state().devices.first])));
}
