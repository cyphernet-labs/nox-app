@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_composer_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_composer_widget',
    () => Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppComposerWidget(controller: TextEditingController()),
        AppComposerWidget(
          controller: TextEditingController(text: 'Draft message'),
          attachment: const AppFileChipWidget(type: FileType.image, name: 'photo.png', size: '1.1 MB', removable: true),
        ),
      ],
    ),
  );
}
