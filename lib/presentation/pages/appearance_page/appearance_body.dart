import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_color_scheme.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/widgets/settings/app_theme_option_widget.dart';

/// 7.3 Appearance content — System / Light / Dark theme cards applied app-wide via
/// the existing [AppRootBloc]. No Scaffold/AppBar so it embeds in both the mobile
/// leaf chrome (AppearancePage) and the desktop Settings list-detail pane (7.1).
/// Requires an [AppRootBloc] ancestor (provided app-wide by AppRoot).
class AppearanceBody extends StatelessWidget {
  const AppearanceBody({super.key});

  static const List<(ThemeMode, String, String)> _options = [
    (ThemeMode.system, TextConstants.themeSystem, TextConstants.themeSystemCaption),
    (ThemeMode.light, TextConstants.themeLight, TextConstants.themeLightCaption),
    (ThemeMode.dark, TextConstants.themeDark, TextConstants.themeDarkCaption),
  ];

  @override
  Widget build(BuildContext context) {
    final current = context.watch<AppRootBloc>().state.themeMode;
    return ListView(
      padding: EdgeInsets.all(AppSpacingTokens.s16),
      children: [
        for (final (mode, label, caption) in _options)
          Padding(
            padding: EdgeInsets.only(bottom: AppSpacingTokens.s12),
            child: AppThemeOptionWidget(
              label: label,
              caption: caption,
              preview: _ThemePreview(mode: mode),
              selected: current == mode,
              onTap: () => context.read<AppRootBloc>().add(AppRootEvent.setTheme(themeMode: mode)),
            ),
          ),
      ],
    );
  }
}

/// Mini-chat theme thumbnail (~96x76). Always rendered with the brand-fixed
/// schemes (noxLightScheme / noxDarkScheme) so each option reads the same
/// regardless of the active theme: Light/Dark show one mini chat, System a
/// diagonal light-over-dark split.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.mode});

  final ThemeMode mode;

  static double get _width => AppSpacingTokens.s96;
  static double get _height => AppSpacingTokens.s72 + AppSpacingTokens.s4; // ~76

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppDimensionTokens.radius.sm);
    final Widget content;
    switch (mode) {
      case ThemeMode.light:
        content = const _MiniChat(noxLightScheme);
      case ThemeMode.dark:
        content = const _MiniChat(noxDarkScheme);
      case ThemeMode.system:
        content = const Stack(
          fit: StackFit.expand,
          children: [
            _MiniChat(noxLightScheme),
            ClipPath(clipper: _DiagonalClipper(), child: _MiniChat(noxDarkScheme)),
          ],
        );
    }
    return Container(
      width: _width,
      height: _height,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: AppDimensionTokens.border.hairline),
      ),
      child: ClipRRect(borderRadius: radius, child: content),
    );
  }
}

/// Static mini-chat illustration for one [ColorScheme]: a surface card with a
/// wordmark app-bar strip, a NOX brand-gradient hairline, and two avatar+text
/// message rows. Sub-element proportions use small flex weights by design — this
/// is a fixed, decorative thumbnail (like a chart), not real chat content.
class _MiniChat extends StatelessWidget {
  const _MiniChat(this.scheme);

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final s = scheme;
    return ColoredBox(
      color: s.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // App-bar strip with a wordmark stand-in bar (~40% width).
          Container(
            height: AppSpacingTokens.s14,
            padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s6),
            alignment: Alignment.centerLeft,
            child: _bar(s.onSurfaceVariant, fillFlex: 2, restFlex: 3),
          ),
          // Brand accent hairline (teal → gold → coral), horizontal gradient.
          Container(
            height: AppSpacingTokens.s3,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [NoxBrand.teal, NoxBrand.gold, NoxBrand.coral])),
          ),
          // Two mini message rows.
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(AppSpacingTokens.s6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _messageRow(avatar: s.primary),
                  SizedBox(height: AppSpacingTokens.s8),
                  _messageRow(avatar: s.secondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Avatar dot + a short name bar (onSurface) and a longer text bar
  /// (onSurfaceVariant).
  Widget _messageRow({required Color avatar}) {
    return Row(
      children: [
        Container(
          width: AppSpacingTokens.s10,
          height: AppSpacingTokens.s10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: avatar),
        ),
        SizedBox(width: AppSpacingTokens.s6),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(scheme.onSurface, fillFlex: 1, restFlex: 1), // ~50% name bar
              SizedBox(height: AppSpacingTokens.s3),
              _bar(scheme.onSurfaceVariant, fillFlex: 5, restFlex: 1), // ~83% text bar
            ],
          ),
        ),
      ],
    );
  }

  /// A single rounded bar occupying `fillFlex / (fillFlex + restFlex)` of the row
  /// width, left-aligned. Height is a 3dp token.
  Widget _bar(Color color, {required int fillFlex, required int restFlex}) {
    return Row(
      children: [
        Expanded(
          flex: fillFlex,
          child: Container(
            height: AppSpacingTokens.s3,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppDimensionTokens.radius.xs)),
          ),
        ),
        Spacer(flex: restFlex),
      ],
    );
  }
}

/// Clips to the bottom-right triangle (diagonal from the top-right corner to the
/// bottom-left corner) so the dark mini-chat reveals over the light one for the
/// System option's diagonal split.
class _DiagonalClipper extends CustomClipper<Path> {
  const _DiagonalClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
