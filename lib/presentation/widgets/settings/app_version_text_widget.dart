import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// App version text from platform info (package_info_plus). [showBuild] appends the
/// build number, e.g. `1.2.3 (456)`. Renders empty while loading. Presentational.
class AppVersionTextWidget extends StatelessWidget {
  const AppVersionTextWidget({super.key, this.showBuild = true, this.style});

  final bool showBuild;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final text = info == null ? '' : (showBuild ? '${info.version} (${info.buildNumber})' : info.version);
        return Text(text, style: style);
      },
    );
  }
}
