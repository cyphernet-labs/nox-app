@Tags(['golden'])
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/ui_kit_page/ui_kit_page.dart';

import '../../../utils/golden.dart';

void main() {
  // settle: false — the gallery renders an endless spinner. Wrapped in AppRootBloc
  // to mirror production (the theme toggle reads it).
  goldenTest('ui_kit_page', () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const UiKitPage()), settle: false);
}
