# GatiVāni Design System — "The Moving Voice"

**Version 0.1 · Phase 0 (brand definition) · 2026-07-02 · branch `feature/live-discovery`**

This document is the single source of truth for GatiVani's brand and product design.
It is written to be executed **in phases** (§12); each phase is independently shippable.

---

## 0. Why this exists

Two design systems currently coexist in the app:

| System | File | Character | Used by |
|---|---|---|---|
| `Gati` tokens | `packages/app/lib/design/tokens.dart` | Warm paper/ink, terracotta accent — self-described "Anthropic-structure, Claude-aligned" | v2 screens (Live, player, Today, reader) |
| `GVColors` / `GVTypography` | `packages/app/lib/design/app_theme.dart` | Flat neutral, **purple** accent — also "Claude-aligned" | 8 legacy v1 screens (settings, filters, upload, browse, home…) |

Both are competent, neither is *ours*. They borrow another product's identity, disagree
with each other on the accent, and carry no typographic voice (system fonts + one stray
`GoogleFonts.notoSansTelugu` call). The goal of this system is an **authentic GatiVani
brand**: derived from the name, rooted in Telugu culture, and impossible to mistake for
a template.

---

## 1. Brand core

### 1.1 The name

- **గతి / gati** — motion, pace, tempo, course. In Carnatic music, *gati* is the
  rhythmic gait of a composition — how the beat subdivides and moves.
- **వాణి / vāṇi** — voice, speech; the voice of Saraswati, goddess of knowledge.

**GatiVāni = the voice in motion.** This is not a newspaper that happens to have audio.
It is a *voice* that carries the news to you, at a pace you choose. Every core feature
already expresses this: TTS reading, the karaoke-style lyrics player, live radio,
Mann Ki Baat archives, the marquee ticker.

### 1.2 Brand promise

> **News on the Go.** *(decided 2026-07-02)*
> Telugu: **మీ వార్త, మీ గతి** *(“your news, your pace” — needs a native-speaker pass before shipping)*

### 1.3 Personality

| We are | We are not |
|---|---|
| Warm — paper, ink, turmeric; a household voice | Cold — blue-grey dashboards, tech gradients |
| Composed — editorial restraint, print heritage | Noisy — doomscroll feeds, red badges everywhere |
| Bilingual by birth — Telugu designed first | Translated — Telugu as an afterthought locale |
| Alive — things that speak, glow and move | Animated for decoration's sake |
| Ownable — every motif derives from the name | Borrowed — Claude terracotta, Material defaults |

### 1.4 The signature asset — the Vāṇi line

The macron over the **ā** in *GatiVāni* is not a diacritic. It is the brand's
**voice line**: a horizontal line that is *flat when silent* and becomes a
*waveform while speaking*. It comes from the name itself, so no one else can own it.

It appears as: the macron in the wordmark (animates during playback), the player's
seek bar, the LIVE indicator's pulse, section dividers, and the loading shimmer.
Full spec in §3.3.

---

## 2. Design principles

1. **Listen-first.** Anything readable is playable. A play affordance is never more
   than one tap away; the mini-player is always reachable.
2. **Telugu is not a translation.** Type, spacing and labels are designed in Telugu
   first, verified in English — never the reverse. No layout may break when the
   Telugu string is 1.4× longer.
3. **Paper is calm, voice is color.** Static surfaces are ink-on-paper restraint.
   Accent color and motion are *reserved* for what speaks, plays, or is live.
   If nothing is playing, the screen should look like a well-set newspaper.
4. **One thumb.** Primary actions live in the bottom 60% of the screen. Navigation
   and the mini-player dock at the bottom; the top is for reading, not reaching.
5. **The pace is yours (gati).** The user controls tempo everywhere: playback speed,
   mix length, year chips, marquee pause. We never autoplay video or hijack scroll.

---

## 3. Visual identity

### 3.1 Wordmark — GatiVāni

- **Lockup:** `GatiVāni` — single word, camelcase G and V, macron over the ā.
- **Face:** Anek Telugu (Latin glyphs), weight 600, tight but not touching. The
  wordmark is *typeset*, not drawn — it must render as text on web for SEO/a11y,
  with the macron replaced by the drawn Vāṇi line positioned over the ā.
