# OAuth setup (Google / Apple / Microsoft)

The app uses the **`supabase_flutter` SDK** for auth. Tapping "Continue with
Google" calls `signInWithOAuth(OAuthProvider.google)`, which redirects through
Supabase → Google → back to the app; the SDK then **captures and persists the
session automatically**, and the menu's account card updates to the signed-in
user (with Log out). No manual token handling.

**Google is the one wired for v1** (Apple / Microsoft buttons exist but need
their own provider config). For the round-trip to actually log a user in, **the
provider must be enabled in the Supabase dashboard with its client id + secret.**
That step requires entering secrets and registering an app in Google Cloud, so it
must be done by you — it can't be automated from here. Once the steps below are
done, sign-in works end-to-end with no code changes.

## 1. Supabase redirect URLs (once)

Supabase dashboard → **Authentication → URL Configuration**:

- **Site URL**: `https://gativani.vercel.app`
- **Redirect URLs**: add `https://gativani.vercel.app` and (for local dev)
  `http://localhost:8080`

Each provider's own console must allow this Supabase callback as a redirect URI:

```
https://jjoxowdvzmlchtfarpbs.supabase.co/auth/v1/callback
```

## 2. Google

1. Google Cloud Console → **APIs & Services → Credentials → Create OAuth client ID**
   → *Web application*.
2. Authorized redirect URI: `https://jjoxowdvzmlchtfarpbs.supabase.co/auth/v1/callback`
3. Copy the **Client ID** and **Client secret**.
4. Supabase → **Authentication → Providers → Google** → enable, paste both, save.

## 3. Microsoft (Supabase "Azure" provider)

1. Azure Portal → **Microsoft Entra ID → App registrations → New registration**.
2. Redirect URI (Web): `https://jjoxowdvzmlchtfarpbs.supabase.co/auth/v1/callback`
3. **Certificates & secrets → New client secret** → copy the value.
4. Copy the **Application (client) ID**.
5. Supabase → **Authentication → Providers → Azure** → enable, paste client id +
   secret. If you want any-tenant logins, set the Azure tenant URL to
   `https://login.microsoftonline.com/common`.

## 4. Apple

Apple is the most involved (needs a paid Apple Developer account):

1. Apple Developer → **Certificates, IDs & Profiles**.
2. Create an **App ID**, then a **Services ID** (this becomes the client id).
3. Configure the Services ID web auth: return URL
   `https://jjoxowdvzmlchtfarpbs.supabase.co/auth/v1/callback`.
4. Create a **Sign in with Apple key**, download the `.p8`, note the Key ID + Team ID.
5. Supabase → **Authentication → Providers → Apple** → enable, fill Services ID +
   the generated client secret (JWT from the key).

## 5. Remaining frontend piece (small)

Once a provider is enabled, the redirect returns to the app with the session in
the URL fragment (`#access_token=…&refresh_token=…`). To persist the login, parse
that fragment on app start and store the tokens (and send the access token as the
`Authorization` header instead of the anon key). This is a focused follow-up; the
buttons and redirect are already wired. Adding `supabase_flutter` would handle the
session automatically if you prefer that over manual parsing.
