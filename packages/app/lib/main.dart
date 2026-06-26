import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "design/app_theme.dart";
import "router.dart";
import "services/settings_provider.dart";
import "ssl_override_stub.dart"
    if (dart.library.io) "ssl_override_io.dart";
import "url_strategy_stub.dart"
    if (dart.library.html) "url_strategy_web.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  useCleanUrls(); // path URL strategy on web so the browser Back button works
  installSslOverride();
  final settings = SettingsProvider();
  await settings.load();
  runApp(
    ChangeNotifierProvider.value(
      value: settings,
      child: const GatiVaniApp(),
    ),
  );
}

class GatiVaniApp extends StatelessWidget {
  const GatiVaniApp({super.key});

  @override
  Widget build(BuildContext context) {
    // effectiveThemeMode resolves the "Auto" (system) choice to light/dark by
    // time of day, so the app re-themes when the daylight boundary passes.
    final themeMode = context.select<SettingsProvider, ThemeMode>(
      (s) => s.effectiveThemeMode,
    );
    return MaterialApp.router(
      title: "Gativani",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
