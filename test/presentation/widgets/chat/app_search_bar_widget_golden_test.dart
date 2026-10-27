@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_search_bar_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest(
    'app_search_bar_widget',
    () => const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppSearchBarWidget(),
          SizedBox(height: 16),
          AppSearchBarWidget(value: 'cyphernet'),
        ],
      ),
    ),
  );
}
