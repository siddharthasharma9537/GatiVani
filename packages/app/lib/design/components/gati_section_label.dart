import 'package:flutter/material.dart';

import '../tokens.dart';

/// THE section heading — one style for every content section on every tab
/// (Latest stories, Editorial & Opinion, All articles, Podcasts…), so the
/// tabs read as one app.
class GatiSectionLabel extends StatelessWidget {
  const GatiSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gati.s5, 0, Gati.s5, Gati.s3),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: GatiPalette.of(context).ink)),
    );
  }
}
