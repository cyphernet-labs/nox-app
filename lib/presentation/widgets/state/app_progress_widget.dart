import 'package:flutter/material.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// Centered loading state for `state.when(initializing: ...)` and first-page
/// pagination indicators. Wraps [AppSpinnerWidget] (`primary` on `surface`).
class AppProgressWidget extends StatelessWidget {
  const AppProgressWidget({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(child: AppSpinnerWidget(size: size));
  }
}
