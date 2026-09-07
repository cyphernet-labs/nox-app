@Tags(['golden'])
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';

import '../../../utils/fake_session_repository.dart';
import '../../../utils/golden.dart';

void main() {
  group('the owner', () {
    // The identity card / Show QR loads the id from the session spine on init.
    setUpAll(() => registerFakeSession(session: kTestSession.copyWith(isOwner: true)));
    tearDownAll(getIt.reset);

    // Mobile layout: identity card + flat settings rows + Log out.
    goldenTest('settings_root_page', () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const SettingsRootPage()));
    // Desktop `_wide` branch: the list-detail (master list + detail pane).
    goldenTestDesktop('settings_root_page', () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const SettingsRootPage()));
  });

  group('somebody who is not the owner', () {
    // The badge-less page needs its own baselines at BOTH widths. Without them
    // the only page-level state locked is the one with the badge, and a
    // regression that renders it unconditionally - or that breaks the name row
    // only when it is absent - passes the whole suite. It is also the state
    // every non-owner will see once 034 lands, and the state anyone sees
    // against a server that has not stated ownership.
    setUpAll(() => registerFakeSession(session: kTestSession.copyWith(isOwner: false)));
    tearDownAll(getIt.reset);

    goldenTest('settings_root_page_member', () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const SettingsRootPage()));
    goldenTestDesktop(
      'settings_root_page_member',
      () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const SettingsRootPage()),
    );
  });
}
