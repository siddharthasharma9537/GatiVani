import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "screens/today_screen.dart";
import "screens/home_screen.dart";
import "design/app_theme.dart";
import "services/settings_provider.dart";
import "ssl_override_stub.dart"
    if (dart.library.io) "ssl_override_io.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    final themeMode = context.select<SettingsProvider, ThemeMode>(
      (s) => s.themeMode,
    );
    return MaterialApp(
      title: "Gativani",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const TodayScreen(),
      routes: {
        '/article-list': (context) {
          return const HomeScreen();
        },
      },
    );
  }
}
