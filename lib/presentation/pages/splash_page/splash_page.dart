import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/pages/placeholder/route_placeholder_page.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

/// Stub auth-resolution outcome for the standalone (gallery) preview only.
enum SplashOutcome { hasId, noId, error }

/// 1.1 Splash — brand launch screen. Brand-fixed dark canvas (`NoxBrand.canvasDark`,
/// theme-independent), centered colored logo + 'NOX' wordmark with a one-shot
/// fade+scale reveal. The screen is passive.
///
/// In the real flow (`demo == false`) the splash is the app entry point under
/// [AppRootBloc]: it plays the reveal and, once the first app state has resolved
/// (`isReady`), dispatches `ApplyAppState` to release the first navigation
/// (FR-006). In demo mode (gallery) it keeps a dev outcome selector and routes
/// to placeholders, touching no real state.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, this.demo = false});

  final bool demo;

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const SplashPage(),
    settings: const RouteSettings(name: '/splash'),
  );

  /// Gallery entry: adds the dev outcome selector and previews routing locally.
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => const SplashPage(demo: true),
    settings: const RouteSettings(name: '/splash'),
  );

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _reveal;
  bool _animationDone = false;

  // Real-flow gate.
  bool _applied = false;

  // Demo-flow (gallery) preview routing.
  SplashOutcome? _outcome;
  bool _routed = false;

  static double get _logoMobile => AppDimensionTokens.size.splashLogo;
  static double get _logoWide => AppDimensionTokens.size.splashLogoWide;
  static const double _scaleFrom = 0.85;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: NoxDuration.splashIn)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _animationDone = true;
          if (widget.demo) {
            _maybeRoute();
          } else {
            _maybeApply();
          }
        }
      });
    _reveal = CurvedAnimation(parent: _controller, curve: NoxEasing.emphasizedDecelerate);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Real flow: release the first navigation once the reveal is done AND the first
  // app state has resolved. The AppRoot routing listener does the actual push.
  void _maybeApply() {
    if (widget.demo || _applied || !_animationDone || !mounted) return;
    if (!context.read<AppRootBloc>().state.isReady) return;
    _applied = true;
    context.read<AppRootBloc>().add(const AppRootEvent.applyAppState());
  }

  void _select(SplashOutcome outcome) {
    setState(() => _outcome = outcome);
    _maybeRoute();
  }

  // Demo flow only: routes no earlier than the reveal completes AND an outcome is
  // resolved. Uses push (so back returns to the gallery).
  void _maybeRoute() {
    if (_routed || !_animationDone || _outcome == null || !mounted) return;
    _routed = true;
    switch (_outcome!) {
      case SplashOutcome.hasId:
        Navigator.of(context).push(RoutePlaceholderPage.route(destinationLabel: 'Chats shell (4.1)'));
      case SplashOutcome.noId:
        Navigator.of(context).push(RoutePlaceholderPage.route(destinationLabel: 'Login (2.1)'));
      case SplashOutcome.error:
        Navigator.of(context).push(
          AppErrorPage.route(
            params: ErrorPageParams.fatal(
              mode: ErrorPageMode.blocking,
              onRetry: () async {
                await Future<void>.delayed(const Duration(milliseconds: 400));
                if (mounted) Navigator.of(context).maybePop();
              },
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canvas = AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: NoxBrand.canvasDark,
        body: Stack(
          children: [
            Center(
              child: FadeTransition(
                opacity: _reveal,
                child: ScaleTransition(
                  scale: Tween<double>(begin: _scaleFrom, end: 1).animate(_reveal),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final logoSize = constraints.maxWidth >= Constants.railBreakpoint ? _logoWide : _logoMobile;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Assets.png.logo.image(width: logoSize, height: logoSize, fit: BoxFit.contain),
                          SizedBox(height: AppSpacingTokens.s16),
                          const AppWordmarkWidget(color: NoxBrand.white),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            // Dev-only preview control — gallery (demo) builds only. The real splash
            // has no controls (FR-012) and routes from the resolved app state.
            if (kDebugMode && widget.demo)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(child: _DevOutcomeBar(onSelect: _select)),
              ),
          ],
        ),
      ),
    );

    if (widget.demo) return canvas;

    // Real flow: also release the first navigation if the app state resolves AFTER
    // the reveal finishes (the reveal may win the race).
    return BlocListener<AppRootBloc, AppRootState>(
      listenWhen: (previous, current) => !previous.isReady && current.isReady,
      listener: (context, state) => _maybeApply(),
      child: canvas,
    );
  }
}

/// Dev-only control to pick the stub [SplashOutcome] and exercise the routing
/// branches while previewing Splash standalone. Not part of the real splash.
class _DevOutcomeBar extends StatelessWidget {
  const _DevOutcomeBar({required this.onSelect});

  final ValueChanged<SplashOutcome> onSelect;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: NoxBrand.white,
      side: const BorderSide(color: NoxBrand.white),
    );
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacingTokens.s8,
        runSpacing: AppSpacingTokens.s8,
        children: [
          OutlinedButton(style: style, onPressed: () => onSelect(SplashOutcome.hasId), child: const Text('Has ID')),
          OutlinedButton(style: style, onPressed: () => onSelect(SplashOutcome.noId), child: const Text('No ID')),
          OutlinedButton(style: style, onPressed: () => onSelect(SplashOutcome.error), child: const Text('Error')),
        ],
      ),
    );
  }
}
