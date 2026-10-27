@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_file_chip_widget',
    () => const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFileChipWidget(type: FileType.pdf, name: 'report.pdf', size: '2.4 MB'),
          SizedBox(height: 12),
          AppFileChipWidget(type: FileType.archive, name: 'logs-2026-06-15.zip', size: '512 KB', removable: true),
        ],
      ),
    ),
  );
}
