import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/general/platform_utils.dart';
import 'package:nox_app/presentation/widgets/state/connection_indicator/bloc/connection_indicator_bloc.dart';

/// The corner of the screen that says how the connection goes (phase 040,
/// FR-027, FR-028, FR-029). Only deviations from the usual show: the `Tor`
/// badge while the connection goes through Tor, `Connecting…` while a path
/// comes up - with the badge when that path is Tor. Direct and current, or
/// offline (the banner speaks then), it draws nothing at all.
///
/// Narrow: in the app bars of 5.1 and 5.2. Wide: at the right edge of the
/// window titlebar. Tapping it explains the path - a bottom sheet when
/// narrow, a dialog when [wide].
class AppConnectionIndicatorWidget extends StatelessWidget {
  const AppConnectionIndicatorWidget({super.key, required this.wide, this.status});

  /// Whether the explanation opens as a dialog rather than a bottom sheet.
  final bool wide;

  /// A fixed status instead of the live one - for goldens and widget tests.
  final ConnectionStatus? status;

  @override
  Widget build(BuildContext context) {
    final fixed = status;
    if (fixed != null) return AppConnectionIndicatorView(status: fixed, wide: wide);
    return BlocProvider<ConnectionIndicatorBloc>(
      create: (_) => ConnectionIndicatorBloc()..add(const ConnectionIndicatorEvent.started()),
      child: BlocBuilder<ConnectionIndicatorBloc, ConnectionIndicatorState>(
        builder: (context, state) => AppConnectionIndicatorView(status: state.status, wide: wide),
      ),
    );
  }
}

/// The indicator drawn for one [status].
class AppConnectionIndicatorView extends StatelessWidget {
  const AppConnectionIndicatorView({super.key, required this.status, required this.wide});

  final ConnectionStatus status;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final connecting = status.showsConnecting;
    final tor = status.showsTorBadge;
    if (!connecting && !tor) return const SizedBox.shrink();
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = switch ((connecting, tor)) {
      (true, true) => l10n.connectionSemanticsConnectingTor,
      (true, false) => l10n.connectionSemanticsConnecting,
      _ => l10n.connectionSemanticsTor,
    };
    // One name for the whole corner: the words inside would otherwise be read
    // as two unrelated labels.
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => showConnectionInfo(context, status: status, wide: wide),
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: AppDimensionTokens.size.hitTarget, minHeight: _minHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (connecting)
                    Text(l10n.connectionConnecting, style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                  if (connecting && tor) SizedBox(width: AppSpacingTokens.s6),
                  if (tor) const _TorBadge(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The full 48 everywhere a finger is the pointer. The wide titlebar is
  /// shorter than that, and the corner fills its height there; the width stays
  /// at least 48.
  double get _minHeight => wide ? AppDimensionTokens.size.windowTitlebarH : AppDimensionTokens.size.hitTarget;
}

class _TorBadge extends StatelessWidget {
  const _TorBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s8, vertical: AppSpacingTokens.s2),
      decoration: BoxDecoration(color: colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(AppDimensionTokens.radius.pill)),
      child: Text(
        context.l10n.connectionTorBadge,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onSecondaryContainer),
      ),
    );
  }
}

/// Explains the path: a bottom sheet when narrow, a dialog when [wide].
Future<void> showConnectionInfo(BuildContext context, {required ConnectionStatus status, required bool wide}) {
  final content = AppConnectionInfoContent(status: status, localNetworkHint: PlatformUtils.isIOS || PlatformUtils.isMacOS);
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(child: content),
    );
  }
  return showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => content);
}

/// What the explanation says.
class AppConnectionInfoContent extends StatelessWidget {
  const AppConnectionInfoContent({super.key, required this.status, required this.localNetworkHint});

  final ConnectionStatus status;

  /// Where to allow Local Network access - a question only iOS and macOS ask,
  /// and the likely reason a device at home goes through Tor.
  final bool localNetworkHint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final body = textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant);
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacingTokens.s24, AppSpacingTokens.s8, AppSpacingTokens.s24, AppSpacingTokens.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.connectionInfoTitle, style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
          SizedBox(height: AppSpacingTokens.s12),
          Text(status.path == ConnectionPath.tor ? l10n.connectionInfoTor : l10n.connectionInfoConnecting, style: body),
          if (localNetworkHint) ...[SizedBox(height: AppSpacingTokens.s8), Text(l10n.connectionInfoLocalNetwork, style: body)],
        ],
      ),
    );
  }
}
