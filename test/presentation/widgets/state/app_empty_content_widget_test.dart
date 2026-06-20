import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/presentation/widgets/state/app_empty_content_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('AppEmptyContentWidget shows illustration, title and message', (tester) async {
    await pumpApp(
      tester,
      AppEmptyContentWidget(illustration: Assets.svg.illustrations.emptyChats, title: 'No chats', message: 'Start a conversation'),
    );

    expect(find.text('No chats'), findsOneWidget);
    expect(find.text('Start a conversation'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
  });
}
