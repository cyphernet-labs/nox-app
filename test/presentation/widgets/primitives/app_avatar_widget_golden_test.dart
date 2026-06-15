@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/primitives/app_avatar_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_avatar_widget',
    () => const Center(
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          AppAvatarWidget(name: 'Ann Lee'),
          AppAvatarWidget(name: 'Bob'),
          AppAvatarWidget(name: '   '), // no valid initials → forum glyph fallback
          AppAvatarWidget(name: 'Cyphernet', size: 56),
        ],
      ),
    ),
  );
}
