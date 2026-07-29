import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/chat/rename_chat_dialog/rename_chat_bloc.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_labeled_field_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// Rename-chat dialog (edit chat name), launched from the 5.4 chat card. A single name
/// field (prefilled + selected) with the same debounced uniqueness + 64-char rules as
/// create-chat, over [RenameChatBloc]. Resolves `true` (via `Navigator.pop`) once the
/// chat is renamed; Cancel / dismiss resolves null. Anyone may rename (open shared space,
/// no owners).
class AppRenameChatDialogWidget extends StatefulWidget {
  const AppRenameChatDialogWidget({super.key, required this.chatId, required this.currentName});

  final String chatId;
  final String currentName;

  /// Shows the dialog; resolves `true` when the chat was renamed.
  static Future<bool?> show(BuildContext context, {required String chatId, required String currentName}) => showDialog<bool>(
    context: context,
    builder: (_) => AppRenameChatDialogWidget(chatId: chatId, currentName: currentName),
  );

  @override
  State<AppRenameChatDialogWidget> createState() => _AppRenameChatDialogWidgetState();
}

class _AppRenameChatDialogWidgetState extends State<AppRenameChatDialogWidget> {
  late final RenameChatBloc _bloc = RenameChatBloc(chatId: widget.chatId, currentName: widget.currentName);
  // Prefilled AND selected, so the user can immediately overtype the whole name.
  late final TextEditingController _controller = TextEditingController(text: widget.currentName)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.currentName.length);

  @override
  void dispose() {
    _bloc.close();
    _controller.dispose();
    super.dispose();
  }

  String? _errorText(BuildContext context, RenameChatState state) {
    if (state.status == RenameChatStatus.taken) return context.l10n.nameTakenError;
    if (state.networkError) return context.l10n.renameChatNetworkError;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BlocProvider<RenameChatBloc>.value(
      value: _bloc,
      child: BlocConsumer<RenameChatBloc, RenameChatState>(
        listenWhen: (previous, current) => current.status == RenameChatStatus.navSuccess,
        listener: (context, state) {
          _bloc.add(const RenameChatEvent.navigationHandled());
          Navigator.of(context).pop(true);
        },
        builder: (context, state) {
          return AlertDialog(
            title: Text(context.l10n.renameChatTitle),
            content: AppLabeledFieldWidget(
              controller: _controller,
              label: context.l10n.createChatNameLabel,
              maxLength: 64,
              autofocus: true,
              errorText: _errorText(context, state),
              checking: state.isChecking,
              enabled: !state.isSubmitting,
              onChanged: (value) => _bloc.add(RenameChatEvent.nameChanged(value)),
              onSubmitted: () {
                if (state.canSubmit) _bloc.add(const RenameChatEvent.saveRequested());
              },
            ),
            actions: [
              TextButton(
                onPressed: state.isSubmitting ? null : () => Navigator.of(context).pop(false),
                child: Text(context.l10n.actionCancel),
              ),
              FilledButton(
                onPressed: state.canSubmit && !state.isSubmitting ? () => _bloc.add(const RenameChatEvent.saveRequested()) : null,
                child: state.isSubmitting
                    ? AppSpinnerWidget(size: AppDimensionTokens.icon.md, color: colorScheme.onPrimary)
                    : Text(context.l10n.actionSave),
              ),
            ],
          );
        },
      ),
    );
  }
}
