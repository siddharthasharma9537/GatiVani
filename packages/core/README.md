# Node core (Express + Gemini + cPanel)

This package is a small Express API intended to run behind **cPanel / Phusion Passenger** (or any Node host). It accepts document uploads, enforces **subscription tier page limits** before calling **Google Gemini** (default `gemini-2.0-flash`, suitable for the standard Generative Language API key flow).

## Quick start (local)

```bash
cd node-core
cp .env.example .env
# set GEMINI_API_KEY in .env
npm install
npm run dev
```

- Health: `GET http://localhost:8788/health`
- Process: `POST http://localhost:8788/api/documents/process` with `multipart/form-data` field **`document`** (PDF or TXT).

### Dev-only tier headers

With `TRUST_CLIENT_TIER_HEADERS=true`, you can send:

- `X-Subscription-Tier: free | standard | premium`
- `X-Subscription-Active: true | false`

In production, verify billing in your auth layer and set `req.trustedSubscription = { tier, active }` on the request **before** `subscriptionContext` (see `src/middleware/subscription.js`).

## cPanel

See [CPANEL_DEPLOY.md](./CPANEL_DEPLOY.md) and `deploy/.htaccess.passenger.example`.

## Layout

| Path | Role |
|------|------|
| `src/server.js` | Express bootstrap |
| `src/routes/documents.js` | Upload + tier limits + Gemini |
| `src/services/gemini.js` | `@google/generative-ai` client |
| `src/lib/tiers.js` | Tier → max pages |
| `src/lib/pdfExtract.js` | PDF text extraction with page cap |
| `src/middleware/subscription.js` | Subscription context |
