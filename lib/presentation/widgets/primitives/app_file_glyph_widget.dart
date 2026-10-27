import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';

/// File-type icon inside a soft tinted rounded square (file lists / file view).
/// Fill = `noxFileColor(type)`@14%, radius = box·0.27. Source: primitives.md `NoxFileGlyph`.
class AppFileGlyphWidget extends StatelessWidget {
  const AppFileGlyphWidget({super.key, required this.type, this.iconSize, this.box});

  final FileType type;

  /// Null falls back to `icon.xl` (24) / `s44` — a token getter can't be a const default.
  final double? iconSize;
  final double? box;

  @override
  Widget build(BuildContext context) {
    final color = noxFileColor(type);
    final boxSize = box ?? AppSpacingTokens.s44;
    return Container(
      width: boxSize,
      height: boxSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(boxSize * 0.27)),
      child: AppIconWidget(noxFileIcon(type), size: iconSize ?? AppDimensionTokens.icon.xl, color: color),
    );
  }
}
