@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/primitives/app_file_glyph_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_file_glyph_widget',
    () => const Center(
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          AppFileGlyphWidget(type: FileType.pdf),
          AppFileGlyphWidget(type: FileType.image),
          AppFileGlyphWidget(type: FileType.archive),
          AppFileGlyphWidget(type: FileType.other),
        ],
      ),
    ),
  );
}
