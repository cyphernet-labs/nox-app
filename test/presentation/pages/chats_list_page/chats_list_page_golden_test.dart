@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/pages/chats_list_page/chats_list_page.dart';

import '../../../utils/golden.dart';

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  // Mobile layout: AppBar wordmark + search + the chat list (the first viewport
  // rows use the stable relative-time buckets). Desktop list-detail is verified by
  // the widget test at a wide surface.
  goldenTest('chats_list_page', () => const ChatsListPage());
}
