import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';

/// Adaptive scaffold for a settings/legal leaf screen: a full-screen `Scaffold`
/// with an app bar (title + NoxIcons back + brand splash hairline) on mobile, and
/// the same chrome with a width-capped, centered body on a wide window (one panel —
/// the real settings list-detail shell is a later milestone). Width-driven by
/// [Constants.railBreakpoint].
class AppDetailScaffoldWidget extends StatelessWidget {
  const AppDetailScaffoldWidget({super.key, required this.title, required this.body, this.actions, this.maxContentWidth});

  final String title;
  final Widget body;
  final List<Widget>? actions;

  /// Wide-window content cap; null falls back to `layout.detailMaxW` (a token
  /// getter can't be a const default).
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Constants.railBreakpoint;
        final content = wide
            ? Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth ?? AppDimensionTokens.layout.detailMaxW),
                  child: body,
                ),
              )
            : body;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: TextConstants.tooltipBack,
              icon: AppIconWidget(NoxIcons.arrowBack),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(title),
            actions: actions,
            bottom: const AppSplashHairlineWidget(),
          ),
          body: content,
        );
      },
    );
  }
}