- **The macron** is drawn (not the font's U+0101 glyph): a rounded-cap stroke in
  Pasupu gold, ~1.6× the width of the ā counter, positioned optically. At rest it
  is flat; while audio plays anywhere in the app it undulates (§3.3).
- **Telugu lockup:** **గతివాణి** — same weight and optical size, used wherever the
  UI language is Telugu. The Vāṇi line sits over the **ణి** vowel length. Both
  lockups are equal citizens; never show one as small print under the other.
- **Clearspace:** ≥ the cap-height of the G on all sides. **Minimum size:** 24 px
  cap height (drop the animated macron below that; keep it static).
- **Misuse:** no gradients, no shadows, no italic, no color other than ink/paper
  for the letters + gold for the macron, never letterspace the Telugu lockup.

### 3.2 App icon

Ink (`#0E0D0B`) rounded square; the Vāṇi line in Pasupu gold, mid-wave, running
edge-to-edge at the optical center; no letterforms (the wave *is* the mark at
small sizes). Favicon: same at 32/16 px with a thicker stroke. Splash: ink field,
wordmark centered, macron animates once (flat → wave → flat) while booting.

### 3.3 The Vāṇi line — motif spec

| Property | Value |
|---|---|
| Stroke | 2 px at 1×, round caps; scales with context (3 px in player, 1 px as divider) |
| Idle | Perfectly flat line |
| Speaking | Sine-ish wave, 3–4 visible cycles, amplitude = 3× stroke, ~1.6 s period, ease-in-out |
| Live | Flat with a single travelling pulse every 2.4 s (Kumkuma red) |
| Loading | Flat line with a low-amplitude shimmer travelling left→right |
| Color | Pasupu gold on ink; Pasupu deep on paper; Kumkuma only for LIVE |

Contexts: wordmark macron · player seek bar (progress fill = gold, remaining =
`onInkTrack`) · LIVE badge underline · section dividers (static, 1 px, `line`
color — shape only, no gold) · skeleton loading rows.

---

## 4. Color — the Pasupu–Kumkuma schema

### 4.1 The story

Turmeric (**pasupu**) and vermilion (**kumkuma**) are the inseparable auspicious
pair of the Telugu household. GatiVani assigns them jobs:

- **Pasupu gold = the Voice.** Everything that speaks or plays: play buttons,
  active seek fill, the macron, speaking indicators, primary actions.
- **Kumkuma vermilion = Live & urgent.** The LIVE dot, breaking tags, destructive
  actions. Because red has *one* job, it never wolf-cries.

No major news product owns gold. Every one of them owns red or blue. This is the
single most identifying decision in the system. (The current terracotta `#D85A30`
is retired; it sits between these two and reads as Claude's brand, not ours.)

### 4.2 Neutrals (kept from current `Gati` — they are already right)

| Token | Light | Dark | Role |
|---|---|---|---|
| `paper` | `#FAF7F0` | `#1A1916` | Page background |
| `ink` | `#2C2C2A` | `#ECE7DD` | Primary text |
| `inkDeep` | `#0E0D0B` | `#0E0D0B` | Player / immersive surfaces (same in both modes) |
| `surface` | `#FFFFFF` | `#26241F` | Cards, tiles |
| `muted` | `#888780` | `#9C968A` | Secondary text |
| `line` | `#E7E4DB` | `#38342C` | Hairlines |
| `chip` | `#EFE9DE` | `#2E2B24` | Chip / segmented backgrounds |
| on-ink set | keep `onInk`, `onInkMuted`, `onInkTrack`, `onInkPast`, `onInkFuture` as-is | | Player text/track |

### 4.3 Brand accents

| Token | Value | Use |
|---|---|---|
| `pasupu` | `#E39A0B` | Fills & icons on ink/dark; play buttons; active states |
| `pasupuDeep` | `#9A6200` | Text & icons **on paper** (AA ≥ 4.5:1 on `#FAF7F0`) |
| `pasupuSoft` | `#FBEFD6` | Tint backgrounds (badges, selected chips) on paper |
| `pasupuGlow` | `#F4B942` | Hover/active on ink; the animated macron highlight |
| `kumkuma` | `#D3402E` | LIVE dot, breaking tag, destructive fill |
| `kumkumaDeep` | `#8F1F13` | Destructive/live text on paper |
| `kumkumaSoft` | `#FBE7E3` | Live/danger tint backgrounds |

**Rules.** Never use pasupu for large text on paper (use `pasupuDeep`). Never use
kumkuma for anything that is not live/breaking/destructive. Gold fills take **ink**
glyphs, not white. Budget: any one screen shows gold in at most ~3 places at rest.

### 4.4 Section ramps

Keep `section_colors.dart`'s muted equal-lightness approach (it already follows
"editorial, not rainbow"). Phase 1 re-tunes only the four ramps that collide with
the new accents (National/Devotional pastels sit too close to `pasupuSoft`/
`kumkumaSoft`) and keeps the dark-mode resolution rule unchanged.

### 4.5 Semantic

`success` `#0F6E56` / dark `#1D9E75` · `warning` = `pasupuDeep` (gold family does
double duty) · `danger` = `kumkuma` family · `info` = ink + muted, never blue.

---

## 5. Typography

### 5.1 Families — two, both bilingual by construction

| Role | Family | Why |
|---|---|---|
| Display, headlines, UI | **Anek Telugu** (variable; ships Latin + Telugu, by Ek Type) | An Indian multiscript type system — Telugu and Latin drawn together, display weights available. This *is* the brand voice. |
| Long-form reading | **Noto Serif Telugu** + **Noto Serif** (Latin) | Comfortable long-read serifs that share design DNA across scripts; newspaper gravitas |

Both load via the existing `google_fonts: ^8.1.0` (`GoogleFonts.anekTelugu()`,
`GoogleFonts.notoSerifTelugu()`, `GoogleFonts.notoSerif()`), cached for offline.

### 5.2 Scale

Sizes in Flutter logical px. **Telugu needs taller line-height** (stacked vowel
signs & consonant conjuncts) — encoded per-script, not left to chance:

| Role | Latin size/lh | Telugu size/lh | Weight | Face |
|---|---|---|---|---|
| `display` | 32 / 38 | 32 / 46 | 600 | Anek |
| `headline` | 24 / 30 | 24 / 36 | 600 | Anek |
| `title` | 18 / 24 | 18 / 27 | 500 | Anek |
| `bodyRead` | 17 / 26 | 18 / 31 | 400 | Noto Serif |
| `bodyUi` | 15 / 21 | 15 / 23 | 400 | Anek |
| `label` | 13 / 16 | 13 / 19 | 500 | Anek |
| `caption` | 12 / 16 | 12 / 17 | 400 | Anek |
| `lyrics` | 22 / 32 | 22 / 35 | 500 | Anek (player karaoke lines) |

### 5.3 Rules

- **Sentence case everywhere.** No ALL-CAPS — Telugu has no case, so caps styling
  creates EN/TE asymmetry. Emphasis comes from weight and color, not caps.
- **Two weights in UI (400/500); 600 for display/headline only.** Never 300 or 700+.
- **Never letterspace Telugu.** Latin tracking allowed only in the wordmark.
- Reading width ≤ 34 em Telugu / 38 em Latin. Numerals: proportional, Latin digits.

---

## 6. Iconography & imagery

- **Icons:** Material Symbols **Rounded**, weight 400, fill for active states only.
  One family; no mixed sets. Play/pause icons always sit on gold or ink circles.
- **Imagery:** news thumbnails are content, not decoration — always behind a subtle
  ink scrim when text overlays. No stock illustrations; empty states use the Vāṇi
  line motif + typography (§8.5), never mascots or clip-art.
- **Elevation:** flat by default. One shadow token only —
  `0 8 24 rgba(14,13,11,0.14)` — for floating layers (mini-player, sheets, menus).
  Cards on paper separate by `line` hairlines + `surface`, never by shadow.

---

## 7. Motion — the three tempos

Named after Carnatic tempo (laya) — because *gati* is the brand:

| Token | Duration | Curve | Use |
|---|---|---|---|
| `druta` | 120 ms | easeOutCubic | Press feedback, chip select, toggles |
| `madhyama` | 240 ms | easeOutCubic in / easeInCubic out | Fades, list changes, chip rows |
| `vilamba` | 360 ms | easeOutCubic | Spatial: sheets, player rise, page transitions |

**Signature moves** (all already half-built — formalize, don't invent):
player expands *from the mini-player dock* bottom-up (router already does 340 ms →
align to `vilamba`); karaoke line-highlight scroll in the player; the Vāṇi-line
wave whenever TTS speaks; LIVE pulse. **Respect `MediaQuery.disableAnimations`** —
waves freeze flat, transitions become fades.

---

## 8. UX & navigation architecture

### 8.1 Information architecture (target)

```
Shell (StatefulShellRoute + bottom nav + mini-player dock)
├── Live      /            marquee · latest stories · podcasts · cricket strip
├── Paper     /paper       today's newspaper (drawer shell, sections)
├── Shows     /shows       podcast archives (MKB…) · stories
└── You       /you         saved · downloads · history · settings · account
Overlay:      mini-player  docked above nav, all tabs → swipe/tap up = /player
Pushed:       /reader · /section/:name · /search  (inside the active tab)
Full-screen:  /player (expands from dock) · /auth
```

### 8.2 Route migration

| Current | Target | Note |
|---|---|---|
| `/` LiveFeedScreen | `/` tab 1 | unchanged as home |
| `/newspaper` HomeDrawerShell | `/paper` tab 2 | keep `/newspaper` redirect |
| `/menu` MenuScreen (left-slide) | dissolves into **You** tab | keep `/menu` → `/you` redirect |
| `/player` route | overlay expanding from dock | keep URL for deep-link/back |
| `/reader`, `/section/:name`, `/search`, `/auth` | unchanged | pushed routes |

Browser back must keep working per-tab (the reason go_router exists here — see
`router.dart` comments); StatefulShellRoute preserves that.

### 8.3 The mini-player dock

The keystone listen-first component. 56 px bar above the tab bar: thumbnail,
title (marquee if long), play/pause, and the **Vāṇi line as its top edge**
(doubling as seek progress). Persistent across all tabs; hidden only when the
queue is empty; swipe up or tap → full player (which already swipe-down-dismisses
back onto it — symmetric).

### 8.4 Key flows (must stay ≤ this tap count)

- Hear the news: open app → tap any tile → playing (2 taps).
- Continue listening: reopen app → mini-player resumes position (0 taps to see it).
- Read instead: player → "Read" pill → reader with related articles below.
- Archive: Shows → MKB tile → year chips → episode (lazy-resolved, spinner on row).

### 8.5 States

Every list screen ships all four, from the kit — no ad-hoc spinners:
**Loading** = skeleton rows with the Vāṇi shimmer · **Empty** = flat Vāṇi line +
one sentence + one action · **Error** = same + retry (never a red wall) ·
**Offline** = paper banner, cached content stays readable, downloads playable.

---

## 9. Voice & microcopy

- Warm, plain, unhurried. Never shout ("BREAKING!!!"), never tech-jargon
  ("synthesizing audio…" → "మాట సిద్ధమవుతోంది…" / "getting the voice ready…").
- Telugu written first, English second; both by hand, never machine-mirrored.
- Feature names are brand assets: **GatiVani Take** (the explainer), **Mix**,
  **Your Queue**. Keep them consistent across UI, marketing, and code.
- Buttons are verbs ("Play", "Save"); empty states offer an action, not an apology.

---

## 10. Core component kit (`packages/app/lib/design/components/`)

| Component | Variants | Replaces / used by |
|---|---|---|
| `VaniLine` | seek · live · loading · divider · macron | player seek, LIVE badge, skeletons, masthead |
| `GatiPlayButton` | hero (56) · tile (40) · inline (28) | ad-hoc play icons everywhere |
| `GatiPill` | action (Read/Mix/Save/Download) · toggle | player pill row |
| `GatiChip` | filter · year · section | year chips, live-feed filters |
| `GatiCard` | article · related · stat | article_card.dart, related strip |
| `GatiTile` | podcast · live · cricket | live-feed tiles |
| `GatiRow` | queue · episode · settings | queue list, MKB list, settings |
| `GatiMasthead` | full (wordmark+date+edition) · compact | Live header, Paper header |
| `GatiTabBar` + `GatiMiniPlayer` | — | new shell (§8) |
| `GatiSheet` / `GatiSnack` / `GatiSkeleton` / `GatiEmpty` | — | modals, toasts, states |

Component rules: props take token names, never raw colors; every component renders
correctly in EN + TE and light + dark before it merges (4-way check).

---

## 11. Current-state audit → migration map

- `design/tokens.dart` — **grows** into the v2 foundation (§4–§7 tokens land here). Keep names `Gati`, `GatiPalette`.
- `design/section_colors.dart` — keep; retune 4 ramps (§4.4).
- `design/app_theme.dart` — `AppTheme.light()/dark()` gets rebuilt on the new tokens in Phase 1; `GVColors/GVTypography/GVSpacing/GVRadius` become thin deprecated aliases, deleted in Phase 5.
- Legacy `GVColors` screens to migrate or retire: `settings`, `newspaper_browse`, `filter`, `sort`, `home`, `article_list`, `audio_queue_player`, `upload_content` (+ `player_screen`, `home_drawer_shell` review). Several look superseded by v2 — **flag, confirm, then delete**; don't silently keep dead screens.

---

## 12. Rollout phases

Each phase = one branch-mergeable unit with its own acceptance check. Sizes: S ≤ half-day, M ≈ 1 day, L ≈ 2–3 days of focused work.

### Phase 0 — Brand definition ✅ (this document)
Mockup/style tile reviewed in chat; open decisions (§13) resolved with Siddhartha.

### Phase 1 — Foundations in code (M) ✅ (2026-07-02)
- Extend `design/tokens.dart`: pasupu/kumkuma accents (§4.3), semantic colors, full type scale as `GatiType` (per-script, google_fonts), motion tokens (`druta/madhyama/vilamba`), elevation token.
- Rebuild `AppTheme.light()/dark()` on these tokens (MaterialApp keeps working); map `kAccent` → pasupu; retune the 4 colliding section ramps.
- **Accept:** app builds & runs both themes on :8082; no v2 screen references raw hex; terracotta gone from v2 surfaces; EN/TE type renders with correct line-heights in reader + player.

### Phase 2 — Identity assets (M) ✅ (2026-07-03)
- `GatiWordmark` widget (text + drawn animated macron, EN/TE lockups), `VaniLine` component (all 5 modes), `GatiMasthead`.
- App icon + favicon + web manifest + splash (ink field, one macron wave cycle).
- Mount masthead on Live + Paper headers.
- **Accept:** wordmark animates only while audio plays; icon/favicon visible in browser tab; splash shows on cold load; reduced-motion freezes the wave.

### Phase 3 — Core component kit (L) ✅ (2026-07-03 — GatiSheet deferred to Phase 4/5 where sheets get restyled; GatiSkeleton to Phase 6 with the states pass)
- Build §10 components; migrate **player + Live screen** onto them (pills, chips, tiles, rows, seek bar → `VaniLine.seek`).
- **Accept:** player & Live import only `design/` components/tokens; 4-way check (EN/TE × light/dark) screenshots on :8082; year-chip archive & queue behave exactly as today.

### Phase 4 — Navigation shell (L)
- StatefulShellRoute in `router.dart`: 4 tabs (§8.1) + `GatiTabBar` + persistent `GatiMiniPlayer` dock; `/newspaper`→`/paper`, `/menu`→`/you` redirects; cricket strip into Live; Shows tab hosts MKB + stories.
- **Accept:** mini-player persists across tabs & resumes on reload; browser back pops within tab (regression-check the `router.dart` history behaviors); deep links `/reader`, `/section/:name` still work; player still expands bottom-up from the dock.

### Phase 5 — Screen migration & deletion (L)
- Migrate `settings`, `search`, `auth`, reader polish, section screen onto the kit.
- Review-and-confirm list, then delete: `home_screen`, `article_list_screen`, `audio_queue_player_screen`, `player_screen`, `filter/sort` (if superseded), `upload_content`/`ocr_review` (decide: keep behind You tab or park).
- Delete `GVColors` aliases; `grep -r "GVColors" lib/` returns nothing.
- **Accept:** zero legacy-token references; every remaining screen passes the 4-way check; no route 404s.

### Phase 6 — Motion, states & accessibility polish (M)
- Transitions onto tempo tokens; `GatiSkeleton/GatiEmpty/error/offline` on all list screens; haptics (mobile) on play/save; contrast audit (gold rules §4.3), 48 px targets, bilingual semantics labels, text-scale 1.3 pass, reduced-motion pass.
- **Accept:** written checklist per screen committed to `docs/` with all boxes ticked.

**Order is deliberate:** tokens → identity → components → shell → migration → polish. Nothing in a later phase blocks earlier ones from shipping to the live site. Merge to `main` stays blocked until you say otherwise.

---

## 13. Open decisions (need Siddhartha)

1. **Accent:** Pasupu–Kumkuma (recommended, mocked) vs keeping terracotta. Gold is the identity bet — see the style tile before deciding.
2. **Tab names:** "Paper" vs "News(paper)"; "Shows" vs "Radio"; Telugu labels for all four (need native pass: లైవ్ · పేపర్ · షోలు · మీరు?).
3. **Telugu tagline** and any Telugu microcopy — native-speaker review before ship.
4. **Legacy screens** (upload/OCR/browse/filter/sort): retire, or park under You?
5. **Anek Telugu** final call after seeing it render real headlines on-device (fallback candidates: Hind Guntur, Baloo Tammudu 2).
