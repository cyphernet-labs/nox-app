import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Persistent search field (5.1). Brand-teal search accent (NOX accent, not a
/// theme role), `surfaceContainerHigh`, stadium, elevation 2. Tapping opens the
/// full search view. Source: nox_widgets.dart `NoxSearchBar`.
class AppSearchBarWidget extends StatelessWidget {
  const AppSearchBarWidget({super.key, this.value, this.hint = TextConstants.searchHint, this.onTap});

  final String? value;
  final String hint;
  final VoidCallback? onTap;

  static double get _height => AppDimensionTokens.size.searchBarH;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasValue = value != null && value!.isNotEmpty;
    return Material(
      color: colorScheme.surfaceContainerHigh,
      elevation: NoxElevation.level2,
      shadowColor: colorScheme.shadow,
      borderRadius: BorderRadius.circular(NoxRadius.full),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NoxRadius.full),
        child: Semantics(
          button: true,
          label: TextConstants.searchHint,
          child: SizedBox(
            height: _height,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s16),
              child: Row(
                children: [
                  AppIconWidget(NoxIcons.search, color: NoxBrand.teal),
                  SizedBox(width: AppSpacingTokens.s12),
                  Expanded(
                    child: Text(
                      hasValue ? value! : hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge?.copyWith(color: hasValue ? colorScheme.onSurface : colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
