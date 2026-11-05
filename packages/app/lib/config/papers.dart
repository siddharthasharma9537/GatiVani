import '../services/edition_meta.dart';

/// A newspaper shown as a tile on the Paper tab. Names come from the
/// masthead table in [EditionMeta] so there is one spelling per paper.
///
/// [licensed] is false for every paper until a licence is agreed; nothing
/// in the app may show a paper's own content while it is false.
class Paper {
  const Paper(this.id, {this.licensed = false});

  /// Lowercase needle understood by [EditionMeta.parse]; also the route id.
  final String id;
  final bool licensed;

  String name(String lang) => EditionMeta.parse(id).publication(lang);
}

const List<Paper> kPapers = [
  Paper('eenadu'),
  Paper('andhrajyothy'),
  Paper('sakshi'),
  Paper('vaartha'),
  Paper('namasthe'),
];

Paper? paperById(String id) {
  for (final p in kPapers) {
    if (p.id == id) return p;
  }
  return null;
}
