import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_segmented_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('AppSegmentedWidget reports the newly selected value', (tester) async {
    int? picked;
    await pumpApp(tester, AppSegmentedWidget<int>(options: const {0: 'One', 1: 'Two'}, selected: 0, onChanged: (value) => picked = value));

    await tester.tap(find.text('Two'));
    expect(picked, 1);
  });
}
