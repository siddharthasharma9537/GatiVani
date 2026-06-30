import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "config/api_config.dart";
import "design/app_theme.dart";
import "router.dart";
import "services/auth_service.dart";
import "services/settings_provider.dart";
import "ssl_override_stub.dart"
    if (dart.library.io) "ssl_override_io.dart";
import "url_strategy_stub.dart"
    if (dart.library.html) "url_strategy_web.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  useCleanUrls(); // path URL strategy on web so the browser Back button works
  installSslOverride();
  // Supabase auth (GoTrue). We disable the SDK's built-in URL detection
  // (detectSessionInUri) because on Flutter web it relies on app_links'
  // getInitialLink(), which often doesn't fire — leaving the OAuth `?code=…`
  // in the URL unexchanged (the account gets created server-side but no session
  // is ever established). Instead we exchange the code explicitly below, so the
  // round-trip is deterministic.
  await Supabase.initialize(
    url: ApiConfig.projectUrl,
    anonKey: ApiConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
  );
  // Complete an OAuth redirect: if the launch URL carries an auth code (or an
  // error), exchange it for a session, then the SDK strips the params so a
  // reload doesn't try to reuse a spent code.
  if (kIsWeb) {
    final launchUri = Uri.base;
    final hasAuthParams = launchUri.queryParameters.containsKey('code') ||
        launchUri.queryParameters.containsKey('error') ||
        launchUri.queryParameters.containsKey('error_description');
    if (hasAuthParams) {
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(launchUri);
      } catch (e) {
        debugPrint('OAuth callback exchange failed: $e');
      }
    }
  }
  final settings = SettingsProvider();
  await settings.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
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
