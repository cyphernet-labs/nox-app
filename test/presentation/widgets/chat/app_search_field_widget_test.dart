import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/chat/app_search_field_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppSearchFieldWidget', () {
    testWidgets('shows the hint and reports typed text via onChanged', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? changed;
      await pumpApp(tester, AppSearchFieldWidget(controller: controller, onChanged: (value) => changed = value));

      expect(find.text(TextConstants.searchHint), findsOneWidget);

      await tester.enterText(find.byType(SearchBar), 'design');
      expect(changed, 'design');
      expect(controller.text, 'design');
    });
  });
}
