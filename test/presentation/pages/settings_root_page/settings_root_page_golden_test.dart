@Tags(['golden'])
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';

import '../../../utils/golden.dart';

void main() {
  // Mobile layout: identity card + flat settings rows + Log out (the desktop
  // list-detail is verified by the widget test at a wide surface).
  goldenTest('settings_root_page', () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const SettingsRootPage()));
}
