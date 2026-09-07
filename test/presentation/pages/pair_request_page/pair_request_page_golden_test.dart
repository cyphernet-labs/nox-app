@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/person/pair_request.dart';
import 'package:nox_app/presentation/pages/pair_request_page/pair_request_page.dart';

import '../../../utils/golden.dart';

/// Frozen moments rather than "now": a golden that renders a clock drifts every
/// time it is verified.
PairRequest _request() => PairRequest(
  requestId: 'r_9c41e0b7',
  invitedAt: DateTime(2026, 6, 15, 14, 32),
  expiresAt: DateTime(2026, 6, 15, 21, 35),
  receivedAt: DateTime(2026, 6, 15, 21, 30),
);

void main() {
  goldenTest('pair_request_page', () => PairRequestPage(request: _request()));

  // The wide form is a modal over whatever the owner is looking at, so the
  // desktop baseline renders the dialog body the same way the create-chat
  // dialog is pinned.
  goldenTestDesktop(
    'pair_request_page',
    () => Scaffold(
      body: Center(child: PairRequestPage(request: _request(), dialog: true)),
    ),
  );
}
