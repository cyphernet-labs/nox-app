import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/ui_kit_page/ui_kit_page.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_item_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('UiKitPage renders the component sections and toggles theme', (tester) async {
    await pumpApp(
      tester,
      BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const UiKitPage()),
      settle: false, // the gallery contains an endless spinner
    );

    expect(find.text('Primitives'), findsOneWidget);
    expect(find.byType(AppChatItemWidget), findsWidgets);

    // The theme toggle dispatches to AppRootBloc without throwing.
    await tester.tap(find.byTooltip(TextConstants.tooltipToggleTheme));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
