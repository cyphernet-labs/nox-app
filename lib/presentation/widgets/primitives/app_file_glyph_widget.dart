import 'package:flutter/material.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/file_type.dart';

/// File-type icon inside a soft tinted rounded square (file lists / file view).
/// Fill = `noxFileColor(type)`@14%, radius = box·0.27. Source: primitives.md `NoxFileGlyph`.
class AppFileGlyphWidget extends StatelessWidget {
  const AppFileGlyphWidget({super.key, required this.type, this.iconSize = 24, this.box = 44});

  final FileType type;
  final double iconSize;
  final double box;

  @override
  Widget build(BuildContext context) {
    final color = noxFileColor(type);
    return Container(
      width: box,
      height: box,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(box * 0.27)),
      child: AppIconWidget(noxFileIcon(type), size: iconSize, color: color),
    );
  }
}
