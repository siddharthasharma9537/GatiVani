import 'package:flutter_web_plugins/url_strategy.dart';

// Path URL strategy → Flutter uses MultiEntriesBrowserHistory, so every pushed
// route is a real browser history entry. That's what makes the browser Back
// button pop the player/section/menu instead of leaving the app entirely.
// (Deep-link/refresh works because vercel.json rewrites every path to index.html.)
void useCleanUrls() => usePathUrlStrategy();
