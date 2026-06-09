import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nox_app/design/theme/app_theme.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/app/widgets/app_shell.dart';

/// Root MaterialApp: theme from AppTheme, themeMode from AppRootBloc, design-scale
/// via ScreenUtil with OS font-scale neutralized. Skeleton home is a placeholder;
/// US1 (T030) replaces it with the adaptive AppShell.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late final AppRootBloc _bloc;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _bloc = AppRootBloc()..add(const AppRootEvent.initialize());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AppRootBloc>.value(
      value: _bloc,
      child: BlocBuilder<AppRootBloc, AppRootState>(
        builder: (context, state) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
            child: ScreenUtilInit(
              designSize: Constants.designSize,
              minTextAdapt: true,
              builder: (context, child) {
                return MaterialApp(
                  title: TextConstants.appName,
                  navigatorKey: _navigatorKey,
                  theme: AppTheme.light(),
                  darkTheme: AppTheme.dark(),
                  themeMode: state.themeMode,
                  scrollBehavior: const MaterialScrollBehavior().copyWith(
                    dragDevices: {
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.touch,
                      PointerDeviceKind.trackpad,
                      PointerDeviceKind.stylus,
                    },
                  ),
                  home: const AppShell(),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

