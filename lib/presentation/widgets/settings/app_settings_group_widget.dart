import 'package:flutter/material.dart';
import 'package:nox_app/presentation/widgets/primitives/app_hairline_divider_widget.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';

/// Groups settings rows inside a single rounded `surfaceContainerLow` card (the
/// 7.x Settings grouping): corner radius `radius.lg`, elevation level1, an outer
/// screen-edge margin, and a hairline divider BETWEEN consecutive [children]
/// (never before the first / after the last). Presentational.
class AppSettingsGroupWidget extends StatelessWidget {
  const AppSettingsGroupWidget({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s4, AppSpacingTokens.s16, AppSpacingTokens.s16),
      elevation: NoxElevation.level1,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensionTokens.radius.lg)),
      child: Column(mainAxisSize: MainAxisSize.min, children: _interleaved()),
    );
  }

  // Insert a hairline divider between each pair of children (not at the edges).
  List<Widget> _interleaved() {
    final result = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) result.add(const AppHairlineDividerWidget());
      result.add(children[i]);
    }
    return result;
  }
}
