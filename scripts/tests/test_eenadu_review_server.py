"""Synthetic layout fixtures only. Telugu fixtures are AI proposals, not newspaper text."""
import collections
import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from eenadu_review_server import Store


def line(text, font='Eenadu-Light', size=13.2, y=10):
    return dict(converted=text, tfonts=[font], size=size, bullet=False, bbox=[0, y, 100, y + 10])


def block(id, lines, kind='body'):
    return dict(id=id, lines=lines, kind=kind, boxed=False, box=[0, 0, 1, 1])


def store(words=None, pairs=None):
    s = Store.__new__(Store)
    s._lex = (collections.Counter(words or {}), collections.Counter(pairs or {}))
    s.rejoin_log = dict(joined=0, unclear=[])
    s.opt_tags = True
    return s


class ReadingTests(unittest.TestCase):
    def test_composite_graphic_crop_attaches_to_body_group(self):
        class Page:
            rect = type('Rect', (), {'width': 1000, 'height': 1500})()
            def get_image_info(self):
                return [{'bbox': [300, 180, 800, 550]}]

        deck = block('deck', [line('Supporting line')], 'headline')
        deck['box'] = [0.3, 0.18, 0.5, 0.19]
        pictures = Store._wide_pictures(Page(), [deck])
        self.assertEqual(pictures, [[0.3, 0.12, 0.8, 0.18]])
        body = block('body', [line('Body text')])
        body['box'] = [0.3, 0.2, 0.5, 0.3]
        far = block('far', [line('Different headline')], 'headline')
        far['box'] = [0.3, 0.5, 0.5, 0.52]
        far_body = block('far-body', [line('First line'), line('Second line'), line('Third line')])
        far_body['box'] = [0.3, 0.53, 0.5, 0.7]
        result = Store._articles([deck, body, far, far_body], pictures)
        self.assertEqual(result[0]['graphicBox'], pictures[0])
        self.assertNotIn('graphicBox', result[1])

    def test_heading_inside_body_block_becomes_own_story(self):
        lines = [line('A tribute', 'GodawariHeading', 36),
                 line('to a writer', 'GodawariHeading', 36, y=20),
                 line('First body line', y=30), line('Second body line', y=40),
                 line('Third body line', y=50)]
        self.assertEqual(Store._leading_headline_lines(lines), 2)
        self.assertEqual(Store._leading_headline_lines(lines[:2]), 0)
        heading = block('left-h', lines[:2], 'headline')
        heading['box'] = [0.02, 0.1, 0.27, 0.2]
        body = block('left-b', lines[2:])
        body['box'] = [0.02, 0.2, 0.27, 0.8]
        teaser = block('right-h', [line('A separate teaser')], 'headline')
        teaser['box'] = [0.84, 0.1, 0.98, 0.2]
        groups = Store._articles([teaser, heading, body])
        self.assertEqual(groups[0]['blockIds'], ['right-h'])
        self.assertEqual(groups[1]['blockIds'], ['left-h', 'left-b'])

    def test_attested_join_keeps_outer_punctuation(self):
        s = store({'పుస్తకాలు': 1, 'పుస్త': 2})
        self.assertEqual(s._join_lines(["'పుస్త", "కాలు.'"]), "'పుస్తకాలు.'")
        self.assertEqual(s.rejoin_log['joined'], 1)

    def test_two_standalone_words_are_ambiguous_even_without_a_pair(self):
        s = store({'పుస్తకాలు': 10, 'పుస్త': 1, 'కాలు': 1})
        self.assertEqual(s._join_lines(['పుస్త', 'కాలు']), 'పుస్త కాలు')
        self.assertEqual(s.rejoin_log['unclear'], [('పుస్త', 'కాలు', 10, 0)])

    def test_unattested_join_is_logged_not_invented(self):
        s = store()
        self.assertEqual(s._join_lines(['పుస్త', 'కాలు']), 'పుస్త కాలు')
        self.assertEqual(s.rejoin_log['unclear'][0][2], 0)

    def test_internal_punctuation_does_not_join_sentences(self):
        s = store({'పుస్తకాలు': 10})
        self.assertEqual(s._join_lines(['పుస్త.', 'కాలు']), 'పుస్త. కాలు')

    def test_lexicon_reads_each_edition_date_once_and_strips_punctuation(self):
        s = store()
        s._lex = None
        s.editions = lambda: [dict(edition='Test', date=d) for d in ['one', 'two', 'one']]
        s.doc = lambda ed, date: [None]
        seen = []
        def page(ed, date, n):
            seen.append(date)
            return {'blocks': [{'lines': [{'converted': "left 'పుస్తకాలు,' right"}]}]}
        s.page = page
        self.assertEqual(s._lexicon()[0]['పుస్తకాలు'], 2)
        self.assertEqual(seen, ['one', 'two'])

    def test_small_heading_separates_side_note_and_following_column(self):
        s = store()
        items = s._structure([
            block('a', [line('First main heading', 'GodawariHeading', 15.6),
                        line('The main paragraph ends here.', y=25),
                        line('Second main heading', 'GodawariHeading', 15.6, 40),
                        line('Another main paragraph ends here.', y=55),
                        line('A small side note', 'GodawariHeading', 14.3, 70)]),
            block('b', [line('The side note starts here', y=90)]),
            block('c', [line('and continues in another column.', y=10)]),
        ])
        self.assertEqual([i['role'] for i in items], ['subhead', 'body', 'subhead', 'body', 'sidebar'])
        self.assertIn('another column.', items[-1]['text'])
        narration = s._narration(dict(headline='A garden visit', items=items))
        self.assertNotIn('side note', narration)
        self.assertEqual(narration.count('Second main heading'), 1)

    def test_inline_page_pointers_removed_without_removing_body(self):
        s = store()
        text = 'The garden (మిగతా 2 లో) opens (మొదటి పేజీ తరువాయి) today.'
        self.assertEqual(s._clean_reading(text), 'The garden opens today.')
        self.assertEqual(s._narration(dict(headline='A garden', items=[dict(role='body', text=text)])),
                         'A garden\n\nThe garden opens today.')

    def test_continuation_keeps_headline_graphic_and_joins_sentence(self):
        s = store()
        s.opt_reflow = False
        s.reflow_log = {}
        s.join_log = dict(kept_jump_headings=[], sentences_rejoined=0)
        s.drive = '/nonexistent-local-fixture'
        s.doc = lambda ed, date: [None, None]
        graphic = [0.1, 0.1, 0.8, 0.2]
        pages = {
            1: dict(width=100, height=100, label='Page', section='News',
                    blocks=[block('1:h', [line('Garden trees bloom')], 'headline'),
                            block('1:b', [line('The garden trees'), line('2లో', y=25)])],
                    articles=[dict(headline='•Garden trees bloom', blockIds=['1:h', '1:b'], graphicBox=graphic)]),
            2: dict(width=100, height=100, label='Page', section='News',
                    blocks=[block('2:h', [line('Garden trees bloom')], 'headline'),
                            block('2:b', [line('(మొదటి పేజీ తరువాయి)', 'GodawariHeading'), line('bloom in spring.', y=25)])],
                    articles=[dict(headline='Garden trees bloom', blockIds=['2:h', '2:b'])]),
        }
        s.page = lambda ed, date, n: pages[n]
        with patch('eenadu_review_server.os.path.exists', return_value=False):
            paper = s._build_paper('Test', 'today')
        self.assertEqual(len(paper['byId']), 1)
        st = next(iter(paper['byId'].values()))
        self.assertEqual(st['headline'], 'Garden trees bloom')
        self.assertEqual(st['graphic'], graphic)
        self.assertEqual(st['contTo'], [dict(page=2, linked=True)])
        self.assertEqual(st['narration'], 'Garden trees bloom\n\nThe garden trees bloom in spring.')
        self.assertEqual([i['role'] for i in st['items']], ['body'])
        self.assertIs(paper['sections'][0]['stories'][0], st)


if __name__ == '__main__':
    unittest.main()
