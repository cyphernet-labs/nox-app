import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

abstract class BaseStatePage<T extends StatefulWidget> extends State<T> {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool _useDrawerValue = false;

  bool get useDrawer => _useDrawerValue;

  set useDrawer(bool value) {
    if (value != _useDrawerValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _useDrawerValue = value);
      });
    }
  }

  void closeDrawer() {
    if (useDrawer) {
      scaffoldKey.currentState?.closeDrawer();
    }
  }

  /// Platform-aware AppBar factory. Override per page; return null for no AppBar.
  /// Default: a thin status-bar spacer on iOS, nothing elsewhere.
  PreferredSizeWidget? buildAppBar() {
    if (Platform.isIOS) {
      return PreferredSize(
        preferredSize: Size.fromHeight(AppSpacingTokens.s28),
        child: SizedBox(height: AppSpacingTokens.s28),
      );
    }
    return null;
  }
}
