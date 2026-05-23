# GatiVani — cPanel deploy (UI + API on gativani.sohum.cloud)

One command builds an upload folder:

```bash
cd gativani-core
./scripts/package-cpanel-deploy.sh
```

Output: `deploy/cpanel-upload/docroot/` → upload to your domain document root.

---

## Before you start

1. cPanel login for `gativani.sohum.cloud`
2. Note **document root** (Domains → gativani.sohum.cloud)
3. Node.js app already running API (or ready to configure)

---

## Step 1 — Build package (on your Mac)

```bash
cd /path/to/gativani-core
chmod +x scripts/package-cpanel-deploy.sh
./scripts/package-cpanel-deploy.sh
```

---

## Step 2 — Upload Flutter UI

1. File Manager → open document root for `gativani.sohum.cloud`
2. **Backup** existing files
3. Upload **everything inside** `deploy/cpanel-upload/docroot/` (including `.htaccess`)
4. Do **not** delete `~/gativani-core` on the server

---

## Step 3 — Node API at `/api`

cPanel → **Setup Node.js App**:

| Setting | Value |
|---------|--------|
| Node.js version | 18+ |
| Application root | `/home/USERNAME/gativani-core` |
| Application startup file | `src/server.js` |
| Application URL | `gativani.sohum.cloud` + mount path **`/api`** |

Environment variables: `GEMINI_API_KEY`, `NODE_ENV=production`, etc. (see `CPANEL_DEPLOY.md`).

Click **Run NPM Install** → **Restart**.

If the panel creates `public_html/api/`, ensure `deploy/htaccess.api-subdir` is copied there (edit `USERNAME` / Node path first).

---

## Step 4 — SSL

cPanel → **SSL/TLS** → **Manage SSL** → run **AutoSSL** / Let's Encrypt for `gativani.sohum.cloud`.

---

## Step 5 — Firebase (web auth)

Firebase Console → Authentication → **Authorized domains** → add:

- `gativani.sohum.cloud`

---

## Step 6 — Verify

```bash
curl -s https://gativani.sohum.cloud/health
curl -sI https://gativani.sohum.cloud/ | head -3
```

| URL | Expected |
|-----|----------|
| `https://gativani.sohum.cloud/` | GatiVani UI (HTML) |
| `https://gativani.sohum.cloud/health` | JSON `ok: true` |
| `https://gativani.sohum.cloud/api/health` | Same health JSON |
| `POST …/api/documents/process` | JSON error if no file |

---

## Redeploy

**UI only:** run `package-cpanel-deploy.sh`, re-upload `docroot/`.

**API only:** upload `gativani-core` changes, `npm ci` on server, restart Node app.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Root shows JSON not UI | Flutter files not in docroot; re-upload `docroot/` |
| `/` works but API 404 | Node app URL must include `/api` mount |
| HTTPS cert warning | Run AutoSSL; wait for Let's Encrypt |
| Upload fails on HTTPS | Ask host to check LiteSpeed/mod_security for POST `/api` |
| Localhost:62798 still works | That is `flutter run` dev only — unrelated to production |
