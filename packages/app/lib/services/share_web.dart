// Getting an article (or the app itself) out to the user's device or other
// apps. No new dependency — `package:web` and raw js_interop are already
// used elsewhere (see speech_web.dart, which this mirrors for the same
// reason: the Web Share API isn't part of package:web's typed surface, so
// it's called dynamically like SpeechRecognition already is).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

bool get canShare {
  final nav = web.window.navigator as JSObject;
  return !nav.getProperty('share'.toJS).isUndefinedOrNull;
}

/// Native share sheet (WhatsApp, Facebook, Mail, Save to Files, and — on
/// many platforms, notably iOS — Print itself: whatever's installed and
/// registered as a share target, populated by the OS/browser, not us).
/// Callers should check [canShare] first and offer downloadArticleText /
/// printArticle instead when it's false (older desktop browsers mainly).
void shareContent({required String title, String? text, String? url}) {
  final nav = web.window.navigator as JSObject;
  final data = JSObject()..setProperty('title'.toJS, title.toJS);
  if (text != null && text.isNotEmpty) {
    data.setProperty('text'.toJS, text.toJS);
  }
  if (url != null && url.isNotEmpty) {
    data.setProperty('url'.toJS, url.toJS);
  }
  // Rejects (e.g. the user cancelled the share sheet) are not errors —
  // nothing to react to either way, so no need to await/catch.
  nav.callMethod('share'.toJS, data);
}

bool get canExportArticle => true;

String _safeFileName(String s) {
  final cleaned = s
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  final trimmed = cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  return trimmed.isEmpty ? 'article' : trimmed;
}

String _escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Download the article as a plain-text file — fallback for browsers
/// without Web Share support: no rendering ambiguity, guaranteed correct.
/// [source] (the publisher/site) is mandatory — a shared or downloaded
/// article always carries attribution, never just bare text.
void downloadArticleText(String title, String source, String body) {
  final content = '$title\n$source\n\n$body';
  final blob = web.Blob(
    [content.toJS].toJS,
    web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = '${_safeFileName(title)}.txt';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

/// Print (or "Save as PDF" via the browser's print dialog) — the other
/// fallback for browsers without Web Share support (which itself often
/// exposes Print as one of its share-sheet options). Flutter web renders to
/// canvas, so printing the app's own window directly would produce a
/// blank/garbled page — instead this opens a plain, real-DOM document in a
/// new tab with just the article's title + body and prints THAT, so the
/// output is clean, paginated, selectable text. [source] (the publisher/
/// site) is mandatory — a printed article always carries attribution.
void printArticle(String title, String source, String body) {
  final win = web.window.open('', '_blank');
  if (win == null) return;
  final doc = win.document;
  final paragraphs = body
      .split(RegExp(r'\n+'))
      .where((p) => p.trim().isNotEmpty)
      .map((p) => '<p>${_escapeHtml(p)}</p>')
      .join('\n');
  final html = '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>${_escapeHtml(title)}</title>
<style>
  body { font-family: Georgia, 'Noto Sans Telugu', serif; max-width: 680px;
         margin: 40px auto; padding: 0 20px; line-height: 1.6; color: #1a1a1a; }
  h1 { font-size: 24px; margin-bottom: 4px; }
  .byline { font-size: 13px; color: #666; margin-bottom: 24px; }
  p { margin: 0 0 16px; }
</style>
</head>
<body>
<h1>${_escapeHtml(title)}</h1>
<p class="byline">${_escapeHtml(source)}</p>
$paragraphs
</body>
</html>
''';
  doc.open();
  doc.write(html);
  doc.close();
  // Give the new document a moment to paint before invoking print.
  Future.delayed(const Duration(milliseconds: 150), () {
    win.print();
  });
}
