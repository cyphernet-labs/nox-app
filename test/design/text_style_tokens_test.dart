import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';

/// US4 / FR-009 — AppTextStyleTokens exposes the full M3 type scale (8 roles), with the
/// correct weights, no height and no fontFamily (both come from noxTextTheme / the theme).
void main() {
  testWidgets('full 8-role scale, correct weights, no height/family', (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(393, 852),
        builder: (context, _) {
          const c = Color(0xFF000000);
          final roles = <String, TextStyle>{
            'displaySmall': AppTextStyleTokens.displaySmall(color: c),
            'headlineSmall': AppTextStyleTokens.headlineSmall(color: c),
            'titleLarge': AppTextStyleTokens.titleLarge(color: c),
            'titleMedium': AppTextStyleTokens.titleMedium(color: c),
            'bodyLarge': AppTextStyleTokens.bodyLarge(color: c),
            'bodyMedium': AppTextStyleTokens.bodyMedium(color: c),
            'labelLarge': AppTextStyleTokens.labelLarge(color: c),
            'labelMedium': AppTextStyleTokens.labelMedium(color: c),
          };
          expect(roles.length, 8);
          for (final style in roles.values) {
            expect(style.height, isNull, reason: 'height must come from noxTextTheme, not the token factory');
            expect(style.fontFamily, isNull, reason: 'family is inherited from the theme');
          }
          expect(roles['titleMedium']!.fontWeight, FontWeight.w500);
          expect(roles['labelLarge']!.fontWeight, FontWeight.w500);
          expect(roles['bodyMedium']!.fontWeight, FontWeight.w400);
          return const SizedBox.shrink();
        },
      ),
    );
  });
}
