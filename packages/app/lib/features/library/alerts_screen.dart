import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/alert_topics.dart';
import '../design/components/gati_states.dart';
import '../design/tokens.dart';
import '../l10n/strings.dart';
import '../services/alerts_service.dart';
import '../services/settings_provider.dart';
import '../widgets/gati_puck.dart';

/// Menu → My Alerts: the user picks topics (exam results, govt job
/// notifications…) and this screen lists release-shaped headlines for them,
/// newest first, each linking to the publisher. Opening it clears the menu
/// badge.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _editing = settings.alertTopics.isEmpty; // first visit → pick topics
    AlertsService.i.refreshIfStale(settings);
    // Everything visible now is "seen" — the badge counts what arrives later.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => settings.markAlertsSeen());
  }

  @override
  Widget build(BuildContext context) {
    final p = GatiPalette.of(context);
    final s = context.watch<SettingsProvider>();
    final lang = s.lang;
    return Scaffold(
      backgroundColor: p.paper,
      body: Stack(children: [
        SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Gati.s3, Gati.s2, Gati.s3, Gati.s2),
              child: Row(children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: p.ink),
                  onPressed: () => context.pop(),
                ),
                Expanded(
                  child: Text(tr(lang, 'alerts'),
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: p.ink)),
                ),
                TextButton(
                  onPressed: () => setState(() => _editing = !_editing),
                  child: Text(
                      tr(lang, _editing ? 'alerts_done' : 'alerts_edit'),
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: Gati.accent)),
                ),
              ]),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: AlertsService.i,
                builder: (context, _) => _body(p, s, lang),
              ),
            ),
          ]),
        ),
        const GatiPuck(),
      ]),
    );
  }

  Widget _body(GatiPalette p, SettingsProvider s, String lang) {
    final svc = AlertsService.i;
    final children = <Widget>[];

    if (_editing || s.alertTopics.isEmpty) {
      children.addAll(_topicPicker(p, s, lang));
    }

    if (s.alertTopics.isNotEmpty) {
      if (svc.loading && svc.items.isEmpty) {
        children.add(const Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Gati.accent))),
        ));
      } else if (svc.failed && svc.items.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 48),
          child: GatiEmpty(message: tr(lang, 'alerts_error'), onInk: false),
        ));
      } else if (svc.items.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 48),
          child: GatiEmpty(message: tr(lang, 'alerts_empty'), onInk: false),
        ));
      } else {
        for (var i = 0; i < svc.items.length; i++) {
          if (i > 0) children.add(Divider(height: 1, color: p.line));
          children.add(_row(p, lang, svc.items[i]));
        }
      }
    }

    return RefreshIndicator(
      color: Gati.accent,
      onRefresh: () => AlertsService.i.refresh(s),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding:
            const EdgeInsets.fromLTRB(Gati.s5, Gati.s2, Gati.s5, Gati.s6),
        children: children,
      ),
    );
  }

  List<Widget> _topicPicker(GatiPalette p, SettingsProvider s, String lang) {
    Widget group(String key, String groupId) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 14),
              child: Text(tr(lang, key),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: p.muted,
                      letterSpacing: 0.3)),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in kAlertTopics.where((t) => t.group == groupId))
                  _topicChip(p, s, lang == 'te' ? t.te : t.en, t.id),
              ],
            ),
          ],
        );

    return [
      if (s.alertTopics.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(tr(lang, 'alerts_pick'),
              style: TextStyle(fontSize: 13.5, height: 1.45, color: p.muted)),
        ),
      group('alerts_group_exams', 'exams'),
      group('alerts_group_jobs', 'jobs'),
      const SizedBox(height: 10),
      Divider(height: 24, color: p.line),
    ];
  }

  // Paper-side selectable chip (GatiChip is the on-ink player variant).
  Widget _topicChip(
      GatiPalette p, SettingsProvider s, String label, String id) {
    final selected = s.alertTopics.contains(id);
    return GestureDetector(
      onTap: () {
        s.toggleAlertTopic(id);
        AlertsService.i.refresh(s);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Gati.pasupu : p.surface,
          border: Border.all(color: selected ? Gati.pasupu : p.line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Gati.inkDeep : p.ink,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _row(GatiPalette p, String lang, AlertItem a) {
    final topic = alertTopicById(a.topic);
    final topicLabel =
        topic == null ? a.topic : (lang == 'te' ? topic.te : topic.en);
    return InkWell(
      onTap: () {
        final uri = Uri.tryParse(a.link);
        if (uri != null) {
          launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gati.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(topicLabel,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Gati.accent)),
            const SizedBox(height: 4),
            Text(a.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 14.5, height: 1.35, color: p.ink)),
            const SizedBox(height: 4),
            Text(
                '${a.source}'
                '${a.date != null ? ' · ${_ago(a.date!, lang)}' : ''}',
                style: TextStyle(fontSize: 11.5, color: p.muted)),
          ],
        ),
      ),
    );
  }

  String _ago(DateTime d, String lang) {
    final diff = DateTime.now().toUtc().difference(d);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes.clamp(1, 59)} ${lang == 'te' ? 'నిమి క్రితం' : 'min ago'}';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} ${lang == 'te' ? 'గం క్రితం' : 'h ago'}';
    }
    return formatEditionDate(d.toLocal(), lang);
  }
}
