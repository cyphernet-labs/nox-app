@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_icon_widget',
    () => Center(
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [AppIconWidget(NoxIcons.forum), AppIconWidget(NoxIcons.forumFill), AppIconWidget(NoxIcons.search, size: 32)],
      ),
    ),
  );
}
