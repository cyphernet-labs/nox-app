import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_onboard_card_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

/// Shared onboarding page scaffold for 2.1 Login and 2.3 Set username — the two
/// screens are the same layout, a [field] that scrolls above a pinned [actions]
/// block, differing only in the field, the actions, the desktop titlebar [subtitle],
/// and the mobile actions padding. Mobile: an `AppBar` (wordmark + splash hairline)
/// with the field in a scroll view and the actions pinned at the bottom. Desktop
/// (`>= Constants.railBreakpoint`): a window titlebar over a centered
/// [AppOnboardCardWidget] holding the field and actions.
class AppOnboardingScaffoldWidget extends StatelessWidget {
  const AppOnboardingScaffoldWidget({
    super.key,
    required this.subtitle,
    required this.field,
    required this.actions,
    this.mobileActionsPadding,
  });

  /// Desktop titlebar screen label (e.g. 'Sign in', 'Set up').
  final String subtitle;

  /// The single input the screen collects (an id / labeled field).
  final Widget field;

  /// The pinned action block (primary button + secondary affordances).
  final Widget actions;

  /// Padding around the pinned mobile actions block. Defaults to a uniform `s16`;
  /// Login overrides it to add breathing room at the very bottom.
  final EdgeInsets? mobileActionsPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Constants.railBreakpoint;
        return wide ? _wide(context) : _narrow(context);
      },
    );
  }

  Widget _narrow(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const AppWordmarkWidget(), bottom: const AppSplashHairlineWidget()),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s24, AppSpacingTokens.s16, 0),
                child: field,
              ),
            ),
            Padding(padding: mobileActionsPadding ?? EdgeInsets.all(AppSpacingTokens.s16), child: actions),
          ],
        ),
      ),
    );
  }

  Widget _wide(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppWindowTitlebarWidget(subtitle: subtitle),
          Expanded(
            child: AppOnboardCardWidget(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  field,
                  SizedBox(height: AppSpacingTokens.s24),
                  actions,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
