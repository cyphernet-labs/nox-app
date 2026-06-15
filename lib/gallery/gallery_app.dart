import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nox_app/design/theme/app_theme.dart';
import 'package:nox_app/gallery/gallery_page.dart';
import 'package:nox_app/general/constants.dart';

/// Dev-only root for the UI-kit gallery. NOT part of the product app — it is
/// only ever mounted from `lib/main_gallery.dart`, never from `lib/main.dart`,
/// so it cannot reach product navigation or release builds (FR-015).
class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key});

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() => _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _themeMode == ThemeMode.dark;
    return ScreenUtilInit(
      designSize: Constants.designSize,
      minTextAdapt: true,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'NOX UI Kit',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _themeMode,
        home: GalleryPage(onToggleTheme: _toggleTheme, isDark: isDark),
      ),
    );
  }
}
