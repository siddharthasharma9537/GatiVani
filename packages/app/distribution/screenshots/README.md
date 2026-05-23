# Store Screenshots

Source-of-truth screenshots and the export pipeline for both stores.

## Required outputs

### Google Play
| Asset           | Size                | Count | Notes                              |
|-----------------|---------------------|-------|------------------------------------|
| Icon            | 512x512 PNG         | 1     | No alpha, no rounded corners       |
| Feature graphic | 1024x500 PNG/JPG    | 1     | No transparency, no text in margin |
| Phone           | 1080x1920 portrait  | 4–8   | 16:9 ratio                         |
| 7" tablet       | 1200x1920           | 2–4   | If tablet support advertised       |
| 10" tablet      | 1800x2560           | 2–4   | If tablet support advertised       |

### App Store
| Asset           | Size                | Count | Notes                              |
|-----------------|---------------------|-------|------------------------------------|
| App icon        | 1024x1024 PNG       | 1     | Embedded in IPA, also uploaded     |
| iPhone 6.7"     | 1290x2796           | 3–10  | iPhone 14/15 Pro Max               |
| iPhone 6.5"     | 1242x2688           | 3–10  | Optional, auto-scaled if missing   |
| iPad 12.9"      | 2048x2732           | 3–10  | Required if iPad advertised        |
| App Preview     | 1080x1920+ mp4/m4v  | 0–3   | 15–30s, optional                   |

## Screen narrative (suggested ordering, both stores)

1. **Hero** — "Newspapers, as podcasts" overlay on home grid.
2. **Now playing** — full-screen player with scrubber, speed control, article art.
3. **Daily edition** — list of today's articles with summary previews.
4. **Offline** — saved articles screen with "Available offline" badge.
5. **Multi-language** — language picker showing Telugu/Tamil/Hindi/Kannada.
6. **Background playback** — lock-screen control card mockup.
7. **Bookmarks** — saved articles list with audio progress.

## Pipeline

Screenshots are produced by the `screenshots` integration test driver:

```bash
flutter drive \
  --target=integration_test/screenshots_test.dart \
  --driver=test_driver/screenshot_driver.dart \
  --device-id=<device>
```

Captured PNGs land in `distribution/screenshots/raw/<device>/`. Run the framing
script to add device bezels and marketing copy:

```bash
./distribution/screenshots/frame.sh
```

Framed outputs land in `distribution/screenshots/final/<store>/<device>/`.

## Naming convention

`{order}-{locale}-{device}-{slug}.png`

Examples:
- `01-en-US-iphone67-hero.png`
- `02-te-IN-pixel7-now-playing.png`
- `03-en-US-ipad129-daily-edition.png`

This convention is what `r0adkll/upload-google-play` and `apple-actions/upload-testflight-build`
expect when uploading metadata in bulk.
