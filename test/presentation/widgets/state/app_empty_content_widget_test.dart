import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/presentation/widgets/state/app_empty_content_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('shows the glyph, the title and the message', (tester) async {
    await pumpApp(tester, AppEmptyContentWidget(glyph: NoxIcons.forum, title: 'No chats', message: 'Start a conversation'));

    expect(find.text('No chats'), findsOneWidget);
    expect(find.text('Start a conversation'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('the art box carries both brand accents', (tester) async {
    // The design composes this state from a stock glyph plus two brand dots. They
    // are the only colour in it, and they are brand-fixed rather than a
    // `ColorScheme` role - a theme change must not take them with it.
    await pumpApp(tester, AppEmptyContentWidget(glyph: NoxIcons.forum, title: 'No chats', message: 'Start a conversation'));

    final dots = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.shape == BoxShape.circle)
        .map((d) => d.color)
        .toList();

    expect(dots, containsAll(<Color>[NoxBrand.teal, NoxBrand.gold]));
  });
}
