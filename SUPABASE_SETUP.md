# Supabase setup for the Driver App POD dashboard

This deployment uses Supabase Auth, one shared JSONB snapshot, optimistic revision checks, RLS, and Supabase Realtime. It does not use localStorage as the data store, a service-role key, or a separate application server.

## 1. Create the Supabase project and team users

1. Create a Supabase project and keep the database password in a password manager.
2. In **Authentication → Providers → Email**, enable email/password sign-in. Turn off public sign-ups so only invited team members can access the dashboard.
3. In **Authentication → Users**, create/invite each team member and set their login credentials.
4. In **Project Settings → API**, copy the Project URL and the **publishable key** (or legacy `anon` key). Never use a secret/service-role key in the HTML.

## 2. Create the shared database and access rules

1. Open **SQL Editor → New query** in Supabase.
2. Paste the full contents of [`supabase-schema.sql`](./supabase-schema.sql) and run it.
3. The script creates one `driver_dashboard_state` record, restricts table reads to authenticated users using RLS, validates unique `(period, branch_code)` keys, and installs RPC functions for revision-safe initialization and writes.
4. Confirm **Database → Replication** includes `public.driver_dashboard_state` for the `supabase_realtime` publication. The SQL script enables it automatically where publication changes are allowed.

## 3. Check the Supabase configuration and deploy to Netlify

1. [`index.html`](./index.html) is configured with the supplied Project URL `https://feiwubgqggzsqxdrbxrg.supabase.co` and publishable key.
2. The URL is the base project URL; do not add `/rest/v1/`. The HTML still blocks access and reports a configuration error if either value is replaced with a placeholder.
3. Deploy the folder to Netlify as usual. Serve the site over HTTPS; do not open the production page as a `file://` URL.

The publishable/anon key is designed to be public. RLS and the RPC authorization checks protect the data. A Supabase service-role/secret key must never be added to this file.

## 4. Sign in and initialize the shared dataset

1. Open the Netlify HTTPS URL and sign in with a team email/password.
2. On the first authenticated open, the database initializes from the dataset embedded in the existing dashboard HTML. This preserves the current data and calculations.
3. Later opens load the existing latest cloud snapshot instead of replacing it with the embedded copy.
4. Upload a new Excel file to replace the shared dataset. All signed-in devices then receive the new snapshot over Realtime.
5. Delete actions update the same shared dataset. Each full-dataset update checks its expected revision; if another device has saved first, the app reloads that latest version and asks the user to review/retry rather than overwriting it.

## Data model and update behavior

- There is one shared dashboard record, keyed by `id = true`; this ensures only one current dataset exists.
- Branch rows retain the existing 11-column raw array format. `period + branch_code` is validated as a unique key, including on the server.
- The dashboard continues to derive all calculated metrics, region mappings, charts, exports, and PNGs using its existing code.
- Excel uploads replace the entire active snapshot, as the existing upload action does. Delete operations remove rows from that snapshot.
- Paste-data support is not present in the existing UI, so this integration does not add or alter a paste workflow.
- A concurrent write is rejected when the stored revision differs from the revision loaded by the client. Resolve by reviewing the refreshed dashboard and retrying; this prevents silent last-write-wins data loss.
- The dashboard requires an authenticated Supabase session to access the shared dataset; sign out to end that browser session.
