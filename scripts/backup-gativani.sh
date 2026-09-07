#!/usr/bin/env bash
# Weekly backup of the GatiVāni Supabase project, written straight into the
# Google Drive folder so the only copy is never the local disk.
#
# Run by ~/Library/LaunchAgents/cloud.sohum.gativani.backup.plist. Logs to
# ~/Backups/gativani/backup.log.
#
# Two halves, deliberately different in shape:
#   db/       dated dumps, last KEEP kept — small, so history is cheap
#   storage/  an incremental mirror of current bucket contents — 200 MB+, so
#             only one copy, updated in place, and never re-downloaded whole
#
# The DB password comes from the macOS Keychain, never from a file or the
# environment. Add it once with:
#   security add-generic-password -a postgres -s gativani-db -w
#
# On the 2026-08-31 storage lockout this backed up nothing, because it did not
# exist. See docs and memory for that incident.

set -uo pipefail

PROJECT=jjoxowdvzmlchtfarpbs
DRIVE="$HOME/Library/CloudStorage/GoogleDrive-pothulapatisiddhartha@gmail.com/My Drive/Backups/gativani"
LOCAL="$HOME/Backups/gativani"
KEEP=4                       # dated DB dumps to retain
PGBIN=/opt/homebrew/bin
STAMP=$(date +%Y%m%d)

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

mkdir -p "$LOCAL" "$DRIVE/db" "$DRIVE/storage" || fail "cannot create backup dirs"

# Drive can be unmounted (signed out, app not running). Writing to the mount
# point when Drive is down silently fills the local disk instead, which on this
# machine is close to full — so bail rather than "succeed" into the wrong place.
[ -d "$HOME/Library/CloudStorage/GoogleDrive-pothulapatisiddhartha@gmail.com/My Drive" ] \
  || fail "Google Drive not mounted — refusing to write locally"

PGPASSWORD=$(security find-generic-password -a postgres -s gativani-db -w 2>/dev/null) \
  || fail "no DB password in Keychain (service gativani-db, account postgres)"
export PGPASSWORD
CONN="postgresql://postgres@db.$PROJECT.supabase.co:5432/postgres"

# ── database ─────────────────────────────────────────────────────────────────
# public + auth, minus auth's ephemeral session tables: refresh tokens and
# sessions are useless in a restore (users just sign in again) and are the only
# genuinely dangerous rows to keep in cloud storage.
OUT="$DRIVE/db/gativani-db-$STAMP.sql.gz"
log "dumping database…"
if "$PGBIN/pg_dump" "$CONN" \
      -n public -n auth \
      --exclude-table='auth.refresh_tokens' \
      --exclude-table='auth.sessions' \
      --exclude-table='auth.flow_state' \
      --exclude-table='auth.mfa_amr_claims' \
      --exclude-table='auth.audit_log_entries' \
      --no-owner --no-privileges \
    | gzip > "$OUT.part"; then
  mv "$OUT.part" "$OUT"
  log "database -> $(basename "$OUT") ($(du -h "$OUT" | cut -f1))"
else
  rm -f "$OUT.part"
  fail "pg_dump failed"
fi

# ── storage ──────────────────────────────────────────────────────────────────
# Object list comes from the DB rather than the Storage API, so no service-role
# key is needed. Both buckets are public, so the objects themselves are plain
# HTTPS GETs.
log "syncing storage objects…"
MANIFEST=$(mktemp)
"$PGBIN/psql" "$CONN" -At -F $'\t' -c \
  "select bucket_id, name, coalesce((metadata->>'size')::bigint, 0)
     from storage.objects order by bucket_id, name;" > "$MANIFEST" 2>/dev/null \
  || fail "could not list storage objects"

new=0; skip=0; err=0
while IFS=$'\t' read -r bucket key size; do
  [ -z "${bucket:-}" ] && continue
  dest="$DRIVE/storage/$bucket/$key"
  # Already present at the right size — skip. This is what keeps a weekly run
  # cheap once the first one has completed.
  if [ -f "$dest" ] && [ "$(stat -f%z "$dest" 2>/dev/null)" = "$size" ]; then
    skip=$((skip+1)); continue
  fi
  mkdir -p "$(dirname "$dest")"
  enc=$(python3 -c "import sys,urllib.parse as u; print('/'.join(u.quote(p) for p in sys.argv[1].split('/')))" "$key")
  if curl -fsS --max-time 300 -o "$dest.part" \
       "https://$PROJECT.supabase.co/storage/v1/object/public/$bucket/$enc" \
     && [ "$(stat -f%z "$dest.part" 2>/dev/null)" = "$size" ]; then
    mv "$dest.part" "$dest"; new=$((new+1))
  else
    rm -f "$dest.part"; err=$((err+1)); log "  failed: $bucket/$key"
  fi
done < "$MANIFEST"
cp "$MANIFEST" "$DRIVE/storage/manifest.tsv"
rm -f "$MANIFEST"
log "storage: $new new, $skip unchanged, $err failed"

# Objects deleted upstream (by the retention job) are intentionally NOT removed
# from the mirror — that is the point of a backup. Prune by hand if it grows.

# ── retention on the dated dumps ─────────────────────────────────────────────
old=$(ls -1t "$DRIVE/db"/gativani-db-*.sql.gz 2>/dev/null | tail -n +$((KEEP+1)))
if [ -n "$old" ]; then
  echo "$old" | while read -r f; do log "pruning old dump $(basename "$f")"; rm -f "$f"; done
fi

(cd "$DRIVE" && shasum -a 256 db/*.sql.gz > SHA256SUMS.txt 2>/dev/null)
log "done — $(ls -1 "$DRIVE/db" | wc -l | tr -d ' ') dumps retained"
[ "$err" -gt 0 ] && exit 1 || exit 0
