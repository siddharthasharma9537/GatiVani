import 'package:flutter_test/flutter_test.dart';
import 'package:gativani_app/config/papers.dart';

void main() {
  test('five papers, none licensed, names in both languages', () {
    expect(kPapers.map((p) => p.name('en')).toList(), [
      'Eenadu',
      'Andhra Jyothy',
      'Sakshi',
      'Vaartha',
      'Namasthe Telangana',
    ]);
    expect(kPapers.map((p) => p.name('te')).toList(), [
      'ఈనాడు',
      'ఆంధ్రజ్యోతి',
      'సాక్షి',
      'వార్త',
      'నమస్తే తెలంగాణ',
    ]);
    expect(kPapers.any((p) => p.licensed), isFalse);
  });

  test('paperById resolves ids and rejects unknown ones', () {
    expect(paperById('sakshi')?.id, 'sakshi');
    expect(paperById('uploads'), isNull);
  });
}
