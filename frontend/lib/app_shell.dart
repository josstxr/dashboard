part of 'main.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: healthyTThemeMode,
      builder: (context, themeMode, _) {
        final isDarkMode = themeMode == ThemeMode.dark;
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDarkMode
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: isDarkMode
                ? Brightness.dark
                : Brightness.light,
            systemNavigationBarColor: isDarkMode
                ? const Color(0xFF0D0F11)
                : const Color(0xFFE9EDF1),
            systemNavigationBarIconBrightness: isDarkMode
                ? Brightness.light
                : Brightness.dark,
          ),
        );

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Healty-T',
          themeMode: themeMode,
          builder: (context, child) => _HealthyTWebAppShell(child: child),
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFE9EDF1),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF101113),
              secondary: Color(0xFF5D6670),
              surface: Color(0xFFF1F4F6),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: Color(0xFF101113),
              elevation: 0,
            ),
            cardTheme: CardThemeData(color: Colors.white.withOpacity(0.86)),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF101113),
                foregroundColor: Colors.white,
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF101113),
              ),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Colors.transparent,
              selectedItemColor: Color(0xFF101113),
              unselectedItemColor: Color(0xFF7A828C),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: Color(0xFF101113),
              foregroundColor: Colors.white,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0D0F11),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFF2F5F7),
              secondary: Color(0xFFB3BAC2),
              surface: Color(0xFF171A1D),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: Color(0xFFF2F5F7),
              elevation: 0,
            ),
            cardTheme: CardThemeData(color: const Color(0xFF171A1D)),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2F5F7),
                foregroundColor: const Color(0xFF0D0F11),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFF2F5F7),
              ),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Colors.transparent,
              selectedItemColor: Color(0xFFF2F5F7),
              unselectedItemColor: Color(0xFF949CA5),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: Color(0xFFF2F5F7),
              foregroundColor: Color(0xFF0D0F11),
            ),
          ),
          home: const AuthGate(),
        );
      },
    );
  }
}

class _HealthyTWebAppShell extends StatelessWidget {
  final Widget? child;

  const _HealthyTWebAppShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final app = child ?? const SizedBox.shrink();
    if (!kIsWeb) {
      return app;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        if (constraints.maxWidth <= 600) {
          return app;
        }

        const appWidth = 430.0;
        final isLight = Theme.of(context).brightness == Brightness.light;
        final shellHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : media.size.height;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isLight
                  ? const [Color(0xFFDDE4EA), Color(0xFFC9D4DE)]
                  : const [Color(0xFF111418), Color(0xFF050607)],
            ),
          ),
          child: Center(
            child: SizedBox(
              width: appWidth,
              height: shellHeight,
              child: ClipRect(
                child: MediaQuery(
                  data: media.copyWith(size: Size(appWidth, shellHeight)),
                  child: app,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
