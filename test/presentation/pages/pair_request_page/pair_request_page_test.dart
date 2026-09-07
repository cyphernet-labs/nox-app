import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/person/pair_request.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/pair_request_page/pair_request_page.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

PairRequest _request() => PairRequest(
  requestId: 'r_9c41e0b7',
  invitedAt: DateTime(2026, 6, 15, 14, 32),
  expiresAt: DateTime(2026, 6, 15, 14, 37),
  receivedAt: DateTime(2026, 6, 15, 14, 32),
);

void main() {
  setUp(() => AppClock.freeze(DateTime(2026, 6, 15, 14, 33)));
  tearDown(AppClock.reset);

  testWidgets('the question states what is being decided, and what saying yes grants', (tester) async {
    await pumpApp(tester, PairRequestPage(request: _request()));

    expect(find.text(l10nEn.pairRequestTitle), findsOneWidget);
    expect(find.text(l10nEn.pairRequestMessage), findsOneWidget);
    expect(find.text(l10nEn.pairRequestApprove), findsOneWidget);
    expect(find.text(l10nEn.pairRequestDecline), findsOneWidget);
  });

  testWidgets('it says nothing about who is knocking, because the server knows nothing', (tester) async {
    await pumpApp(tester, PairRequestPage(request: _request()));

    // Not the request id either: that is machinery, not something to read.
    expect(find.textContaining('r_9c41e0b7'), findsNothing);
    // What it does show is what the server actually knows, WITH the date - a
    // person invite lives 24 hours, so a bare time reads as a send moment
    // later than the expiry whenever the two straddle midnight.
    expect(find.textContaining('15 Jun 14:32'), findsOneWidget);
    expect(find.textContaining('15 Jun 14:37'), findsOneWidget);
  });

  testWidgets('a moment the server did not state is not shown at all', (tester) async {
    // Saying nothing beats saying 1970.
    await pumpApp(
      tester,
      PairRequestPage(
        request: PairRequest(requestId: 'r_1', invitedAt: null, expiresAt: null, receivedAt: DateTime(2026, 6, 15, 14, 32)),
      ),
    );

    expect(find.textContaining('Invite sent'), findsNothing);
    expect(find.textContaining('Expires'), findsNothing);
    expect(find.text(l10nEn.pairRequestApprove), findsOneWidget);
  });

  testWidgets('the wide form is a modal that a tap outside does not answer', (tester) async {
    // Driven through showAsDialog, not by constructing the dialog body: the
    // barrier is the thing under test, and it only exists on the route.
    late BuildContext hostContext;
    await pumpApp(
      tester,
      Builder(
        builder: (context) {
          hostContext = context;
          return const Scaffold(body: SizedBox.expand());
        },
      ),
    );
    unawaited(PairRequestPage.showAsDialog(hostContext, _request()));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    // A tap on the barrier is not an answer, and treating it as one would
    // silently decline somebody.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget, reason: 'the only exits are the two answers');

    // Escape follows the barrier: Flutter gates the dismiss action on
    // barrierDismissible, so this fails the moment the flag is dropped.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });
}
