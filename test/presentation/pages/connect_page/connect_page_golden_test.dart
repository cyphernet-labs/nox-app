@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/presentation/pages/connect_page/bloc/connect_bloc.dart';
import 'package:nox_app/presentation/pages/connect_page/connect_page.dart';

import '../../../utils/golden.dart';

/// The contract's `full` vector: a direct address, a name and an onion service.
const String _link =
    'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7AxFub3guZXhhbXBsZS5vcmcg-wQgF8t5-ytBIPKx7GXkGY1uCLKOgT_rAeSkAIObheGAgM4';

const String _onion = '25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion';

/// The fields as a link carrying both addresses fills them. Seeded rather
/// than derived: the onion address comes from the Tor module, which no golden
/// loads.
const ConnectState _prefilled = ConnectState(
  serverAddress: '192.168.1.20:8443',
  onionAddress: _onion,
  linkServerAddress: '192.168.1.20:8443',
  linkOnionAddress: _onion,
);

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  // What a link with an onion address puts on the screen: both fields filled,
  // Use Tor off, the server key nowhere.
  goldenTest('connect_page', () => const ConnectPage(link: _link, initialState: _prefilled));
  goldenTestDesktop('connect_page', () => const ConnectPage(link: _link, initialState: _prefilled));

  // A link without one: the onion field empty, and saying it is optional.
  goldenTest(
    'connect_page_no_onion',
    () => const ConnectPage(
      link: _link,
      initialState: ConnectState(serverAddress: '192.168.1.20:8443', linkServerAddress: '192.168.1.20:8443'),
    ),
  );
  goldenTestDesktop(
    'connect_page_no_onion',
    () => const ConnectPage(
      link: _link,
      initialState: ConnectState(serverAddress: '192.168.1.20:8443', linkServerAddress: '192.168.1.20:8443'),
    ),
  );

  // Connect pressed over an address that cannot be one: the error at its
  // field, nothing gone out (US5, scenario 1).
  const fieldError = ConnectState(
    serverAddress: '192.168.1.20:8443',
    onionAddress: 'example.onion',
    linkServerAddress: '192.168.1.20:8443',
    linkOnionAddress: _onion,
    onionAddressInvalid: true,
    showFieldErrors: true,
  );
  goldenTest('connect_page_field_error', () => const ConnectPage(link: _link, initialState: fieldError));
  goldenTestDesktop('connect_page_field_error', () => const ConnectPage(link: _link, initialState: fieldError));

  // A failed attempt, said under Connect: no direct answer, Use Tor off, and
  // an onion address there to use (US3, scenario 2).
  final failed = _prefilled.copyWith(status: ConnectStatus.failed, problem: ConnectionProblem.turnOnTor);
  goldenTest('connect_page_reason', () => ConnectPage(link: _link, initialState: failed));
  goldenTestDesktop('connect_page_reason', () => ConnectPage(link: _link, initialState: failed));
}
