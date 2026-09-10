@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/app_invite_seam_action_widget.dart';

import '../../../utils/golden.dart';

void main() {
  // Its whole reason for existing is a hand-applied dim: AppIconWidget paints
  // its own colour filter and never consults IconTheme, so a null onPressed
  // alone leaves the glyph identical to the live action beside it. No unit test
  // can see a colour, and the header baseline that covers it incidentally moves
  // for any unrelated edit to that row.
  goldenTest('app_invite_seam_action_widget', () => const Padding(padding: EdgeInsets.all(16), child: AppInviteSeamActionWidget()));
}
