import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_labeled_field_widget.dart';

/// The two address fields of the connection screen and of Settings >
/// Connection (phase 045): "Server address" (`host:port`) and "Onion address"
/// (`<56>.onion`, optional). One widget so the two screens cannot drift apart
/// in wording, keyboard or error placement. Presentational: the owner keeps
/// the controllers and decides the errors.
class AppConnectionFieldsWidget extends StatelessWidget {
  const AppConnectionFieldsWidget({
    super.key,
    required this.serverController,
    required this.onionController,
    required this.onServerChanged,
    required this.onOnionChanged,
    this.serverError,
    this.onionError,
    this.enabled = true,
  });

  final TextEditingController serverController;
  final TextEditingController onionController;
  final ValueChanged<String> onServerChanged;
  final ValueChanged<String> onOnionChanged;

  /// Shown under the field; null for none.
  final String? serverError;
  final String? onionError;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppLabeledFieldWidget(
          controller: serverController,
          label: context.l10n.connectServerAddressLabel,
          maxLength: null,
          keyboardType: TextInputType.url,
          autocorrect: false,
          errorText: serverError,
          enabled: enabled,
          onChanged: onServerChanged,
        ),
        SizedBox(height: AppSpacingTokens.s16),
        // "Optional" while the field is empty: no onion address is a valid
        // answer, and the field says so rather than looking unfinished.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: onionController,
          builder: (context, value, _) => AppLabeledFieldWidget(
            controller: onionController,
            label: context.l10n.connectOnionAddressLabel,
            maxLength: null,
            keyboardType: TextInputType.url,
            autocorrect: false,
            helperText: value.text.trim().isEmpty ? context.l10n.connectOnionAddressHint : null,
            errorText: onionError,
            enabled: enabled,
            onChanged: onOnionChanged,
          ),
        ),
      ],
    );
  }
}
