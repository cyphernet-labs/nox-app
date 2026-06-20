import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/pages/placeholder/route_placeholder_page.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

/// Stub auth-resolution outcome. In the real cold-start flow this comes from the
/// stored-identifier/session check (backend phase); here it is chosen via the dev
/// control while the screen is previewed standalone from the gallery.
enum SplashOutcome { hasId, noId, error }

/// 1.1 Splash — brand launch screen. Brand-fixed dark canvas (`NoxBrand.canvasDark`,
/// theme-independent — one of the two sanctioned theming exceptions), centered
/// colored logo + 'NOX' wordmark with a one-shot fade+scale reveal. The screen is
/// passive; routing happens no earlier than the reveal completes and waits for a
/// resolved [SplashOutcome] (FR-011/FR-012/FR-013).
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const SplashPage(),
    settings: const RouteSettings(name: '/splash'),
  );

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _reveal;
  bool _animationDone = false;
  SplashOutcome? _outcome;
  bool _routed = false;

  static const double _logoMobile = 168;
  static const double _logoWide = 220;
  static const double _scaleFrom = 0.85;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: NoxDuration.splashIn)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _animationDone = true;
          _maybeRoute();
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

  void _select(SplashOutcome outcome) {
    setState(() => _outcome = outcome);
    _maybeRoute();
  }

  // Routes no earlier than the reveal completes AND an outcome is resolved.
  void _maybeRoute() {
    if (_routed || !_animationDone || _outcome == null || !mounted) return;
    _routed = true;
    final String label;
    switch (_outcome!) {
      case SplashOutcome.hasId:
        label = 'Chats shell (4.1)';
      case SplashOutcome.noId:
        label = 'Login (2.1)';
      case SplashOutcome.error:
        // TODO(US2): route to AppErrorPage(mode: blocking) once 3.1 lands.
        label = 'Error (3.1)';
    }
    // Preview uses push (so back returns to the gallery).
    // TODO(backend): pushReplacement in the real cold-start flow (no return to splash).
    Navigator.of(context).push(RoutePlaceholderPage.route(destinationLabel: label));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
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
            // Dev-only preview control; the real cold-start splash has no controls (FR-012).
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
