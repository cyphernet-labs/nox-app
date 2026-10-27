import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/theme/nox_text_theme.dart';

/// US4 / FR-009 — AppTextStyleTokens reproduces the FULL noxTextTheme M3 scale (9 roles):
/// matching fontWeight + letterSpacing + relative fontSize, with no height and no fontFamily.
/// Expectations are derived from noxTextTheme so the two cannot silently drift.
void main() {
  testWidgets('reproduces all 9 noxTextTheme roles (weight, letterSpacing, size ratio); no height/family', (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(393, 852),
        fontSizeResolver: AppTextStyleTokens.fontSizeResolver,
        builder: (context, _) {
          const c = Color(0xFF000000);
          // factory under test -> the matching noxTextTheme role (source of truth)
          final pairs = <String, (TextStyle, TextStyle)>{
            'displaySmall': (AppTextStyleTokens.displaySmall(color: c), noxTextTheme.displaySmall!),
            'headlineSmall': (AppTextStyleTokens.headlineSmall(color: c), noxTextTheme.headlineSmall!),
            'titleLarge': (AppTextStyleTokens.titleLarge(color: c), noxTextTheme.titleLarge!),
            'titleMedium': (AppTextStyleTokens.titleMedium(color: c), noxTextTheme.titleMedium!),
            'bodyLarge': (AppTextStyleTokens.bodyLarge(color: c), noxTextTheme.bodyLarge!),
            'bodyMedium': (AppTextStyleTokens.bodyMedium(color: c), noxTextTheme.bodyMedium!),
            'labelLarge': (AppTextStyleTokens.labelLarge(color: c), noxTextTheme.labelLarge!),
            'labelMedium': (AppTextStyleTokens.labelMedium(color: c), noxTextTheme.labelMedium!),
            'labelSmall': (AppTextStyleTokens.labelSmall(color: c), noxTextTheme.labelSmall!),
          };
          expect(pairs.length, 9, reason: 'full M3 scale has 9 roles');

          final refFactory = pairs['bodyMedium']!.$1;
          final refNox = pairs['bodyMedium']!.$2;

          pairs.forEach((name, p) {
            final factory = p.$1;
            final nox = p.$2;
            expect(factory.height, isNull, reason: '$name: factory must not set height');
            expect(factory.fontFamily, isNull, reason: '$name: family is inherited from the theme');
            expect(factory.color, c, reason: '$name: injected color');
            expect(factory.fontWeight, nox.fontWeight, reason: '$name: weight must match noxTextTheme');
            expect(factory.letterSpacing, nox.letterSpacing, reason: '$name: letterSpacing must match noxTextTheme');
            // .sp scales every size by the same factor, so the ratio to a reference role is scale-independent.
            expect(
              factory.fontSize! / refFactory.fontSize!,
              closeTo(nox.fontSize! / refNox.fontSize!, 1e-9),
              reason: '$name: fontSize ratio must match noxTextTheme',
            );
          });
          return const SizedBox.shrink();
        },
      ),
    );
  });
}
