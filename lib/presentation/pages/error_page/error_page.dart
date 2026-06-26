import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';

/// 3.1 Universal error screen — parameterized icon/title/message + `Try again`.
/// Modes: [ErrorPageMode.embedded] (back arrow) and [ErrorPageMode.blocking] (no
/// back; last in the stack — system back is suppressed). On a wide window the body
/// sits under a faux window title bar with a larger icon. `demo: true` adds a dev
/// control to switch mode while previewing from the gallery; the real screen is
/// constructed with fixed [ErrorPageParams].
class AppErrorPage extends StatefulWidget {
  const AppErrorPage({super.key, required this.params, this.demo = false});

  final ErrorPageParams params;
  final bool demo;

  static Route<void> route({required ErrorPageParams params}) => MaterialPageRoute<void>(
    builder: (_) => AppErrorPage(params: params),
    settings: const RouteSettings(name: '/error'),
  );

  /// Gallery entry: interactive demo (embedded by default, mode switch + fake retry).
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => AppErrorPage(
      params: ErrorPageParams.network(mode: ErrorPageMode.embedded, onRetry: _fakeRetry),
      demo: true,
    ),
    settings: const RouteSettings(name: '/error'),
  );

  @override
  State<AppErrorPage> createState() => _AppErrorPageState();
}

Future<void> _fakeRetry() => Future<void>.delayed(const Duration(milliseconds: 800));

class _AppErrorPageState extends State<AppErrorPage> {
  late ErrorPageMode _mode;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.params.mode;
  }

  Future<void> _retry() async {
    final onRetry = widget.params.onRetry;
    if (onRetry == null || _retrying) return;
    setState(() => _retrying = true);
    await onRetry();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Constants.railBreakpoint;
        final body = _ErrorBody(
          params: widget.params,
          iconSize: wide ? AppDimensionTokens.icon.heroWide : AppDimensionTokens.icon.hero,
          retrying: _retrying,
          onRetry: widget.params.onRetry == null ? null : _retry,
          devControl: (kDebugMode && widget.demo) ? _modeControl() : null,
        );
        if (wide) {
          return Scaffold(
            body: Column(
              children: [
                const AppWindowTitlebarWidget(title: TextConstants.appName),
                Expanded(child: body),
              ],
            ),
          );
        }
        if (_mode == ErrorPageMode.embedded) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                tooltip: TextConstants.tooltipBack,
                icon: AppIconWidget(NoxIcons.arrowBack),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            body: body,
          );
        }
        // Blocking: no back affordance; system back is suppressed (last in the stack).
        return PopScope(canPop: false, child: Scaffold(body: body));
      },
    );
  }

  Widget _modeControl() {
    return SegmentedButton<ErrorPageMode>(
      segments: const [
        ButtonSegment<ErrorPageMode>(value: ErrorPageMode.embedded, label: Text('Embedded')),
        ButtonSegment<ErrorPageMode>(value: ErrorPageMode.blocking, label: Text('Blocking')),
      ],
      selected: {_mode},
      onSelectionChanged: (selection) => setState(() => _mode = selection.first),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.params, required this.iconSize, required this.retrying, required this.onRetry, this.devControl});

  final ErrorPageParams params;
  final double iconSize;
  final bool retrying;
  final Future<void> Function()? onRetry;
  final Widget? devControl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacingTokens.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIconWidget(params.icon, size: iconSize, color: colorScheme.onSurfaceVariant),
                SizedBox(height: AppSpacingTokens.s16),
                Text(
                  params.title,
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
                ),
                SizedBox(height: AppSpacingTokens.s8),
                Text(
                  params.message,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: AppSpacingTokens.s24),
                FilledButton(
                  onPressed: retrying ? null : onRetry,
                  child: retrying
                      ? AppSpinnerWidget(size: AppDimensionTokens.icon.md, color: colorScheme.onPrimary)
                      : const Text(TextConstants.actionTryAgain),
                ),
              ],
            ),
          ),
        ),
        if (devControl != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(AppSpacingTokens.s16),
                child: Center(child: devControl),
              ),
            ),
          ),
      ],
    );
  }
}
