@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/presentation/widgets/state/app_empty_content_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_empty_content_widget',
    () => AppEmptyContentWidget(
      illustration: Assets.svg.illustrations.emptyChats,
      title: 'No chats yet',
      message: 'Create the first chat to get the conversation going.',
    ),
  );
}
