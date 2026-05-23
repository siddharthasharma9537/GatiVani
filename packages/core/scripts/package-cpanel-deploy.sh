#!/usr/bin/env bash
# Builds Flutter web + copies cPanel docroot package.
set -euo pipefail

CORE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$(cd "$CORE_ROOT/../gativani-app" && pwd)"
OUT="$CORE_ROOT/deploy/cpanel-upload"
DOCROOT="$OUT/docroot"

API_BASE="${BACKEND_API_BASE:-https://gativani.sohum.cloud/api}"
PUBLIC_ORIGIN="${PUBLIC_ORIGIN:-https://gativani.sohum.cloud}"

echo "==> GatiVani cPanel package"
echo "    API base: $API_BASE"
echo "    Origin:   $PUBLIC_ORIGIN"

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter not in PATH. Install Flutter SDK first." >&2
  exit 1
fi

if [[ ! -d "$APP_ROOT" ]]; then
  echo "ERROR: gativani-app not found at $APP_ROOT" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$DOCROOT"

echo "==> flutter pub get"
(cd "$APP_ROOT" && flutter pub get)

echo "==> flutter build web --release"
(cd "$APP_ROOT" && flutter build web --release \
  --dart-define="BACKEND_API_BASE=$API_BASE" \
  --dart-define="PUBLIC_ORIGIN=$PUBLIC_ORIGIN")

echo "==> copy web build to docroot"
cp -R "$APP_ROOT/build/web/"* "$DOCROOT/"
cp "$CORE_ROOT/deploy/htaccess.docroot" "$DOCROOT/.htaccess"

mkdir -p "$OUT/guides"
cp "$CORE_ROOT/deploy/DEPLOY_CPANEL.md" "$OUT/guides/"
cp "$CORE_ROOT/deploy/htaccess.api-subdir" "$OUT/guides/htaccess.api-subdir.example"
cp "$CORE_ROOT/CPANEL_DEPLOY.md" "$OUT/guides/CPANEL_API.md"

cat > "$OUT/README.txt" <<EOF
GatiVani cPanel upload package
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

UPLOAD docroot/*  ->  cPanel document root for gativani.sohum.cloud
READ guides/DEPLOY_CPANEL.md for Node /api mount + SSL + Firebase

API: $API_BASE
UI:  $PUBLIC_ORIGIN
EOF

echo ""
echo "Done. Upload folder:"
echo "  $DOCROOT"
echo ""
ls -la "$DOCROOT" | head -20
echo "..."
echo "Total size: $(du -sh "$OUT" | cut -f1)"

ZIP="$OUT/gativani-docroot.zip"
rm -f "$ZIP"
(cd "$DOCROOT" && zip -qr "$ZIP" .)
echo "Zip for File Manager upload: $ZIP"
