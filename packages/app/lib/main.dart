import "package:flutter/material.dart";
import "screens/home_screen.dart";
import "design/app_theme.dart";
import "ssl_override_stub.dart"
    if (dart.library.io) "ssl_override_io.dart";

void main() {
  installSslOverride();
  runApp(const GatiVaniApp());
}

class GatiVaniApp extends StatelessWidget {
  const GatiVaniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "GatiVani",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
      routes: {
        '/article-list': (context) {
          // This route should not be accessed directly; use push instead
          return const HomeScreen();
        },
      },
    );
  }
}
