@Tags(['golden'])
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/screens_gallery_page/screens_gallery_page.dart';

import '../../../utils/golden.dart';

void main() {
  // Wrapped in AppRootBloc to mirror production (AppRoot provides it above MaterialApp).
  goldenTest('screens_gallery_page', () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const ScreensGalleryPage()));
}
