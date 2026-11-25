// Neutral synthetic Telugu; AI proposals, not newspaper content.
Map<String, dynamic> storyJson(
        {String id = 'p1-g0',
        String section = 'front',
        String edition = 'TELANGANA',
        String date = '2026-11-13',
        String? narration}) =>
    {
      'source_id': id,
      'edition': edition,
      'source_date': date,
      'section': section,
      'sort_order': 0,
      'headline': 'తోటలో చెట్లు',
      'headline_is_graphic': false,
      'headline_image_url': null,
      'byline': 'రచయిత',
      'word_count': 4,
      'display_text': 'తోటలో చెట్లు\nతోటలో పూలు వికసించాయి.',
      'narration_text': narration ?? 'తోటలో చెట్లు.\n\nతోటలో పూలు వికసించాయి.',
      'page_numbers': [1, 2],
      'continuation_info': [
        {'page': 2, 'linked': true},
        {'page': 3, 'linked': false}
      ],
      'items': [
        {'role': 'headline', 'text': 'తోటలో చెట్లు'},
        {'role': 'kicker', 'text': 'ప్రకృతి'},
        {'role': 'deck', 'text': 'మొక్కల సంరక్షణ'},
        {'role': 'byline', 'text': 'రచయిత'},
        {'role': 'subheading', 'text': 'పూల రంగులు'},
        {'role': 'body', 'text': 'తోటలో పూలు వికసించాయి.'},
        {'role': 'caption', 'text': 'పూల చిత్రం'},
        {'role': 'side', 'text': 'మొక్కలకు నీరు అవసరం.'},
      ],
    };
