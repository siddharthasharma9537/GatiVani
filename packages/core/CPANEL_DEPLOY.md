# Deploying `node-core` on cPanel (Phusion Passenger)

**Full stack (Flutter UI + API on one domain):** see [deploy/DEPLOY_CPANEL.md](./deploy/DEPLOY_CPANEL.md) and run `./scripts/package-cpanel-deploy.sh`.

## 1. Upload code

Upload this folder to your account, for example `/home/USERNAME/node-core`.

## 2. Install dependencies

In cPanel **Terminal** or **Setup Node.js App**:

```bash
cd ~/node-core
npm ci
```

(Use `npm install` if you do not commit a lockfile yet.)

## 3. Environment variables

In **Setup Node.js App → Environment variables**, add at least:

| Name | Purpose |
|------|---------|
| `GEMINI_API_KEY` | Google AI Studio / Gemini API key |
| `GEMINI_MODEL` | Optional; default `gemini-2.0-flash` (free-tier-capable model id) |
| `PORT` | Usually injected by Passenger; safe to omit if the panel sets it |
| `TIER_*_MAX_PAGES` | Optional caps; see `.env.example` |
| `TRUST_CLIENT_TIER_HEADERS` | `true` only in dev; production should verify subscriptions server-side |

Copy `.env.example` to `.env` for local runs. cPanel typically does not read `.env` unless you load it—this app uses `dotenv` when the file exists.

## 4. Application startup file

Set **Application startup file** to `src/server.js` (matches `package.json` `npm start`).

## 5. Passenger / `.htaccess`

Place an `.htaccess` next to the app (see `deploy/.htaccess.passenger.example`). Uncomment and set `PassengerAppRoot`, `PassengerNodejs`, and `PassengerBaseURI` per your host’s documentation.

After changing code or env vars, restart the app from cPanel or `touch tmp/restart.txt` if your host uses that convention.

## 6. API

- `GET /health` — liveness
- `POST /api/documents/process` — multipart form field `document` (PDF or TXT)

Optional headers when `TRUST_CLIENT_TIER_HEADERS=true` (development only):

- `X-Subscription-Tier`: `free` | `standard` | `premium`
- `X-Subscription-Active`: `true` | `false`

Production: attach verified claims in middleware (e.g. JWT) on `req.trustedSubscription = { tier, active }` before `subscriptionContext` runs (see `src/middleware/subscription.js`).

## 7. Subscription enforcement

Page caps are enforced before calling Gemini: only the first _N_ pages of PDF text (see `src/lib/pdfExtract.js`) are sent, where _N_ depends on tier (`src/lib/tiers.js`). Responses include `limits.truncated` when the PDF has more pages than the tier allows.
