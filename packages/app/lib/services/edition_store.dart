import '../models/newspaper_article.dart';

/// Holds the currently-loaded edition's articles app-wide, so a route like
/// `/section/State` can resolve its list even after a browser back/forward —
/// go_router's `extra` is NOT preserved across history navigation, so passing
/// the articles that way crashes on Back. The section name lives in the URL;
/// the articles come from here.
class EditionStore {
  EditionStore._();
  static final EditionStore i = EditionStore._();

  List<NewspaperArticle> articles = [];

  List<NewspaperArticle> forSection(String section) =>
      articles.where((a) => a.category == section).toList();
}
