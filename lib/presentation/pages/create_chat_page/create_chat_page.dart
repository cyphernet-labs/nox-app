import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
import 'package:nox_app/presentation/pages/create_chat_page/bloc/create_chat_bloc.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_labeled_field_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// 6.1 Create chat — a name form with debounced uniqueness (unrestricted charset).
/// Mobile: a full-screen pushed screen (AppBar `New chat` + back). Desktop: a
/// centered modal `Dialog` (≈460) over a scrim with `Cancel` + `Create`
/// (corpus `07-create.md`). Real `showDialog` from the chats shell is a later
/// milestone (`// TODO(M3)`). Owns [CreateChatBloc].
class CreateChatPage extends StatefulWidget {
  const CreateChatPage({super.key, this.demo = false});

  final bool demo;

  /// Pops with the created [ChatModel] on success (null on cancel) so the caller can
  /// open the new thread and refresh the list.
  static Route<ChatModel?> route() => MaterialPageRoute<ChatModel?>(
    builder: (_) => const CreateChatPage(),
    settings: const RouteSettings(name: '/create/chat'),
  );

  /// Gallery entry: adds the dev create-outcome selector.
  static Route<ChatModel?> routeDemo() => MaterialPageRoute<ChatModel?>(
    builder: (_) => const CreateChatPage(demo: true),
    settings: const RouteSettings(name: '/create/chat'),
  );

  @override
  State<CreateChatPage> createState() => _CreateChatPageState();
}

class _CreateChatPageState extends BaseStatePage<CreateChatPage> {
  late final CreateChatBloc _bloc;
  final TextEditingController _controller = TextEditingController();
  CreateChatOutcome _outcome = CreateChatOutcome.success;

  @override
  void initState() {
    super.initState();
    _bloc = CreateChatBloc();
  }

  @override
  void dispose() {
    _controller.dispose();
    _bloc.close();
    super.dispose();
  }

  void _create() => _bloc.add(CreateChatEvent.createRequested(outcome: _outcome));

  void _cancel() => Navigator.of(context).maybePop();

  void _onStatus(BuildContext context, CreateChatState state) {
    switch (state.status) {
      case CreateChatStatus.navSuccess:
        // Close the Create screen and hand the created chat back to the caller (the
        // shell), which opens the new thread (mobile push / desktop select) and
        // refreshes the list. Was a RoutePlaceholderPage dead-end.
        Navigator.of(context).pop(state.createdChat);
      case CreateChatStatus.navFatal:
        Navigator.of(context).push(AppErrorPage.route(params: ErrorPageParams.fatal()));
        _bloc.add(const CreateChatEvent.navigationHandled());
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CreateChatBloc>.value(
      value: _bloc,
      child: BlocConsumer<CreateChatBloc, CreateChatState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: _onStatus,
        builder: (context, state) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= Constants.railBreakpoint;
              return wide ? _wide(context, state) : _narrow(context, state);
            },
          );
        },
      ),
    );
  }

  Widget _narrow(BuildContext context, CreateChatState state) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: context.l10n.tooltipBack, icon: AppIconWidget(NoxIcons.arrowBack), onPressed: _cancel),
        title: Text(context.l10n.createChatTitle),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s20, AppSpacingTokens.s16, AppSpacingTokens.s16),
                child: _field(context, state),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s16, AppSpacingTokens.s16, AppSpacingTokens.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: double.infinity, child: _createButton(context, state)),
                  if (kDebugMode && widget.demo) _outcomeControl(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wide(BuildContext context, CreateChatState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      // Simulated modal scrim — the scrim is the Scaffold background so the backdrop
      // is well-defined. Real showDialog over the chats window is M3 (// TODO(M3)).
      backgroundColor: colorScheme.scrim.withValues(alpha: 0.4),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _cancel),
          ),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppDimensionTokens.layout.dialogMaxW),
              child: Padding(
                padding: EdgeInsets.all(AppSpacingTokens.s24),
                child: Material(
                  color: colorScheme.surfaceContainerHigh,
                  elevation: NoxElevation.level5,
                  borderRadius: BorderRadius.circular(NoxRadius.xl),
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacingTokens.s24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(context.l10n.createChatTitle, style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
                        SizedBox(height: AppSpacingTokens.s16),
                        _field(context, state),
                        SizedBox(height: AppSpacingTokens.s24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(onPressed: state.isSubmitting ? null : _cancel, child: Text(context.l10n.actionCancel)),
                            SizedBox(width: AppSpacingTokens.s8),
                            _createButton(context, state),
                          ],
                        ),
                        if (kDebugMode && widget.demo) _outcomeControl(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, CreateChatState state) {
    return AppLabeledFieldWidget(
      controller: _controller,
      label: context.l10n.createChatNameLabel,
      maxLength: 64,
      placeholder: context.l10n.createChatNameHint,
      errorText: _errorText(context, state),
      checking: state.isChecking,
      enabled: !state.isSubmitting,
      onChanged: (value) => _bloc.add(CreateChatEvent.nameChanged(value)),
    );
  }

  String? _errorText(BuildContext context, CreateChatState state) {
    if (state.status == CreateChatStatus.taken) return context.l10n.nameTakenError;
    if (state.networkError) return context.l10n.createChatNetworkError;
    return null;
  }

  Widget _createButton(BuildContext context, CreateChatState state) {
    final colorScheme = Theme.of(context).colorScheme;
    return FilledButton(
      onPressed: state.canSubmit && !state.isSubmitting ? _create : null,
      child: state.isSubmitting
          ? AppSpinnerWidget(size: AppDimensionTokens.icon.md, color: colorScheme.onPrimary)
          : Text(context.l10n.actionCreate),
    );
  }

  Widget _outcomeControl() {
    return Padding(
      padding: EdgeInsets.only(top: AppSpacingTokens.s8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Outcome:'),
          SizedBox(width: AppSpacingTokens.s8),
          DropdownButton<CreateChatOutcome>(
            value: _outcome,
            onChanged: (selected) {
              if (selected != null) setState(() => _outcome = selected);
            },
            items: const [
              DropdownMenuItem(value: CreateChatOutcome.success, child: Text('success')),
              DropdownMenuItem(value: CreateChatOutcome.network, child: Text('network error')),
              DropdownMenuItem(value: CreateChatOutcome.fatal, child: Text('fatal')),
            ],
          ),
        ],
      ),
    );
  }
}
