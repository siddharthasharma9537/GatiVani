/// Test fixtures for Gemini service responses
class GeminiFixtures {
  /// Sample article text for testing summarization
  static const String sampleArticleText = '''
    The state government announced new policies for sustainable development today.
    Chief Minister expressed commitment to environmental protection and economic growth.
    The announcement comes after extensive consultations with stakeholders.
    The new initiatives are expected to create thousands of jobs in green sectors.
    Industry leaders have welcomed the move as forward-thinking and progressive.
  ''';

  /// Sample Telugu article text
  static const String sampleTeluguArticleText = '''
    రాష్ట్ర ప్రభుత్వం నేడు టిక్కాऊ అభివృద్ధి కోసం కొత్త విధానాలను ప్రకటించింది.
    ముఖ్యమంత్రి పরిసర రక్షణ మరియు ఆర్థిక వృద్ధికి సంకల్పం చెప్పారు.
    ఈ ప్రకటన వివిధ వర్గాల కూడా సమీక్షలు జరిపిన తర్వాత వచ్చింది.
  ''';

  /// Sample summary output
  static const String sampleSummary = '''
    The state government has unveiled new sustainable development policies aimed at
    balancing environmental protection with economic growth, promising job creation
    in green sectors.
  ''';

  /// Sample Telugu summary
  static const String sampleTeluguSummary = '''
    రాష్ట్ర ప్రభుత్వం పరిసర రక్షణ మరియు ఆర్థిక వృద్ధిని సమతుల్యం చేసేందుకు కొత్త
    టిక్కాऊ అభివృద్ధి విధానాలను ప్రకటించింది.
  ''';

  /// Sample audio script
  static const String sampleAudioScript = '''
    Welcome to GatiVani, your daily newspaper in audio format.

    [PAUSE]

    Today's top story comes from the state government which has announced new policies
    for sustainable development. The Chief Minister emphasized the importance of both
    environmental protection and economic growth.

    [PAUSE]

    Key highlights of this announcement include:
    - Creation of thousands of jobs in green sectors
    - New environmental protection initiatives
    - Support for sustainable industries

    [PAUSE]

    Industry leaders have welcomed these policies as forward-thinking and progressive
    steps for our state's future. More details on these initiatives will be available
    through official channels.

    [PAUSE]

    Thank you for listening to GatiVani. Tune in tomorrow for more news updates.
  ''';

  /// Sample Telugu audio script
  static const String sampleTeluguAudioScript = '''
    గతివాణిలోకి స్వాగతం, మీ రోజువారీ వార్తాపత్రికను ఆడియో ఫార్మాట్‌లో.

    [PAUSE]

    ఈ రోజు ముఖ్య విషయం రాష్ట్ర ప్రభుత్వం టిక్కాऊ అభివృద్ధి కోసం కొత్త విధానాలను ప్రకటించిన దీని గురించి.
    ముఖ్యమంత్రి పరిసర రక్షణ మరియు ఆర్థిక వృద్ధి రెండింటి ముఖ్యత ఎత్తారు.

    [PAUSE]

    ఈ ప్రకటన యొక్క ముఖ్య విషయాలు:
    - ఆకుపచ్చ రంగాలలో లక్షల ఉద్యోగాలు
    - కొత్త పరిసర రక్షణ చర్యలు
    - టిక్కాऊ పరిశ్రమలకు సమర్థన

    [PAUSE]

    పరిశ్రమ నేతలు ఈ విధానాలను ముందుకు చూసే మరియు ప్రగతిశీల చర్యలుగా ప్రశంసించారు.
  ''';

  /// Short article for quick tests
  static const String shortArticleText = '''
    Breaking news: New technology launched today that promises to revolutionize
    the industry. Experts are optimistic about its potential impact.
  ''';

  /// Very long article for stress testing
  static String generateLongArticle({int paragraphs = 10}) {
    final buffer = StringBuffer();
    for (int i = 1; i <= paragraphs; i++) {
      buffer.writeln('''
        Paragraph $i: This is a detailed paragraph discussing various aspects of
        an important topic. It contains multiple sentences that together form a
        coherent narrative about the subject at hand. The content is designed to
        be lengthy enough to test summarization algorithms with realistic data.
      ''');
    }
    return buffer.toString();
  }

  /// Sample articles with different topics
  static final Map<String, String> sampleArticlesByTopic = {
    'politics': '''
      The opposition party has criticized the government's latest budget proposal.
      They argue that it doesn't address the needs of the common people.
      The government defended its stance, saying it is necessary for economic stability.
    ''',
    'sports': '''
      The local cricket team won their match against the visiting team by 50 runs.
      The captain scored a brilliant century that guided the team to victory.
      The crowd at the stadium was thrilled with the exciting performance.
    ''',
    'technology': '''
      A new artificial intelligence startup has announced funding of $50 million.
      The company plans to use AI to revolutionize healthcare diagnostics.
      Industry analysts believe this could be a game-changer in medical technology.
    ''',
    'environment': '''
      New research shows that renewable energy adoption has increased by 30% this year.
      Scientists predict that we could achieve carbon neutrality by 2050.
      Environmental groups are celebrating this progress but call for faster action.
    ''',
  };

  /// Generate test articles with variations
  static List<String> generateVariedArticles(int count) {
    final articles = <String>[];
    final topics = sampleArticlesByTopic.values.toList();

    for (int i = 0; i < count; i++) {
      final topicIndex = i % topics.length;
      articles.add('${topics[topicIndex]} (Variant $i)');
    }
    return articles;
  }

  /// Common summarization prompt patterns for testing
  static const Map<String, String> promptPatterns = {
    'summary': 'Please summarize the following article in 500 words or less',
    'bullet_points': 'Provide the key points of this article in bullet format',
    'podcast': 'Create a podcast-style summary of this article',
    'technical': 'Summarize the technical aspects of this content',
    'executive': 'Provide an executive summary of this article',
  };

  /// Expected summary characteristics for validation
  static const Map<String, dynamic> expectedSummaryCharacteristics = {
    'minLength': 50,
    'maxLength': 1000,
    'containsKeywords': ['announced', 'government', 'development'],
    'avoidsRedundancy': true,
    'maintainsContext': true,
  };

  /// Test cases for different audio script durations
  static const Map<int, int> durationToWordCount = {
    1: 130,
    2: 260,
    5: 650,
    10: 1300,
    30: 3900,
    60: 7800,
  };

  /// Expected characteristics of audio scripts
  static const List<String> audioScriptMarkers = [
    'Welcome',
    'Today',
    'PAUSE',
    'highlights',
    'Thank you',
  ];
}
