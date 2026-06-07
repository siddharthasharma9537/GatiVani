import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/app_theme.dart';
import '../services/settings_provider.dart';

// ── Voice catalogue (mirrors audio_queue_player_screen) ──────────────────────

class _Voice {
  final String id;
  final String label;
  final String gender;
  const _Voice(this.id, this.label, this.gender);
}

const _sarvamVoices = [
  _Voice('priya',   'Priya',   'Female'),
  _Voice('neha',    'Neha',    'Female'),
  _Voice('kavya',   'Kavya',   'Female'),
  _Voice('shreya',  'Shreya',  'Female'),
  _Voice('suhani',  'Suhani',  'Female'),
  _Voice('kavitha', 'Kavitha', 'Female'),
  _Voice('shubh',   'Shubh',   'Male'),
  _Voice('aditya',  'Aditya',  'Male'),
  _Voice('rahul',   'Rahul',   'Male'),
  _Voice('anand',   'Anand',   'Male'),
  _Voice('gokul',   'Gokul',   'Male'),
  _Voice('varun',   'Varun',   'Male'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<({int fileCount, int bytes})> _statsFuture;

  @override
  void initState() {
    super.initState();
    _refreshStats();
  }

  void _refreshStats() {
    _statsFuture = context.read<SettingsProvider>().downloadStats();
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '${b} B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: GVColors.bgSecondary(context),
      appBar: AppBar(
        backgroundColor: GVColors.bgPrimary(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: GVColors.textPrimary(context),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Settings', style: GVTypography.heading(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // ── Appearance ────────────────────────────────────────────────────
          _SectionHeader(label: 'Appearance'),
          _SettingsCard(
            children: [
              _SegmentedRow(
                icon: Icons.brightness_medium_outlined,
                label: 'Theme',
                options: const ['System', 'Light', 'Dark'],
                selectedIndex: settings.themeMode.index,
                onSelected: (i) => settings.setThemeMode(ThemeMode.values[i]),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Audio ─────────────────────────────────────────────────────────
          _SectionHeader(label: 'Audio'),
          _SettingsCard(
            children: [
              // Default voice
              _TileHeader(
                icon: Icons.record_voice_over_outlined,
                label: 'Default voice',
                subtitle: 'Used for new playback sessions & downloads',
              ),
              const SizedBox(height: 12),
              _VoicePicker(
                selected: settings.defaultVoice,
                onSelect: settings.setDefaultVoice,
              ),
              Divider(height: 24, thickness: 0.5, color: GVColors.borderTertiary(context)),
              // Playback speed
              _SpeedRow(
                speed: settings.playbackSpeed,
                onChanged: settings.setPlaybackSpeed,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Downloads ────────────────────────────────────────────────────
          if (!kIsWeb) ...[
            _SectionHeader(label: 'Downloads'),
            _SettingsCard(
              children: [
                FutureBuilder<({int fileCount, int bytes})>(
                  future: _statsFuture,
                  builder: (ctx, snap) {
                    final count = snap.data?.fileCount ?? 0;
                    final bytes = snap.data?.bytes ?? 0;
                    final label = snap.connectionState == ConnectionState.done
                        ? count == 0
                            ? 'No downloaded articles'
                            : '$count article${count == 1 ? '' : 's'} · ${_fmtBytes(bytes)}'
                        : 'Calculating…';
                    return _InfoRow(
                      icon: Icons.download_rounded,
                      label: 'Saved audio',
                      value: label,
                    );
                  },
                ),
                Divider(height: 20, thickness: 0.5, color: GVColors.borderTertiary(context)),
                _ActionRow(
                  icon: Icons.delete_outline_rounded,
                  label: 'Clear all downloads',
                  color: GVColors.danger(context),
                  onTap: () => _confirmClear(context, settings),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // ── About ────────────────────────────────────────────────────────
          _SectionHeader(label: 'About'),
          _SettingsCard(
            children: [
              _InfoRow(
                icon: Icons.info_outline_rounded,
                label: 'Version',
                value: '1.0.0',
              ),
              Divider(height: 20, thickness: 0.5, color: GVColors.borderTertiary(context)),
              _InfoRow(
                icon: Icons.language_outlined,
                label: 'TTS engine',
                value: 'Sarvam Bulbul:v3 · Telugu',
              ),
              Divider(height: 20, thickness: 0.5, color: GVColors.borderTertiary(context)),
              _InfoRow(
                icon: Icons.document_scanner_outlined,
                label: 'OCR engine',
                value: 'Gemini 3.1 Flash-Lite',
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GVColors.bgPrimary(context),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GVRadius.xl)),
        title: Text('Clear downloads?', style: GVTypography.heading(context)),
        content: Text(
          'All saved audio files will be deleted. Articles can be re-downloaded at any time.',
          style: GVTypography.bodySecondary(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: GVColors.textSecondary(context))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              await settings.clearDownloads();
              setState(_refreshStats);
              messenger.showSnackBar(
                SnackBar(
                  content: const Text('Downloads cleared.'),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GVRadius.md)),
                ),
              );
            },
            child: Text('Clear',
                style: TextStyle(color: GVColors.danger(context))),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: GVTypography.label(context).copyWith(
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          color: GVColors.textTertiary(context),
        ),
      ),
    );
  }
}

// ── Settings card ─────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GVColors.bgPrimary(context),
        borderRadius: BorderRadius.circular(GVRadius.lg),
        border: Border.all(
            color: GVColors.borderTertiary(context), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

// ── Row widgets ───────────────────────────────────────────────────────────────

class _TileHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  const _TileHeader(
      {required this.icon, required this.label, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: GVColors.textSecondary(context)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GVTypography.body(context)),
              Text(subtitle, style: GVTypography.small(context)),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: GVColors.textSecondary(context)),
        const SizedBox(width: 10),
        Text(label, style: GVTypography.body(context)),
        const Spacer(),
        Text(value, style: GVTypography.small(context)),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionRow(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GVRadius.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: GVTypography.body(context).copyWith(color: color)),
        ],
      ),
    );
  }
}

class _SegmentedRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  const _SegmentedRow(
      {required this.icon,
      required this.label,
      required this.options,
      required this.selectedIndex,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: GVColors.textSecondary(context)),
        const SizedBox(width: 10),
        Text(label, style: GVTypography.body(context)),
        const Spacer(),
        ...List.generate(options.length, (i) {
          final sel = i == selectedIndex;
          return GestureDetector(
            onTap: () => onSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: sel
                    ? GVColors.accent(context)
                    : GVColors.bgSecondary(context),
                borderRadius: BorderRadius.circular(GVRadius.sm),
                border: Border.all(
                  color: sel
                      ? GVColors.accent(context)
                      : GVColors.borderSecondary(context),
                ),
              ),
              child: Text(
                options[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      sel ? FontWeight.w600 : FontWeight.normal,
                  color: sel
                      ? Colors.white
                      : GVColors.textSecondary(context),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _SpeedRow extends StatelessWidget {
  final double speed;
  final ValueChanged<double> onChanged;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
  static const _labels = ['0.75×', '1×', '1.25×', '1.5×', '2×'];

  const _SpeedRow({required this.speed, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.speed_outlined,
                size: 18, color: GVColors.textSecondary(context)),
            const SizedBox(width: 10),
            Text('Playback speed', style: GVTypography.body(context)),
            const Spacer(),
            Text(
              speed == 1.0 ? 'Normal' : '${speed}×',
              style: GVTypography.small(context),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_speeds.length, (i) {
            final sel = _speeds[i] == speed;
            return GestureDetector(
              onTap: () => onChanged(_speeds[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: sel
                      ? GVColors.accent(context)
                      : GVColors.bgSecondary(context),
                  borderRadius: BorderRadius.circular(GVRadius.sm),
                  border: Border.all(
                    color: sel
                        ? GVColors.accent(context)
                        : GVColors.borderSecondary(context),
                  ),
                ),
                child: Text(
                  _labels[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                    color: sel ? Colors.white : GVColors.textSecondary(context),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ── Voice picker ──────────────────────────────────────────────────────────────

class _VoicePicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _VoicePicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final female = _sarvamVoices.where((v) => v.gender == 'Female').toList();
    final male = _sarvamVoices.where((v) => v.gender == 'Male').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _VoiceGroup(label: 'Female', voices: female, selected: selected, onSelect: onSelect),
        const SizedBox(height: 12),
        _VoiceGroup(label: 'Male', voices: male, selected: selected, onSelect: onSelect),
      ],
    );
  }
}

class _VoiceGroup extends StatelessWidget {
  final String label;
  final List<_Voice> voices;
  final String selected;
  final ValueChanged<String> onSelect;
  const _VoiceGroup(
      {required this.label,
      required this.voices,
      required this.selected,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GVTypography.label(context)
              .copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: voices.map((v) {
            final sel = v.id == selected;
            return GestureDetector(
              onTap: () => onSelect(v.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: sel
                      ? GVColors.accent(context)
                      : GVColors.bgSecondary(context),
                  border: Border.all(
                    color: sel
                        ? GVColors.accent(context)
                        : GVColors.borderSecondary(context),
                    width: sel ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(GVRadius.md),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sel) ...[
                      const Icon(Icons.check_rounded,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      v.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            sel ? FontWeight.w600 : FontWeight.normal,
                        color: sel
                            ? Colors.white
                            : GVColors.textPrimary(context),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
