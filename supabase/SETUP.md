# Supabase setup — free tier, ≈10 minutes

## 1. Create a project
1. Go to https://supabase.com → **Start your project** (free).
2. **New project** → pick any name (e.g. `nyvox`), set a database password,
   choose the closest region.
3. Wait ~1 minute while the project provisions.

The free tier includes: 500 MB Postgres, Realtime, and 50k monthly active
users — plenty for a messenger launch.

## 2. Enable anonymous sign-ins (Session-style, no email/phone)
1. Left sidebar → **Authentication** → **Sign In / Providers**.
2. Scroll to **Anonymous Sign-Ins** → toggle **on** → Save.

This lets devices get a JWT without any personal identifier. The JWT is only
used to satisfy Row Level Security; identity comes from the on-device keypair.

## 3. Create the database schema
1. Left sidebar → **SQL Editor** → **New query**.
2. Paste the entire contents of [`schema.sql`](schema.sql) → **Run**.
3. You should see "Success". This creates:
   - `profiles`, `device_auth`, `conversations`, `conversation_members`, `messages`
   - Row Level Security policies (users only see their own conversations)
   - Helper functions (`create_dm_conversation`, `lookup_profile_by_account_id`)
   - Realtime publication for instant message delivery

## 4. (Optional) Auto-purge expired disappearing messages
1. Left sidebar → **Database** → **Extensions** → enable **pg_cron**.
2. Uncomment the `cron.schedule` block at the bottom of `schema.sql` and run it.

## 5. Get your API credentials
1. Left sidebar → **Project Settings** (gear) → **API**.
2. Copy:
   - **Project URL** → `SUPABASE_URL`
   - **anon public** key → `SUPABASE_ANON_KEY`

> The anon key is safe to ship inside the app — all tables are protected by
> RLS, and message content is end-to-end encrypted anyway.
> **Never** ship the `service_role` key in the app.

## 6. Run the app
```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

## Verifying privacy
In **Table Editor** → `messages`, you'll see rows whose `ciphertext` column is
opaque base64 — proof the server never sees plaintext.
