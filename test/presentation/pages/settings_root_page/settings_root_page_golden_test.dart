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
  // The identity card / Show QR loads the id from the session spine on init.
  registerFakeSession();
  tearDownAll(getIt.reset);

  // Mobile layout: identity card + flat settings rows + Log out.
  goldenTest('settings_root_page', () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const SettingsRootPage()));
  // Desktop `_wide` branch: the list-detail (master list + detail pane).
  goldenTestDesktop('settings_root_page', () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const SettingsRootPage()));
}
