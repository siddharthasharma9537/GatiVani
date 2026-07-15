// Non-web platforms: no browser share/print/download APIs yet, so the
// Reader's share icon and Menu's "Share GatiVani" row both stay hidden
// (see canShare / canExportArticle). Native share (share_plus or similar)
// would need a new plugin dependency this environment can't wire in
// (no Flutter toolchain to regenerate native plugin registration).
bool get canShare => false;
bool get canExportArticle => false;

void shareContent({required String title, String? text, String? url}) {}
void downloadArticleText(String title, String source, String body) {}
void printArticle(String title, String source, String body) {}
