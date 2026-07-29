@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/chat/rename_chat_dialog/app_rename_chat_dialog_widget.dart';

import '../../../../utils/golden.dart';

void main() {
  // The resting rename dialog: title, the prefilled name field, and Cancel / Save (Save
  // disabled until the name changes). settle:false — the autofocused field's blinking
  // cursor never settles. No DI needed: the bloc only touches the repo on a name change.
  goldenTest(
    'app_rename_chat_dialog_widget',
    () => const Center(
      child: AppRenameChatDialogWidget(chatId: 'chat_0', currentName: 'Design crit'),
    ),
    settle: false,
  );
}
