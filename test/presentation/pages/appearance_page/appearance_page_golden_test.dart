@Tags(['golden'])
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/appearance_page/appearance_page.dart';

import '../../../utils/golden.dart';

void main() {
  // Fresh AppRootBloc → System selected.
  goldenTest('appearance_page', () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const AppearancePage()));
}
