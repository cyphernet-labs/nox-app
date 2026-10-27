import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/theme/app_theme.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/l10n/app_localizations.dart';

/// Pumps [child] inside the app's ScreenUtil + theme canvas so AppSpacingTokens /
/// AppTextStyleTokens and `context.appColors` resolve as in production. Reused by
/// both widget tests and golden tests (see .claude/commands/{widget,golden}-test.md).
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  bool settle = true,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: Constants.designSize,
      // Mirror production: clamp `.sp` so test font metrics match the app (AppRoot).
      fontSizeResolver: AppTextStyleTokens.fontSizeResolver,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        // Pin English so localized copy renders deterministically in tests/goldens.
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
        // Clamp OS font scaling so text metrics match production (mirror AppRoot).
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: widget ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}
