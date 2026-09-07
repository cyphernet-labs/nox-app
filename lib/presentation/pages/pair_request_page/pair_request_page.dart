import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/domain/model/person/pair_request.dart';
import 'package:nox_app/general/formatters/date_formatter.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/pair_request_page/bloc/pair_request_bloc.dart';

/// "Somebody wants to join" — the owner's decision about one presented invite
/// (contract §8B).
///
/// A screen of its own, not a snackbar or a banner. Letting a person onto this
/// machine cannot be undone, and an affordance that can be dismissed by
/// brushing past it is the wrong shape for a decision that cannot.
///
/// It says nothing about who is knocking, and that is not an omission: until
/// they are let in the server knows nothing about them — no name, no picture.
/// What it does state is what the invite was, so the owner can recognise their
/// own, and what saying yes actually grants.
class PairRequestPage extends StatefulWidget {
  const PairRequestPage({super.key, required this.request, this.dialog = false});

  final PairRequest request;

  /// When true, render as a modal `Dialog` body (no full-screen Scaffold) — the
  /// wide-width form. When false, the narrow full-screen one.
  final bool dialog;

  static Route<void> route(PairRequest request) => MaterialPageRoute<void>(
    builder: (_) => PairRequestPage(request: request),
    settings: const RouteSettings(name: '/pair/request'),
  );

  /// Wide entry: a real modal dialog over whatever the owner is looking at.
  ///
  /// `barrierDismissible: false` like the logout dialog — the two buttons are
  /// the only way out. A barrier tap is not an answer, and treating it as one
  /// would silently decline somebody.
  static Future<void> showAsDialog(BuildContext context, PairRequest request) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PairRequestPage(request: request, dialog: true),
  );

  @override
  State<PairRequestPage> createState() => _PairRequestPageState();
}

class _PairRequestPageState extends State<PairRequestPage> {
  late final PairRequestBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = PairRequestBloc(requestId: widget.request.requestId);
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PairRequestBloc, PairRequestState>(
      bloc: _bloc,
      listenWhen: (previous, current) => !previous.settled && current.settled,
      listener: (context, state) => Navigator.of(context).maybePop(),
      builder: (context, state) {
        final body = _body(context, state);
        if (widget.dialog) {
          return Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppDimensionTokens.layout.dialogMaxW),
              child: Padding(padding: EdgeInsets.all(AppSpacingTokens.s24), child: body),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(context.l10n.pairRequestTitle), automaticallyImplyLeading: false),
          body: SafeArea(
            child: Padding(padding: EdgeInsets.all(AppSpacingTokens.s24), child: body),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, PairRequestState state) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.dialog) ...[
          Text(context.l10n.pairRequestTitle, style: theme.textTheme.titleLarge),
          SizedBox(height: AppSpacingTokens.s12),
        ],
        Text(context.l10n.pairRequestMessage, style: theme.textTheme.bodyMedium),
        SizedBox(height: AppSpacingTokens.s16),
        // The two things the server actually knows: which invite this is, and
        // how long there is to answer.
        //
        // Rendered with the date when it is not today. A person invite lives
        // 24 hours, so a bare HH:mm routinely shows a send time that reads as
        // LATER than the expiry — the invite minted at 21:40 and opened at
        // 09:05 the next morning.
        //
        // A moment the server did not state is simply not shown. Saying nothing
        // beats saying 1970.
        if (widget.request.invitedAt != null)
          Text(
            context.l10n.pairRequestInvited(DateFormatter.momentShort(widget.request.invitedAt!, l10n: context.l10n)),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        if (widget.request.expiresAt != null)
          Text(
            context.l10n.pairRequestExpires(DateFormatter.momentShort(widget.request.expiresAt!, l10n: context.l10n)),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        if (state.failed) ...[
          SizedBox(height: AppSpacingTokens.s12),
          Text(
            state.offline ? context.l10n.pairRequestOffline : context.l10n.pairRequestFailed,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        SizedBox(height: AppSpacingTokens.s24),
        FilledButton(
          onPressed: state.sending ? null : () => _bloc.add(const PairRequestEvent.answered(approve: true)),
          child: Text(context.l10n.pairRequestApprove),
        ),
        SizedBox(height: AppSpacingTokens.s8),
        TextButton(
          onPressed: state.sending ? null : () => _bloc.add(const PairRequestEvent.answered(approve: false)),
          child: Text(context.l10n.pairRequestDecline),
        ),
      ],
    );
  }
}
