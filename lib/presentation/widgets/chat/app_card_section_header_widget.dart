import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

/// The heading of a section inside the chat card (5.4).
///
/// One widget because the card stacks two of them — People and Files — and they
/// have to line up. Hand-copied padding and a hand-copied text role agree until
/// somebody bumps a token on one of them, after which two headings of a single
/// screen sit at different insets with nothing failing.
///
/// [trailing] is for a control that belongs to the heading row, like the Files
/// List/Grid toggle.
class AppCardSectionHeaderWidget extends StatelessWidget {
  const AppCardSectionHeaderWidget({required this.title, super.key, this.trailing});

  final String title;
  final Widget? trailing;

  /// The inset both sections share, exposed so a section body can align its own
  /// content with its heading without repeating the numbers.
  static EdgeInsets get padding =>
      EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s0, AppSpacingTokens.s16, AppSpacingTokens.s12);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ?trailing,
        ],
      ),
    );
  }
}
