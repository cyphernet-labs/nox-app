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

    testWidgets('initials override is rendered while the background stays hashed from name', (tester) async {
      await pumpApp(tester, const AppAvatarWidget(name: 'User7421', initials: 'AB'));

      // The override is drawn verbatim, not noxInitials('User7421') ('US').
      expect(find.text('AB'), findsOneWidget);
      expect(find.text('US'), findsNothing);

      // The background remains hashed from `name`, independent of the override.
      final decoration = tester.widget<Container>(find.byType(Container)).decoration! as BoxDecoration;
      expect(decoration.color, noxAvatarColor('User7421'));
    });

    test('background color is deterministic per name', () {
      expect(noxAvatarColor('Ann Lee'), noxAvatarColor('Ann Lee'));
    });

    test('background color is always a member of the avatar palette', () {
      expect(noxAvatarPalette, contains(noxAvatarColor('Ann Lee')));
    });

    test('different names can resolve to different palette entries', () {
      // 'Ann Lee' hashes to index 5, 'Charlie' to index 2.
      expect(noxAvatarColor('Ann Lee'), isNot(noxAvatarColor('Charlie')));
    });

    test('initials use the first two words of a multi-word name', () {
      expect(noxInitials('Mary Jane Watson'), 'MJ');
    });

    test('initials fall back to the first two alphanumerics of a single-word name', () {
      expect(noxInitials('Cher'), 'CH');
    });

    test('initials skip a leading non-letter from the allowed label charset', () {
      // '_bob' starts with '_' (not alphanumeric), so the two-word branch is
      // skipped and the first two alphanumerics of the whole name are used.
      expect(noxInitials('_bob smith'), 'BO');
    });

    test('initials are normalized to uppercase', () {
      expect(noxInitials('ann lee'), 'AL');
    });
  });
}
