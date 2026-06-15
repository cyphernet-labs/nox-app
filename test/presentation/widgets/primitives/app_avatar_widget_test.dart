import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/presentation/widgets/primitives/app_avatar_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppAvatarWidget', () {
    testWidgets('shows initials for a valid name', (tester) async {
      await pumpApp(tester, const AppAvatarWidget(name: 'Ann Lee'));

      expect(find.text('AL'), findsOneWidget);
    });

    testWidgets('falls back to a glyph when there are no valid initials', (tester) async {
      await pumpApp(tester, const AppAvatarWidget(name: '   '));

      expect(find.byType(AppIconWidget), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    test('background color is deterministic per name', () {
      expect(noxAvatarColor('Ann Lee'), noxAvatarColor('Ann Lee'));
    });
  });
}
