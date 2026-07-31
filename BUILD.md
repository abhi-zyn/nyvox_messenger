# Building the APK with GitHub Actions

Every push to `main` (or a manual run) builds `app-release.apk` in the cloud —
no local Flutter install needed.

## Supabase credentials

Your Supabase URL and **publishable** key are baked into the app at build time
via `--dart-define` in [`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml).
The publishable key is Supabase's client-side key — it is designed to ship
inside apps; data access is enforced by Row Level Security (see
[`supabase/schema.sql`](supabase/schema.sql)). Never use the `service_role`
key here.

To rotate or change projects, edit the two `--dart-define` lines in the
workflow file. (Optionally, move them to repo **Settings → Secrets and
variables → Actions** and reference `${{ secrets.SUPABASE_URL }}` /
`${{ secrets.SUPABASE_ANON_KEY }}` instead.)

## Build & download the APK

1. Go to the repo → **Actions** tab → **Build Android APK**.
2. Click **Run workflow** → **Run workflow** (or just push a commit).
3. Wait ~5–8 minutes for the run to finish.
4. Open the completed run → scroll to **Artifacts** → download
   **`nyvox-release-apk`** (a zip containing `app-release.apk`).
5. Copy the APK to your phone and install it (allow "install unknown apps").

## Notes

- The workflow first runs `flutter create . --platforms=android` to generate
  the Android scaffold, since the repo intentionally contains only `lib/` and
  `pubspec.yaml`.
- `flutter analyze` runs in non-blocking mode — warnings won't fail the build.
- **Before the app can log in, finish the Supabase side**: enable anonymous
  sign-ins and run `supabase/schema.sql` in the SQL editor — see
  [`supabase/SETUP.md`](supabase/SETUP.md).
- To ship via the Play Store later, build an App Bundle instead:
  `flutter build appbundle --release` (requires signing — see
  https://docs.flutter.dev/deployment/android#signing-the-app).
