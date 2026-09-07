import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/person/pair_request.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/pair_request_page/pair_request_page.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

PairRequest _request() =>
    PairRequest(requestId: 'r_9c41e0b7', invitedAt: DateTime(2026, 6, 15, 14, 32), expiresAt: DateTime(2026, 6, 15, 14, 37));

void main() {
  testWidgets('the question states what is being decided, and what saying yes grants', (tester) async {
    await pumpApp(tester, PairRequestPage(request: _request()));

    expect(find.text(l10nEn.pairRequestTitle), findsOneWidget);
    expect(find.text(l10nEn.pairRequestMessage), findsOneWidget);
    expect(find.text(l10nEn.pairRequestApprove), findsOneWidget);
    expect(find.text(l10nEn.pairRequestDecline), findsOneWidget);
  });

  testWidgets('it says nothing about who is knocking, because the server knows nothing', (tester) async {
    await pumpApp(tester, PairRequestPage(request: _request()));

    // No name, no platform, no id - and not the request id either, which is
    // machinery rather than something to read.
    expect(find.textContaining('r_9c41e0b7'), findsNothing);
    expect(find.textContaining('ios', findRichText: true), findsNothing);
    // What it does show is what the server actually knows: which invite this is
    // and how long is left.
    expect(find.textContaining('14:32'), findsOneWidget);
    expect(find.textContaining('14:37'), findsOneWidget);
  });

  testWidgets('the wide form is a modal whose only exits are the two answers', (tester) async {
    // The wide branch picks itself by width, so the surface is sized rather
    // than asked - the convention every responsive test here follows.
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(
      tester,
      Scaffold(
        body: Center(child: PairRequestPage(request: _request(), dialog: true)),
      ),
    );

    expect(find.byType(Dialog), findsOneWidget);
    // No back arrow and no close button: brushing past is not an answer.
    expect(find.byType(BackButton), findsNothing);
    expect(find.text(l10nEn.pairRequestApprove), findsOneWidget);
    expect(find.text(l10nEn.pairRequestDecline), findsOneWidget);
  });
}
