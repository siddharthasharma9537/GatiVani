import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/districts.dart';
import '../design/tokens.dart';
import '../services/news_feed_service.dart';
import '../services/settings_provider.dart';

/// The flash-news strip: market ticker + diverse headlines on the gold band.
/// Self-fetching, so any tab can mount it (Live and Paper both do).
class NewsTicker extends StatefulWidget {
  const NewsTicker({super.key});

  @override
  State<NewsTicker> createState() => _NewsTickerState();
}

class _NewsTickerState extends State<NewsTicker> {
  final _feed = NewsFeedService();
  List<MarketItem> _markets = [];
  List<NewsItem> _headlines = [];
  String? _city; // slug the current prices were fetched for

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  // Prices follow the user's district: refetch when the nearest priced
  // city changes (district picked in the filter / menu / via Vāni).
  void _sync() {
    if (!mounted) return;
    final d = districtByEn(context.read<SettingsProvider>().district);
    final slug = d == null ? null : citySlugFor(d);
    if (slug == _city && _markets.isNotEmpty) return;
    _city = slug;
    _load(slug);
  }

  Future<void> _load(String? city) async {
    final marketsF = _feed.fetchMarkets(city: city);
    final headlinesF =
        _headlines.isEmpty ? _feed.fetch(topic: 'top', limit: 8) : null;
    final markets = await marketsF;
    final headlines = await headlinesF ?? _headlines;
    if (!mounted) return;
    setState(() {
      _markets = markets;
      _headlines = headlines;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.lang;
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    final items = [
      ..._markets.map((m) => _marketString(m, lang)),
      ..._headlines.take(6).map((e) => e.title),
    ];
    return BreakingMarquee(
        items: items.isEmpty
            ? [lang == 'te' ? 'లోడ్ అవుతోంది…' : 'Loading…']
            : items);
  }
}

class BreakingMarquee extends StatefulWidget {
  const BreakingMarquee({required this.items});
  final List<String> items;

  @override
  State<BreakingMarquee> createState() => BreakingMarqueeState();
}

class BreakingMarqueeState extends State<BreakingMarquee>
    with SingleTickerProviderStateMixin {
  // A fixed ⚡ badge sits on the left; ONLY the headline band scrolls. The band
  // is the full run of headlines at their natural width, drawn twice
  // back-to-back and translated by exactly one band-width for a seamless loop.
  // Speed is a constant px/sec (duration ∝ width), so the scroll feels the
  // same no matter how many headlines there are.
  //
  // The width MUST come from the real render pipeline, not a parallel
  // TextPainter measurement — a separate TextPainter can disagree with the
  // actual painted width by a pixel or two (font hinting, mixed Telugu/Latin/
  // symbol shaping), and with `Clip.none` that tiny gap shows up once per loop
  // as either an overlap or a flash of blank space right at the seam. So an
  // identical, offstage copy of the same Text is kept in the tree purely to be
  // measured via its real RenderBox — guaranteeing the scrolling twins below
  // are pixel-exact.
  static const _style =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kPaper);
  static const _pxPerSec = 40.0;

  late final AnimationController _c;
  final _measureKey = GlobalKey();
  String _line = '';
  double _bandWidth = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 20));
    _line = _composeLine(widget.items);
    // Flutter web loads the Telugu font asynchronously — the same string can
    // render wider once the real font (vs. a fallback) is in. Re-measure
    // whenever a system font finishes loading.
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _onFontsChanged() {
    if (!mounted) return;
    setState(() {}); // force a relayout so the offstage copy re-shapes
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(BreakingMarquee old) {
    super.didUpdateWidget(old);
    final next = _composeLine(widget.items);
    if (next != _line) {
      setState(() => _line = next);
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  // Headlines separated by a bullet, with a trailing gap so the loop seam keeps
  // a separator between the last and first item.
  String _composeLine(List<String> items) =>
      '${items.map((s) => s.trim()).join('   •   ')}   •   ';

  void _measure() {
    if (!mounted) return;
    final box = _measureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.width <= 0) return;
    final w = box.size.width;
    if (_ready && (w - _bandWidth).abs() < 0.5) return; // no real change
    setState(() {
      _bandWidth = w;
      _ready = true;
    });
    final secs = (_bandWidth / _pxPerSec).clamp(6.0, 240.0);
    _c
      ..stop()
      ..value = 0
      ..duration = Duration(milliseconds: (secs * 1000).round())
      ..repeat();
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      color: kAccent,
      child: Row(children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Gati.s3),
          child: Icon(Icons.bolt, size: 16, color: kPaper),
        ),
        Offstage(
          offstage: true,
          child: Text(_line,
              key: _measureKey, maxLines: 1, softWrap: false, style: _style),
        ),
        Expanded(
          child: !_ready
              ? const SizedBox.shrink()
              : ClipRect(
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) {
                      final dx = -_c.value * _bandWidth;
                      return Stack(clipBehavior: Clip.none, children: [
                        Positioned(
                            left: dx,
                            top: 0,
                            bottom: 0,
                            width: _bandWidth,
                            child: _band()),
                        Positioned(
                            left: dx + _bandWidth,
                            top: 0,
                            bottom: 0,
                            width: _bandWidth,
                            child: _band()),
                      ]);
                    },
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _band() => Align(
        alignment: Alignment.centerLeft,
        child: Text(_line,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: _style),
      );
}

String _marketString(MarketItem m, String lang) {
  const labels = {
    'nifty': ['Nifty', 'నిఫ్టీ'],
    'sensex': ['Sensex', 'సెన్సెక్స్'],
    'gold': ['Gold', 'బంగారం'],
    'silver': ['Silver', 'వెండి'],
    'petrol': ['Petrol', 'పెట్రోల్'],
    'diesel': ['Diesel', 'డీజిల్'],
  };
  final l = labels[m.key];
  final label = l == null ? m.key : (lang == 'te' ? l[1] : l[0]);
  // Daily-fixed prices (city fuel/gold) carry no intraday change — no arrow.
  final chg = m.changePct == 0
      ? ''
      : ' ${m.changePct >= 0 ? '▲' : '▼'}${m.changePct.abs().toStringAsFixed(2)}%';
  switch (m.key) {
    case 'gold':
      return '$label ₹${_inr(m.value)}/10g$chg';
    case 'silver':
      return '$label ₹${_inr(m.value)}/kg$chg';
    case 'petrol':
    case 'diesel':
      return '$label ₹${m.value.toStringAsFixed(2)}/L$chg';
    default:
      return '$label ${_inr(m.value, decimals: 2)}$chg';
  }
}
String _inr(double v, {int decimals = 0}) {
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  var intPart = dot >= 0 ? fixed.substring(0, dot) : fixed;
  final dec = dot >= 0 ? fixed.substring(dot) : '';
  String grouped;
  if (intPart.length <= 3) {
    grouped = intPart;
  } else {
    final last3 = intPart.substring(intPart.length - 3);
    var rest = intPart.substring(0, intPart.length - 3);
    final chunks = <String>[];
    while (rest.length > 2) {
      chunks.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) chunks.insert(0, rest);
    grouped = '${chunks.join(',')},$last3';
  }
  return '${neg ? '-' : ''}$grouped$dec';
}