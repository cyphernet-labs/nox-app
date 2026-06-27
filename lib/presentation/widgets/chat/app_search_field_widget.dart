import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Editable search field for the chats list (5.1) — a real M3 `SearchBar` with a
/// leading glyph and live `onChanged` (debounced by the bloc). Distinct from the
/// display-only `AppSearchBarWidget`, which only opens a search view on tap.
/// Styling comes from the themed `searchBarTheme`.
class AppSearchFieldWidget extends StatelessWidget {
  const AppSearchFieldWidget({super.key, required this.controller, this.onChanged, this.hint = TextConstants.searchHint});

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s16, vertical: AppSpacingTokens.s8),
      child: SearchBar(
        controller: controller,
        hintText: hint,
        onChanged: onChanged,
        // Brand-teal search glyph (design: SearchBar leading uses BRAND.teal in both themes).
        leading: AppIconWidget(NoxIcons.search, color: NoxBrand.teal),
        constraints: BoxConstraints(minHeight: AppDimensionTokens.size.hitTarget, maxWidth: double.infinity),
      ),
    );
  }
}
