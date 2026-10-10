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

/// A version-3 link with one direct address and nothing else - the contract's
/// `minimal` vector: neither an onion nor a public address, so it works only
/// on the home network (phase 045).
const DeviceInvite _homeOnlyInvite = DeviceInvite(
  link: 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7',
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

  // An invite whose link carries neither an onion nor a public address (phase
  // 045): the card says it works only on the home network. Pinned on both
  // widths because the card sits above the list and the extra line moves
  // everything under it.
  goldenTest('devices_page_invite_home_only', () => DevicesPage(initialState: _state().copyWith(invite: _homeOnlyInvite)));
  goldenTestDesktop('devices_page_invite_home_only', () => DevicesPage(initialState: _state().copyWith(invite: _homeOnlyInvite)));

  // Nothing but this device: the sentence has to say so rather than showing a
  // blank pane.
  goldenTest('devices_page_alone', () => DevicesPage(initialState: _state().copyWith(devices: [_state().devices.first])));
  goldenTestDesktop('devices_page_alone', () => DevicesPage(initialState: _state().copyWith(devices: [_state().devices.first])));
}
