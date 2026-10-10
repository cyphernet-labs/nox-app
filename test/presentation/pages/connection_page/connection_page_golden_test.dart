@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/presentation/pages/connection_page/bloc/connection_settings_bloc.dart';
import 'package:nox_app/presentation/pages/connection_page/connection_page.dart';

import '../../../utils/golden.dart';

const String _onion = '25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion';

/// The section as a server with a public and an onion address leaves it, with
/// Use Tor on. Seeded: the values come from a server, and there is none here.
const ConnectionSettingsState _settled = ConnectionSettingsState(
  loading: false,
  serverAddress: 'nox.example.org:8443',
  appliedServerAddress: 'nox.example.org:8443',
  onionAddress: _onion,
  appliedOnionAddress: _onion,
  serverDefaultAddress: 'nox.example.org:8443',
  serverDefaultOnion: _onion,
  useTor: true,
);

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  // The fields as they stand, Save off - nothing changed - and Use Tor on.
  goldenTest('connection_page', () => const ConnectionPage(initialState: _settled));
  goldenTestDesktop('connection_page', () => const ConnectionPage(initialState: _settled));

  // No connection, and why: the line above the fields (FR-017).
  final down = _settled.copyWith(offline: true, problem: ConnectionProblem.onionNotFound);
  goldenTest('connection_page_problem', () => ConnectionPage(initialState: down));
  goldenTestDesktop('connection_page_problem', () => ConnectionPage(initialState: down));

  // An edit that is not an address: the field says so, and Save stays off.
  final invalid = _settled.copyWith(onionAddress: 'example.onion', onionAddressInvalid: true);
  goldenTest('connection_page_field_error', () => ConnectionPage(initialState: invalid));
  goldenTestDesktop('connection_page_field_error', () => ConnectionPage(initialState: invalid));
}
