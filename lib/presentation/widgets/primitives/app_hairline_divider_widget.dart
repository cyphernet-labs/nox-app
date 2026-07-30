import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';

/// A horizontal hairline separator — a `Divider` whose height collapses to the
/// design hairline token (`border.hairline`), inheriting colour/thickness from the
/// `DividerTheme`. The single source for the ~dozen inline
/// `Divider(height: AppDimensionTokens.border.hairline)` copies across settings,
/// the chat card, notifications and identity surfaces.
class AppHairlineDividerWidget extends StatelessWidget {
  const AppHairlineDividerWidget({super.key});

  @override
  Widget build(BuildContext context) => Divider(height: AppDimensionTokens.border.hairline);
}
