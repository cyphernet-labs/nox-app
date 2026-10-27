@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_search_field_widget.dart';

import '../../../utils/golden.dart';

void main() {
  goldenTest('app_search_field_widget', () => AppSearchFieldWidget(controller: TextEditingController()));
}
