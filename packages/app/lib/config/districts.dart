/// District directory for the location preference. English + Telugu names —
/// the Telugu spelling is what actually matches feed/edition text, since all
/// news content is Telugu.
///
/// Andhra Pradesh (26) and Telangana (33) are complete — the districts Telugu
/// news actually covers. Other states plug into the same structure when
/// non-Telugu feeds arrive.
class District {
  const District(this.en, this.te, this.state);
  final String en;
  final String te;
  final String state;

  /// Does [text] mention this district (either script)?
  bool matches(String text) =>
      text.contains(te) || text.toLowerCase().contains(en.toLowerCase());
}

const kDistricts = <District>[
  // ── Andhra Pradesh ──────────────────────────────────────────────────────
  District('Alluri Sitharama Raju', 'అల్లూరి సీతారామరాజు', 'Andhra Pradesh'),
  District('Anakapalli', 'అనకాపల్లి', 'Andhra Pradesh'),
  District('Anantapur', 'అనంతపురం', 'Andhra Pradesh'),
  District('Annamayya', 'అన్నమయ్య', 'Andhra Pradesh'),
  District('Bapatla', 'బాపట్ల', 'Andhra Pradesh'),
  District('Chittoor', 'చిత్తూరు', 'Andhra Pradesh'),
  District('East Godavari', 'తూర్పు గోదావరి', 'Andhra Pradesh'),
  District('Eluru', 'ఏలూరు', 'Andhra Pradesh'),
  District('Guntur', 'గుంటూరు', 'Andhra Pradesh'),
  District('Kadapa', 'కడప', 'Andhra Pradesh'),
  District('Kakinada', 'కాకినాడ', 'Andhra Pradesh'),
  District('Konaseema', 'కోనసీమ', 'Andhra Pradesh'),
  District('Krishna', 'కృష్ణా', 'Andhra Pradesh'),
  District('Kurnool', 'కర్నూలు', 'Andhra Pradesh'),
  District('Nandyal', 'నంద్యాల', 'Andhra Pradesh'),
  District('NTR', 'ఎన్టీఆర్', 'Andhra Pradesh'),
  District('Palnadu', 'పల్నాడు', 'Andhra Pradesh'),
  District('Parvathipuram Manyam', 'పార్వతీపురం మన్యం', 'Andhra Pradesh'),
  District('Prakasam', 'ప్రకాశం', 'Andhra Pradesh'),
  District('Nellore', 'నెల్లూరు', 'Andhra Pradesh'),
  District('Sri Sathya Sai', 'శ్రీ సత్యసాయి', 'Andhra Pradesh'),
  District('Srikakulam', 'శ్రీకాకుళం', 'Andhra Pradesh'),
  District('Tirupati', 'తిరుపతి', 'Andhra Pradesh'),
  District('Visakhapatnam', 'విశాఖపట్నం', 'Andhra Pradesh'),
  District('Vizianagaram', 'విజయనగరం', 'Andhra Pradesh'),
  District('West Godavari', 'పశ్చిమ గోదావరి', 'Andhra Pradesh'),
  // ── Telangana ───────────────────────────────────────────────────────────
  District('Adilabad', 'ఆదిలాబాద్', 'Telangana'),
  District('Bhadradri Kothagudem', 'భద్రాద్రి కొత్తగూడెం', 'Telangana'),
  District('Hanumakonda', 'హనుమకొండ', 'Telangana'),
  District('Hyderabad', 'హైదరాబాద్', 'Telangana'),
  District('Jagtial', 'జగిత్యాల', 'Telangana'),
  District('Jangaon', 'జనగామ', 'Telangana'),
  District('Jayashankar Bhupalpally', 'జయశంకర్ భూపాలపల్లి', 'Telangana'),
  District('Jogulamba Gadwal', 'జోగులాంబ గద్వాల', 'Telangana'),
  District('Kamareddy', 'కామారెడ్డి', 'Telangana'),
  District('Karimnagar', 'కరీంనగర్', 'Telangana'),
  District('Khammam', 'ఖమ్మం', 'Telangana'),
  District('Komaram Bheem Asifabad', 'కొమరం భీమ్ ఆసిఫాబాద్', 'Telangana'),
  District('Mahabubabad', 'మహబూబాబాద్', 'Telangana'),
  District('Mahabubnagar', 'మహబూబ్‌నగర్', 'Telangana'),
  District('Mancherial', 'మంచిర్యాల', 'Telangana'),
  District('Medak', 'మెదక్', 'Telangana'),
  District('Medchal Malkajgiri', 'మేడ్చల్ మల్కాజిగిరి', 'Telangana'),
  District('Mulugu', 'ములుగు', 'Telangana'),
  District('Nagarkurnool', 'నాగర్‌కర్నూల్', 'Telangana'),
  District('Nalgonda', 'నల్గొండ', 'Telangana'),
  District('Narayanpet', 'నారాయణపేట', 'Telangana'),
  District('Nirmal', 'నిర్మల్', 'Telangana'),
  District('Nizamabad', 'నిజామాబాద్', 'Telangana'),
  District('Peddapalli', 'పెద్దపల్లి', 'Telangana'),
  District('Rajanna Sircilla', 'రాజన్న సిరిసిల్ల', 'Telangana'),
  District('Rangareddy', 'రంగారెడ్డి', 'Telangana'),
  District('Sangareddy', 'సంగారెడ్డి', 'Telangana'),
  District('Siddipet', 'సిద్దిపేట', 'Telangana'),
  District('Suryapet', 'సూర్యాపేట', 'Telangana'),
  District('Vikarabad', 'వికారాబాద్', 'Telangana'),
  District('Wanaparthy', 'వనపర్తి', 'Telangana'),
  District('Warangal', 'వరంగల్', 'Telangana'),
  District('Yadadri Bhuvanagiri', 'యాదాద్రి భువనగిరి', 'Telangana'),
];

District? districtByEn(String? en) {
  if (en == null || en.isEmpty) return null;
  for (final d in kDistricts) {
    if (d.en == en) return d;
  }
  return null;
}
