import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../l10n/strings.dart';
import '../../services/tts/narration_controller.dart';
import '../../services/tts/voice_pack/pack_manifest.dart';

typedef SettingsSectionLabel = Widget Function(GatiPalette p, String text);
typedef SettingsCard = Widget Function(GatiPalette p, Widget child);
typedef SettingsChoiceRow = Widget Function(GatiPalette p, String label, bool selected, VoidCallback onTap, {String? subtitle});

/// "Voice" block of the Settings screen: which voice reads stories (automatic / on-device / phone / online), female or male,
/// and the on-device voice pack (download with progress, cancel, delete, credits). The Telugu strings are AI proposals.
class VoiceSettingsSection extends StatefulWidget {
  const VoiceSettingsSection({
    super.key,
    required this.p,
    required this.lang,
    required this.sectionLabel,
    required this.card,
    required this.choiceRow,
  });

  final GatiPalette p;
  final String lang;
  final SettingsSectionLabel sectionLabel;
  final SettingsCard card;
  final SettingsChoiceRow choiceRow;

  @override
  State<VoiceSettingsSection> createState() => _VoiceSettingsSectionState();
}

class _VoiceSettingsSectionState extends State<VoiceSettingsSection> {
  @override
  void initState() {
    super.initState();
    NarrationController.i.load();
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

  void _showCredits() {
    final p = widget.p;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: p.surface,
        title: Text(tr(widget.lang, 'vs_credits'), style: TextStyle(color: p.ink, fontSize: 16)),
        content: SingleChildScrollView(
          child: SelectableText(voicePackCredits, style: TextStyle(color: p.ink, fontSize: 12.5, height: 1.45)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(widget.lang, 'vs_close')))],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(widget.lang, 'vs_delete_q')),
        content: Text(tr(widget.lang, 'vs_delete_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(widget.lang, 'vs_cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(widget.lang, 'vs_delete'))),
        ],
      ),
    );
    if (ok == true) await NarrationController.i.deletePack();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p, lang = widget.lang;
    return ListenableBuilder(
      listenable: NarrationController.i,
      builder: (context, _) {
        final c = NarrationController.i;
        Widget engineRow(NarrationEngine e, String key) => widget.choiceRow(
              p,
              tr(lang, 'vs_engine_$key'),
              c.engine == e,
              () => c.setEngine(e),
              subtitle: tr(lang, 'vs_engine_${key}_sub'),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          widget.sectionLabel(p, tr(lang, 'voice')),
          widget.card(
            p,
            Semantics(
              container: true,
              label: tr(lang, 'vs_engine_group'),
              child: Column(children: [
                engineRow(NarrationEngine.auto, 'auto'),
                Divider(height: 1, color: p.line),
                engineRow(NarrationEngine.onDevice, 'ondevice'),
                Divider(height: 1, color: p.line),
                engineRow(NarrationEngine.system, 'system'),
                Divider(height: 1, color: p.line),
                engineRow(NarrationEngine.cloud, 'cloud'),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          widget.card(
            p,
            Column(children: [
              widget.choiceRow(p, tr(lang, 'vs_voice_female'), c.voice == 'female', () => c.setVoice('female')),
              Divider(height: 1, color: p.line),
              widget.choiceRow(p, tr(lang, 'vs_voice_male'), c.voice == 'male', () => c.setVoice('male')),
            ]),
          ),
          const SizedBox(height: 12),
          widget.card(p, _pack(context, c)),
          const SizedBox(height: 20),
        ]);
      },
    );
  }

  Widget _pack(BuildContext context, NarrationController c) {
    final p = widget.p, lang = widget.lang;
    final size = _mb(VoicePackManifest.indicTinyTelugu.totalBytes);
    final installing = c.packStatus == PackStatus.installing;
    final installed = c.packStatus == PackStatus.installed;
    final pct = c.packTotal == 0 ? 0.0 : (c.packDone / c.packTotal).clamp(0.0, 1.0);
    String? error;
    if (c.packStatus == PackStatus.failed) {
      error = (c.packError ?? '').contains('Not enough storage') ? tr(lang, 'vs_no_space') : tr(lang, 'vs_failed');
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(lang, 'vs_pack_title'), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: p.ink)),
        const SizedBox(height: 4),
        Text(
          installed ? '${tr(lang, 'vs_installed')} · $size' : tr(lang, 'vs_pack_desc').replaceAll('{size}', size),
          style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.4),
        ),
        if (installing) ...[
          const SizedBox(height: 12),
          Semantics(
            label: tr(lang, 'vs_downloading'),
            value: '${(pct * 100).round()}%',
            child: LinearProgressIndicator(value: pct, color: kAccent, backgroundColor: p.chip, minHeight: 6),
          ),
          const SizedBox(height: 6),
          Text('${_mb(c.packDone)} / ${_mb(c.packTotal)}', style: TextStyle(fontSize: 12, color: p.muted)),
        ],
        if (error != null) ...[
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(error, style: TextStyle(fontSize: 12.5, color: Gati.kumkuma))),
        ],
        const SizedBox(height: 10),
        Row(children: [
          TextButton(onPressed: _showCredits, child: Text(tr(lang, 'vs_credits'))),
          const Spacer(),
          if (installed)
            TextButton(
              onPressed: _confirmDelete,
              child: Semantics(label: tr(lang, 'vs_delete_a11y'), child: Text(tr(lang, 'vs_delete'), style: TextStyle(color: Gati.kumkuma))),
            )
          else if (installing)
            OutlinedButton(onPressed: c.cancelInstall, child: Text(tr(lang, 'vs_cancel')))
          else
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kAccent, foregroundColor: kPaper),
              onPressed: c.installPack,
              child: Semantics(
                  label: tr(lang, 'vs_download_a11y').replaceAll('{size}', size),
                  child: Text(c.packStatus == PackStatus.failed ? tr(lang, 'vs_retry') : tr(lang, 'vs_download'))),
            ),
        ]),
      ]),
    );
  }
}
