import 'package:flutter/material.dart';

import '../tokens.dart';

/// THE section heading — one style for every content section on every tab
/// (Latest stories, Editorial & Opinion, All articles, Podcasts…), so the
/// tabs read as one app.
class GatiSectionLabel extends StatelessWidget {
  const GatiSectionLabel(this.text, {super.key, this.padding});
  final String text;

  /// Override when the surrounding scroll view already supplies the
  /// horizontal gutter (e.g. Live's snap scroll) — the default assumes the
  /// label must inset itself.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ?? const EdgeInsets.fromLTRB(Gati.s5, 0, Gati.s5, Gati.s3),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: GatiPalette.of(context).ink)),
    );
  }
}
