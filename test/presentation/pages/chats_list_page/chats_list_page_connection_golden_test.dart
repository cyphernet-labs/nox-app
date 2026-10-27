@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/presentation/pages/chats_list_page/bloc/chats_list_bloc.dart';
import 'package:nox_app/presentation/pages/chats_list_page/chats_list_page.dart';

import '../../../utils/fixed_connection_status.dart';
import '../../../utils/golden.dart';

/// 5.1 with the connection corner (phase 040): the narrow app bar while the
/// connection goes through Tor and while it comes up through Tor, and the
/// request to update when the Tor network refused this build - on both
/// widths.
void main() {
  final status = FixedConnectionStatusService();

  setUpAll(() async {
    await configureDependencies(Environment.test);
    getIt.allowReassignment = true;
    getIt.registerSingleton<ConnectionStatusService>(status);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  goldenTest('chats_list_page_tor', () {
    status.value = FixedConnectionStatusService.tor;
    return const ChatsListPage(inShell: true);
  });

  goldenTest('chats_list_page_connecting_tor', () {
    status.value = FixedConnectionStatusService.connectingTor;
    return const ChatsListPage(inShell: true);
  });

  goldenTest('chats_list_page_tor_obsolete', () {
    status.value = FixedConnectionStatusService.direct;
    return const ChatsListPage(inShell: true, initialScenario: ChatsListScenario.torObsolete);
  });

  goldenTestDesktop('chats_list_page_tor_obsolete', () {
    status.value = FixedConnectionStatusService.direct;
    return const ChatsListPage(inShell: false, initialScenario: ChatsListScenario.torObsolete);
  });
}
