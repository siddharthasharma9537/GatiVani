# GatiVani (గతివాణి) status            updated 2026-10-27 by Desk · GatiVani

Telugu news you can listen to. Repo `siddharthasharma9537/GatiVani`, default branch `main` (last change 2026-09-27, #16). Operating model: sohum-contracts `docs/OPERATING_MODEL.md`.

## Now

- Setup only: this ledger. No build step is running.

## Next

1. Owner decision on PR #17 (`gativani-actions`, the SoHum/Vāni manifest and four read actions): it is the only open item that unblocks another vertical (Vāni routing GatiVani). See "Waiting on the owner".
2. Decide the fate of PR #3 (45-second playback) and PR #2 (extraction fix). Both conflict with `main` and are 39 and 46 commits behind it; neither can merge as it stands. Likely outcome: re-do the still-wanted parts as fresh, small step sessions from a brief.
3. Tidy: the 11 Dependabot PRs, stale branches and a leftover worktree (proposals below).

## Blocked

- **OCR evaluation** (older session "GatiVani-local-Remote control", 2026-09-08): it needed the real `SARVAM_API_KEY` to capture OCR output and could not read the Supabase secret. Still blocked; no one has supplied a route.
- **OCR reprocess** (older session "OCR accuracy improvements", 2026-08-01): every page failed against Sarvam even though the owner's dashboard showed credits; that session suspected the key deployed in Supabase belongs to a different, exhausted account. Not known to be resolved.
- Telugu wording and TTS voice quality in GatiVani have not been checked by a native reader (per the suite document for the other verticals; not re-verified here for GatiVani).

## Waiting on the owner

Nothing below has been done. All are proposals.

1. **PR #17 (`feat/gativani-actions`)**: merge or not? CI was green on 2026-09-30 and it is mergeable. Merging to `main` runs `deploy-functions.yml`, which deploys **every** edge function to the `sohum` project. Note: `gativani-actions` already shows as ACTIVE (version 1) on the `sohum` Supabase project (read-only check, 2026-10-27), although the suite document says "Built, not deployed". Somebody deployed it by hand from the branch; the owner should confirm that was intended and update the master doc row.
2. **PR #3 and PR #2**: close, or ask for a fresh rebuild? Both are stale and conflicting. #3 removes chunked narration and was never deployed or compiled (its session had no Dart or Deno toolchain); its server migration and function deploy were deliberately left undone.
3. **Dependabot** (#5, #6, #9, #10, #11, #12, #14, #18, #19, #20): merge, batch, or close? Several are major-version jumps (Android Gradle plugin 8 to 9, Kotlin 2.2 to 2.4, `cached_network_image` 3 to 4, `archive` 3 to 4, `file_picker` 11 to 12, `permission_handler` 12 to 13, `go_router` 17 to 18). The three GitHub Actions bumps (#5, #6, #20) are lower risk. Merging a workflow change can affect deploys.
4. **Old Supabase project `gativani`** (ref `jjoxowdvzmlchtfarpbs`): the app moved to the `sohum` project in Phase 3 (#16). The old project is ACTIVE_HEALTHY, has an empty `storage.objects`, and holds two backup tables, `articles_review_backfill_bak` (about 101 rows) and `articles_title_backfill_bak`. Both have row-level security **on** (the earlier claim that it was off is not true today). Pause or delete the old project, or drop the two tables? Not touched.
5. **Orphaned-audio list**: `.cleanup/orphaned-audio.txt` (91 files, 427.6 MB) is not in the repository or in this checkout, and the old project's storage is now empty, so that list is obsolete. No deletion is needed from it. On `sohum`, storage holds 138 audio objects (188 MB) and 41 uploads (180 MB). The `storage-cleanup` function is deployed on `sohum`; the nightly workflow still needs a GitHub secret (per an earlier ledger note; not re-checked). Say if you want it armed.
6. **Sarvam key** for the OCR evaluation: supply it to a step session (or say to skip the evaluation).
7. **Housekeeping, local only**: delete local branches `chore/flutter-app-point-at-sohum` (remote gone, its content is in `main` via #16) and `claude/gativani-analysis-design-3ate8o` (remote gone, merged as #4/#15); `feature/live-discovery` (remote gone), `fix/chunk-gapless-playlist` (never pushed, a reverted rewrite) and the three git stashes are also candidates. Remove the prunable worktree `scratchpad/gativani-main`. Nothing deleted.

## Open pull requests

| # | What | State |
|---|------|-------|
| 17 | `gativani-actions`: SoHum/Vāni manifest and four read actions | Open since 2026-09-30, CI green, mergeable; function already live on `sohum` (see above) |
| 3 | Playback: stop articles dying at about 45 s (removes chunked narration) | Open since 2026-09-02, conflicts with `main`, uncompiled, never deployed |
| 2 | Extraction: stop losing, hiding and scrambling newspaper articles | Open since 2026-08-01, conflicts with `main` |
| 5, 6, 20 | Dependabot: GitHub Actions bumps (checkout 7, setup-cli 3, setup-node 6) | Open |
| 9, 10, 11, 12, 14 | Dependabot: Flutter packages (file_picker, archive, cached_network_image, go_router, permission_handler) | Open |
| 18, 19 | Dependabot: Android Gradle plugin 9.4.1, Kotlin 2.4.20 | Open |

## Live

- Web app `gativani.sohum.cc` (Flutter web on the Cloudflare Worker `gativani`; since 2026-10-17); `gativani.sohum.cloud` redirects to it (308). Source of truth: the GatiVani row in section 3.1 of sohum-contracts `docs/SOHUM_SUITE_AND_CLOUD_CONSOLE.md`.
- Backend: edge functions on the `sohum` Supabase project (`ziebgspujtdzkiwyybsa`), 22 active functions: 21 GatiVani's including `gativani-actions`, plus ChantTracker's `vani-actions`. The `deploy-functions.yml` workflow deploys every function when `main` changes.
- Not verified by this desk: the live site itself, and whether `gativani-actions` answers correctly (only its existence was read).
